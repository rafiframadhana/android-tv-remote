import 'package:basic_utils/basic_utils.dart';

/// Generates a self-signed RSA-2048 certificate like androidtvremote2 does.
/// Pure Dart and slow (seconds on a phone) — run it off the UI isolate.
({String certificatePem, String privateKeyPem}) generateClientCertificate() {
  final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final privateKey = pair.privateKey as RSAPrivateKey;
  final publicKey = pair.publicKey as RSAPublicKey;
  final csr = X509Utils.generateRsaCsrPem({'CN': 'atvremote'}, privateKey, publicKey);
  final cert = X509Utils.generateSelfSignedCertificate(privateKey, csr, 365 * 10, serialNumber: '1000');
  return (certificatePem: cert, privateKeyPem: CryptoUtils.encodeRSAPrivateKeyToPemPkcs1(privateKey));
}
