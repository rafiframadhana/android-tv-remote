// End-to-end check against a real Android TV / Google TV (or the Google TV emulator)
// using the app's own protocol and TLS code.
//
//   dart run tool/tv_e2e.dart pair   <host> <stateDir> [pairPort]
//       Starts pairing, then waits for the code in <stateDir>/code.txt (or type it on stdin).
//   dart run tool/tv_e2e.dart remote <host> <stateDir> [remotePort] [command ...]
//       Connects, prints TV state, then runs commands:
//       key:<code>  long:<code>  text:<string>  link:<uri>  wait:<ms>
import 'dart:async';
import 'dart:io';

import 'package:tv_remote/core/certificate.dart';
import 'package:tv_remote/core/pairing_flow.dart';
import 'package:tv_remote/core/saved_tv.dart';
import 'package:tv_remote/core/share_link.dart';
import 'package:tv_remote/core/tls.dart';
import 'package:tv_remote/protocol/pairing_crypto.dart';
import 'package:tv_remote/protocol/remote_messages.dart';
import 'package:tv_remote/protocol/remote_session.dart';

Future<ClientIdentity> loadIdentity(Directory dir) async {
  final cert = File('${dir.path}/client.crt');
  final key = File('${dir.path}/client.key');
  if (!cert.existsSync()) {
    dir.createSync(recursive: true);
    final g = generateClientCertificate();
    cert.writeAsStringSync(g.certificatePem);
    key.writeAsStringSync(g.privateKeyPem);
  }
  return ClientIdentity(certificatePem: cert.readAsStringSync(), privateKeyPem: key.readAsStringSync());
}

Future<String> waitForCode(Directory dir) async {
  final f = File('${dir.path}/code.txt');
  if (f.existsSync()) f.deleteSync();
  stdout.writeln('WAITING_FOR_CODE (write it to ${f.path})');
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (f.existsSync()) {
      final code = f.readAsStringSync().trim();
      if (code.length == 6) return code;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  throw TimeoutException('no code');
}

Future<void> main(List<String> args) async {
  final mode = args[0];
  final host = args[1];
  final dir = Directory(args[2]);
  final identity = await loadIdentity(dir);

  if (mode == 'pair') {
    final port = args.length > 3 && !args[3].startsWith('--') ? int.parse(args[3]) : pairingPort;
    final name = args.firstWhere((a) => a.startsWith('--name='), orElse: () => '--name=TV Remote').substring(7);
    final service = args
        .firstWhere((a) => a.startsWith('--service='), orElse: () => '--service=atvremote')
        .substring(10);
    final flow = await PairingFlow.begin(host, identity, port: port, clientName: name, serviceName: service);
    stdout.writeln('TV_SHOWS_CODE');
    final code = await waitForCode(dir);
    await flow.submit(code);
    stdout.writeln('PAIRED');
    await flow.close();
    exit(0);
  }

  if (mode == 'pair-cancel') {
    // Starts pairing (TV shows a code), then cancels after a few seconds.
    final flow = await PairingFlow.begin(host, identity);
    stdout.writeln('TV_SHOWS_CODE');
    await Future<void>.delayed(const Duration(seconds: 4));
    await flow.close();
    stdout.writeln('CANCELLED');
    await Future<void>.delayed(const Duration(seconds: 1));
    exit(0);
  }

  if (mode == 'share-host') {
    // Phone A: offers its (working) pairing for this TV to other phones.
    final fp = await fetchTvFingerprint(host, identity);
    final tv = SavedTv(host: host, name: 'TV', pins: [fp], remoteVerified: true);
    final shareHost = ShareHost(findTv: (id) => id == tvShareId(fp) ? tv : null, identityForTv: (_) async => identity);
    final p = await shareHost.start(identity);
    stdout.writeln('SHARE_HOST_READY port=$p tvId=${tvShareId(fp)}');
    await Future<void>.delayed(const Duration(minutes: 6));
    await shareHost.stop();
    exit(0);
  }

  if (mode == 'share-join') {
    // Phone B: joins phone A's pairing using the code shown on the TV.
    final hostPort = args[3].split(':');
    final fp = await fetchTvFingerprint(host, identity);
    final join = await ShareJoin.begin(
      hostAddress: hostPort[0],
      hostPort: int.parse(hostPort[1]),
      tvId: tvShareId(fp),
      tvHost: host,
    );
    stdout.writeln('TV_SHOWS_CODE');
    while (true) {
      final code = await waitForCode(dir);
      try {
        final shared = await join.submit(code);
        File('${dir.path}/client.crt').writeAsStringSync(shared.identity.certificatePem);
        File('${dir.path}/client.key').writeAsStringSync(shared.identity.privateKeyPem);
        stdout.writeln('JOINED (verified with the TV)');
        break;
      } on PairingCodeException catch (e) {
        stdout.writeln('RETRY: ${e.message}');
      }
    }
    await join.close();
    exit(0);
  }

  final port = args.length > 3 ? int.parse(args[3]) : remotePort;
  final noVoice = args.contains('--novoice');
  final socket = await connectTls(host, port, identity);
  final s = RemoteSession(
    channel: SocketMessageChannel(socket),
    requestedFeatures: noVoice ? RemoteFeature.all & ~RemoteFeature.voice : RemoteFeature.all,
  );
  final t0 = DateTime.now();
  String ts() => '${(DateTime.now().difference(t0).inMilliseconds / 1000).toStringAsFixed(1)}s';
  void dump(String why) => stdout.writeln(
    '[${ts()}] $why: on=${s.isOn} vol=${s.volumeLevel}/${s.volumeMax} muted=${s.muted} '
    'app=${s.currentApp} voice=${s.voiceSupported} features=${s.features} (${s.vendor} ${s.model})',
  );
  // Log what the TV tells us (pings are noise).
  s.inbound.listen((m) {
    final line = switch (m) {
      RemoteImeShowRequest(:final value) => 'TV: keyboard shown, field="$value"',
      RemoteImeBatchEdit(:final text, :final imeCounter, :final fieldCounter) =>
        'TV: text field="$text" (ime $imeCounter/$fieldCounter)',
      RemoteImeKeyInject(:final appPackage) => 'TV: app=$appPackage',
      RemoteVoiceBegin(:final sessionId) => 'TV: voice session $sessionId',
      RemoteStart(:final started) => 'TV: screen ${started ? 'on' : 'off'}',
      RemoteVolume(:final level, :final max, :final muted) => 'TV: volume $level/$max muted=$muted',
      RemoteError() => 'TV: ERROR reply',
      _ => null,
    };
    if (line != null) stdout.writeln('[${ts()}] $line');
  });
  try {
    await s.ready.timeout(const Duration(seconds: 10));
  } on Object catch (e) {
    stdout.writeln(
      'NOT_READY $e receivedMessage=${s.receivedMessage} '
      'classified=${classifyConnectFailure(e, receivedMessage: s.receivedMessage).name}',
    );
    exit(2);
  }
  dump('ready');
  for (final cmd in args.skip(4).where((a) => !a.startsWith('--'))) {
    final i = cmd.indexOf(':');
    final (verb, arg) = (cmd.substring(0, i), cmd.substring(i + 1));
    if (verb != 'wait') stdout.writeln('[${ts()}] > $cmd');
    switch (verb) {
      case 'key':
        s.sendKey(int.parse(arg));
      case 'long':
        s.sendKey(int.parse(arg), KeyDirection.startLong);
        await Future<void>.delayed(const Duration(milliseconds: 900));
        s.sendKey(int.parse(arg), KeyDirection.endLong);
      case 'text':
        s.sendText(arg);
      case 'link':
        s.launchApp(arg);
      case 'voice':
        // 16-bit PCM mono 8 kHz WAV, streamed in real time like the phone mic would.
        final pcm = wavPcm(File(arg).readAsBytesSync());
        try {
          final v = await s.startVoice();
          stdout.writeln('[${ts()}] voice session ${v.sessionId} open, streaming ${pcm.length} bytes');
          for (var p = 0; p < pcm.length; p += 1600) {
            v.add(pcm.sublist(p, (p + 1600).clamp(0, pcm.length)));
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          v.end();
          stdout.writeln('[${ts()}] voice ended');
        } on Object catch (e) {
          stdout.writeln('[${ts()}] VOICE FAILED: $e');
        }
      case 'wait':
        await Future<void>.delayed(Duration(milliseconds: int.parse(arg)));
    }
  }
  await Future<void>.delayed(const Duration(seconds: 1));
  dump('final');
  await s.close();
  exit(0);
}

/// Returns the raw samples of a PCM WAV file (contents of its "data" chunk).
List<int> wavPcm(List<int> wav) {
  var p = 12;
  while (p + 8 <= wav.length) {
    final id = String.fromCharCodes(wav.sublist(p, p + 4));
    final size = wav[p + 4] | wav[p + 5] << 8 | wav[p + 6] << 16 | wav[p + 7] << 24;
    if (id == 'data') return wav.sublist(p + 8, (p + 8 + size).clamp(0, wav.length));
    p += 8 + size + (size & 1);
  }
  throw const FormatException('no data chunk');
}
