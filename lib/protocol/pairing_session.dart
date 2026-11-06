import 'dart:async';
import 'dart:typed_data';

import 'channel.dart';
import 'pairing_crypto.dart';
import 'polo_messages.dart';

class PairingException implements Exception {
  PairingException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Drives the pairing handshake on port 6467.
///
/// 1. [start] sends the pairing request and negotiates a 6-hex-digit code;
///    when it completes, the TV is showing the code.
/// 2. [finish] verifies the typed code locally and sends the secret.
class PairingSession {
  PairingSession({
    required this.channel,
    required this.clientName,
    this.serviceName = 'atvremote',
    required this.clientKey,
    required this.serverKey,
    this.timeout = const Duration(seconds: 10),
  }) {
    _sub = channel.messages.listen(
      _onMessage,
      onError: (Object e) => _fail(ChannelClosedException(e)),
      onDone: () => _fail(ChannelClosedException()),
    );
  }

  final MessageChannel channel;
  final String clientName;

  /// Identifies the remote app to the TV (androidtvremote2 uses 'atvremote').
  final String serviceName;
  final RsaPublicKey clientKey;
  final RsaPublicKey serverKey;
  final Duration timeout;

  late final StreamSubscription<Uint8List> _sub;
  Completer<void>? _waiting;
  PoloKind? _waitingFor;
  bool _closed = false;
  Object? _deadError;

  /// The TV's own name, from pairing_request_ack (may be empty).
  String serverName = '';

  Future<void> start() {
    channel.send(Polo.pairingRequest(clientName: clientName, serviceName: serviceName));
    return _wait(PoloKind.configurationAck);
  }

  /// Throws [PairingCodeException] for a mistyped code (nothing is sent, the
  /// user can retry), [PairingException] if the TV rejects it.
  Future<void> finish(String code) {
    final secret = computePairingSecret(client: clientKey, server: serverKey, code: code);
    channel.send(Polo.secret(secret));
    return _wait(PoloKind.secretAck);
  }

  /// Whether the TV accepted the secret (pairing finished).
  bool _paired = false;

  Future<void> close() async {
    // Leaving mid-pairing: tell the TV, so it closes its code screen instead of leaving it up.
    if (!_paired && !_closed && _deadError == null) channel.send(Polo.abort());
    _closed = true;
    await _sub.cancel();
    await channel.close();
  }

  Future<void> _wait(PoloKind kind) {
    if (_closed) return Future.error(PairingException('Pairing was cancelled.'));
    if (_deadError case final e?) return Future.error(e);
    final c = Completer<void>();
    _waiting = c;
    _waitingFor = kind;
    return c.future.timeout(
      timeout,
      onTimeout: () {
        _waiting = null;
        throw PairingException("The TV didn't respond. Make sure it's on and try again.");
      },
    );
  }

  void _onMessage(Uint8List data) {
    final PoloMessage msg;
    try {
      msg = PoloMessage.decode(data);
    } on Object catch (e) {
      _fail(PairingException('Unexpected reply from the TV ($e).'));
      return;
    }
    if (!msg.isOk) {
      _fail(
        PairingException(
          msg.status == Polo.statusBadSecret
              ? 'The TV rejected the code. Start pairing again.'
              : 'The TV refused pairing (status ${msg.status}).',
        ),
      );
      return;
    }
    switch (msg.kind) {
      case PoloKind.pairingRequestAck:
        serverName = msg.serverName;
        channel.send(Polo.options());
      case PoloKind.options:
        channel.send(Polo.configuration());
      case PoloKind.configurationAck || PoloKind.secretAck:
        if (msg.kind == PoloKind.secretAck) _paired = true;
        if (_waitingFor == msg.kind) _complete();
      case PoloKind.other:
        break;
    }
  }

  void _complete() {
    final c = _waiting;
    _waiting = null;
    _waitingFor = null;
    c?.complete();
  }

  /// Any failure ends the session: the TV drops the connection after an error.
  void _fail(Object error) {
    _deadError ??= error;
    final c = _waiting;
    _waiting = null;
    _waitingFor = null;
    if (c != null && !c.isCompleted) c.completeError(error);
  }
}
