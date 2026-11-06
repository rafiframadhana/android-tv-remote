import 'dart:async';
import 'dart:typed_data';

import 'channel.dart';
import 'key_codes.dart';
import 'remote_messages.dart';

/// Talks to the TV on port 6466 once paired: answers configuration and pings,
/// tracks TV state and sends commands. Port of androidtvremote2's RemoteProtocol.
class RemoteSession {
  RemoteSession({
    required this.channel,
    int requestedFeatures = RemoteFeature.all,
    this.idleTimeout = const Duration(seconds: 16),
    this.silenceTimeout = const Duration(seconds: 60),
  }) : _features = requestedFeatures {
    _ready.future.ignore();
    _sub = channel.messages.listen(
      _onMessage,
      onError: (Object e) => _shutdown(ChannelClosedException(e)),
      onDone: () => _shutdown(ChannelClosedException()),
    );
    _resetIdle();
    _resetSilence();
  }

  final MessageChannel channel;
  final Duration idleTimeout;

  /// Closes the connection when the TV has sent nothing for this long, even while we keep
  /// sending keys (the idle timer alone can't see a dead TV during continuous use).
  final Duration silenceTimeout;
  int _features;

  late final StreamSubscription<Uint8List> _sub;
  final _ready = Completer<void>();
  final _done = Completer<Object?>();
  final _changes = StreamController<void>.broadcast(sync: true);
  Timer? _idle;
  Timer? _silence;
  bool _closed = false;

  // ---- TV state
  bool isOn = false;
  String vendor = '';
  String model = '';
  String currentApp = '';
  int? volumeLevel;
  int? volumeMax;
  bool muted = false;
  int _imeCounter = 0;
  int _imeFieldCounter = 0;

  Completer<int>? _voiceBegin;
  VoiceStream? _voice;

  /// Completes when the TV reports it's ready for commands (first remote_start).
  Future<void> get ready => _ready.future;

  /// Completes with the cause once the connection is gone.
  Future<Object?> get done => _done.future;

  /// Fires whenever any state field changes.
  Stream<void> get changes => _changes.stream;

  /// Every decoded message from the TV (for diagnostics and end-to-end tests).
  Stream<RemoteIn> get inbound => _inbound.stream;
  final _inbound = StreamController<RemoteIn>.broadcast(sync: true);

  bool get isClosed => _closed;

  /// Feature bitmask in effect after negotiation (what we asked for ∩ what the TV offers).
  int get features => _features;

  /// True if the TV accepted the voice feature during negotiation.
  bool get voiceSupported => _features & RemoteFeature.voice != 0;

  void sendKey(int keyCode, [KeyDirection direction = KeyDirection.short]) =>
      _send(RemoteOut.keyInject(keyCode, direction));

  /// Sets the focused TV text field to [text]. Empty text is sent as a delete key,
  /// since the protocol can't express an empty field.
  void sendText(String text) {
    if (text.isEmpty) {
      sendKey(Keys.del);
      return;
    }
    _send(RemoteOut.imeText(imeCounter: _imeCounter, fieldCounter: _imeFieldCounter, text: text));
  }

  void launchApp(String link) => _send(RemoteOut.appLink(link));

  /// Starts a voice search: sends SEARCH, waits for the TV to open a voice
  /// session, then echoes remote_voice_begin. Stream PCM 16-bit mono 8 kHz.
  Future<VoiceStream> startVoice({Duration timeout = const Duration(seconds: 2)}) async {
    if (_closed) throw ChannelClosedException();
    if (!voiceSupported) throw UnsupportedError('This TV does not accept voice from the remote protocol.');
    if (_voiceBegin != null || _voice != null) throw StateError('Voice session already in progress');
    final begin = _voiceBegin = Completer<int>();
    try {
      sendKey(Keys.search);
      final id = await begin.future.timeout(timeout);
      _send(RemoteOut.voiceBegin(id));
      return _voice = VoiceStream._(this, id);
    } finally {
      _voiceBegin = null;
    }
  }

  Future<void> close() async {
    await _sub.cancel();
    await channel.close();
    _shutdown(null);
  }

  void _send(Uint8List msg) {
    if (_closed) return;
    _resetIdle();
    channel.send(msg);
  }

  void _resetIdle() {
    _idle?.cancel();
    if (_closed) return;
    _idle = Timer(idleTimeout, () {
      _shutdown(TimeoutException('TV stopped responding', idleTimeout));
      _sub.cancel();
      channel.close();
    });
  }

  void _resetSilence() {
    _silence?.cancel();
    if (_closed) return;
    _silence = Timer(silenceTimeout, () {
      _shutdown(TimeoutException('TV stopped responding', silenceTimeout));
      _sub.cancel();
      channel.close();
    });
  }

  void _notify() => _changes.add(null);

  /// Whether the TV has sent anything on this connection.
  bool get receivedMessage => _receivedMessage;
  bool _receivedMessage = false;

  void _onMessage(Uint8List data) {
    _receivedMessage = true;
    _resetIdle();
    _resetSilence();
    final RemoteIn msg;
    try {
      msg = RemoteIn.decode(data);
    } on Object {
      return; // Unknown/garbled message: ignore, like the reference implementation.
    }
    _inbound.add(msg);
    switch (msg) {
      case RemoteConfigure():
        _features &= msg.features;
        vendor = msg.vendor;
        model = msg.model;
        _send(RemoteOut.configureReply(_features));
        _notify();
      case RemoteSetActive():
        _send(RemoteOut.setActive(_features));
      case RemotePingRequest():
        _send(RemoteOut.pingResponse(msg.val1));
      case RemoteStart():
        isOn = msg.started;
        if (!_ready.isCompleted) _ready.complete();
        _notify();
      case RemoteVolume():
        volumeLevel = msg.level;
        volumeMax = msg.max;
        muted = msg.muted;
        _notify();
      case RemoteImeKeyInject():
        if (msg.appPackage != currentApp) {
          currentApp = msg.appPackage;
          _notify();
        }
      case RemoteImeBatchEdit():
        _imeCounter = msg.imeCounter;
        _imeFieldCounter = msg.fieldCounter;
      case RemoteVoiceBegin():
        final c = _voiceBegin;
        if (c != null && !c.isCompleted) c.complete(msg.sessionId);
      case RemoteImeShowRequest() || RemoteError() || RemoteUnknown():
        break;
    }
  }

  void _shutdown(Object? cause) {
    if (_closed) return;
    _closed = true;
    _idle?.cancel();
    _silence?.cancel();
    _voice?._closed = true;
    _voice = null;
    final err = cause ?? ChannelClosedException();
    if (!_ready.isCompleted) _ready.completeError(err);
    final vb = _voiceBegin;
    if (vb != null && !vb.isCompleted) vb.completeError(err);
    _done.complete(cause);
    _changes.close();
    _inbound.close();
  }
}

/// An open voice session. Audio is re-chunked: the TV closes the connection on
/// chunks > 20 KB and Shield rejects chunks < 8 KB (androidtvremote2 findings).
class VoiceStream {
  VoiceStream._(this._session, this.sessionId);

  static const int chunkSize = 20 * 1024;
  static const int minChunkSize = 8 * 1024;

  final RemoteSession _session;
  final int sessionId;
  final BytesBuilder _pending = BytesBuilder(copy: true);
  bool _closed = false;

  bool get isClosed => _closed;

  void add(List<int> pcm) {
    if (_closed) return;
    _pending.add(pcm);
    if (_pending.length < chunkSize) return;
    final data = _pending.takeBytes();
    var pos = 0;
    while (data.length - pos >= chunkSize) {
      _session._send(RemoteOut.voicePayload(sessionId, Uint8List.sublistView(data, pos, pos + chunkSize)));
      pos += chunkSize;
    }
    _pending.add(Uint8List.sublistView(data, pos));
  }

  /// Flushes remaining audio (zero-padded to the minimum chunk) and ends the session.
  void end() {
    if (_closed) return;
    _closed = true;
    if (_pending.isNotEmpty) {
      final rest = _pending.takeBytes();
      final chunk = rest.length >= minChunkSize ? rest : (Uint8List(minChunkSize)..setRange(0, rest.length, rest));
      _session._send(RemoteOut.voicePayload(sessionId, chunk));
    }
    _session._send(RemoteOut.voiceEnd(sessionId));
    if (identical(_session._voice, this)) _session._voice = null;
  }
}
