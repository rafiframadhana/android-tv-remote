import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/device_store.dart';
import '../core/discovery.dart';
import 'app_scope.dart';
import 'pairing_sheet.dart';
import 'remote_screen.dart';
import 'theme.dart';
import 'widgets/brand_mark.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late final AppServices _services = AppScope.of(context);

  /// This screen lives at the bottom of the stack for the app's lifetime, so it owns
  /// discovery's lifecycle: no network browsing while the app is in the background.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    unawaited(_services.discovery.scan());
    _lifecycle = AppLifecycleListener(
      onHide: () {
        unawaited(_services.discovery.stop());
        unawaited(_services.share.stop());
      },
      onShow: () {
        unawaited(_services.discovery.scan());
        unawaited(_services.share.start());
      },
    );
    // While the app is open, let other phones join this phone's TVs instead of replacing them.
    unawaited(_services.share.start());
    // Create the phone's certificate early; it takes a few seconds the first time.
    unawaited(_services.identity.identity.then((_) {}, onError: (_) {}));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _open(SavedTv tv) async {
    await _services.devices.touch(tv);
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => RemoteScreen(tv: tv)));
  }

  Future<void> _pair(String host, String name, {bool manualName = false}) async {
    final tv = await showPairingSheet(context, host: host, name: name, manualName: manualName);
    if (tv != null && mounted) await _open(tv);
  }

  Future<void> _addByIp() async {
    final host = await showDialog<String>(context: context, builder: (_) => const _AddByIpDialog());
    if (host != null && mounted) await _pair(host, 'TV at $host', manualName: true);
  }

  Future<void> _forget(SavedTv tv) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Forget ${tv.name}?'),
        content: const Text("You'll need to pair again to use it."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Forget')),
        ],
      ),
    );
    if (ok ?? false) {
      await _services.identity.removeShared(tv);
      await _services.devices.forget(tv);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Row(children: [BrandMark(size: 28), SizedBox(width: 12), Text('TVs')])),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addByIp,
        icon: const Icon(Icons.add),
        label: const Text('Add by IP address'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([_services.devices, _services.discovery]),
        builder: (context, _) {
          final saved = _services.devices.tvs;
          final found = _unpaired(_services.discovery.tvs, _services.devices);
          return RefreshIndicator(
            onRefresh: _services.discovery.scan,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              children: [
                if (saved.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 32, 4, 8),
                    child: Column(
                      children: [
                        const BrandMark(size: 88),
                        const SizedBox(height: 20),
                        Text('Use this phone as your TV remote', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 6),
                        Text(
                          'Works with Android TV and Google TV. Pick your TV below to pair it once.',
                          style: theme.textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                if (saved.isNotEmpty) ...[
                  _Section('Paired'),
                  for (final tv in saved)
                    _TvTile(
                      title: tv.name,
                      subtitle: tv.host,
                      icon: Icons.tv_rounded,
                      onTap: () => _open(tv),
                      onLongPress: () => _forget(tv),
                    ),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    Expanded(child: _Section('On this Wi-Fi')),
                    if (_services.discovery.isScanning)
                      const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: Row(
                          children: [
                            SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 8),
                            Text('Searching', style: TextStyle(color: RemoteColors.muted)),
                          ],
                        ),
                      )
                    else
                      TextButton.icon(
                        onPressed: _services.discovery.scan,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Search again'),
                      ),
                  ],
                ),
                if (found.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _services.discovery.error != null
                          ? "Couldn't search the network. Add your TV by its IP address instead "
                                '(on the TV: Settings › Network › About).'
                          : _services.discovery.isScanning
                          ? 'Looking for Android TV and Google TV devices on this Wi-Fi…'
                          : 'No new TVs found. Check the TV is on and on the same Wi-Fi as this phone, '
                                'then search again, or add it by IP address.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                for (final d in found)
                  _TvTile(
                    title: d.name,
                    subtitle: d.host,
                    icon: Icons.add_link_rounded,
                    trailing: const Text(
                      'Pair',
                      style: TextStyle(color: RemoteColors.led, fontWeight: FontWeight.w600),
                    ),
                    onTap: () => _pair(d.host, d.name),
                  ),
                if (saved.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: Text('Press and hold a paired TV to forget it.', style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: RemoteColors.muted)),
  );
}

class _TvTile extends StatelessWidget {
  const _TvTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.onLongPress,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: RemoteColors.key,
      borderRadius: BorderRadius.circular(18),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        leading: Icon(icon, color: RemoteColors.text),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(color: RemoteColors.muted)),
        trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: RemoteColors.muted),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    ),
  );
}

class _AddByIpDialog extends StatefulWidget {
  const _AddByIpDialog();

  @override
  State<_AddByIpDialog> createState() => _AddByIpDialogState();
}

class _AddByIpDialogState extends State<_AddByIpDialog> {
  final _ip = TextEditingController();
  String? _error;

  void _submit() {
    final value = _ip.text.trim();
    if (InternetAddress.tryParse(value) == null) {
      setState(() => _error = 'Enter an address like 192.168.1.20');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  void dispose() {
    _ip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add by IP address'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Find it on the TV under Settings › Network & Internet, then select your Wi-Fi network.'),
        const SizedBox(height: 16),
        TextField(
          controller: _ip,
          autofocus: true,
          // Not a decimal number keyboard: Android's number field accepts only one '.'.
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(hintText: '192.168.1.20', errorText: _error),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _submit, child: const Text('Pair')),
    ],
  );
}

/// Discovered TVs that aren't paired yet (matched by name or address).
List<DiscoveredTv> _unpaired(List<DiscoveredTv> found, DeviceStore store) =>
    found.where((d) => store.byHost(d.host) == null).toList();
