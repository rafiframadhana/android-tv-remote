import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/certificate.dart';
import 'package:tv_remote/core/saved_tv.dart';
import 'package:tv_remote/core/share_link.dart';
import 'package:tv_remote/core/tls.dart';
import 'package:tv_remote/protocol/framing.dart';
import 'package:tv_remote/protocol/pairing_crypto.dart';
import 'package:tv_remote/protocol/proto.dart';
import 'package:tv_remote/protocol/remote_messages.dart';

ClientIdentity _newIdentity() {
  final g = generateClientCertificate();
  return ClientIdentity(certificatePem: g.certificatePem, privateKeyPem: g.privateKeyPem);
}

/// A fake TV that, like the Panasonic, only trusts the certificate that last paired with it.
class _FakeTv {
  _FakeTv(this.identity, this.trusted);

  final ClientIdentity identity;

  /// The one remote this TV remembers.
  ClientIdentity trusted;
  late final SecureServerSocket pairing;
  late final SecureServerSocket remote;
  String? shownCode;

  String get fingerprint => sha256Fingerprint(identity);

  SecurityContext _ctx(ClientIdentity client) => SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(identity.certificatePem))
    ..usePrivateKeyBytes(utf8.encode(identity.privateKeyPem))
    ..setTrustedCertificatesBytes(utf8.encode(client.certificatePem));

  Future<void> start() async {
    // Pairing port: shows a code (valid checksum for this client), accepts the matching secret.
    pairing = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      _ctx(trusted),
      requestClientCertificate: true,
    );
    pairing.listen((s) {
      final client = rsaPublicKeyFromCertificate(s.peerCertificate!.der);
      final d = FrameDecoder();
      Uint8List polo(int field, ProtoWriter body) =>
          (ProtoWriter()
                ..varint(1, 2, always: true)
                ..varint(2, 200, always: true)
                ..message(field, body))
              .toBytes();
      s.listen((chunk) {
        for (final msg in d.add(chunk)) {
          final m = ProtoMessage.decode(msg);
          if (m.has(10)) s.add(encodeFrame(polo(11, ProtoWriter()..string(1, 'Fake TV'))));
          if (m.has(20)) s.add(encodeFrame(msg));
          if (m.has(30)) {
            shownCode = _validCode(client);
            s.add(encodeFrame(polo(31, ProtoWriter())));
          }
          if (m.has(40)) {
            final expected = computePairingSecret(client: client, server: identity.publicKey, code: shownCode!);
            final got = m.message(40)!.bytes(1)!;
            if (_eq(got, expected)) {
              s.add(encodeFrame(polo(41, ProtoWriter()..bytes(1, [1], always: true))));
            } else {
              s.add(
                encodeFrame(
                  (ProtoWriter()
                        ..varint(1, 2, always: true)
                        ..varint(2, 402, always: true))
                      .toBytes(),
                ),
              );
            }
          }
        }
      });
    });
    // Remote port: only the remembered certificate gets in.
    remote = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      _ctx(trusted),
      requestClientCertificate: true,
      requireClientCertificate: true,
    );
    remote.listen((s) {
      s.add(encodeFrame(RemoteOut.configureReply(RemoteFeature.all)));
      s.add(encodeFrame((ProtoWriter()..message(40, ProtoWriter()..boolean(1, true))).toBytes()));
    }, onError: (_) {});
  }

  String _validCode(RsaPublicKey client) {
    for (var b = 0; b < 256; b++) {
      final c = '${b.toRadixString(16).padLeft(2, '0').toUpperCase()}0A0B';
      try {
        computePairingSecret(client: client, server: identity.publicKey, code: c);
        return c;
      } on PairingCodeException {
        continue;
      }
    }
    throw StateError('unreachable');
  }

  Future<void> close() async {
    await pairing.close();
    await remote.close();
  }
}

bool _eq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String sha256Fingerprint(ClientIdentity id) => sha256.convert(pemToDer(id.certificatePem)).toString();

void main() {
  late ClientIdentity tvId, phoneA, other;
  late _FakeTv tv;
  late ShareHost host;
  late int hostPort;
  late SavedTv tvOnA;

  setUpAll(() {
    tvId = _newIdentity();
    phoneA = _newIdentity();
    other = _newIdentity();
  });

  setUp(() async {
    tv = _FakeTv(tvId, phoneA);
    await tv.start();
    tvOnA = SavedTv(host: '127.0.0.1', name: 'Fake TV', pins: [tv.fingerprint], remoteVerified: true);
    host = ShareHost(
      findTv: (id) => id == tvShareId(tvOnA.pins.first) ? tvOnA : null,
      identityForTv: (_) async => phoneA,
      tvPairingPort: tv.pairing.port,
    );
    hostPort = await host.start(phoneA);
  });

  tearDown(() async {
    await host.stop();
    await tv.close();
  });

  Future<ShareJoin> join() => ShareJoin.begin(
    hostAddress: '127.0.0.1',
    hostPort: hostPort,
    tvId: tvShareId(tv.fingerprint),
    tvHost: '127.0.0.1',
    tvRemotePort: tv.remote.port,
  );

  test('a new phone joins with the code shown on the TV and gets a working pairing', () async {
    final j = await join();
    expect(tv.shownCode, isNotNull, reason: 'the host started pairing, so the TV shows a code');

    // A typo is caught and can be retried without a new code.
    final first = int.parse(tv.shownCode!.substring(0, 2), radix: 16);
    final typo = (first ^ 1).toRadixString(16).padLeft(2, '0') + tv.shownCode!.substring(2);
    await expectLater(j.submit(typo), throwsA(isA<PairingCodeException>()));

    final shared = await j.submit(tv.shownCode!);
    await j.close();
    expect(shared.identity.publicKey.modulus, phoneA.publicKey.modulus, reason: 'B now uses A’s pairing');
    expect(shared.tv.pins, [tv.fingerprint]);
    expect(shared.tv.host, '127.0.0.1');
    // The TV still remembers A's certificate, so both phones work at the same time.
    await verifySharedPairing(shared.tv, shared.identity, port: tv.remote.port);
    await verifySharedPairing(tvOnA, phoneA, port: tv.remote.port);
  });

  test('a phone that does not use the TV refuses', () async {
    await expectLater(
      ShareJoin.begin(hostAddress: '127.0.0.1', hostPort: hostPort, tvId: '0123456789abcdef', tvHost: '127.0.0.1'),
      throwsA(isA<ShareException>()),
    );
  });

  test('a pairing that the TV does not accept is never saved', () async {
    await expectLater(verifySharedPairing(tvOnA, other, port: tv.remote.port), throwsA(isA<ShareException>()));
  });
}
