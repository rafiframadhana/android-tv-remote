import 'saved_tv.dart';

export 'tls.dart' show certificateFingerprint;

enum PinResult {
  /// The TV presented a pinned certificate.
  match,

  /// Accepted and recorded: no pin yet (TV paired by an older version), or the first remote
  /// connection after pairing presented a different certificate than the pairing port did.
  firstUse,

  /// The certificate differs from the pinned one: this is not the paired TV (or it was reset).
  mismatch,
}

/// Decides whether to trust the TV's certificate on the remote port.
///
/// Pairing binds both public keys into the pairing secret, so the certificate seen on the
/// pairing port is authentic; we pin it. Google's Remote Service uses the same certificate on
/// both ports (verified on Remote Service 5.99), so normally every connection is a [PinResult.match].
/// [SavedTv.remoteVerified] allows one different certificate right after pairing, so a TV
/// that uses separate certificates per port still works instead of being locked out.
({PinResult result, SavedTv? updated}) checkPin(SavedTv tv, String fingerprint) {
  if (tv.pins.isEmpty) {
    return (result: PinResult.firstUse, updated: tv.copyWith(pins: [fingerprint], remoteVerified: true));
  }
  if (tv.pins.contains(fingerprint)) {
    return (result: PinResult.match, updated: tv.remoteVerified ? null : tv.copyWith(remoteVerified: true));
  }
  if (!tv.remoteVerified) {
    return (result: PinResult.firstUse, updated: tv.copyWith(pins: [...tv.pins, fingerprint], remoteVerified: true));
  }
  return (result: PinResult.mismatch, updated: null);
}
