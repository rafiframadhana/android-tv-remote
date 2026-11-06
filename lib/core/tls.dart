import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../protocol/channel.dart';
import '../protocol/framing.dart';
import '../protocol/pairing_crypto.dart';

const int pairingPort = 6467;
const int remotePort = 6466;

/// The app's self-signed client certificate, presented to every TV.
class ClientIdentity {
  ClientIdentity({required this.certificatePem, required this.privateKeyPem})
    : publicKey = rsaPublicKeyFromCertificate(pemToDer(certificatePem));

  final String certificatePem;
  final String privateKeyPem;
  final RsaPublicKey publicKey;

  late final SecurityContext securityContext = SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(certificatePem))
    ..usePrivateKeyBytes(utf8.encode(privateKeyPem));
}

/// SHA-256 (hex) of a certificate's DER encoding; the TV pin (see core/pinning.dart).
String certificateFingerprint(X509Certificate cert) => sha256.convert(cert.der).toString();

/// Opens TLS to the TV. The TV's certificate is self-signed, so the TLS layer accepts it;
/// the caller must check it against the pin recorded at pairing (core/pinning.dart)
/// before sending anything.
///
/// [timeout] covers the TCP connect; the whole handshake is bounded too, so a TV that
/// accepts the connection but never finishes TLS can't stall the reconnect loop.
Future<SecureSocket> connectTls(
  String host,
  int port,
  ClientIdentity identity, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final pending = SecureSocket.connect(
    host,
    port,
    context: identity.securityContext,
    onBadCertificate: (_) => true,
    timeout: timeout,
  );
  final socket = await pending.timeout(
    timeout + const Duration(seconds: 5),
    onTimeout: () {
      // Don't leak a socket whose handshake finishes after we gave up.
      pending.then((s) => s.destroy(), onError: (Object _) {});
      throw TimeoutException('TLS handshake with $host:$port timed out');
    },
  );
  socket.setOption(SocketOption.tcpNoDelay, true);
  return socket;
}

/// The TV's certificate fingerprint, read from a TLS handshake on the pairing port. Sends no
/// pairing request, so the TV shows nothing. Used to recognise the same TV across phones.
Future<String> fetchTvFingerprint(String host, ClientIdentity identity) async {
  final socket = await connectTls(host, pairingPort, identity);
  try {
    final cert = socket.peerCertificate;
    if (cert == null) throw const TlsException('no certificate');
    return certificateFingerprint(cert);
  } finally {
    socket.destroy();
  }
}

/// True when [error] is a TLS-level failure. That can mean the TV rejected our certificate,
/// but also a handshake cut short by a reboot or Wi-Fi drop — callers need it twice in a row.
bool isTlsFailure(Object? error) => switch (error) {
  TlsException() => true,
  ChannelClosedException(:final cause) => cause is TlsException,
  _ => false,
};

enum ConnectFailure {
  /// A TLS failure, or (TLS 1.3 rejects client certificates *after* the handshake, which
  /// dart:io reports as a plain close) the TV hung up before sending anything — it always
  /// sends remote_configure first. Repeated, this means the TV no longer knows this phone.
  probablyRejected,

  /// Network problem / TV off: retry later.
  unreachable,
}

ConnectFailure classifyConnectFailure(Object? error, {required bool receivedMessage}) {
  if (isTlsFailure(error)) return ConnectFailure.probablyRejected;
  if (!receivedMessage && error is ChannelClosedException) return ConnectFailure.probablyRejected;
  return ConnectFailure.unreachable;
}

/// [MessageChannel] over a socket with varint framing.
class SocketMessageChannel implements MessageChannel {
  SocketMessageChannel(this._socket);

  final Socket _socket;
  bool _closed = false;

  @override
  late final Stream<Uint8List> messages = _socket.transform(
    StreamTransformer<Uint8List, Uint8List>.fromBind((input) async* {
      final decoder = FrameDecoder();
      await for (final chunk in input) {
        for (final frame in decoder.add(chunk)) {
          yield frame;
        }
      }
    }),
  );

  @override
  void send(Uint8List message) {
    if (_closed) return;
    try {
      _socket.add(encodeFrame(message));
    } on Object {
      // Socket already failing; the messages stream reports the error.
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _socket.destroy();
  }
}
