import 'dart:async';
import 'dart:io' show TlsException;
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/core/key_presser.dart';
import 'package:tv_remote/protocol/channel.dart';
import 'package:tv_remote/protocol/key_codes.dart';
import 'package:tv_remote/protocol/pairing_crypto.dart';
import 'package:tv_remote/protocol/pairing_session.dart';
import 'package:tv_remote/protocol/proto.dart';
import 'package:tv_remote/protocol/remote_messages.dart';
import 'package:tv_remote/protocol/remote_session.dart';

import '../fixtures/vectors.dart' as v;
import '../support/fake_tv.dart';
import 'messages_test.dart' show hex, toHex;

void main() {
  final clientKey = rsaPublicKeyFromCertificate(hex(v.secretClientCertDer));
  final serverKey = rsaPublicKeyFromCertificate(hex(v.secretServerCertDer));

  group('PairingSession', () {
    late FakeChannel tv;
    late PairingSession session;
    Uint8List? receivedSecret;

    setUp(() {
      tv = FakeChannel();
      receivedSecret = null;
      tv.onSend = (msg) {
        final hexMsg = toHex(msg);
        scheduleMicrotask(() {
          if (hexMsg == v.pairingRequest) {
            tv.receive(hex(v.inPairingRequestAck));
          } else if (hexMsg == v.options) {
            tv.receive(hex(v.inOptions));
          } else if (hexMsg == v.configuration) {
            tv.receive(hex(v.inConfigurationAck));
          } else {
            receivedSecret = ProtoMessage.decode(msg).message(40)!.bytes(1);
            tv.receive(toHex(receivedSecret!) == v.secretExpected ? hex(v.inSecretAck) : hex(v.inBadSecret));
          }
        });
      };
      session = PairingSession(channel: tv, clientName: 'TV Remote', clientKey: clientKey, serverKey: serverKey);
    });

    test('full handshake sends the reference secret', () async {
      await session.start();
      expect(tv.sent.map(toHex), [v.pairingRequest, v.options, v.configuration]);
      await session.finish(v.secretCode);
      expect(toHex(receivedSecret!), v.secretExpected);
    });

    test('mistyped code is caught locally and can be retried', () async {
      await session.start();
      final first = int.parse(v.secretCode.substring(0, 2), radix: 16);
      final typo = ((first ^ 0x01)).toRadixString(16).padLeft(2, '0') + v.secretCode.substring(2);
      expect(() => session.finish(typo), throwsA(isA<PairingCodeException>()));
      expect(tv.sent.length, 3, reason: 'nothing sent for a bad code');
      await session.finish(v.secretCode);
    });

    test('TV error status fails the pending step', () async {
      tv.onSend = (_) => scheduleMicrotask(() => tv.receive(hex(v.inBadSecret)));
      await expectLater(session.start(), throwsA(isA<PairingException>()));
    });

    test('connection drop fails the pending step and later calls', () async {
      tv.onSend = (_) => scheduleMicrotask(() => tv.disconnect());
      await expectLater(session.start(), throwsA(isA<ChannelClosedException>()));
      await expectLater(session.finish(v.secretCode), throwsA(isA<ChannelClosedException>()));
    });
  });

  group('RemoteSession', () {
    late FakeChannel tv;
    late RemoteSession s;

    setUp(() {
      tv = FakeChannel();
      s = RemoteSession(channel: tv);
    });
    tearDown(() => s.close());

    Future<void> flush() => Future<void>.delayed(Duration.zero);

    test('negotiates features masked by what the TV supports', () async {
      tv.receive(hex(v.inConfigure)); // TV offers 639 (includes every bit we ask for)
      tv.receive(hex(v.inSetActive));
      await flush();
      expect(toHex(tv.sent[0]), toHex(RemoteOut.configureReply(RemoteFeature.all)));
      expect(toHex(tv.sent[1]), toHex(RemoteOut.setActive(RemoteFeature.all)));
      expect(RemoteFeature.all, 623);
      expect((s.vendor, s.model), ('Sony', 'BRAVIA 4K'));
      expect(s.voiceSupported, isTrue);
    });

    test('drops voice when the TV does not offer it', () async {
      tv.receive(RemoteOut.configureReply(RemoteFeature.all & ~RemoteFeature.voice)); // same shape as TV's message
      await flush();
      expect(s.voiceSupported, isFalse);
      expect(ProtoMessage.decode(tv.sent.single).message(1)!.int32(1), RemoteFeature.all & ~RemoteFeature.voice);
    });

    test('answers pings and becomes ready on remote_start', () async {
      var readyFired = false;
      unawaited(s.ready.then((_) => readyFired = true));
      tv.receive(hex(v.inPing));
      await flush();
      expect(toHex(tv.sent.single), v.pingResponse);
      expect(readyFired, isFalse);
      tv.receive(hex(v.inStartOn));
      await flush();
      expect(readyFired, isTrue);
      expect(s.isOn, isTrue);
      tv.receive(hex(v.inStartOff));
      await flush();
      expect(s.isOn, isFalse);
    });

    test('tracks volume and current app, notifying listeners', () async {
      var changes = 0;
      s.changes.listen((_) => changes++);
      tv.receive(hex(v.inVolume));
      tv.receive(hex(v.inImeKeyInject));
      await flush();
      expect((s.volumeLevel, s.volumeMax, s.muted), (25, 100, true));
      expect(s.currentApp, 'com.google.android.youtube.tv');
      expect(changes, 2);
    });

    test('text uses IME counters from the TV', () async {
      tv.receive(hex(v.inImeBatchEdit)); // counters 7/8
      await flush();
      s.sendText('héllo');
      final edit = ProtoMessage.decode(tv.sent.single).message(21)!;
      expect((edit.int32(1), edit.int32(2)), (7, 8));
      expect(edit.messages(3).single.message(2)!.string(3), 'héllo');
    });

    test('empty text clears with a delete key', () {
      s.sendText('');
      expect(toHex(tv.sent.single), toHex(RemoteOut.keyInject(Keys.del, KeyDirection.short)));
    });

    test('ready fails if the TV hangs up first (e.g. unknown certificate)', () async {
      tv.disconnect(const TlsException('CERTIFICATE_UNKNOWN'));
      await expectLater(s.ready, throwsA(isA<ChannelClosedException>()));
      final cause = await s.done as ChannelClosedException;
      expect(cause.cause, isA<TlsException>());
    });

    test('idle connection is closed after the timeout', () {
      fakeAsync((fa) {
        final ch = FakeChannel();
        final session = RemoteSession(channel: ch);
        Object? cause = 'pending';
        session.done.then((c) => cause = c);
        fa.elapse(const Duration(seconds: 10));
        ch.receive(hex(v.inPing)); // activity resets the timer
        fa.elapse(const Duration(seconds: 10));
        expect(session.isClosed, isFalse);
        fa.elapse(const Duration(seconds: 7));
        expect(session.isClosed, isTrue);
        expect(cause, isA<TimeoutException>());
        expect(ch.closed, isTrue);
      });
    });

    group('voice', () {
      Future<void> offerVoice() async {
        tv.receive(hex(v.inConfigure));
        await flush();
        tv.sent.clear();
        tv.onSend = (msg) {
          if (toHex(msg) == toHex(RemoteOut.keyInject(Keys.search, KeyDirection.short))) {
            scheduleMicrotask(() => tv.receive(hex(v.inVoiceBegin))); // session 42
          }
        };
      }

      test('SEARCH → voice_begin echo → 20 KB chunks → padded tail → end', () async {
        await offerVoice();
        final voice = await s.startVoice();
        expect(voice.sessionId, 42);
        voice.add(Uint8List(30 * 1024));
        voice.add(Uint8List(1000));
        voice.end();
        final payloads = tv.sent.map(ProtoMessage.decode).toList();
        expect(payloads[0].message(10)!.int32(1), Keys.search);
        expect(payloads[1].message(30)!.int32(1), 42);
        final chunks = payloads.where((m) => m.has(31)).map((m) => m.message(31)!.bytes(2)!.length).toList();
        expect(chunks, [20 * 1024, 10 * 1024 + 1000]);
        expect(payloads.last.message(32)!.int32(1), 42);
      });

      test('times out when the TV never opens a session', () async {
        await offerVoice();
        tv.onSend = null;
        await expectLater(s.startVoice(timeout: const Duration(milliseconds: 50)), throwsA(isA<TimeoutException>()));
      });

      test('short utterance is padded to 8 KB', () async {
        await offerVoice();
        final voice = await s.startVoice();
        voice.add(Uint8List(100));
        voice.end();
        final chunk = tv.sent.map(ProtoMessage.decode).firstWhere((m) => m.has(31)).message(31)!.bytes(2)!;
        expect(chunk.length, 8 * 1024);
      });
    });
  });

  group('KeyPresser', () {
    List<String> run(void Function(KeyPresser p, FakeAsync fa) script) {
      final log = <String>[];
      fakeAsync((fa) {
        final p = KeyPresser((code, dir) => log.add('$code:${dir.name}'));
        script(p, fa);
      });
      return log;
    }

    test('tap sends SHORT on release', () {
      expect(
        run((p, fa) {
          p.down(Keys.dpadCenter, PressMode.normal);
          fa.elapse(const Duration(milliseconds: 150));
          p.up();
        }),
        ['23:short'],
      );
    });

    test('hold sends START_LONG then END_LONG', () {
      expect(
        run((p, fa) {
          p.down(Keys.home, PressMode.normal);
          fa.elapse(const Duration(milliseconds: 900));
          p.up();
        }),
        ['3:startLong', '3:endLong'],
      );
    });

    test('cancelled tap sends nothing, cancelled hold still ends', () {
      expect(
        run((p, fa) {
          p.down(Keys.back, PressMode.normal);
          p.cancel();
          p.down(Keys.back, PressMode.normal);
          fa.elapse(const Duration(milliseconds: 500));
          p.cancel();
        }),
        ['4:startLong', '4:endLong'],
      );
    });

    test('repeat keys fire immediately then auto-repeat', () {
      final log = run((p, fa) {
        p.down(Keys.dpadDown, PressMode.repeat);
        fa.elapse(const Duration(milliseconds: 399));
        fa.elapse(const Duration(milliseconds: 1)); // 400: second press
        fa.elapse(const Duration(milliseconds: 300)); // +3 repeats
        p.up();
        fa.elapse(const Duration(seconds: 1)); // nothing after release
      });
      expect(log, List.filled(5, '20:short'));
    });
  });
}
