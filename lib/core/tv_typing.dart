import 'dart:async';

import '../protocol/key_codes.dart';

/// What [TvTyping] needs from the TV connection.
abstract interface class TypingTarget {
  String get currentApp;
  bool get textFieldActive;
  void sendText(String text);
  void appendText(int at, String suffix);
  void sendKey(int keyCode);
  void launchApp(String link);
}

/// Turns what the user types on the phone into edits on the TV.
///
/// Most apps report their focused text box, and the box is mirrored exactly
/// (`RemoteSession.sendText`).
///
/// YouTube draws its own keyboard and reports nothing. It does take typed text into its search box
/// (from anywhere in the app except its side menu), but every deletion becomes a Backspace, and an
/// empty box treats Backspace as Back, which leaves the search or the app (verified on a Panasonic
/// Android TV). So for YouTube:
/// - the first keystroke opens the search for the phone's text through YouTube's search link,
///   which also replaces whatever was in the box before;
/// - adding letters at the end types just those letters;
/// - any other change (delete, clear, edit in the middle) sets the whole box through the link
///   again, after a short pause so a burst of deletions becomes one update;
/// - Enter opens the results through the link, with focus on the first video.
class TvTyping {
  TvTyping(
    this._tv, {
    this.settle = const Duration(milliseconds: 1500),
    this.resync = const Duration(milliseconds: 700),
    this.nudgeSettle = const Duration(milliseconds: 500),
  });

  final TypingTarget _tv;

  /// How long YouTube takes to show a search link; typing waits for it.
  final Duration settle;

  /// Pause before a deletion is sent as a new search link.
  final Duration resync;

  /// Pause after moving focus out of YouTube's side menu.
  final Duration nudgeSettle;

  static const youtube = 'com.google.android.youtube.tv';

  static String youtubeSearch(String query) =>
      'https://www.youtube.com/results?search_query=${Uri.encodeQueryComponent(query)}';

  /// YouTube's box content as far as we know: null until our first search link.
  String? _box;
  String _latest = '';
  bool _settling = false;
  bool _nudged = false;
  Timer? _settleTimer;
  Timer? _resyncTimer;

  /// YouTube is in front and hasn't reported a text box.
  bool get youtubeMode => !_tv.textFieldActive && _tv.currentApp == youtube;

  void changed(String text) {
    _latest = text;
    if (!youtubeMode) {
      _tv.sendText(text);
      return;
    }
    if (_settling) return; // sent once YouTube has shown the last link
    final box = _box;
    if (box == null) {
      _setBox(text);
      return;
    }
    if (text.startsWith(box)) {
      _resyncTimer?.cancel();
      if (text.length > box.length) {
        _tv.appendText(box.length, text.substring(box.length));
        _box = text;
      }
      return;
    }
    _resyncTimer?.cancel();
    _resyncTimer = Timer(resync, () => _setBox(_latest));
  }

  /// Enter, with [text] the phone box's content.
  void submit(String text) {
    _latest = text;
    if (!youtubeMode) {
      _tv.sendKey(Keys.enter);
      return;
    }
    _resyncTimer?.cancel();
    _setBox(_latest);
  }

  void _setBox(String text) {
    _resyncTimer?.cancel();
    _tv.launchApp(youtubeSearch(text));
    _box = text;
    _settling = true;
    final nudge = !_nudged;
    _nudged = true;
    _settleTimer?.cancel();
    _settleTimer = Timer(settle, () {
      if (!nudge) return _settled();
      // Typing is ignored while YouTube's side menu has focus, and the link doesn't move focus out
      // of it. Right moves into the content (elsewhere it just moves between results). Text sent
      // while focus is still moving is lost, so give it a moment.
      _tv.sendKey(Keys.dpadRight);
      _settleTimer = Timer(nudgeSettle, _settled);
    });
  }

  void _settled() {
    _settling = false;
    if (_latest != _box) changed(_latest);
  }

  void dispose() {
    _settleTimer?.cancel();
    // Don't drop a deletion that was waiting to be sent.
    if (_resyncTimer?.isActive ?? false) _tv.launchApp(youtubeSearch(_latest));
    _resyncTimer?.cancel();
  }
}
