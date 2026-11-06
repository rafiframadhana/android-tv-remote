import 'dart:isolate';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'certificate.dart';
import 'saved_tv.dart';
import 'tls.dart';

/// Loads the app's client identity from secure storage, creating it on first use.
/// TVs remember this certificate after pairing, so it must survive app restarts.
class IdentityStore {
  IdentityStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  static const _certKey = 'client_cert_pem';
  static const _keyKey = 'client_key_pem';

  final FlutterSecureStorage _storage;
  Future<ClientIdentity>? _identity;

  Future<ClientIdentity> get identity => _identity ??= _load().catchError((Object e) {
    _identity = null; // allow retry
    throw e;
  });

  Future<ClientIdentity> _load() async {
    final cert = await _storage.read(key: _certKey);
    final key = await _storage.read(key: _keyKey);
    if (cert != null && key != null) {
      try {
        final stored = ClientIdentity(certificatePem: cert, privateKeyPem: key);
        stored.securityContext; // Parse the key now, not on first connect.
        return stored;
      } on Object {
        // Corrupted entry: a fresh identity (TVs ask to pair again) beats a dead app.
      }
    }
    final generated = await Isolate.run(generateClientCertificate);
    await _storage.write(key: _keyKey, value: generated.privateKeyPem);
    await _storage.write(key: _certKey, value: generated.certificatePem);
    return ClientIdentity(certificatePem: generated.certificatePem, privateKeyPem: generated.privateKeyPem);
  }

  // ---- Pairings shared from another phone (see core/pairing_share.dart).
  // Stored per TV under the TV's certificate pin, which survives IP-address changes.

  static String _sharedKey(SavedTv tv, String part) => 'shared_${tv.pins.first}_$part';

  /// The identity to use for [tv]: a pairing shared from another phone, else this phone's own.
  Future<ClientIdentity> forTv(SavedTv tv) async {
    if (tv.pins.isNotEmpty) {
      final cert = await _storage.read(key: _sharedKey(tv, 'cert'));
      final key = await _storage.read(key: _sharedKey(tv, 'key'));
      if (cert != null && key != null) {
        try {
          return ClientIdentity(certificatePem: cert, privateKeyPem: key);
        } on Object {
          await removeShared(tv);
        }
      }
    }
    return identity;
  }

  Future<void> saveShared(SavedTv tv, ClientIdentity id) async {
    await _storage.write(key: _sharedKey(tv, 'key'), value: id.privateKeyPem);
    await _storage.write(key: _sharedKey(tv, 'cert'), value: id.certificatePem);
  }

  /// After pairing this phone itself (or forgetting the TV), drop any shared pairing.
  Future<void> removeShared(SavedTv tv) async {
    if (tv.pins.isEmpty) return;
    await _storage.delete(key: _sharedKey(tv, 'key'));
    await _storage.delete(key: _sharedKey(tv, 'cert'));
  }
}
