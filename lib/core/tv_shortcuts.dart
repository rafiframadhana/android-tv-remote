import 'dart:async';

import '../protocol/key_codes.dart';
import 'tv_connection.dart';

enum ShortcutResult {
  /// The TV reported the target screen.
  opened,

  /// Sent, but the TV didn't confirm (it may still have opened).
  unconfirmed,

  /// This TV can't open it from a phone.
  unsupported,
}

/// Opens Settings or the input picker in a way that works across TVs.
///
/// The standard keys (KEYCODE_SETTINGS, KEYCODE_TV_INPUT) work where the TV's remote bridge
/// supports them. Some TVs drop them before they reach the system — verified on a Panasonic /
/// Realtek Android TV 9 (Remote Service bridge: "unknown keycode of 178"; no SETTINGS mapping in
/// its virtual-remote key layout). There the shortcut falls back to navigating the classic
/// Android TV home screen's top bar, where Inputs and Settings are buttons, exactly as a person
/// would with the D-pad. The TV's foreground-app reports confirm each step.
class TvShortcuts {
  TvShortcuts(this._tv);

  final TvConnection _tv;

  /// Remembered per connection: the standard key didn't work on this TV, navigate directly.
  bool _settingsNeedsNav = false;
  bool _inputsNeedsNav = false;
  bool _busy = false;

  bool get isBusy => _busy;

  static const _classicLauncher = 'com.google.android.tvlauncher';
  static const _launchers = {
    _classicLauncher,
    'com.google.android.apps.tv.launcherx',
    'com.google.android.leanbacklauncher',
  };

  /// Top bar of the classic launcher, counted back from its right end (verified on device):
  /// … Inputs · Settings · (status button).
  static const _navStepsBackFromEnd = {_Target.settings: 1, _Target.inputs: 2};

  Future<ShortcutResult> openSettings() => _open(_Target.settings);
  Future<ShortcutResult> openInputs() => _open(_Target.inputs);

  Future<ShortcutResult> _open(_Target target) async {
    if (_busy || !_tv.isConnected) return ShortcutResult.unconfirmed;
    _busy = true;
    try {
      final needsNav = target == _Target.settings ? _settingsNeedsNav : _inputsNeedsNav;
      if (!needsNav) {
        final before = _tv.currentApp;
        _tv.sendKey(target.keyCode);
        if (await _tv.waitForApp((app) => target.matches(app, before), const Duration(milliseconds: 1500))) {
          return ShortcutResult.opened;
        }
      }
      final result = await _navigate(target);
      if (result == ShortcutResult.opened) {
        if (target == _Target.settings) {
          _settingsNeedsNav = true;
        } else {
          _inputsNeedsNav = true;
        }
      }
      return result;
    } finally {
      _busy = false;
    }
  }

  Future<ShortcutResult> _navigate(_Target target) async {
    // Go home and learn which home screen this TV has.
    _tv.sendKey(Keys.home);
    final home = await _tv.waitForApp(_launchers.contains, const Duration(milliseconds: 2500));
    if (!home || _tv.currentApp != _classicLauncher) return ShortcutResult.unsupported;
    await _pause(500);
    for (var i = 0; i < 4; i++) {
      _tv.sendKey(Keys.dpadUp); // up to the top bar
      await _pause(150);
    }
    for (var i = 0; i < 10; i++) {
      _tv.sendKey(Keys.dpadRight); // to its right end
      await _pause(120);
    }
    for (var i = 0; i < _navStepsBackFromEnd[target]!; i++) {
      _tv.sendKey(Keys.dpadLeft);
      await _pause(150);
    }
    _tv.sendKey(Keys.dpadCenter);
    final opened = await _tv.waitForApp(
      (app) => target.matches(app, _classicLauncher),
      const Duration(milliseconds: 2000),
    );
    return opened ? ShortcutResult.opened : ShortcutResult.unconfirmed;
  }

  Future<void> _pause(int ms) => Future<void>.delayed(Duration(milliseconds: ms));
}

enum _Target {
  settings(Keys.settings),
  inputs(Keys.tvInput);

  const _Target(this.keyCode);
  final int keyCode;

  /// Whether [app] (the TV's new foreground app) shows this target, given the app [before].
  bool matches(String app, String before) => switch (this) {
    // Android TV Settings, or a vendor's own settings app (e.g. com.realtek.tv.settings).
    _Target.settings => app.contains('settings'),
    // The input picker belongs to the TV app (com.android.tv on most TVs).
    _Target.inputs => app != before && app.isNotEmpty && !TvShortcuts._launchers.contains(app),
  };
}
