import 'dart:typed_data';

/// Varint length-delimited framing used on both the pairing and remote ports.
Uint8List encodeFrame(Uint8List message) {
  final out = BytesBuilder(copy: false);
  var len = message.length;
  while (len >= 0x80) {
    out.addByte((len & 0x7f) | 0x80);
    len >>= 7;
  }
  out.addByte(len);
  out.add(message);
  return out.toBytes();
}

class FrameException implements Exception {
  FrameException(this.message);
  final String message;
  @override
  String toString() => 'FrameException: $message';
}

/// Reassembles frames from arbitrary TCP chunks (a chunk may hold a partial
/// frame, several frames, or split the length varint itself).
class FrameDecoder {
  /// Upper bound for a single message. Real messages are < 64 KB.
  static const int maxFrameLength = 1 << 20;

  final BytesBuilder _buffer = BytesBuilder(copy: true);

  List<Uint8List> add(List<int> chunk) {
    _buffer.add(chunk);
    final data = _buffer.toBytes();
    final frames = <Uint8List>[];
    var pos = 0;
    while (pos < data.length) {
      var len = 0;
      var shift = 0;
      var p = pos;
      var complete = false;
      while (p < data.length) {
        final b = data[p++];
        len |= (b & 0x7f) << shift;
        if (b & 0x80 == 0) {
          complete = true;
          break;
        }
        shift += 7;
        if (shift > 28) throw FrameException('length varint too long');
      }
      if (!complete) break;
      if (len > maxFrameLength) throw FrameException('frame too large: $len');
      if (p + len > data.length) break;
      frames.add(Uint8List.fromList(data.sublist(p, p + len)));
      pos = p + len;
    }
    _buffer.clear();
    if (pos < data.length) _buffer.add(data.sublist(pos));
    return frames;
  }
}
