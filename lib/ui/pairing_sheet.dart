import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/device_store.dart';
import '../core/pairing_flow.dart';
import '../core/share_link.dart';
import '../core/tls.dart';
import '../protocol/channel.dart';
import '../protocol/pairing_crypto.dart';
import '../protocol/pairing_session.dart';
import 'app_scope.dart';
import 'theme.dart';

/// Pairs with the TV at [host]. Returns the saved TV on success, null if dismissed.
Future<SavedTv?> showPairingSheet(
  BuildContext context, {
  required String host,
  required String name,
  bool manualName = false,
}) {
  return showModalBottomSheet<SavedTv>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _PairingSheet(host: host, name: name, manualName: manualName),
    ),
  );
}

enum _Stage { connecting, enterCode, verifying, failed }

class _PairingSheet extends StatefulWidget {
  const _PairingSheet({required this.host, required this.name, required this.manualName});
  final String host;
  final String name;

  /// [name] is a placeholder; use the TV's reported name instead.
  final bool manualName;

  @override
  State<_PairingSheet> createState() => _PairingSheetState();
}

class _PairingSheetState extends State<_PairingSheet> {
  _Stage _stage = _Stage.connecting;
  PairingFlow? _flow;

  /// Set when another phone already uses this TV: we join its pairing instead of replacing it.
  ShareJoin? _join;
  String? _error;
  final _code = TextEditingController();

  @override
  void initState() {
    super.initState();
    _begin();
  }

  String _describe(Object e) => switch (e) {
    PairingException(:final message) || PairingCodeException(:final message) => message,
    ShareException(:final message) => message,
    ChannelClosedException() => 'The TV closed the connection. Start pairing again.',
    _ => 'Pairing failed: $e',
  };

  Future<void> _begin() async {
    setState(() {
      _stage = _Stage.connecting;
      _error = null;
      _code.clear();
    });
    final services = AppScope.of(context);
    await _flow?.close();
    _flow = null;
    await _join?.close();
    _join = null;
    try {
      final identity = await services.identity.identity;
      // Another phone already using this TV? Join its pairing so nobody gets logged out
      // (some TVs remember only the most recently paired remote).
      final join = await _tryJoin(services, identity);
      if (join != null) {
        if (!mounted) {
          await join.close();
          return;
        }
        setState(() {
          _join = join;
          _stage = _Stage.enterCode;
        });
        return;
      }
      final flow = await PairingFlow.begin(widget.host, identity);
      if (!mounted) {
        await flow.close();
        return;
      }
      setState(() {
        _flow = flow;
        _stage = _Stage.enterCode;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _stage = _Stage.failed;
          _error = _describe(e);
        });
      }
    }
  }

  Future<ShareJoin?> _tryJoin(AppServices services, ClientIdentity identity) async {
    try {
      final tvId = tvShareId(await fetchTvFingerprint(widget.host, identity));
      final phone = await services.share.findPhoneFor(tvId);
      if (phone == null) return null;
      return await ShareJoin.begin(hostAddress: phone.address, hostPort: phone.port, tvId: tvId, tvHost: widget.host);
    } on Object {
      return null; // No phone to join (or it didn't answer): pair this phone directly.
    }
  }

  Future<void> _submit() async {
    if (_stage == _Stage.verifying) return;
    final join = _join;
    if (join != null) return _submitJoin(join);
    final flow = _flow;
    if (flow == null) return;
    setState(() {
      _stage = _Stage.verifying;
      _error = null;
    });
    try {
      await flow.submit(_code.text);
      await flow.close();
      _flow = null;
      // Prefer the name the TV gave itself over a placeholder like "TV at 192.168.1.20".
      final reported = flow.tvName.trim();
      final tv = SavedTv(
        host: widget.host,
        name: widget.manualName && reported.isNotEmpty ? reported : widget.name,
        pins: [flow.tvFingerprint],
      );
      if (!mounted) return;
      final services = AppScope.of(context);
      await services.identity.removeShared(tv); // this phone now has its own pairing
      await services.devices.touch(tv);
      if (mounted) Navigator.of(context).pop(tv);
    } on PairingCodeException catch (e) {
      // Typo caught locally: the TV still shows the same code, let them fix it.
      if (mounted) {
        setState(() {
          _stage = _Stage.enterCode;
          _error = e.message;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _stage = _Stage.failed;
          _error = _describe(e);
        });
      }
    }
  }

  Future<void> _submitJoin(ShareJoin join) async {
    setState(() {
      _stage = _Stage.verifying;
      _error = null;
    });
    final services = AppScope.of(context);
    try {
      final shared = await join.submit(_code.text);
      await join.close();
      _join = null;
      final tv = widget.manualName ? shared.tv : shared.tv.copyWith(name: widget.name);
      await services.identity.saveShared(tv, shared.identity);
      await services.devices.touch(tv);
      if (mounted) Navigator.of(context).pop(tv);
    } on PairingCodeException catch (e) {
      if (mounted) {
        setState(() {
          _stage = _Stage.enterCode;
          _error = e.message;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _stage = _Stage.failed;
          _error = _describe(e);
        });
      }
    }
  }

  @override
  void dispose() {
    _join?.close();
    _flow?.close();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pair with ${widget.name}', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            switch (_stage) {
              _Stage.connecting => const _Row(spinner: true, text: 'Connecting to the TV…'),
              _Stage.verifying => const _Row(spinner: true, text: 'Checking the code…'),
              _Stage.failed => Text(_error ?? '', style: const TextStyle(color: RemoteColors.power)),
              _Stage.enterCode => Text(
                _join != null
                    ? 'Another phone already uses this TV. Enter the 6-character code shown on the TV to '
                          'join it, so both phones keep working.'
                    : 'Enter the 6-character code shown on your TV.',
                style: theme.textTheme.bodyMedium,
              ),
            },
            if (_stage == _Stage.enterCode || _stage == _Stage.verifying) ...[
              const SizedBox(height: 20),
              TextField(
                controller: _code,
                autofocus: true,
                enabled: _stage == _Stage.enterCode,
                textAlign: TextAlign.center,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 6,
                style: const TextStyle(fontSize: 32, letterSpacing: 10, fontWeight: FontWeight.w600),
                inputFormatters: [
                  // The code is hex: a typed letter O is a zero.
                  TextInputFormatter.withFunction(
                    (_, v) => v.copyWith(text: v.text.toUpperCase().replaceAll('O', '0')),
                  ),
                  FilteringTextInputFormatter.allow(RegExp('[0-9A-F]')),
                ],
                decoration: InputDecoration(
                  counterText: '',
                  errorText: _stage == _Stage.enterCode ? _error : null,
                  filled: true,
                  fillColor: RemoteColors.key,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                ),
                onChanged: (v) {
                  if (_error != null) setState(() => _error = null);
                  if (v.length == 6) _submit();
                },
                onSubmitted: (_) => _submit(),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                const SizedBox(width: 8),
                if (_stage == _Stage.failed)
                  FilledButton(onPressed: _begin, child: const Text('Try again'))
                else
                  FilledButton(onPressed: _stage == _Stage.enterCode ? _submit : null, child: const Text('Pair')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.spinner, required this.text});
  final bool spinner;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      if (spinner) const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
      const SizedBox(width: 12),
      Expanded(child: Text(text)),
    ],
  );
}
