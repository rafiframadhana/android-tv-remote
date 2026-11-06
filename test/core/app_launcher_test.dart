import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/app_launcher.dart';
import 'package:tv_remote/ui/shortcuts/catalog.dart';

class FakeTv implements LaunchTarget {
  @override
  bool isConnected = true;
  String _app = 'com.google.android.tvlauncher';
  int _errors = 0;
  final links = <String>[];
  final _changes = StreamController<void>.broadcast(sync: true);

  @override
  String get currentApp => _app;
  set currentApp(String v) {
    _app = v;
    _changes.add(null);
  }

  @override
  int get errorReplies => _errors;
  void errorReply() {
    _errors++;
    _changes.add(null);
  }

  @override
  void launchApp(String link) => links.add(link);
  @override
  void sendKey(int keyCode) {}

  @override
  Future<T?> waitFor<T extends Object>(T? Function() check, Duration timeout) {
    final first = check();
    if (first != null) return Future.value(first);
    final done = Completer<T?>();
    late final StreamSubscription<void> sub;
    final timer = Timer(timeout, () {
      if (!done.isCompleted) done.complete(null);
      sub.cancel();
    });
    sub = _changes.stream.listen((_) {
      final r = check();
      if (r != null && !done.isCompleted) {
        done.complete(r);
        timer.cancel();
        sub.cancel();
      }
    });
    return done.future;
  }
}

TvShortcut app(String id, {String link = '', String package = ''}) => TvShortcut(
  id: id,
  name: id,
  link: link,
  package: package,
  icon: const BadgeIcon('X'),
  color: const Color(0xFF000000),
);

void main() {
  late FakeTv tv;
  late AppLauncher launcher;
  setUp(() {
    tv = FakeTv();
    launcher = AppLauncher(tv);
  });

  final stremio = app('stremio', link: 'stremio:///board', package: 'com.stremio.one');
  final spotify = app('spotify', link: 'spotify://', package: 'com.spotify.tv.android');

  LaunchResult? run(FakeAsync time, TvShortcut s, {void Function()? during, Duration after = Duration.zero}) {
    LaunchResult? result;
    launcher.open(s).then((r) => result = r);
    time.flushMicrotasks();
    if (during != null) {
      time.elapse(after);
      during();
    }
    time.elapse(const Duration(seconds: 20));
    return result;
  }

  test('an app that takes 8 s to start (Stremio, cold) is opened, not "not installed"', () {
    fakeAsync((time) {
      final r = run(time, stremio, after: const Duration(seconds: 8), during: () => tv.currentApp = 'com.stremio.one');
      expect(r, LaunchResult.opened);
      expect(tv.links, ['stremio:///board']);
    });
  });

  test('an error reply right after the link means it is not installed', () {
    fakeAsync((time) {
      LaunchResult? r;
      launcher.open(spotify).then((v) => r = v);
      time.flushMicrotasks();
      tv.errorReply();
      time.flushMicrotasks();
      expect(r, LaunchResult.notOpened, reason: 'reported at once, no 15 s wait');
    });
  });

  test('a late error reply (e.g. a rejected key the user pressed) is not blamed on the launch', () {
    fakeAsync((time) {
      final r = run(
        time,
        stremio,
        after: const Duration(seconds: 5),
        during: () {
          tv.errorReply();
          time.elapse(const Duration(seconds: 2));
          tv.currentApp = 'com.stremio.one';
        },
      );
      expect(r, LaunchResult.opened);
    });
  });

  test('nothing happening for 15 s means it did not open', () {
    fakeAsync((time) {
      expect(
        run(time, app('disney', link: 'https://www.disneyplus.com', package: 'com.disney')),
        LaunchResult.notOpened,
      );
    });
  });

  test('another app coming to the front is not reported as a failure', () {
    fakeAsync((time) {
      final r = run(
        time,
        stremio,
        after: const Duration(seconds: 4),
        during: () => tv.currentApp = 'com.android.vending',
      );
      expect(r, LaunchResult.sent);
    });
  });

  test('a second tap replaces the first wait', () {
    fakeAsync((time) {
      LaunchResult? first;
      LaunchResult? second;
      launcher.open(stremio).then((r) => first = r);
      time.elapse(const Duration(seconds: 1));
      launcher
          .open(app('yt', link: 'https://www.youtube.com', package: 'com.google.android.youtube.tv'))
          .then((r) => second = r);
      time.elapse(const Duration(seconds: 4));
      tv.currentApp = 'com.google.android.youtube.tv';
      time.elapse(const Duration(seconds: 20));
      expect(first, LaunchResult.superseded);
      expect(second, LaunchResult.opened);
    });
  });

  test('already in front counts as opened', () {
    fakeAsync((time) {
      tv.currentApp = 'com.stremio.one';
      expect(run(time, stremio), LaunchResult.opened);
    });
  });
}
