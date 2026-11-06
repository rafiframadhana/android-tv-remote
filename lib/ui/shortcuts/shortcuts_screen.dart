import 'package:flutter/material.dart';

import '../../core/app_settings.dart';
import '../app_scope.dart';
import '../theme.dart';
import 'catalog.dart';
import 'shortcut_tile.dart';

/// Choose and order the app shortcuts on the remote.
class ShortcutsScreen extends StatefulWidget {
  const ShortcutsScreen({super.key});

  @override
  State<ShortcutsScreen> createState() => _ShortcutsScreenState();
}

class _ShortcutsScreenState extends State<ShortcutsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('Shortcuts')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final enabled = settings.enabledShortcuts;
          final q = _query.toLowerCase();
          final more = [
            for (final s in settings.allShortcuts)
              if (!settings.isEnabled(s.id) && (q.isEmpty || s.name.toLowerCase().contains(q))) s,
          ];
          return CustomScrollView(
            slivers: [
              _header(context, 'On your remote', 'Drag to change the order.'),
              if (enabled.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Text('No shortcuts yet. Turn some on below.', style: Theme.of(context).textTheme.bodySmall),
                  ),
                )
              else
                SliverReorderableList(
                  itemCount: enabled.length,
                  onReorderItem: settings.moveEnabled,
                  itemBuilder: (context, i) => _Row(
                    key: ValueKey(enabled[i].id),
                    shortcut: enabled[i],
                    settings: settings,
                    enabled: true,
                    dragIndex: i,
                  ),
                ),
              _header(context, 'More apps', null),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v.trim()),
                    decoration: InputDecoration(
                      hintText: 'Search apps',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: p.key,
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                ),
              ),
              SliverList.builder(
                itemCount: more.length,
                itemBuilder: (context, i) =>
                    _Row(key: ValueKey('more-${more[i].id}'), shortcut: more[i], settings: settings, enabled: false),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: OutlinedButton.icon(
                    onPressed: () => _editCustom(context, settings, null),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add your own app'),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  child: Text(
                    'App names and logos are trademarks of their owners. TV Remote is not affiliated with them. '
                    'A shortcut works only if the app is installed on your TV.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context, String title, String? hint) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: context.palette.muted)),
          ),
          if (hint != null) Text(hint, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({super.key, required this.shortcut, required this.settings, required this.enabled, this.dragIndex});

  final TvShortcut shortcut;
  final AppSettings settings;
  final bool enabled;
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final custom = shortcut.id.startsWith('custom-');
    final status = switch (shortcut) {
      TvShortcut(template: true) => 'Link needed: tap ⋯ to add it',
      TvShortcut(storeFallback: true) => 'Opens through Play Store',
      _ when custom => shortcut.link,
      _ when settings.hasLinkOverride(shortcut.id) => 'Custom link',
      _ => null,
    };
    return Material(
      color: p.body,
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 16, right: 4),
        leading: ShortcutIconTile(shortcut: shortcut, size: 40),
        title: Text(shortcut.name),
        subtitle: status == null ? null : Text(status, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: enabled, onChanged: (on) => settings.setEnabled(shortcut.id, on)),
            IconButton(
              tooltip: 'Edit ${shortcut.name}',
              icon: Icon(Icons.more_horiz_rounded, color: p.muted),
              onPressed: () =>
                  custom ? _editCustom(context, settings, shortcut) : _editLink(context, settings, shortcut),
            ),
            if (dragIndex != null)
              ReorderableDragStartListener(
                index: dragIndex!,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.drag_handle_rounded, color: p.muted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Lets the user set or reset a catalogue shortcut's link (links can break after app updates).
Future<void> _editLink(BuildContext context, AppSettings settings, TvShortcut s) async {
  final defaultLink = shortcutCatalog.firstWhere((c) => c.id == s.id).link;
  final controller = TextEditingController(text: s.link);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${s.name} link'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The address the TV opens for this app, e.g. "netflix://" or "https://www.youtube.com".',
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(hintText: defaultLink.isEmpty ? 'app://' : defaultLink),
          ),
        ],
      ),
      actions: [
        if (settings.hasLinkOverride(s.id))
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Reset')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Save')),
      ],
    ),
  );
  controller.dispose();
  if (result == null) return;
  // Saving the default value (or an empty field) means "no override".
  await settings.setLinkOverride(s.id, result.trim() == defaultLink ? '' : result);
}

/// Add a new app or edit/remove one the user added.
Future<void> _editCustom(BuildContext context, AppSettings settings, TvShortcut? existing) async {
  final name = TextEditingController(text: existing?.name ?? '');
  final link = TextEditingController(text: existing?.link ?? '');
  final action = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(existing == null ? 'Add your own app' : 'Edit ${existing.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            autofocus: existing == null,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: link,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Link', hintText: 'app:// or https://…'),
          ),
        ],
      ),
      actions: [
        if (existing != null) TextButton(onPressed: () => Navigator.pop(ctx, 'remove'), child: const Text('Remove')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
      ],
    ),
  );
  final n = name.text.trim(), l = link.text.trim();
  name.dispose();
  link.dispose();
  if (action == 'remove' && existing != null) {
    await settings.removeCustom(existing.id);
  } else if (action == 'save' && n.isNotEmpty && l.isNotEmpty) {
    if (existing == null) {
      await settings.addCustom(n, l);
    } else {
      await settings.updateCustom(existing.id, name: n, link: l);
    }
  }
}
