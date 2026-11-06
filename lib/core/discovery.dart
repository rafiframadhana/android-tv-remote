import 'dart:async';

import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';

@immutable
class DiscoveredTv {
  const DiscoveredTv({required this.name, required this.host});
  final String name;
  final String host;
}

/// Finds TVs advertising the Android TV Remote Service (`_androidtvremote2._tcp`).
///
/// Searches in bounded scans instead of forever: a scan runs at least [minScan], keeps going
/// while TVs are still appearing (until [quietAfterLastFind] passes without a new one), and
/// never longer than [maxScan]. TVs that weren't seen again by the end of a scan are dropped.
class TvDiscovery extends ChangeNotifier {
  TvDiscovery({
    this.minScan = const Duration(seconds: 12),
    this.quietAfterLastFind = const Duration(seconds: 4),
    this.maxScan = const Duration(seconds: 30),
  });

  static const serviceType = '_androidtvremote2._tcp';

  final Duration minScan;
  final Duration quietAfterLastFind;
  final Duration maxScan;

  BonsoirDiscovery? _discovery;
  StreamSubscription<BonsoirDiscoveryEvent>? _sub;
  final Map<String, DiscoveredTv> _found = {};
  final Set<String> _seenThisScan = {};
  Timer? _timer;
  DateTime _scanStarted = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastFind = DateTime.fromMillisecondsSinceEpoch(0);
  bool _scanning = false;
  bool _disposed = false;
  String? error;

  List<DiscoveredTv> get tvs => _found.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  bool get isScanning => _scanning;

  /// Starts a scan (or restarts the minimum window of the running one). Safe to call repeatedly.
  Future<void> scan() async {
    if (_disposed) return;
    if (_scanning) {
      _scanStarted = DateTime.now();
      return;
    }
    _scanning = true;
    error = null;
    _seenThisScan.clear();
    _scanStarted = DateTime.now();
    _lastFind = _scanStarted;
    _notify();
    try {
      final d = _discovery = BonsoirDiscovery(type: serviceType);
      await d.initialize();
      _sub = d.eventStream?.listen((event) {
        switch (event) {
          case BonsoirDiscoveryServiceFoundEvent(:final service):
            service.resolve(d.serviceResolver);
          case BonsoirDiscoveryServiceResolvedEvent(:final service) ||
              BonsoirDiscoveryServiceUpdatedEvent(:final service):
            final host = service.hostAddresses.where((a) => !a.contains(':')).firstOrNull ?? service.hostAddress;
            if (host != null) {
              _seenThisScan.add(service.name);
              if (_found[service.name]?.host != host) {
                _found[service.name] = DiscoveredTv(name: service.name, host: host);
                _lastFind = DateTime.now();
                _notify();
              }
            }
          case BonsoirDiscoveryServiceLostEvent(:final service):
            if (_found.remove(service.name) != null) _notify();
          default:
            break;
        }
      });
      await d.start();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _maybeFinish());
    } on Object catch (e) {
      error = '$e';
      await _endScan(dropUnseen: false);
    }
  }

  void _maybeFinish() {
    final now = DateTime.now();
    final ranMin = now.difference(_scanStarted) >= minScan;
    final quiet = now.difference(_lastFind) >= quietAfterLastFind;
    final ranMax = now.difference(_scanStarted) >= maxScan;
    if ((ranMin && quiet) || ranMax) unawaited(_endScan(dropUnseen: true));
  }

  /// Stops scanning (e.g. the app went to the background). Results are kept.
  Future<void> stop() => _endScan(dropUnseen: false);

  Future<void> _endScan({required bool dropUnseen}) async {
    _timer?.cancel();
    _timer = null;
    final wasScanning = _scanning;
    _scanning = false;
    if (dropUnseen) _found.removeWhere((name, _) => !_seenThisScan.contains(name));
    await _sub?.cancel();
    _sub = null;
    final d = _discovery;
    _discovery = null;
    try {
      await d?.stop();
    } on Object {
      // Already stopped.
    }
    if (wasScanning) _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
