import 'dart:async';
import 'dart:io';

import '../protocol/pairing_crypto.dart';
import '../protocol/pairing_session.dart';
import 'tls.dart';

/// One pairing attempt with one TV: connect → TV shows code → [submit].
class PairingFlow {
  PairingFlow._(this._session, this.tvFingerprint);

  final PairingSession _session;

  /// SHA-256 of the TV's certificate. Pairing proves it belongs to the TV (both public keys
  /// are bound into the pairing secret), so it becomes the pin for later connections.
  final String tvFingerprint;

  static const defaultClientName = 'TV Remote';

  /// Completes when the TV is showing the code.
  static Future<PairingFlow> begin(
    String host,
    ClientIdentity identity, {
    int port = pairingPort,
    String clientName = defaultClientName,
    String serviceName = 'atvremote',
  }) async {
    final SecureSocket socket;
    try {
      socket = await connectTls(host, port, identity);
    } on SocketException {
      throw PairingException("Can't reach the TV at $host. Check it's on and on the same Wi-Fi as this phone.");
    } on TlsException catch (e) {
      throw PairingException('Secure connection to the TV failed ($e).');
    } on TimeoutException {
      throw PairingException("The TV at $host didn't answer. Check it's on and on the same Wi-Fi as this phone.");
    }
    final cert = socket.peerCertificate;
    final RsaPublicKey serverKey;
    try {
      if (cert == null) throw CertificateParseException('no certificate');
      serverKey = rsaPublicKeyFromCertificate(cert.der);
    } on Object {
      socket.destroy();
      throw PairingException("This device didn't present a valid TV certificate. Is it an Android TV?");
    }
    final session = PairingSession(
      channel: SocketMessageChannel(socket),
      clientName: clientName,
      serviceName: serviceName,
      clientKey: identity.publicKey,
      serverKey: serverKey,
    );
    try {
      await session.start();
    } on Object {
      await session.close();
      rethrow;
    }
    return PairingFlow._(session, certificateFingerprint(cert));
  }

  /// The name the TV reported for itself, or empty.
  String get tvName => _session.serverName;

  /// Throws [PairingCodeException] for a typo (try again), [PairingException] if rejected.
  Future<void> submit(String code) => _session.finish(code);

  Future<void> close() => _session.close();
}
