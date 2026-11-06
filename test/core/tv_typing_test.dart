import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/tv_typing.dart';
import 'package:tv_remote/protocol/key_codes.dart';

class FakeTv implements TypingTarget {
  @override
  String currentApp = TvTyping.youtube;
  @override
  bool textFieldActive = false;
  final sent = <String>[];

  @override
  void sendText(String text) => sent.add('text:$text');
  @override
  void appendText(int at, String suffix) => sent.add('append:$at:$suffix');
  @override
  void sendKey(int keyCode) => sent.add('key:$keyCode');
  @override
  void launchApp(String link) => sent.add('link:${Uri.parse(link).queryParameters['search_query']}');
}

void main() {
  late FakeTv tv;
  setUp(() => tv = FakeTv());

  group('apps that report their text box', () {
    test('mirror the text and press Enter', () {
      tv
        ..currentApp = 'com.stremio.one'
        ..textFieldActive = true;
      final t = TvTyping(tv)
        ..changed('a')
        ..changed('')
        ..submit('');
      expect(tv.sent, ['text:a', 'text:', 'key:${Keys.enter}']);
      t.dispose();
    });

    test('YouTube too, if it ever reports one', () {
      tv.textFieldActive = true;
      TvTyping(tv).changed('a');
      expect(tv.sent, ['text:a']);
    });
  });

  group('YouTube (reports no text box)', () {
    test('first keystroke opens the search for it, then letters are appended', () {
      fakeAsync((time) {
        final t = TvTyping(tv);
        t.changed('s');
        expect(tv.sent, ['link:s']);
        t
          ..changed('sp')
          ..changed('spi'); // typed while YouTube shows the link
        time.elapse(const Duration(milliseconds: 1500));
        // Right gets focus out of YouTube's side menu, then (once focus has moved) the letters
        // typed meanwhile.
        expect(tv.sent, ['link:s', 'key:${Keys.dpadRight}']);
        t.changed('spid');
        time.elapse(const Duration(milliseconds: 500));
        expect(tv.sent, ['link:s', 'key:${Keys.dpadRight}', 'append:1:pid']);
        t.changed('spide');
        expect(tv.sent.last, 'append:4:e');
      });
    });

    test('never sends a deletion: deleting sets the box through the link after a pause', () {
      fakeAsync((time) {
        final t = TvTyping(tv)..changed('cat');
        time.elapse(const Duration(seconds: 2));
        tv.sent.clear();
        t
          ..changed('ca')
          ..changed('c');
        expect(tv.sent, isEmpty);
        time.elapse(const Duration(milliseconds: 700));
        expect(tv.sent, ['link:c']);
        time.elapse(const Duration(seconds: 2));
        t.changed('co');
        expect(tv.sent.last, 'append:1:o');
        expect(tv.sent.where((s) => s.startsWith('text:')), isEmpty);
      });
    });

    test('retyping a deleted letter cancels the pending update', () {
      fakeAsync((time) {
        final t = TvTyping(tv)..changed('cat');
        time.elapse(const Duration(seconds: 2));
        tv.sent.clear();
        t
          ..changed('ca')
          ..changed('cat');
        time.elapse(const Duration(seconds: 2));
        expect(tv.sent, isEmpty);
      });
    });

    test('clearing opens the empty search page', () {
      fakeAsync((time) {
        final t = TvTyping(tv)..changed('cat');
        time.elapse(const Duration(seconds: 2));
        t.changed('');
        time.elapse(const Duration(seconds: 1));
        expect(tv.sent.last, 'link:');
      });
    });

    test('Enter opens the results for the exact text, without pressing Enter', () {
      fakeAsync((time) {
        final t = TvTyping(tv)..changed('batman lego');
        time.elapse(const Duration(seconds: 2));
        t.submit('batman lego');
        expect(tv.sent.last, 'link:batman lego');
        expect(tv.sent, isNot(contains('key:${Keys.enter}')));
        time.elapse(const Duration(seconds: 2));
        expect(tv.sent.where((s) => s == 'key:${Keys.dpadRight}'), hasLength(1), reason: 'nudge only once');
      });
    });

    test('closing the keyboard sends a deletion that was still waiting', () {
      fakeAsync((time) {
        final t = TvTyping(tv)..changed('cat');
        time.elapse(const Duration(seconds: 2));
        t
          ..changed('ca')
          ..dispose();
        expect(tv.sent.last, 'link:ca');
      });
    });

    test('the search link encodes the query', () {
      expect(TvTyping.youtubeSearch('tom & jerry'), 'https://www.youtube.com/results?search_query=tom+%26+jerry');
    });
  });
}
