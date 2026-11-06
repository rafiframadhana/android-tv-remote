import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tv_remote/protocol/framing.dart';
import 'package:tv_remote/protocol/pairing_crypto.dart';
import 'package:tv_remote/protocol/polo_messages.dart';
import 'package:tv_remote/protocol/remote_messages.dart';

import '../fixtures/vectors.dart' as v;

Uint8List hex(String s) =>
    Uint8List.fromList([for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);

String toHex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('pairing messages match androidtvremote2 encoding', () {
    test('pairing_request', () => expect(toHex(Polo.pairingRequest(clientName: 'TV Remote')), v.pairingRequest));
    test('options', () => expect(toHex(Polo.options()), v.options));
    test('configuration', () => expect(toHex(Polo.configuration()), v.configuration));
    test('secret', () => expect(toHex(Polo.secret(List.generate(32, (i) => i))), v.secret));
  });

  group('pairing messages decode', () {
    test('pairing_request_ack', () {
      final m = PoloMessage.decode(hex(v.inPairingRequestAck));
      expect(m.kind, PoloKind.pairingRequestAck);
      expect(m.serverName, 'Living Room TV');
      expect(m.isOk, isTrue);
    });
    test('options', () => expect(PoloMessage.decode(hex(v.inOptions)).kind, PoloKind.options));
    test(
      'empty configuration_ack is still detected',
      () => expect(PoloMessage.decode(hex(v.inConfigurationAck)).kind, PoloKind.configurationAck),
    );
    test('secret_ack', () => expect(PoloMessage.decode(hex(v.inSecretAck)).kind, PoloKind.secretAck));
    test('bad secret status', () {
      final m = PoloMessage.decode(hex(v.inBadSecret));
      expect(m.isOk, isFalse);
      expect(m.status, Polo.statusBadSecret);
    });
  });

  group('remote messages match androidtvremote2 encoding', () {
    test('configure reply', () => expect(toHex(RemoteOut.configureReply(622)), v.configureReply));
    test('set_active', () => expect(toHex(RemoteOut.setActive(622)), v.setActiveReply));
    test('ping response', () => expect(toHex(RemoteOut.pingResponse(12)), v.pingResponse));
    test('key short', () => expect(toHex(RemoteOut.keyInject(19, KeyDirection.short)), v.keyDpadUpShort));
    test('key start long', () => expect(toHex(RemoteOut.keyInject(23, KeyDirection.startLong)), v.keyCenterStartLong));
    test('key > 127 end long', () => expect(toHex(RemoteOut.keyInject(286, KeyDirection.endLong)), v.key286EndLong));
    test('ime text', () => expect(toHex(RemoteOut.imeText(imeCounter: 3, fieldCounter: 4, text: 'héllo')), v.imeText));
    test(
      'ime text with zero counters',
      () => expect(toHex(RemoteOut.imeText(imeCounter: 0, fieldCounter: 0, text: 'a')), v.imeTextZeroCounters),
    );
    test('app link', () => expect(toHex(RemoteOut.appLink('https://www.youtube.com')), v.appLink));
    test('voice begin', () => expect(toHex(RemoteOut.voiceBegin(9)), v.voiceBegin));
    test('voice payload', () => expect(toHex(RemoteOut.voicePayload(9, [0, 1, 2, 3])), v.voicePayload));
    test('voice end', () => expect(toHex(RemoteOut.voiceEnd(9)), v.voiceEnd));
  });

  group('remote messages decode', () {
    test('configure', () {
      final m = RemoteIn.decode(hex(v.inConfigure)) as RemoteConfigure;
      expect(m.features, 639);
      expect(m.vendor, 'Sony');
      expect(m.model, 'BRAVIA 4K');
      expect(m.appVersion, '6.3.726776162');
    });
    test('empty set_active', () => expect(RemoteIn.decode(hex(v.inSetActive)), isA<RemoteSetActive>()));
    test('ping', () => expect((RemoteIn.decode(hex(v.inPing)) as RemotePingRequest).val1, 12));
    test('start on', () => expect((RemoteIn.decode(hex(v.inStartOn)) as RemoteStart).started, isTrue));
    test(
      'start off (empty message)',
      () => expect((RemoteIn.decode(hex(v.inStartOff)) as RemoteStart).started, isFalse),
    );
    test('volume', () {
      final m = RemoteIn.decode(hex(v.inVolume)) as RemoteVolume;
      expect((m.level, m.max, m.muted), (25, 100, true));
    });
    test('ime key inject → current app', () {
      final m = RemoteIn.decode(hex(v.inImeKeyInject)) as RemoteImeKeyInject;
      expect(m.appPackage, 'com.google.android.youtube.tv');
      expect(m.label, 'YouTube');
    });
    test('ime batch edit counters', () {
      final m = RemoteIn.decode(hex(v.inImeBatchEdit)) as RemoteImeBatchEdit;
      expect((m.imeCounter, m.fieldCounter), (7, 8));
    });
    test('ime show', () => expect((RemoteIn.decode(hex(v.inImeShow)) as RemoteImeShowRequest).value, 'q'));
    test('voice begin', () => expect((RemoteIn.decode(hex(v.inVoiceBegin)) as RemoteVoiceBegin).sessionId, 42));
    test('error', () => expect(RemoteIn.decode(hex(v.inError)), isA<RemoteError>()));
  });

  group('framing', () {
    test('round-trips frames split at every byte boundary', () {
      final msgs = [hex(v.inConfigure), hex(v.inPing), Uint8List(300)];
      final stream = <int>[for (final m in msgs) ...encodeFrame(m)];
      for (var split = 1; split < stream.length; split++) {
        final d = FrameDecoder();
        final out = [...d.add(stream.sublist(0, split)), ...d.add(stream.sublist(split))];
        expect(out.map(toHex).toList(), msgs.map(toHex).toList(), reason: 'split at $split');
      }
    });
    test('300-byte frame uses a 2-byte length', () => expect(encodeFrame(Uint8List(300)).sublist(0, 2), [0xac, 0x02]));
  });

  group('pairing secret', () {
    final client = rsaPublicKeyFromCertificate(hex(v.secretClientCertDer));
    final server = rsaPublicKeyFromCertificate(hex(v.secretServerCertDer));

    test('parses RSA key from certificate', () {
      expect(client.modulus.toRadixString(16), v.secretClientModulus);
      expect(client.exponent, BigInt.from(65537));
    });
    test('matches Python reference', () {
      expect(toHex(computePairingSecret(client: client, server: server, code: v.secretCode)), v.secretExpected);
    });
    test('accepts lowercase and spaces', () {
      final messy = '${v.secretCode.substring(0, 3)} ${v.secretCode.substring(3)}'.toLowerCase();
      expect(toHex(computePairingSecret(client: client, server: server, code: messy)), v.secretExpected);
    });
    test('rejects a code whose checksum byte is wrong', () {
      final first = int.parse(v.secretCode.substring(0, 2), radix: 16);
      final wrong = ((first + 1) & 0xff).toRadixString(16).padLeft(2, '0') + v.secretCode.substring(2);
      expect(
        () => computePairingSecret(client: client, server: server, code: wrong),
        throwsA(isA<PairingCodeException>()),
      );
    });
    test('rejects malformed codes', () {
      expect(normalizePairingCode('169eoe'), '169E0E');
      for (final bad in ['', '12345', '1234567', 'GHIJKL']) {
        expect(() => normalizePairingCode(bad), throwsA(isA<PairingCodeException>()), reason: bad);
      }
    });
  });
}
