import 'dart:async';
import 'dart:typed_data';

import 'package:tv_remote/protocol/channel.dart';

/// In-memory [MessageChannel]: the test plays the TV.
class FakeChannel implements MessageChannel {
  final _incoming = StreamController<Uint8List>();
  final List<Uint8List> sent = [];
  bool closed = false;

  /// Called for every message the client sends (lets a test script replies).
  void Function(Uint8List msg)? onSend;

  @override
  Stream<Uint8List> get messages => _incoming.stream;

  @override
  void send(Uint8List message) {
    sent.add(message);
    onSend?.call(message);
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!_incoming.isClosed) await _incoming.close();
  }

  /// TV → client.
  void receive(Uint8List message) => _incoming.add(message);

  void disconnect([Object? error]) {
    if (error != null) _incoming.addError(error);
    _incoming.close();
  }
}
