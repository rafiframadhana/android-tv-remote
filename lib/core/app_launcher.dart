import '../protocol/key_codes.dart';
import '../ui/shortcuts/catalog.dart';
import 'tv_connection.dart';

enum LaunchResult {
  /// The TV reported the app in front.
  opened,

  /// The link was sent but the TV didn't confirm (custom apps without a known package).
  sent,

  /// The TV didn't open it: probably not installed.
  notOpened,

  /// No link known yet (template entry); set one in Settings → Shortcuts.
  notConfigured,
}

/// Opens a shortcut's app on the TV and confirms it from the TV's foreground-app reports.
class AppLauncher {
  AppLauncher(this._tv);

  final TvConnection _tv;
  bool _busy = false;

  static const _confirmTimeout = Duration(seconds: 4);

  Future<LaunchResult> open(TvShortcut s) async {
    if (_busy || !_tv.isConnected) return LaunchResult.sent;
    _busy = true;
    try {
      if (s.link.isNotEmpty) {
        _tv.launchApp(s.link);
        if (s.package.isEmpty) return LaunchResult.sent;
        final ok = await _tv.waitForApp(s.matchesPackage, _confirmTimeout);
        return ok ? LaunchResult.opened : LaunchResult.notOpened;
      }
      if (s.storeFallback && s.package.isNotEmpty) return await _openViaStore(s);
      return LaunchResult.notConfigured;
    } finally {
      _busy = false;
    }
  }

  /// For apps with no link: open the app's Play Store page, where the focused button is
  /// "Open" when the app is installed, and press it.
  Future<LaunchResult> _openViaStore(TvShortcut s) async {
    _tv.launchApp('https://play.google.com/store/apps/details?id=${s.package}');
    final inStore = await _tv.waitForApp((a) => a == 'com.android.vending', _confirmTimeout);
    if (!inStore) return LaunchResult.notOpened;
    await Future<void>.delayed(const Duration(milliseconds: 1500)); // let the page and its buttons load
    _tv.sendKey(Keys.dpadCenter);
    final ok = await _tv.waitForApp(s.matchesPackage, _confirmTimeout);
    return ok ? LaunchResult.opened : LaunchResult.notOpened;
  }
}
