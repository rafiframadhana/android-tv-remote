import 'dart:async';
import 'dart:typed_data';

/// A bidirectional stream of protobuf messages (frames already removed).
/// Implemented over TLS sockets in the app and by fakes in tests.
abstract interface class MessageChannel {
  /// Incoming messages. Completes when the connection closes; errors on transport errors.
  Stream<Uint8List> get messages;

  void send(Uint8List message);

  Future<void> close();
}

/// Thrown when the peer closed the connection or it failed.
class ChannelClosedException implements Exception {
  ChannelClosedException([this.cause]);
  final Object? cause;
  @override
  String toString() => 'Connection closed${cause == null ? '' : ': $cause'}';
}
