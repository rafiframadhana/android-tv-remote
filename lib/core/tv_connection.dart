import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../protocol/remote_messages.dart';
import '../protocol/remote_session.dart';
import 'device_store.dart';
import 'pinning.dart';
import 'tls.dart';

enum TvStatus {
  connecting,
  connected,
  needsPairing,
  unreachable,

  /// The device at this address presented a different certificate than the paired TV.
  /// Nothing was sent to it. Either it isn't our TV, or the TV was reset: pair again.
  identityChanged,
}

/// Keeps a live remote session to one TV, reconnecting with backoff
/// (0.1 s → 30 s, like androidtvremote2) until stopped.
class TvConnection extends ChangeNotifier {
  TvConnection({required SavedTv tv, required this.identity, this.onTvChanged, this.onConnected}) : _current = tv;

  final ClientIdentity identity;

  /// Called when the TV's stored record changes (certificate pins recorded) and must be saved.
  final void Function(SavedTv tv)? onTvChanged;

  /// Called after each verified, ready connection.
  final void Function(SavedTv tv)? onConnected;

  SavedTv _current;
  SavedTv get tv => _current;

  TvStatus _status = TvStatus.connecting;
  TvStatus get status => _status;

  RemoteSession? _session;
  StreamSubscription<void>? _changesSub;
  bool _active = false;
  int _generation = 0;
  Completer<void>? _wake;

  bool get isConnected => _status == TvStatus.connected && _session != null;
  bool get isOn => _session?.isOn ?? false;
  String get currentApp => _session?.currentApp ?? '';
  int? get volumeLevel => _session?.volumeLevel;
  int? get volumeMax => _session?.volumeMax;
  bool get muted => _session?.muted ?? false;
  bool get voiceSupported => _session?.voiceSupported ?? false;

  void start() {
    if (_active) return;
    _active = true;
    unawaited(_run(++_generation));
  }

  /// Retry right now (user tapped "Retry", or the app came back to the foreground).
  void retryNow() {
    if (!_active) return start();
    _wakeUp();
  }

  Future<void> stop() async {
    _active = false;
    _generation++;
    _wakeUp();
    await _closeSession();
    // Don't show "Connected" (or enable keys) while a later start() is reconnecting.
    _set(TvStatus.connecting);
  }

  void _wakeUp() {
    final w = _wake;
    if (w != null && !w.isCompleted) w.complete();
  }

  void sendKey(int keyCode, [KeyDirection direction = KeyDirection.short]) {
    if (isConnected) _session?.sendKey(keyCode, direction);
  }

  void sendText(String text) {
    if (isConnected) _session?.sendText(text);
  }

  void launchApp(String link) {
    if (isConnected) _session?.launchApp(link);
  }

  Future<VoiceStream> startVoice() {
    final s = _session;
    if (s == null || !isConnected) return Future.error(StateError('Not connected'));
    return s.startVoice();
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void _set(TvStatus s) {
    if (_status == s) return;
    _status = s;
    notifyListeners();
  }

  void _halt(TvStatus s) {
    _active = false;
    _set(s);
  }

  Future<void> _run(int gen) async {
    var delay = const Duration(milliseconds: 100);
    var rejections = 0;
    bool alive() => _active && gen == _generation;

    while (alive()) {
      if (_status != TvStatus.connected) _set(TvStatus.connecting);
      RemoteSession? session;
      Object? failure;
      try {
        final socket = await connectTls(_current.host, remotePort, identity);
        if (!alive()) {
          socket.destroy();
          return;
        }
        // Verify the TV's identity before sending a single byte to it.
        final cert = socket.peerCertificate;
        final pin = cert == null ? null : checkPin(_current, certificateFingerprint(cert));
        if (pin == null || pin.result == PinResult.mismatch) {
          socket.destroy();
          _halt(TvStatus.identityChanged);
          return;
        }
        if (pin.updated case final updated?) {
          _current = updated;
          onTvChanged?.call(updated);
        }
        session = RemoteSession(channel: SocketMessageChannel(socket));
        _session = session;
        _changesSub = session.changes.listen((_) => notifyListeners());
        await session.ready.timeout(const Duration(seconds: 10));
        // A key sent the instant the TV reports ready can be dropped (seen on a Panasonic
        // Android TV: mute ignored at t=0, reliable from 150 ms). Enable keys a moment later.
        await Future<void>.delayed(const Duration(milliseconds: 300));
        if (!alive()) continue;
        rejections = 0;
        delay = const Duration(milliseconds: 100);
        _set(TvStatus.connected);
        onConnected?.call(_current);
        failure = await session.done;
      } on Object catch (e) {
        failure = e;
      }
      final received = session?.receivedMessage ?? false;
      await _closeSession();
      if (!alive()) return;

      switch (classifyConnectFailure(failure, receivedMessage: received)) {
        case ConnectFailure.probablyRejected:
          // Twice in a row → the TV no longer accepts our certificate. Once may be a
          // handshake cut short by a reboot or Wi-Fi drop.
          if (++rejections >= 2) {
            _halt(TvStatus.needsPairing);
            return;
          }
          _set(TvStatus.connecting);
        case ConnectFailure.unreachable:
          rejections = 0;
          _set(failure is SocketException || failure is TimeoutException ? TvStatus.unreachable : TvStatus.connecting);
      }

      final wake = _wake = Completer<void>();
      await Future.any([Future<void>.delayed(delay), wake.future]);
      _wake = null;
      delay = delay * 2 > const Duration(seconds: 30) ? const Duration(seconds: 30) : delay * 2;
    }
  }

  Future<void> _closeSession() async {
    await _changesSub?.cancel();
    _changesSub = null;
    final s = _session;
    _session = null;
    if (s != null && !s.isClosed) await s.close();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
