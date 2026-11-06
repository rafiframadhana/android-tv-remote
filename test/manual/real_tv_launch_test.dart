// Manual check: opens catalogue apps on a real TV from a cold start with the app's launcher logic
// and prints what it would tell the user (not part of the normal suite).
// Run: REAL_TV=<tv ip> REAL_TV_ID=.e2e4 [ADB=<adb path>] flutter test --tags manual --run-skipped \
//        test/manual/real_tv_launch_test.dart
// With ADB set (and `adb connect <tv ip>:5555` done), each app is force-stopped first.
@Tags(['manual'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/app_launcher.dart';
import 'package:tv_remote/core/saved_tv.dart';
import 'package:tv_remote/core/tls.dart';
import 'package:tv_remote/core/tv_connection.dart';
import 'package:tv_remote/protocol/key_codes.dart';
import 'package:tv_remote/ui/shortcuts/catalog.dart';

void main() {
  final host = Platform.environment['REAL_TV'];
  final idDir = Platform.environment['REAL_TV_ID'] ?? '.e2e4';
  final adb = Platform.environment['ADB'];
  final ids = (Platform.environment['APPS'] ?? 'stremio,netflix,primevideo,bittv,ytmusic,youtube,spotify,disneyplus')
      .split(',');

  test(
    'launch results from a cold start',
    () async {
      final identity = ClientIdentity(
        certificatePem: File('$idDir/client.crt').readAsStringSync(),
        privateKeyPem: File('$idDir/client.key').readAsStringSync(),
      );
      final fp = await fetchTvFingerprint(host!, identity);
      final c = TvConnection(
        tv: SavedTv(host: host, name: 'TV', pins: [fp], remoteVerified: true),
        identity: identity,
      )..start();
      expect(await c.waitFor(() => c.isConnected ? true : null, const Duration(seconds: 15)), isTrue);
      final launcher = AppLauncher(c);
      final lines = <String>[];
      for (final id in ids) {
        final s = shortcutCatalog.firstWhere((s) => s.id == id);
        if (adb != null) await Process.run(adb, ['-s', '$host:5555', 'shell', 'am', 'force-stop', s.package]);
        c.sendKey(Keys.home);
        await Future<void>.delayed(const Duration(seconds: 3));
        final sw = Stopwatch()..start();
        final r = await launcher.open(s);
        final line =
            '${s.name.padRight(14)} ${r.name.padRight(10)} after ${sw.elapsedMilliseconds} ms '
            '(TV shows ${c.currentApp})';
        lines.add(line);
        // ignore: avoid_print
        print(line);
      }
      c.sendKey(Keys.home);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      // ignore: avoid_print
      print('\n${lines.join('\n')}');
      c.dispose();
    },
    skip: host == null ? 'set REAL_TV to run' : false,
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
