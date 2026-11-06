import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class RsaPublicKey {
  const RsaPublicKey(this.modulus, this.exponent);
  final BigInt modulus;
  final BigInt exponent;
}

class CertificateParseException implements Exception {
  CertificateParseException(this.message);
  final String message;
  @override
  String toString() => 'CertificateParseException: $message';
}

/// A DER TLV: tag byte and the [start, end) range of its contents.
class _Tlv {
  _Tlv(this.tag, this.start, this.end);
  final int tag;
  final int start;
  final int end;
}

_Tlv _readTlv(Uint8List d, int pos) {
  if (pos + 2 > d.length) throw CertificateParseException('truncated TLV');
  final tag = d[pos];
  var p = pos + 1;
  var len = d[p++];
  if (len & 0x80 != 0) {
    final n = len & 0x7f;
    if (n == 0 || n > 4 || p + n > d.length) throw CertificateParseException('bad length');
    len = 0;
    for (var i = 0; i < n; i++) {
      len = (len << 8) | d[p++];
    }
  }
  if (p + len > d.length) throw CertificateParseException('length past end');
  return _Tlv(tag, p, p + len);
}

List<_Tlv> _children(Uint8List d, _Tlv parent) {
  final out = <_Tlv>[];
  var p = parent.start;
  while (p < parent.end) {
    final t = _readTlv(d, p);
    out.add(t);
    p = t.end;
  }
  return out;
}

BigInt _unsignedInt(Uint8List d, _Tlv t) {
  var v = BigInt.zero;
  for (var i = t.start; i < t.end; i++) {
    v = (v << 8) | BigInt.from(d[i]);
  }
  return v;
}

const _rsaEncryptionOid = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01];

/// Extracts the RSA public key from an X.509 certificate in DER form.
RsaPublicKey rsaPublicKeyFromCertificate(Uint8List der) {
  const seq = 0x30;
  final cert = _readTlv(der, 0);
  if (cert.tag != seq) throw CertificateParseException('not a certificate');
  final tbs = _children(der, cert).first;
  for (final el in _children(der, tbs)) {
    if (el.tag != seq) continue;
    final parts = _children(der, el);
    if (parts.length != 2 || parts[0].tag != seq || parts[1].tag != 0x03) continue;
    final algo = _children(der, parts[0]);
    if (algo.isEmpty || algo[0].tag != 0x06) continue;
    final oid = der.sublist(algo[0].start, algo[0].end);
    if (!_listEquals(oid, _rsaEncryptionOid)) {
      throw CertificateParseException('certificate key is not RSA');
    }
    // BIT STRING: first content byte is the unused-bits count.
    final keyBytes = Uint8List.sublistView(der, parts[1].start + 1, parts[1].end);
    final rsa = _readTlv(keyBytes, 0);
    final ints = _children(keyBytes, rsa);
    if (ints.length < 2) throw CertificateParseException('bad RSAPublicKey');
    return RsaPublicKey(_unsignedInt(keyBytes, ints[0]), _unsignedInt(keyBytes, ints[1]));
  }
  throw CertificateParseException('no subjectPublicKeyInfo');
}

/// PEM certificate → DER bytes.
Uint8List pemToDer(String pem) {
  final body = pem.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty && !l.startsWith('-----')).join();
  return base64.decode(body);
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Minimal big-endian bytes of a non-negative integer (no sign byte).
Uint8List unsignedBytes(BigInt v) {
  if (v == BigInt.zero) return Uint8List.fromList([0]);
  var hex = v.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

class PairingCodeException implements Exception {
  PairingCodeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Uppercases and strips whitespace; throws if not exactly 6 hex characters.
String normalizePairingCode(String raw) {
  // The code is hex, so a letter O can only be a mistyped zero.
  final code = raw.replaceAll(RegExp(r'\s'), '').toUpperCase().replaceAll('O', '0');
  if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(code)) {
    throw PairingCodeException('The code is 6 characters: digits 0–9 and letters A–F.');
  }
  return code;
}

/// Pairing secret = SHA-256(client n ‖ client e ‖ server n ‖ server e ‖ code[2..6]).
/// The first hash byte must equal code[0..2] — a checksum that catches typos
/// before anything is sent. Throws [PairingCodeException] when it doesn't match.
Uint8List computePairingSecret({required RsaPublicKey client, required RsaPublicKey server, required String code}) {
  final c = normalizePairingCode(code);
  final input = BytesBuilder(copy: false)
    ..add(unsignedBytes(client.modulus))
    ..add(unsignedBytes(client.exponent))
    ..add(unsignedBytes(server.modulus))
    ..add(unsignedBytes(server.exponent))
    ..add(unsignedBytes(BigInt.parse(c.substring(2), radix: 16)).padLeft(2));
  final digest = Uint8List.fromList(sha256.convert(input.toBytes()).bytes);
  if (digest[0] != int.parse(c.substring(0, 2), radix: 16)) {
    throw PairingCodeException("That code doesn't match the one on the TV. Check it and try again.");
  }
  return digest;
}

extension on Uint8List {
  /// Left-pads with zero bytes to [length] (code[2..6] is always exactly 2 bytes).
  Uint8List padLeft(int length) {
    if (this.length >= length) return this;
    return Uint8List(length)..setRange(length - this.length, length, this);
  }
}
