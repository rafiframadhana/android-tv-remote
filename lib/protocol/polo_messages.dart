import 'dart:typed_data';

import 'proto.dart';

/// Pairing ("Polo") messages, see polo.proto (proto2) in tronikos/androidtvremote2.
abstract final class Polo {
  static const int protocolVersion = 2;

  static const int statusOk = 200;
  static const int statusError = 400;
  static const int statusBadConfiguration = 401;
  static const int statusBadSecret = 402;

  static const int encodingHexadecimal = 3;
  static const int roleInput = 1;
  static const int codeLength = 6;

  // OuterMessage field numbers.
  static const int _fVersion = 1;
  static const int _fStatus = 2;
  static const int _fPairingRequest = 10;
  static const int _fPairingRequestAck = 11;
  static const int _fOptions = 20;
  static const int _fConfiguration = 30;
  static const int _fConfigurationAck = 31;
  static const int _fSecret = 40;
  static const int _fSecretAck = 41;

  static ProtoWriter _outer() => ProtoWriter()
    ..varint(_fVersion, protocolVersion, always: true)
    ..varint(_fStatus, statusOk, always: true);

  static ProtoWriter _hexEncoding() => ProtoWriter()
    ..varint(1, encodingHexadecimal, always: true)
    ..varint(2, codeLength, always: true);

  static Uint8List pairingRequest({required String clientName, String serviceName = 'atvremote'}) =>
      (_outer()..message(
            _fPairingRequest,
            ProtoWriter()
              ..string(1, serviceName, always: true)
              ..string(2, clientName),
          ))
          .toBytes();

  static Uint8List options() =>
      (_outer()..message(
            _fOptions,
            ProtoWriter()
              ..message(1, _hexEncoding())
              ..varint(3, roleInput),
          ))
          .toBytes();

  static Uint8List configuration() =>
      (_outer()..message(
            _fConfiguration,
            ProtoWriter()
              ..message(1, _hexEncoding())
              ..varint(2, roleInput, always: true),
          ))
          .toBytes();

  /// Error status with no payload: tells the TV to abandon the pairing (closes its code screen).
  static Uint8List abort() =>
      (ProtoWriter()
            ..varint(_fVersion, protocolVersion, always: true)
            ..varint(_fStatus, statusError, always: true))
          .toBytes();

  static Uint8List secret(List<int> secret) =>
      (_outer()..message(_fSecret, ProtoWriter()..bytes(1, secret, always: true))).toBytes();
}

enum PoloKind { pairingRequestAck, options, configurationAck, secretAck, other }

class PoloMessage {
  PoloMessage({required this.status, required this.kind, this.serverName = ''});

  final int status;
  final PoloKind kind;
  final String serverName;

  bool get isOk => status == Polo.statusOk;

  factory PoloMessage.decode(Uint8List data) {
    final m = ProtoMessage.decode(data);
    final PoloKind kind;
    var serverName = '';
    if (m.has(Polo._fPairingRequestAck)) {
      kind = PoloKind.pairingRequestAck;
      serverName = m.message(Polo._fPairingRequestAck)!.string(1);
    } else if (m.has(Polo._fOptions)) {
      kind = PoloKind.options;
    } else if (m.has(Polo._fConfigurationAck)) {
      kind = PoloKind.configurationAck;
    } else if (m.has(Polo._fSecretAck)) {
      kind = PoloKind.secretAck;
    } else {
      kind = PoloKind.other;
    }
    return PoloMessage(status: m.uint32(Polo._fStatus), kind: kind, serverName: serverName);
  }
}
