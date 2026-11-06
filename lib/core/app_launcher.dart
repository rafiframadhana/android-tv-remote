import '../protocol/key_codes.dart';
import '../ui/shortcuts/catalog.dart';

enum LaunchResult {
  /// The TV reported the app in front.
  opened,

  /// The link was sent but the app wasn't confirmed, and nothing says it failed (another app came to
  /// the front instead, or the shortcut has no known package).
  sent,

  /// The TV didn't open it: probably not installed.
  notOpened,

  /// No link known yet (template entry); set one in Settings → Shortcuts.
  notConfigured,

  /// Another shortcut was tapped before this one was confirmed.
  superseded,
}

/// What [AppLauncher] needs from the TV connection.
abstract interface class LaunchTarget {
  bool get isConnected;
  String get currentApp;

  /// Error replies the TV has sent on this connection.
  int get errorReplies;
  void launchApp(String link);
  void sendKey(int keyCode);

  /// Completes with the first non-null [check] result, re-checked on every TV update, or null when
  /// [timeout] passes.
  Future<T?> waitFor<T extends Object>(T? Function() check, Duration timeout);
}

/// Opens a shortcut's app on the TV and confirms it from the TV's foreground-app reports.
///
/// Measured on a Panasonic Android TV, from a cold start, the TV reports the app 4–6 s after the
/// link (YouTube 4.1 s, Netflix 4.5 s, BitTV 5.9 s) and up to 8 s for Stremio, so a short wait
/// reports installed apps as missing. A link whose scheme no installed app handles (`spotify://`
/// without Spotify) gets an error reply right away; a web link nothing handles gets no reaction.
class AppLauncher {
  AppLauncher(this._tv);

  final LaunchTarget _tv;
  int _generation = 0;

  /// How long an app may take to start before we say it didn't open.
  static const confirmTimeout = Duration(seconds: 15);

  /// An error reply this soon after the link means nothing can open it.
  static const errorWindow = Duration(seconds: 3);

  Future<LaunchResult> open(TvShortcut s) async {
    if (!_tv.isConnected) return LaunchResult.sent;
    final gen = ++_generation;
    final LaunchResult result;
    if (s.link.isNotEmpty) {
      result = await _openLink(s);
    } else if (s.storeFallback && s.package.isNotEmpty) {
      result = await _openViaStore(s);
    } else {
      return LaunchResult.notConfigured;
    }
    return gen == _generation ? result : LaunchResult.superseded;
  }

  Future<LaunchResult> _openLink(TvShortcut s) async {
    final before = _tv.currentApp;
    final errors = _tv.errorReplies;
    _tv.launchApp(s.link);
    if (s.package.isEmpty) return LaunchResult.sent;
    final early = await _tv.waitFor(
      () => s.matchesPackage(_tv.currentApp)
          ? LaunchResult.opened
          : (_tv.errorReplies > errors ? LaunchResult.notOpened : null),
      errorWindow,
    );
    if (early != null) return early;
    if (await _waitForApp(s, confirmTimeout - errorWindow)) return LaunchResult.opened;
    // Not confirmed. If something else came to the front (a web link opened elsewhere, or the user
    // moved on), don't claim it failed.
    return _tv.currentApp == before ? LaunchResult.notOpened : LaunchResult.sent;
  }

  /// For apps with no link: open the app's Play Store page, where the focused button is
  /// "Open" when the app is installed, and press it.
  Future<LaunchResult> _openViaStore(TvShortcut s) async {
    _tv.launchApp('https://play.google.com/store/apps/details?id=${s.package}');
    final inStore = await _tv.waitFor(() => _tv.currentApp == 'com.android.vending' ? true : null, confirmTimeout);
    if (inStore == null) return LaunchResult.notOpened;
    await Future<void>.delayed(const Duration(milliseconds: 1500)); // let the page and its buttons load
    _tv.sendKey(Keys.dpadCenter);
    return await _waitForApp(s, confirmTimeout) ? LaunchResult.opened : LaunchResult.notOpened;
  }

  Future<bool> _waitForApp(TvShortcut s, Duration timeout) async =>
      await _tv.waitFor(() => s.matchesPackage(_tv.currentApp) ? true : null, timeout) ?? false;
}
