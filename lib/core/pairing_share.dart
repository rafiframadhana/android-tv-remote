import 'dart:convert';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';

import '../protocol/pairing_crypto.dart';
import '../protocol/proto.dart';
import 'saved_tv.dart';
import 'tls.dart';

class ShareCodeException implements Exception {
  ShareCodeException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One TV's pairing, packed so another phone can use it too.
///
/// Why: some TVs (verified on a Panasonic/Realtek Android TV 9) remember only the most recently
/// paired remote, so a second phone pairing on its own logs the first one out. Sharing the
/// pairing lets several phones use the same credentials at once — the TV accepts concurrent
/// connections with the same certificate (also verified).
///
/// The code carries the client certificate and private key: whoever has it can control the TV.
/// It is shown only on request and never stored outside secure storage.
///
/// Format: `tvremote1:` + base64url(protobuf). The private key is sent as its two primes (the
/// rest is recomputed), which keeps the code ~1 KB — a QR code a phone camera reads easily.
class SharedPairing {
  SharedPairing({required this.tv, required this.identity});

  static const prefix = 'tvremote1:';

  final SavedTv tv;
  final ClientIdentity identity;

  // Field numbers.
  static const _fHost = 1, _fName = 2, _fPin = 3, _fCert = 4, _fP = 5, _fQ = 6;

  String encode() {
    final key = CryptoUtils.rsaPrivateKeyFromPemPkcs1(identity.privateKeyPem);
    final w = ProtoWriter()
      ..string(_fHost, tv.host, always: true)
      ..string(_fName, tv.name);
    for (final pin in tv.pins) {
      w.bytes(_fPin, _hexToBytes(pin), always: true);
    }
    w
      ..bytes(_fCert, pemToDer(identity.certificatePem), always: true)
      ..bytes(_fP, unsignedBytes(key.p!), always: true)
      ..bytes(_fQ, unsignedBytes(key.q!), always: true);
    return prefix + base64Url.encode(w.toBytes()).replaceAll('=', '');
  }

  /// Parses and verifies a code. Throws [ShareCodeException] for anything that isn't a valid,
  /// self-consistent pairing (wrong text, truncated scan, key not matching the certificate).
  static SharedPairing decode(String raw) {
    final code = raw.trim();
    if (!code.startsWith(prefix)) throw ShareCodeException("That isn't a TV Remote pairing code.");
    final ProtoMessage m;
    try {
      m = ProtoMessage.decode(Uint8List.fromList(base64Url.decode(base64Url.normalize(code.substring(prefix.length)))));
    } on Object {
      throw ShareCodeException('The code is incomplete. Scan or copy it again.');
    }
    final host = m.string(_fHost);
    final certDer = m.bytes(_fCert);
    final p = m.bytes(_fP), q = m.bytes(_fQ);
    if (host.isEmpty || host.length > 255 || certDer == null || p == null || q == null) {
      throw ShareCodeException('The code is incomplete. Scan or copy it again.');
    }
    final pins = [
      for (final pin in m.bytesList(_fPin))
        if (pin.length == 32) _bytesToHex(pin),
    ];
    if (pins.isEmpty) throw ShareCodeException('The code is missing the TV identity.');

    final RsaPublicKey pub;
    try {
      pub = rsaPublicKeyFromCertificate(certDer);
    } on Object {
      throw ShareCodeException('The code contains an invalid certificate.');
    }
    final pBig = _toBig(p), qBig = _toBig(q);
    if (pBig * qBig != pub.modulus) throw ShareCodeException("The code's key doesn't match its certificate.");
    final phi = (pBig - BigInt.one) * (qBig - BigInt.one);
    final key = RSAPrivateKey(pub.modulus, pub.exponent.modInverse(phi), pBig, qBig);

    final certPem = X509Utils.formatKeyString(base64.encode(certDer), X509Utils.BEGIN_CERT, X509Utils.END_CERT);
    final name = m.string(_fName).trim();
    return SharedPairing(
      tv: SavedTv(host: host, name: name.isEmpty ? 'TV at $host' : name, pins: pins, remoteVerified: true),
      identity: ClientIdentity(certificatePem: certPem, privateKeyPem: CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(key)),
    );
  }

  static BigInt _toBig(Uint8List b) => b.fold(BigInt.zero, (v, x) => (v << 8) | BigInt.from(x));

  static Uint8List _hexToBytes(String hex) =>
      Uint8List.fromList([for (var i = 0; i + 1 < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)]);

  static String _bytesToHex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
}
