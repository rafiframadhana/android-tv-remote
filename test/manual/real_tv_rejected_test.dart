// Manual check against a real TV that no longer knows this client (not part of the normal suite).
// Run: REAL_TV=<tv ip> REAL_TV_ID=.e2e2 flutter test --tags manual --run-skipped test/manual/
@Tags(['manual'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/saved_tv.dart';
import 'package:tv_remote/core/tls.dart';
import 'package:tv_remote/core/tv_connection.dart';

void main() {
  final host = Platform.environment['REAL_TV'];
  final idDir = Platform.environment['REAL_TV_ID'] ?? '.e2e2';

  test(
    'status sequence when the TV has forgotten this client',
    () async {
      final identity = ClientIdentity(
        certificatePem: File('$idDir/client.crt').readAsStringSync(),
        privateKeyPem: File('$idDir/client.key').readAsStringSync(),
      );
      final fp = await fetchTvFingerprint(host!, identity);
      final c = TvConnection(
        tv: SavedTv(host: host, name: 'TV', pins: [fp], remoteVerified: true),
        identity: identity,
      );
      final t0 = DateTime.now();
      final log = <String>[];
      void record() => log.add('${DateTime.now().difference(t0).inMilliseconds}ms ${c.status.name}');
      c.addListener(record);
      c.start();
      await Future<void>.delayed(const Duration(seconds: 40));
      // ignore: avoid_print
      print(log.join('\n'));
      // ignore: avoid_print
      print('FINAL ${c.status.name} lastFailure=${c.lastFailure}');
      c.dispose();
    },
    skip: host == null ? 'set REAL_TV to run' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
