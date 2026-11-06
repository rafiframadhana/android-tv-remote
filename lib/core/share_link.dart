import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../protocol/pairing_crypto.dart';
import '../protocol/pairing_session.dart';
import '../protocol/remote_session.dart';
import 'pairing_flow.dart';
import 'pairing_share.dart';
import 'saved_tv.dart';
import 'tls.dart';

/// Lets several phones use one TV at the same time on TVs that remember only one paired remote
/// (verified on a Panasonic/Realtek Android TV 9: every new pairing replaces the previous one).
///
/// A phone that holds a pairing for the TV ("host") offers it on the Wi-Fi. A phone that wants to
/// use the TV ("joiner") asks the host to start a pairing with the TV; the TV shows a code; the
/// user types it on the joiner; the host completes *its own* pairing with that code — re-pairing
/// the same certificate, so nobody is logged out — and hands its pairing to the joiner.
///
/// Security is the same as normal pairing: the code is only visible on the TV screen, and the
/// host only hands over its pairing after the TV accepted the code. The link between phones is
/// TLS (encrypted). The joiner checks the received pairing with the TV before saving it.
const shareServiceType = '_tvremote-share._tcp';

/// Short TV id used in announcements: the start of the TV certificate's fingerprint.
String tvShareId(String pin) => pin.substring(0, 16);

class ShareException implements Exception {
  ShareException(this.message);
  final String message;
  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------------------------
// Host side (the phone that already uses the TV)
// ---------------------------------------------------------------------------------------------

class ShareHost {
  ShareHost({required this.findTv, required this.identityForTv, this.tvPairingPort = pairingPort});

  /// Finds the stored TV for a share id, or null.
  final SavedTv? Function(String tvId) findTv;

  /// The pairing this phone uses for [tv].
  final Future<ClientIdentity> Function(SavedTv tv) identityForTv;

  /// The TV's pairing port (overridable for tests).
  final int tvPairingPort;

  /// One join at a time; at most one new TV pairing prompt every few seconds.
  static const _cooldown = Duration(seconds: 5);
  static const _sessionTimeout = Duration(minutes: 3);

  SecureServerSocket? _server;
  bool _busy = false;
  DateTime _lastStart = DateTime.fromMillisecondsSinceEpoch(0);

  int? get port => _server?.port;

  Future<int> start(ClientIdentity tlsIdentity) async {
    final server = _server ??= await SecureServerSocket.bind(InternetAddress.anyIPv4, 0, tlsIdentity.securityContext);
    server.listen(_handle, onError: (Object _) {});
    return server.port;
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }

  Future<void> _handle(SecureSocket socket) async {
    final link = _Link(socket);
    if (_busy || DateTime.now().difference(_lastStart) < _cooldown) {
      link.send({'op': 'error', 'msg': 'The other phone is busy. Try again in a moment.'});
      return link.close();
    }
    _busy = true;
    PairingFlow? flow;
    try {
      final hello = await link.next().timeout(const Duration(seconds: 10));
      final tv = hello['op'] == 'start' ? findTv('${hello['tv']}') : null;
      if (tv == null) {
        link.send({'op': 'error', 'msg': "The other phone doesn't use this TV."});
        return;
      }
      _lastStart = DateTime.now();
      final identity = await identityForTv(tv);
      flow = await PairingFlow.begin(tv.host, identity, port: tvPairingPort);
      link.send({'op': 'code-shown'});
      final deadline = DateTime.now().add(_sessionTimeout);
      while (DateTime.now().isBefore(deadline)) {
        final msg = await link.next().timeout(deadline.difference(DateTime.now()));
        if (msg['op'] != 'code') break;
        try {
          await flow.submit('${msg['code']}');
        } on PairingCodeException catch (e) {
          link.send({'op': 'retry', 'msg': e.message}); // typo: the TV still shows the same code
          continue;
        }
        // The TV accepted the code: the user can see the TV. Hand over this phone's pairing.
        link.send({'op': 'pairing', 'data': SharedPairing(tv: tv, identity: identity).encode()});
        return;
      }
    } on Object catch (e) {
      link.send({'op': 'error', 'msg': e is PairingException ? e.message : "The other phone couldn't pair: $e"});
    } finally {
      await flow?.close();
      await link.close();
      _busy = false;
    }
  }
}

// ---------------------------------------------------------------------------------------------
// Joiner side (the new phone)
// ---------------------------------------------------------------------------------------------

class ShareJoin {
  ShareJoin._(this._link, this._tvHost, this._tvRemotePort);

  final _Link _link;
  final String _tvHost;
  final int _tvRemotePort;

  /// Connects to a host phone and has it start pairing with the TV. When this completes, the TV
  /// is showing a code.
  static Future<ShareJoin> begin({
    required String hostAddress,
    required int hostPort,
    required String tvId,
    required String tvHost,
    int tvRemotePort = remotePort,
  }) async {
    final socket = await SecureSocket.connect(
      hostAddress,
      hostPort,
      onBadCertificate: (_) => true, // encryption only; trust comes from the TV's code
      timeout: const Duration(seconds: 5),
    );
    final link = _Link(socket);
    link.send({'op': 'start', 'tv': tvId});
    final reply = await link.next().timeout(const Duration(seconds: 20));
    if (reply['op'] != 'code-shown') {
      await link.close();
      throw ShareException('${reply['msg'] ?? "The other phone didn't respond."}');
    }
    return ShareJoin._(link, tvHost, tvRemotePort);
  }

  /// Sends the code typed by the user. Throws [PairingCodeException] for a typo (try again), or
  /// [ShareException]. Returns the shared pairing, already verified with the TV.
  Future<SharedPairing> submit(String code) async {
    final normalized = normalizePairingCode(code);
    _link.send({'op': 'code', 'code': normalized});
    final reply = await _link.next().timeout(const Duration(seconds: 30));
    switch (reply['op']) {
      case 'retry':
        throw PairingCodeException('${reply['msg']}');
      case 'pairing':
        final shared = SharedPairing.decode('${reply['data']}');
        final tv = shared.tv.copyWith(host: _tvHost);
        await verifySharedPairing(tv, shared.identity, port: _tvRemotePort);
        return SharedPairing(tv: tv, identity: shared.identity);
      default:
        throw ShareException('${reply['msg'] ?? "The other phone couldn't pair."}');
    }
  }

  Future<void> close() => _link.close();
}

/// Confirms that [identity] really works with the TV at [tv.host] and that the TV presents one of
/// [tv.pins]: never save a pairing just because another phone sent it.
Future<void> verifySharedPairing(SavedTv tv, ClientIdentity identity, {int port = remotePort}) async {
  final SecureSocket socket;
  try {
    socket = await connectTls(tv.host, port, identity);
  } on Object {
    throw ShareException("Couldn't reach the TV to check the pairing.");
  }
  final cert = socket.peerCertificate;
  if (cert == null || !tv.pins.contains(certificateFingerprint(cert))) {
    socket.destroy();
    throw ShareException("The pairing from the other phone doesn't belong to this TV.");
  }
  final session = RemoteSession(channel: SocketMessageChannel(socket));
  try {
    await session.ready.timeout(const Duration(seconds: 10));
  } on Object {
    throw ShareException('The TV did not accept the shared pairing.');
  } finally {
    await session.close();
  }
}

// ---------------------------------------------------------------------------------------------

/// Newline-delimited JSON over a socket, with a size cap.
class _Link {
  _Link(this._socket) {
    _sub = _socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .listen(
          (chunk) {
            _buf.write(chunk);
            if (_buf.length > _maxBytes) {
              close();
              return;
            }
            var text = _buf.toString();
            var i = text.indexOf('\n');
            while (i >= 0) {
              final line = text.substring(0, i);
              text = text.substring(i + 1);
              try {
                final decoded = jsonDecode(line);
                if (decoded is Map<String, Object?>) _incoming.add(decoded);
              } on Object {
                // ignore malformed line
              }
              i = text.indexOf('\n');
            }
            _buf
              ..clear()
              ..write(text);
          },
          onDone: () => _incoming.close(),
          onError: (Object _) => _incoming.close(),
          cancelOnError: true,
        );
  }

  static const _maxBytes = 16 * 1024;
  final Socket _socket;
  final _buf = StringBuffer();
  final _incoming = StreamController<Map<String, Object?>>();
  late final StreamIterator<Map<String, Object?>> _it = StreamIterator(_incoming.stream);
  late final StreamSubscription<String> _sub;
  bool _closed = false;

  void send(Map<String, Object?> msg) {
    if (_closed) return;
    try {
      _socket.write('${jsonEncode(msg)}\n');
    } on Object {
      // peer gone; next() will report it
    }
  }

  Future<Map<String, Object?>> next() async {
    if (await _it.moveNext()) return _it.current;
    throw ShareException('The other phone disconnected.');
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub.cancel();
    try {
      await _socket.flush();
    } on Object {
      // ignore
    }
    _socket.destroy();
  }
}
