import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_launcher.dart';
import '../core/device_store.dart';
import '../core/key_presser.dart';
import '../core/tv_connection.dart';
import '../core/tv_shortcuts.dart';
import '../core/voice_capture.dart';
import '../protocol/key_codes.dart';
import 'shortcuts/catalog.dart';
import 'shortcuts/shortcut_tile.dart';
import 'app_scope.dart';
import 'keyboard_sheet.dart';
import 'more_keys_sheet.dart';
import 'pairing_sheet.dart';
import 'theme.dart';
import 'widgets/dpad.dart';
import 'widgets/remote_key.dart';
import 'widgets/rocker.dart';

class RemoteScreen extends StatefulWidget {
  const RemoteScreen({super.key, required this.tv});
  final SavedTv tv;

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  /// The stored record of this TV (its saved address and certificate pins).
  late SavedTv _tv = widget.tv;
  TvConnection? _connection;
  TvShortcuts? _shortcuts;
  AppLauncher? _launcher;

  /// Id of the app being opened (shows a spinner on its tile).
  String? _launching;
  late final AppLifecycleListener _lifecycle;
  late final AppServices _services;
  final _voice = VoiceCapture();
  bool _touchpad = false;
  bool _listening = false;
  bool _identityFailed = false;

  /// A new address seen in discovery for this TV's name, being tried. It is only saved after
  /// a connection there presents the pinned certificate — a name in mDNS proves nothing.
  String? _tryingHost;
  final _rejectedHosts = <String>{};

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => _connection?.retryNow(),
      onHide: () {
        // The TV drops idle connections anyway; release the socket and the mic while hidden.
        _stopVoice();
        _connection?.stop();
      },
      onShow: () => _connection?.start(),
    );
    _services = AppScope.of(context);
    _services.discovery.addListener(_followIpChange);
    _connect();
  }

  Future<void> _connect({String? host}) async {
    final old = _connection;
    _connection = null;
    old?.removeListener(_watchTriedHost);
    old?.removeListener(_watchTvKeyboard);
    old?.dispose();
    try {
      final identity = await _services.identity.forTv(_tv);
      if (!mounted) return;
      final c =
          TvConnection(
              tv: host == null ? _tv : _tv.copyWith(host: host),
              identity: identity,
              onTvChanged: _save,
              onConnected: _save,
            )
            ..addListener(_watchTriedHost)
            ..addListener(_watchTvKeyboard);
      c.start();
      setState(() {
        _connection = c;
        _shortcuts = TvShortcuts(c);
        _launcher = AppLauncher(c);
        _identityFailed = false;
      });
    } on Object {
      if (mounted) setState(() => _identityFailed = true);
    }
  }

  /// Persists a verified record: new pins, or the address of a verified new-host connection.
  void _save(SavedTv tv) {
    if (tv.host != _tv.host && tv.host != _tryingHost) return; // stale connection
    final unchanged = tv.host == _tv.host && tv.remoteVerified == _tv.remoteVerified && listEquals(tv.pins, _tv.pins);
    if (unchanged) return;
    final oldHost = _tv.host;
    _tv = tv;
    if (tv.host == _tryingHost) _tryingHost = null;
    unawaited(_services.devices.replace(oldHost, tv));
  }

  /// Looks for the TV on the network when it can't be reached (it may have a new address), and
  /// goes back to the saved address when a tried new one didn't turn out to be our TV.
  void _watchTriedHost() {
    final tried = _tryingHost;
    final status = _connection?.status;
    if (tried == null && status == TvStatus.unreachable) unawaited(_services.discovery.scan());
    // The TV forgot this phone (another phone paired, TV reset…): ask for the code right away
    // instead of leaving the user on a dead remote. Once per visit; the banner stays as backup.
    if (tried == null && status == TvStatus.needsPairing && !_autoPairOffered) {
      _autoPairOffered = true;
      scheduleMicrotask(() {
        if (mounted) _pairAgain(forgotten: true);
      });
    }
    if (tried == null || status == null || status == TvStatus.connecting || status == TvStatus.connected) return;
    _rejectedHosts.add(tried);
    _tryingHost = null;
    // Not from inside the connection's own notification: _connect() disposes it.
    scheduleMicrotask(_connect);
  }

  /// DHCP may give the TV a new address: try it when discovery shows our TV's name elsewhere.
  void _followIpChange() {
    if (!mounted || _tryingHost != null) return;
    // Only a TV with a verified pin can be followed safely (the pin is what proves identity).
    if (_tv.pins.isEmpty || !_tv.remoteVerified) return;
    if (_connection?.status == TvStatus.connected) return;
    final found = _services.discovery.tvs.where((d) => d.name == _tv.name).firstOrNull;
    if (found == null || found.host == _tv.host || _rejectedHosts.contains(found.host)) return;
    _tryingHost = found.host;
    _connect(host: found.host);
  }

  /// A keyboard sheet is showing (opened by the user or by a TV text box).
  bool _keyboardOpen = false;
  bool _tvFieldWasActive = false;

  /// Live keyboard: when a text box opens on the TV, open the phone keyboard on it.
  void _watchTvKeyboard() {
    final c = _connection;
    if (c == null) return;
    final active = c.textFieldActive;
    final opened = active && !_tvFieldWasActive;
    _tvFieldWasActive = active;
    if (!opened || _keyboardOpen || _pairingOpen) return;
    // Wait a moment: leaving a screen can report "box open" and "box closed" back to back.
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      if (mounted && identical(c, _connection) && !_keyboardOpen && !_pairingOpen && c.textFieldActive) {
        _openKeyboard(c, auto: true);
      }
    });
  }

  Future<void> _openKeyboard(TvConnection c, {bool auto = false}) async {
    if (_keyboardOpen) return;
    _keyboardOpen = true;
    try {
      await showKeyboardSheet(context, c, auto: auto);
    } finally {
      _keyboardOpen = false;
    }
  }

  /// Whether the pairing sheet already opened by itself during this visit.
  bool _autoPairOffered = false;
  bool _pairingOpen = false;

  Future<void> _pairAgain({bool forgotten = false}) async {
    if (_pairingOpen) return;
    _pairingOpen = true;
    try {
      final tv = await showPairingSheet(context, host: _tv.host, name: _tv.name, forgotten: forgotten);
      if (tv != null && mounted) {
        _tv = tv;
        _tryingHost = null;
        _autoPairOffered = false; // paired again; if it is forgotten again later, ask again
        _connect();
      }
    } finally {
      _pairingOpen = false;
    }
  }

  /// Settings and Input: standard key first, home-screen navigation where the TV ignores it.
  Future<void> _runShortcut(String what, Future<ShortcutResult> Function(TvShortcuts s) open) async {
    final s = _shortcuts;
    if (s == null || s.isBusy) return;
    HapticFeedback.selectionClick();
    final result = await open(s);
    if (!mounted || result != ShortcutResult.unsupported) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("This TV doesn't let phones open $what. Use the TV's own remote for this one.")),
    );
  }

  Future<void> _startVoice() async {
    final c = _connection;
    if (c == null || !c.isConnected) return;
    HapticFeedback.mediumImpact();
    setState(() => _listening = true);
    try {
      await _voice.start(c);
    } on VoiceException catch (e) {
      if (mounted) {
        setState(() => _listening = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  Future<void> _stopVoice() async {
    if (_listening && mounted) setState(() => _listening = false);
    await _voice.stop();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _services.discovery.removeListener(_followIpChange);
    _voice.dispose();
    _connection?.removeListener(_watchTriedHost);
    _connection?.removeListener(_watchTvKeyboard);
    _connection?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _connection;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(title: Text(_tv.name)),
        body: Center(
          child: _identityFailed
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Couldn't set up this phone's security key."),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _connect, child: const Text('Try again')),
                  ],
                )
              : const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Preparing this phone…')],
                ),
        ),
      );
    }
    return RemoteScope(
      connection: c,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: _Header(tv: _tv),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: RemoteKey(
                keyCode: Keys.power,
                label: 'Power',
                icon: Icons.power_settings_new_rounded,
                color: context.palette.power,
                width: 48,
                height: 48,
                circle: true,
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              _StatusBanner(onPair: _pairAgain),
              Expanded(
                child: ListenableBuilder(
                  listenable: c, // keyboard/app keys and the volume label follow connection state
                  builder: (context, _) => LayoutBuilder(
                    builder: (context, box) {
                      final pad = (box.maxWidth - 80).clamp(200.0, 280.0);
                      return SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Column(
                          children: [
                            _topRow(c),
                            const SizedBox(height: 20),
                            SizedBox(
                              height: pad,
                              child: Center(
                                child: _touchpad ? Touchpad(size: pad) : DPad(size: pad),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _padToggle(),
                            const SizedBox(height: 16),
                            _navRow(),
                            const SizedBox(height: 20),
                            _volumeRow(c),
                            const SizedBox(height: 20),
                            _mediaRow(),
                            const SizedBox(height: 24),
                            _appsGrid(c),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topRow(TvConnection c) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      _ActionKey(
        label: 'Input',
        icon: Icons.input_rounded,
        onTap: c.isConnected ? () => _runShortcut('the input list', (s) => s.openInputs()) : null,
      ),
      _ActionKey(
        label: 'Settings',
        icon: Icons.settings_outlined,
        onTap: c.isConnected ? () => _runShortcut('Settings', (s) => s.openSettings()) : null,
      ),
      _ActionKey(
        label: 'Keyboard',
        icon: Icons.keyboard_outlined,
        onTap: c.isConnected ? () => _openKeyboard(c) : null,
      ),
      _ActionKey(
        label: 'More keys',
        icon: Icons.dialpad_rounded,
        onTap: c.isConnected ? () => showMoreKeysSheet(context, c) : null,
      ),
    ],
  );

  Widget _padToggle() => SegmentedButton<bool>(
    showSelectedIcon: false,
    style: SegmentedButton.styleFrom(
      visualDensity: VisualDensity.compact,
      selectedBackgroundColor: context.palette.keyPressed,
      selectedForegroundColor: context.palette.led,
      foregroundColor: context.palette.muted,
      side: BorderSide(color: context.palette.keyEdge),
    ),
    segments: const [
      ButtonSegment(value: false, label: Text('D-pad')),
      ButtonSegment(value: true, label: Text('Touchpad')),
    ],
    selected: {_touchpad},
    onSelectionChanged: (s) => setState(() => _touchpad = s.first),
  );

  Widget _navRow() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      const RemoteKey(keyCode: Keys.back, label: 'Back', icon: Icons.arrow_back_rounded, width: 80),
      const RemoteKey(keyCode: Keys.home, label: 'Home', icon: Icons.home_outlined, width: 80),
      _MicKey(listening: _listening, onDown: _startVoice, onUp: _stopVoice),
    ],
  );

  Widget _volumeRow(TvConnection c) {
    final level = c.volumeLevel;
    final max = c.volumeMax;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Rocker(
          upCode: Keys.volumeUp,
          downCode: Keys.volumeDown,
          upIcon: Icons.add_rounded,
          downIcon: Icons.remove_rounded,
          legend: 'Vol',
          upLabel: 'Volume up',
          downLabel: 'Volume down',
        ),
        Column(
          children: [
            RemoteKey(
              keyCode: Keys.volumeMute,
              label: c.muted ? 'Unmute' : 'Mute',
              icon: c.muted ? Icons.volume_off_rounded : Icons.volume_mute_rounded,
              color: c.muted ? context.palette.led : null,
              width: 80,
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 18,
              child: level != null && max != null && max > 0
                  ? Text(c.muted ? 'Muted' : 'Volume $level', style: Theme.of(context).textTheme.bodySmall)
                  : null,
            ),
          ],
        ),
        const Rocker(
          upCode: Keys.channelUp,
          downCode: Keys.channelDown,
          upIcon: Icons.keyboard_arrow_up_rounded,
          downIcon: Icons.keyboard_arrow_down_rounded,
          legend: 'CH',
          upLabel: 'Channel up',
          downLabel: 'Channel down',
        ),
      ],
    );
  }

  Widget _mediaRow() => const Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      RemoteKey(keyCode: Keys.mediaRewind, label: 'Rewind', icon: Icons.fast_rewind_rounded, mode: PressMode.repeat),
      RemoteKey(keyCode: Keys.mediaPlayPause, label: 'Play or pause', icon: Icons.pause_rounded),
      RemoteKey(
        keyCode: Keys.mediaFastForward,
        label: 'Fast forward',
        icon: Icons.fast_forward_rounded,
        mode: PressMode.repeat,
      ),
    ],
  );

  /// The user's app shortcuts (Settings → Shortcuts), as a grid that grows with them.
  Widget _appsGrid(TvConnection c) => ListenableBuilder(
    listenable: _services.settings,
    builder: (context, _) {
      final apps = _services.settings.enabledShortcuts;
      if (apps.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'No app shortcuts. Add some in Settings → Shortcuts.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      }
      return Wrap(
        spacing: 6,
        runSpacing: 4,
        alignment: WrapAlignment.center,
        children: [
          for (final app in apps)
            ShortcutButton(
              shortcut: app,
              busy: _launching == app.id,
              onTap: c.isConnected ? () => _openApp(app) : null,
            ),
        ],
      );
    },
  );

  Future<void> _openApp(TvShortcut app) async {
    final launcher = _launcher;
    if (launcher == null) return;
    HapticFeedback.selectionClick();
    // Another tap while one app is still starting replaces it (the launcher drops the older wait).
    setState(() => _launching = app.id);
    final result = await launcher.open(app);
    if (!mounted) return;
    if (_launching == app.id) setState(() => _launching = null);
    final message = switch (result) {
      LaunchResult.notOpened => "${app.name} didn't open. It may not be installed on this TV.",
      LaunchResult.notConfigured => "${app.name} isn't set up yet. Add its link in Settings → Shortcuts.",
      LaunchResult.opened || LaunchResult.sent || LaunchResult.superseded => null,
    };
    if (message != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.tv});
  final SavedTv tv;

  @override
  Widget build(BuildContext context) {
    final c = RemoteScope.of(context);
    final (color, text) = switch (c.status) {
      TvStatus.connected when !c.isOn => (context.palette.muted, 'Screen off'),
      TvStatus.connected => (context.palette.ok, c.currentApp.isEmpty ? 'Connected' : appNameFor(c.currentApp)),
      TvStatus.connecting => (context.palette.led, 'Connecting'),
      TvStatus.unreachable => (context.palette.power, 'Not reachable'),
      TvStatus.needsPairing => (context.palette.power, 'Needs pairing'),
      TvStatus.identityChanged => (context.palette.power, 'Not verified'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tv.name, style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.onPair});
  final VoidCallback onPair;

  @override
  Widget build(BuildContext context) {
    final c = RemoteScope.of(context);
    final (String? message, String? action, VoidCallback? onAction) = switch (c.status) {
      TvStatus.needsPairing => (
        'The TV no longer recognises this phone. Usually another phone or remote app was paired with it '
            'since, and some TVs remember only one. Pair again to take over.',
        'Pair again',
        onPair,
      ),
      TvStatus.identityChanged => (
        "The device at this address isn't the TV you paired, so nothing was sent to it. "
            'If you reset or replaced the TV, pair again.',
        'Pair again',
        onPair,
      ),
      TvStatus.unreachable => (
        "Can't reach the TV. If it's fully off, turn it on with its own remote once, "
            'and keep this phone on the same Wi-Fi.',
        'Retry',
        c.retryNow,
      ),
      _ => (null, null, null),
    };
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: BoxDecoration(
                color: context.palette.key,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.palette.power.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium)),
                  TextButton(onPressed: onAction, child: Text(action!)),
                ],
              ),
            ),
    );
  }
}

/// A key that opens something on the phone rather than sending a key code.
class _ActionKey extends StatelessWidget {
  const _ActionKey({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Material(
      color: context.palette.key,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: context.palette.keyEdge),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: SizedBox(
          width: 64,
          height: 56,
          child: Icon(icon, color: context.palette.text.withValues(alpha: onTap == null ? 0.4 : 1)),
        ),
      ),
    ),
  );
}

/// Hold to talk. Glows while listening.
class _MicKey extends StatelessWidget {
  const _MicKey({required this.listening, required this.onDown, required this.onUp});
  final bool listening;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    final c = RemoteScope.of(context);
    final enabled = c.isConnected && c.voiceSupported;
    return Semantics(
      button: true,
      label: 'Voice search. Hold and speak.',
      child: Listener(
        onPointerDown: enabled ? (_) => onDown() : null,
        onPointerUp: (_) => onUp(),
        onPointerCancel: (_) => onUp(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 80,
          height: 56,
          decoration: BoxDecoration(
            color: listening ? context.palette.led : context.palette.key,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: listening ? context.palette.led : context.palette.keyEdge),
            boxShadow: listening
                ? [BoxShadow(color: context.palette.led.withValues(alpha: 0.45), blurRadius: 18)]
                : null,
          ),
          child: Icon(
            Icons.mic_none_rounded,
            color: listening ? context.palette.body : context.palette.text.withValues(alpha: enabled ? 1 : 0.4),
          ),
        ),
      ),
    );
  }
}
