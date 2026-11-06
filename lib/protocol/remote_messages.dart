import 'dart:typed_data';

import 'proto.dart';

/// Key press direction (RemoteDirection in remotemessage.proto).
enum KeyDirection {
  startLong(1),
  endLong(2),
  short(3);

  const KeyDirection(this.wire);
  final int wire;
}

/// Feature bitmask negotiated in remote_configure / remote_set_active.
abstract final class RemoteFeature {
  static const int ping = 1 << 0;
  static const int key = 1 << 1;
  static const int ime = 1 << 2;
  static const int voice = 1 << 3;
  static const int power = 1 << 5;
  static const int volume = 1 << 6;
  static const int appLink = 1 << 9;

  /// What we request (623), same as androidtvremote2; the TV masks it with what it supports.
  static const int all = ping | key | ime | voice | power | volume | appLink;
}

/// RemoteMessage field numbers (remotemessage.proto, proto3).
abstract final class _F {
  static const configure = 1;
  static const setActive = 2;
  static const error = 3;
  static const pingRequest = 8;
  static const pingResponse = 9;
  static const keyInject = 10;
  static const imeKeyInject = 20;
  static const imeBatchEdit = 21;
  static const imeShowRequest = 22;
  static const voiceBegin = 30;
  static const voicePayload = 31;
  static const voiceEnd = 32;
  static const start = 40;
  static const setVolumeLevel = 50;
  static const appLinkLaunch = 90;
}

/// Encoders for client → TV messages.
abstract final class RemoteOut {
  static Uint8List _wrap(int field, ProtoWriter body) => (ProtoWriter()..message(field, body)).toBytes();

  static Uint8List configureReply(int features, {String packageName = 'atvremote', String appVersion = '1.0.0'}) =>
      _wrap(
        _F.configure,
        ProtoWriter()
          ..varint(1, features)
          ..message(
            2,
            ProtoWriter()
              ..varint(3, 1)
              ..string(4, '1')
              ..string(5, packageName)
              ..string(6, appVersion),
          ),
      );

  static Uint8List setActive(int features) => _wrap(_F.setActive, ProtoWriter()..varint(1, features));

  static Uint8List pingResponse(int val1) => _wrap(_F.pingResponse, ProtoWriter()..varint(1, val1));

  static Uint8List keyInject(int keyCode, KeyDirection direction) => _wrap(
    _F.keyInject,
    ProtoWriter()
      ..varint(1, keyCode)
      ..varint(2, direction.wire),
  );

  /// Replaces the focused TV text field's content with [text].
  /// Mirrors androidtvremote2: start = end = text length - 1 (cursor at the end).
  static Uint8List imeText({required int imeCounter, required int fieldCounter, required String text}) {
    final cursor = text.length - 1;
    return _wrap(
      _F.imeBatchEdit,
      ProtoWriter()
        ..varint(1, imeCounter)
        ..varint(2, fieldCounter)
        ..message(
          3,
          ProtoWriter()
            ..varint(1, 1)
            ..message(
              2,
              ProtoWriter()
                ..varint(1, cursor)
                ..varint(2, cursor)
                ..string(3, text),
            ),
        ),
    );
  }

  static Uint8List appLink(String link) => _wrap(_F.appLinkLaunch, ProtoWriter()..string(1, link));

  static Uint8List voiceBegin(int sessionId) => _wrap(_F.voiceBegin, ProtoWriter()..varint(1, sessionId));

  static Uint8List voicePayload(int sessionId, List<int> samples) => _wrap(
    _F.voicePayload,
    ProtoWriter()
      ..varint(1, sessionId)
      ..bytes(2, samples),
  );

  static Uint8List voiceEnd(int sessionId) => _wrap(_F.voiceEnd, ProtoWriter()..varint(1, sessionId));
}

/// Decoded TV → client message.
sealed class RemoteIn {
  const RemoteIn();

  factory RemoteIn.decode(Uint8List data) {
    final m = ProtoMessage.decode(data);
    if (m.message(_F.configure) case final c?) {
      final info = c.message(2);
      return RemoteConfigure(
        features: c.int32(1),
        vendor: info?.string(2) ?? '',
        model: info?.string(1) ?? '',
        appVersion: info?.string(6) ?? '',
      );
    }
    if (m.has(_F.setActive)) return const RemoteSetActive();
    if (m.message(_F.pingRequest) case final p?) return RemotePingRequest(p.int32(1));
    if (m.message(_F.start) case final s?) return RemoteStart(s.boolean(1));
    if (m.message(_F.setVolumeLevel) case final v?) {
      return RemoteVolume(level: v.uint32(7), max: v.uint32(6), muted: v.boolean(8));
    }
    if (m.message(_F.imeKeyInject) case final k?) {
      final app = k.message(1);
      return RemoteImeKeyInject(appPackage: app?.string(12) ?? '', label: app?.string(10) ?? '');
    }
    if (m.message(_F.imeBatchEdit) case final b?) {
      final edit = b.messages(3).firstOrNull?.message(2);
      return RemoteImeBatchEdit(imeCounter: b.int32(1), fieldCounter: b.int32(2), text: edit?.string(3) ?? '');
    }
    if (m.message(_F.imeShowRequest) case final s?) {
      return RemoteImeShowRequest(s.message(2)?.string(2) ?? '');
    }
    if (m.message(_F.voiceBegin) case final v?) return RemoteVoiceBegin(v.int32(1));
    if (m.has(_F.error)) return const RemoteError();
    return const RemoteUnknown();
  }
}

class RemoteConfigure extends RemoteIn {
  const RemoteConfigure({required this.features, required this.vendor, required this.model, required this.appVersion});
  final int features;
  final String vendor;
  final String model;
  final String appVersion;
}

class RemoteSetActive extends RemoteIn {
  const RemoteSetActive();
}

class RemotePingRequest extends RemoteIn {
  const RemotePingRequest(this.val1);
  final int val1;
}

class RemoteStart extends RemoteIn {
  const RemoteStart(this.started);
  final bool started;
}

class RemoteVolume extends RemoteIn {
  const RemoteVolume({required this.level, required this.max, required this.muted});
  final int level;
  final int max;
  final bool muted;
}

class RemoteImeKeyInject extends RemoteIn {
  const RemoteImeKeyInject({required this.appPackage, required this.label});
  final String appPackage;
  final String label;
}

class RemoteImeBatchEdit extends RemoteIn {
  const RemoteImeBatchEdit({required this.imeCounter, required this.fieldCounter, this.text = ''});
  final int imeCounter;
  final int fieldCounter;

  /// Current content of the TV's focused text field, as reported by the TV.
  final String text;
}

class RemoteImeShowRequest extends RemoteIn {
  const RemoteImeShowRequest(this.value);
  final String value;
}

class RemoteVoiceBegin extends RemoteIn {
  const RemoteVoiceBegin(this.sessionId);
  final int sessionId;
}

class RemoteError extends RemoteIn {
  const RemoteError();
}

class RemoteUnknown extends RemoteIn {
  const RemoteUnknown();
}
