import 'package:flutter/material.dart';

import '../core/tv_connection.dart';
import '../protocol/key_codes.dart';
import 'theme.dart';

/// Type on the phone; the text replaces the TV's focused text field as you go.
Future<void> showKeyboardSheet(BuildContext context, TvConnection connection) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _KeyboardSheet(connection: connection),
    ),
  );
}

class _KeyboardSheet extends StatefulWidget {
  const _KeyboardSheet({required this.connection});
  final TvConnection connection;

  @override
  State<_KeyboardSheet> createState() => _KeyboardSheetState();
}

class _KeyboardSheetState extends State<_KeyboardSheet> {
  final _text = TextEditingController();

  void _enter() {
    widget.connection.sendKey(Keys.enter);
    _text.clear();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type on the TV', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('Select a search box on the TV first.', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: _text,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search or type',
                filled: true,
                fillColor: RemoteColors.key,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                suffixIcon: IconButton(
                  tooltip: 'Delete on TV',
                  icon: const Icon(Icons.backspace_outlined),
                  onPressed: () => widget.connection.sendKey(Keys.del),
                ),
              ),
              onChanged: widget.connection.sendText,
              onSubmitted: (_) => _enter(),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _enter,
                icon: const Icon(Icons.keyboard_return),
                label: const Text('Enter'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
