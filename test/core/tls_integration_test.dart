import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/certificate.dart';
import 'package:tv_remote/core/tls.dart';
import 'package:tv_remote/protocol/framing.dart';
import 'package:tv_remote/protocol/pairing_crypto.dart';
import 'package:tv_remote/protocol/pairing_session.dart';
import 'package:tv_remote/protocol/proto.dart';
import 'package:tv_remote/protocol/remote_messages.dart';
import 'package:tv_remote/protocol/remote_session.dart';

/// Real TLS sockets on localhost against a fake TV that has its own self-signed
/// certificate and requests a client certificate, like the Android TV Remote Service.
void main() {
  late ClientIdentity client;
  late ClientIdentity tv;

  setUpAll(() {
    final c = generateClientCertificate();
    client = ClientIdentity(certificatePem: c.certificatePem, privateKeyPem: c.privateKeyPem);
    final t = generateClientCertificate();
    tv = ClientIdentity(certificatePem: t.certificatePem, privateKeyPem: t.privateKeyPem);
  });

  SecurityContext tvContext() => SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(tv.certificatePem))
    ..usePrivateKeyBytes(utf8.encode(tv.privateKeyPem));

  /// Starts a fake TV; [onConnect] gets the server-side socket and a stream of decoded client messages.
  Future<SecureServerSocket> startTv(void Function(SecureSocket socket, Stream<Uint8List> fromClient) onConnect) async {
    // Dart's server side can't skip client-cert verification, so trust our self-signed cert explicitly
    // (the real TV accepts any client cert on the pairing port and remembers it after pairing).
    final ctx = tvContext()..setTrustedCertificatesBytes(utf8.encode(client.certificatePem));
    final server = await SecureServerSocket.bind(InternetAddress.loopbackIPv4, 0, ctx, requestClientCertificate: true);
    server.listen((s) {
      final d = FrameDecoder();
      onConnect(s, s.expand(d.add).asBroadcastStream());
    });
    return server;
  }

  Uint8List polo(int field, ProtoWriter body) =>
      (ProtoWriter()
            ..varint(1, 2, always: true)
            ..varint(2, 200, always: true)
            ..message(field, body))
          .toBytes();

  test('client certificate is presented and pairing completes over TLS', () async {
    RsaPublicKey? seenClientKey;
    final server = await startTv((s, fromClient) {
      seenClientKey = rsaPublicKeyFromCertificate(s.peerCertificate!.der);
      fromClient.listen((msg) {
        final m = ProtoMessage.decode(msg);
        if (m.has(10)) s.add(encodeFrame(polo(11, ProtoWriter()..string(1, 'Fake TV'))));
        if (m.has(20)) s.add(encodeFrame(msg)); // echo options
        if (m.has(30)) s.add(encodeFrame(polo(31, ProtoWriter())));
        if (m.has(40)) s.add(encodeFrame(polo(41, ProtoWriter()..bytes(1, [1], always: true))));
      });
    });
    addTearDown(server.close);

    final socket = await connectTls('127.0.0.1', server.port, client);
    final serverKey = rsaPublicKeyFromCertificate(socket.peerCertificate!.der);
    expect(serverKey.modulus, tv.publicKey.modulus);

    final session = PairingSession(
      channel: SocketMessageChannel(socket),
      clientName: 'test',
      clientKey: client.publicKey,
      serverKey: serverKey,
    );
    await session.start();
    expect(seenClientKey!.modulus, client.publicKey.modulus);

    // Exactly one checksum byte matches a given suffix — find it like the TV would display it.
    final code = [for (var b = 0; b < 256; b++) '${b.toRadixString(16).padLeft(2, '0')}0A0B'].firstWhere((c) {
      try {
        computePairingSecret(client: client.publicKey, server: serverKey, code: c);
        return true;
      } on PairingCodeException {
        return false;
      }
    });
    await session.finish(code);
    await session.close();
  });

  test('remote session runs over TLS and reports TV state', () async {
    final fromClientMsgs = StreamController<Uint8List>();
    final server = await startTv((s, fromClient) {
      fromClient.listen(fromClientMsgs.add);
      s.add(encodeFrame(RemoteOut.configureReply(RemoteFeature.all))); // same shape as the TV's configure
      s.add(encodeFrame((ProtoWriter()..message(40, ProtoWriter()..boolean(1, true))).toBytes()));
    });
    addTearDown(server.close);

    final socket = await connectTls('127.0.0.1', server.port, client);
    final session = RemoteSession(channel: SocketMessageChannel(socket));
    await session.ready.timeout(const Duration(seconds: 5));
    expect(session.isOn, isTrue);
    session.sendKey(26);
    final msgs = await fromClientMsgs.stream.take(2).toList();
    expect(ProtoMessage.decode(msgs[0]).has(1), isTrue, reason: 'configure reply first');
    expect(ProtoMessage.decode(msgs[1]).message(10)!.int32(1), 26);
    await session.close();
  });

  test('a TV that rejects our certificate is reported as "needs pairing"', () async {
    final ctx = tvContext()..setTrustedCertificatesBytes(utf8.encode(tv.certificatePem));
    final server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      ctx,
      requestClientCertificate: true,
      requireClientCertificate: true,
    );
    addTearDown(server.close);
    server.listen((_) {}, onError: (_) {});

    Object? failure;
    RemoteSession? session;
    try {
      final socket = await connectTls('127.0.0.1', server.port, client);
      session = RemoteSession(channel: SocketMessageChannel(socket));
      await session.ready.timeout(const Duration(seconds: 5));
    } on Object catch (e) {
      failure = e;
    }
    final kind = classifyConnectFailure(failure, receivedMessage: session?.receivedMessage ?? false);
    expect(kind, isNot(ConnectFailure.unreachable), reason: '$failure');
  });
}
