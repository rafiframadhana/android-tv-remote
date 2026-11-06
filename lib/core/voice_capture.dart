import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import '../protocol/remote_session.dart';
import 'tv_connection.dart';

class VoiceException implements Exception {
  VoiceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Hold-to-talk: records 16-bit PCM, mono, 8 kHz and streams it to the TV's
/// voice session. Recording starts before the TV session opens so the first
/// words aren't lost; audio is buffered until the session is ready.
class VoiceCapture {
  /// At most ~10 s of audio is buffered while the TV opens its voice session.
  static const _maxBufferedBytes = 10 * 8000 * 2;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  VoiceStream? _voice;
  final List<Uint8List> _buffer = [];
  int _bufferedBytes = 0;

  /// The finger is on the mic key. Every await in [start] re-checks it, so letting go at any
  /// moment (even during the permission prompt) never leaves the microphone running.
  bool _held = false;
  bool _starting = false;
  bool _recording = false;

  bool get isActive => _recording;

  Future<void> start(TvConnection connection) async {
    if (_starting || _recording) return;
    if (!connection.voiceSupported) {
      throw VoiceException("This TV doesn't accept voice from phones. Try the TV's own remote.");
    }
    _held = true;
    _starting = true;
    try {
      if (!await _recorder.hasPermission()) {
        throw VoiceException('Microphone permission is needed for voice search.');
      }
      if (!_held) return; // Released while the permission dialog was up: don't start the mic.

      _buffer.clear();
      _bufferedBytes = 0;
      final stream = await _recorder.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 8000, numChannels: 1),
      );
      _recording = true;
      _sub = stream.listen((chunk) {
        final v = _voice;
        if (v != null) {
          v.add(chunk);
        } else if (_bufferedBytes + chunk.length <= _maxBufferedBytes) {
          _buffer.add(chunk);
          _bufferedBytes += chunk.length;
        }
      });
      if (!_held) {
        await _stopRecording();
        return;
      }

      final VoiceStream voice;
      try {
        voice = await connection.startVoice();
      } on Object {
        await _stopRecording();
        throw VoiceException("The TV didn't start voice search. Try again.");
      }
      for (final b in _buffer) {
        voice.add(b);
      }
      _buffer.clear();
      _bufferedBytes = 0;
      if (!_held) {
        // Released before the TV was ready: send what we heard, then stop.
        await _stopRecording();
        voice.end();
        return;
      }
      _voice = voice;
    } finally {
      _starting = false;
    }
  }

  /// Finger lifted: stop the microphone, send what's left and let the TV process the query.
  Future<void> stop() async {
    _held = false;
    if (_starting || !_recording) return; // A running start() sees _held == false and cleans up.
    await _stopRecording();
    _voice?.end();
    _voice = null;
  }

  Future<void> _stopRecording() async {
    _recording = false;
    try {
      await _recorder.stop();
    } on Object {
      // Not recording.
    }
    await _sub?.cancel();
    _sub = null;
    _buffer.clear();
    _bufferedBytes = 0;
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }
}
