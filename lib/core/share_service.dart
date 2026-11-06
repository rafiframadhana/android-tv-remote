import 'dart:async';
import 'dart:math';

import 'package:bonsoir/bonsoir.dart';

import 'device_store.dart';
import 'identity_store.dart';
import 'share_link.dart';

/// Wi-Fi side of pairing sharing (see share_link.dart): while the app is open, announces the TVs
/// this phone can pair, and finds another phone that uses a given TV.
class ShareService {
  ShareService({required this.devices, required this.identity});

  final DeviceStore devices;
  final IdentityStore identity;

  /// Unique per app run, so a phone never tries to join itself.
  final String instanceName = 'TV Remote ${Random.secure().nextInt(1 << 32).toRadixString(36)}';

  ShareHost? _host;
  BonsoirBroadcast? _broadcast;
  String _advertised = '';
  bool _running = false;

  ShareHost _newHost() => ShareHost(
    findTv: (id) => devices.tvs.where((t) => t.pins.isNotEmpty && tvShareId(t.pins.first) == id).firstOrNull,
    identityForTv: identity.forTv,
  );

  /// Start offering this phone's TVs (call when the app comes to the foreground).
  Future<void> start() async {
    if (_running) return;
    _running = true;
    try {
      final host = _host ??= _newHost();
      await host.start(await identity.identity);
      devices.addListener(_readvertise);
      await _readvertise();
    } on Object {
      _running = false; // Offering is best-effort: pairing still works without it.
    }
  }

  /// Stop offering (app went to the background).
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    devices.removeListener(_readvertise);
    await _stopBroadcast();
    await _host?.stop();
  }

  Future<void> _readvertise() async {
    if (!_running) return;
    final ids = {
      for (final t in devices.tvs)
        if (t.pins.isNotEmpty) tvShareId(t.pins.first),
    }.join(',');
    if (ids == _advertised && _broadcast != null) return;
    await _stopBroadcast();
    _advertised = ids;
    final port = _host?.port;
    if (ids.isEmpty || port == null) return;
    try {
      final b = _broadcast = BonsoirBroadcast(
        service: BonsoirService(name: instanceName, type: shareServiceType, port: port, attributes: {'tvs': ids}),
      );
      await b.initialize();
      await b.start();
    } on Object {
      _broadcast = null;
    }
  }

  Future<void> _stopBroadcast() async {
    final b = _broadcast;
    _broadcast = null;
    try {
      await b?.stop();
    } on Object {
      // already stopped
    }
  }

  /// Looks for another phone on the Wi-Fi that offers the TV with share id [tvId].
  Future<({String address, int port})?> findPhoneFor(
    String tvId, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final found = Completer<({String address, int port})?>();
    final discovery = BonsoirDiscovery(type: shareServiceType);
    StreamSubscription<BonsoirDiscoveryEvent>? sub;
    try {
      await discovery.initialize();
      sub = discovery.eventStream?.listen((event) {
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent(:final service):
            if (service.name != instanceName) service.resolve(discovery.serviceResolver);
          case BonsoirDiscoveryServiceResolvedEvent(:final service):
            final offered = (service.attributes['tvs'] ?? '').split(',');
            final address = service.hostAddresses.where((a) => !a.contains(':')).firstOrNull ?? service.hostAddress;
            if (service.name != instanceName && offered.contains(tvId) && address != null && !found.isCompleted) {
              found.complete((address: address, port: service.port));
            }
          default:
            break;
        }
      });
      await discovery.start();
      return await found.future.timeout(timeout, onTimeout: () => null);
    } on Object {
      return null;
    } finally {
      await sub?.cancel();
      try {
        await discovery.stop();
      } on Object {
        // already stopped
      }
    }
  }
}
