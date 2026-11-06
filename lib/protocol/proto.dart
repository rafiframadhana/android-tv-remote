import 'dart:convert';
import 'dart:typed_data';

/// Minimal protobuf wire-format writer/reader.
///
/// Only what the Android TV Remote protocol needs: varint and length-delimited
/// fields. Field order follows call order, so callers write fields in ascending
/// field-number order like the official encoders do.
class ProtoWriter {
  final BytesBuilder _out = BytesBuilder(copy: false);

  static const int _wireVarint = 0;
  static const int _wireLen = 2;

  void _rawVarint(int value) {
    // Negative numbers are encoded as 10-byte two's complement (int32/int64 semantics).
    var v = value;
    while (true) {
      if (v >= 0 && v < 0x80) {
        _out.addByte(v);
        return;
      }
      _out.addByte((v & 0x7f) | 0x80);
      v = v >>> 7;
    }
  }

  void _tag(int field, int wire) => _rawVarint((field << 3) | wire);

  /// Varint field. Proto3 semantics: zero is omitted unless [always] (proto2 required fields).
  void varint(int field, int value, {bool always = false}) {
    if (value == 0 && !always) return;
    _tag(field, _wireVarint);
    _rawVarint(value);
  }

  void boolean(int field, bool value) => varint(field, value ? 1 : 0);

  void string(int field, String value, {bool always = false}) {
    if (value.isEmpty && !always) return;
    bytes(field, utf8.encode(value), always: true);
  }

  void bytes(int field, List<int> value, {bool always = false}) {
    if (value.isEmpty && !always) return;
    _tag(field, _wireLen);
    _rawVarint(value.length);
    _out.add(value);
  }

  /// Embedded message. Always written (message fields have presence, even when empty).
  void message(int field, ProtoWriter sub) => bytes(field, sub.toBytes(), always: true);

  Uint8List toBytes() => _out.toBytes();
}

class ProtoDecodeException implements Exception {
  ProtoDecodeException(this.message);
  final String message;
  @override
  String toString() => 'ProtoDecodeException: $message';
}

/// Decoded protobuf message: field number → values in wire order.
/// Varint values are [int]; length-delimited values are [Uint8List].
class ProtoMessage {
  ProtoMessage._(this._fields);

  final Map<int, List<Object>> _fields;

  factory ProtoMessage.decode(Uint8List data) {
    final fields = <int, List<Object>>{};
    var pos = 0;

    (int, int) readVarint(int p) {
      var result = 0;
      var shift = 0;
      while (true) {
        if (p >= data.length) throw ProtoDecodeException('truncated varint');
        final b = data[p++];
        if (shift < 64) result |= (b & 0x7f) << shift;
        if (b & 0x80 == 0) return (result, p);
        shift += 7;
        if (shift >= 70) throw ProtoDecodeException('varint too long');
      }
    }

    while (pos < data.length) {
      final (key, p1) = readVarint(pos);
      pos = p1;
      final field = key >>> 3;
      final wire = key & 7;
      switch (wire) {
        case 0:
          final (v, p2) = readVarint(pos);
          pos = p2;
          (fields[field] ??= []).add(v);
        case 1:
          if (pos + 8 > data.length) throw ProtoDecodeException('truncated fixed64');
          pos += 8;
        case 2:
          final (len, p2) = readVarint(pos);
          pos = p2;
          if (len < 0 || len > data.length - pos) throw ProtoDecodeException('truncated bytes');
          (fields[field] ??= []).add(Uint8List.sublistView(data, pos, pos + len));
          pos += len;
        case 5:
          if (pos + 4 > data.length) throw ProtoDecodeException('truncated fixed32');
          pos += 4;
        default:
          throw ProtoDecodeException('unsupported wire type $wire');
      }
    }
    return ProtoMessage._(fields);
  }

  bool has(int field) => _fields.containsKey(field);

  /// Field numbers present, in first-seen order (diagnostics).
  Iterable<int> get fieldNumbers => _fields.keys;

  /// All raw values of a field: ints for varints, bytes for length-delimited (diagnostics).
  List<Object> rawValues(int field) => List.unmodifiable(_fields[field] ?? const []);

  /// Last varint value of [field] as a signed 32-bit int (int32/enum/bool semantics), 0 if absent.
  int int32(int field) {
    final v = _fields[field]?.whereType<int>().lastOrNull;
    return v == null ? 0 : v.toSigned(32);
  }

  /// Last varint value of [field] as an unsigned 32-bit int, 0 if absent.
  int uint32(int field) {
    final v = _fields[field]?.whereType<int>().lastOrNull;
    return v == null ? 0 : v.toUnsigned(32);
  }

  bool boolean(int field) => int32(field) != 0;

  Uint8List? bytes(int field) => _fields[field]?.whereType<Uint8List>().lastOrNull;

  String string(int field) {
    final b = bytes(field);
    return b == null ? '' : utf8.decode(b, allowMalformed: true);
  }

  /// Embedded message, or null when absent.
  ProtoMessage? message(int field) {
    final b = bytes(field);
    return b == null ? null : ProtoMessage.decode(b);
  }

  /// All length-delimited values of a (repeated) bytes field.
  List<Uint8List> bytesList(int field) => (_fields[field] ?? const []).whereType<Uint8List>().toList();

  List<ProtoMessage> messages(int field) =>
      (_fields[field] ?? const []).whereType<Uint8List>().map(ProtoMessage.decode).toList();
}
