import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tv_remote/core/device_store.dart';
import 'package:tv_remote/core/pinning.dart';
import 'package:tv_remote/core/tls.dart';
import 'package:tv_remote/protocol/channel.dart';
import 'package:tv_remote/protocol/proto.dart';
import 'package:tv_remote/protocol/remote_messages.dart';
import 'package:tv_remote/protocol/remote_session.dart';

import '../support/fake_tv.dart';

void main() {
  group('certificate pinning', () {
    const paired = SavedTv(host: '10.0.0.5', name: 'Living Room', pins: ['aa']);

    test('the certificate seen at pairing is trusted and confirms the pin', () {
      final r = checkPin(paired, 'aa');
      expect(r.result, PinResult.match);
      expect(r.updated!.remoteVerified, isTrue);
    });

    test('an impostor at the address is refused once the pin is verified', () {
      final verified = paired.copyWith(remoteVerified: true);
      final r = checkPin(verified, 'bb');
      expect(r.result, PinResult.mismatch);
      expect(r.updated, isNull);
      expect(checkPin(verified, 'aa').result, PinResult.match);
    });

    test('a TV paired by an older version is pinned on first use', () {
      final r = checkPin(const SavedTv(host: 'h', name: 'n'), 'cc');
      expect(r.result, PinResult.firstUse);
      expect(r.updated!.pins, ['cc']);
      expect(r.updated!.remoteVerified, isTrue);
    });

    test('a separate remote-port certificate is accepted only on the first connection after pairing', () {
      final first = checkPin(paired, 'dd');
      expect(first.result, PinResult.firstUse);
      expect(first.updated!.pins, ['aa', 'dd']);
      expect(checkPin(first.updated!, 'ee').result, PinResult.mismatch);
    });

    test('pins survive storage', () {
      const tv = SavedTv(host: 'h', name: 'n', pins: ['aa', 'bb'], remoteVerified: true);
      final back = SavedTv.fromJson(tv.toJson());
      expect(back.pins, ['aa', 'bb']);
      expect(back.remoteVerified, isTrue);
      // Records written before pinning existed still load.
      expect(SavedTv.fromJson({'host': 'h', 'name': 'n'}).pins, isEmpty);
    });
  });

  group('device store', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('two TVs with the same name are both kept', () async {
      final store = DeviceStore();
      await store.touch(const SavedTv(host: '10.0.0.5', name: 'Android TV'));
      await store.touch(const SavedTv(host: '10.0.0.6', name: 'Android TV'));
      expect(store.tvs.map((t) => t.host), ['10.0.0.6', '10.0.0.5']);
    });

    test('re-pairing the same address replaces its record', () async {
      final store = DeviceStore();
      await store.touch(const SavedTv(host: '10.0.0.5', name: 'TV', pins: ['old']));
      await store.touch(const SavedTv(host: '10.0.0.5', name: 'TV', pins: ['new']));
      expect(store.tvs.single.pins, ['new']);
    });

    test('moving a TV to a new address keeps one entry per address', () async {
      final store = DeviceStore();
      await store.touch(const SavedTv(host: '10.0.0.7', name: 'Old entry'));
      await store.touch(const SavedTv(host: '10.0.0.5', name: 'TV'));
      await store.replace('10.0.0.5', const SavedTv(host: '10.0.0.7', name: 'TV'));
      expect(store.tvs.map((t) => (t.host, t.name)), [('10.0.0.7', 'TV')]);
    });
  });

  group('hostile input', () {
    test('a length near 2^63 is rejected cleanly instead of overflowing', () {
      // field 1, wire type 2, length = 0x7fffffffffffffff
      final data = Uint8List.fromList([0x0a, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f, 0x00]);
      expect(() => ProtoMessage.decode(data), throwsA(isA<ProtoDecodeException>()));
    });

    test('garbage from the TV is ignored, not thrown', () async {
      final tv = FakeChannel();
      final s = RemoteSession(channel: tv);
      tv.receive(Uint8List.fromList([0x0a, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f]));
      tv.receive(Uint8List.fromList([0xff, 0xff]));
      await Future<void>.delayed(Duration.zero);
      expect(s.isClosed, isFalse);
      await s.close();
    });
  });

  group('connection failure classification', () {
    test('a connection reset before the TV says anything is a rejection (how Android reports it)', () {
      const reset = SocketException('Connection reset by peer', osError: OSError('Connection reset by peer', 104));
      const readFailed = SocketException('Read failed', osError: OSError('Connection reset by peer', 104));
      const windowsReset = SocketException('An existing connection was forcibly closed', osError: OSError('', 10054));
      for (final e in [reset, readFailed, windowsReset]) {
        expect(classifyConnectFailure(e, receivedMessage: false), ConnectFailure.probablyRejected, reason: '$e');
        expect(
          classifyConnectFailure(ChannelClosedException(e), receivedMessage: false),
          ConnectFailure.probablyRejected,
          reason: 'wrapped $e',
        );
      }
      // After the TV talked to us, a reset is just a dropped connection.
      expect(classifyConnectFailure(reset, receivedMessage: true), ConnectFailure.unreachable);
    });

    test('a TV that is off or out of reach is still "unreachable", never "needs pairing"', () {
      const refused = SocketException('Connection refused', osError: OSError('Connection refused', 111));
      const timedOut = SocketException('Connection timed out', osError: OSError('Connection timed out', 110));
      const noRoute = SocketException('No route to host', osError: OSError('No route to host', 113));
      for (final e in [refused, timedOut, noRoute]) {
        expect(classifyConnectFailure(e, receivedMessage: false), ConnectFailure.unreachable, reason: '$e');
        expect(classifyConnectFailure(ChannelClosedException(e), receivedMessage: false), ConnectFailure.unreachable);
      }
    });

    test('one TLS failure is not yet "needs pairing" — the loop decides after two', () {
      expect(
        classifyConnectFailure(
          const HandshakeException('Connection terminated during handshake'),
          receivedMessage: false,
        ),
        ConnectFailure.probablyRejected,
      );
      expect(classifyConnectFailure(ChannelClosedException(), receivedMessage: false), ConnectFailure.probablyRejected);
      expect(classifyConnectFailure(ChannelClosedException(), receivedMessage: true), ConnectFailure.unreachable);
      expect(
        classifyConnectFailure(const SocketException('no route'), receivedMessage: false),
        ConnectFailure.unreachable,
      );
    });
  });

  test('a silent TV is detected even while keys keep being sent', () {
    fakeAsync((fa) {
      final ch = FakeChannel();
      final s = RemoteSession(channel: ch);
      for (var i = 0; i < 70; i++) {
        s.sendKey(19, KeyDirection.short); // keeps the idle timer alive
        fa.elapse(const Duration(seconds: 1));
      }
      expect(s.isClosed, isTrue);
    });
  });
}
