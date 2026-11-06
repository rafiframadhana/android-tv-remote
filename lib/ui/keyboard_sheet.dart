import 'package:flutter/material.dart';

import '../core/tv_connection.dart';
import '../core/tv_typing.dart';
import 'shortcuts/catalog.dart';
import 'theme.dart';

/// Live keyboard: mirrors the text box that is focused on the TV. What you type replaces the TV
/// box's content as you go, and changes made on the TV show up here. In YouTube, which doesn't
/// report its search box, it types into YouTube's search instead (see [TvTyping]).
///
/// [auto] means it opened by itself because a text box was opened on the TV; it then also closes
/// by itself when the TV's keyboard closes.
Future<void> showKeyboardSheet(BuildContext context, TvConnection connection, {bool auto = false}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _KeyboardSheet(connection: connection, auto: auto),
    ),
  );
}

class _KeyboardSheet extends StatefulWidget {
  const _KeyboardSheet({required this.connection, required this.auto});
  final TvConnection connection;
  final bool auto;

  @override
  State<_KeyboardSheet> createState() => _KeyboardSheetState();
}

class _KeyboardSheetState extends State<_KeyboardSheet> {
  late final _typing = TvTyping(widget.connection);
  // YouTube's box content is unknown until the first keystroke sets it, so start empty there.
  late final _text = TextEditingController(text: _typing.youtubeMode ? '' : widget.connection.textFieldValue);
  DateTime _lastLocalEdit = DateTime.fromMillisecondsSinceEpoch(0);
  bool _wasActive = false;

  TvConnection get _tv => widget.connection;

  @override
  void initState() {
    super.initState();
    _wasActive = _tv.textFieldActive;
    _tv.addListener(_onTvChanged);
  }

  @override
  void dispose() {
    _tv.removeListener(_onTvChanged);
    _typing.dispose();
    _text.dispose();
    super.dispose();
  }

  void _onTvChanged() {
    if (!mounted) return;
    final active = _tv.textFieldActive;
    if (_wasActive && !active && widget.auto) {
      // The TV's keyboard closed (search submitted, Back pressed): close ours too.
      Navigator.of(context).maybePop();
      return;
    }
    _wasActive = active;
    // Mirror changes made on the TV, but never overwrite what the user is typing right now.
    final tvValue = _tv.textFieldValue;
    final typingNow = DateTime.now().difference(_lastLocalEdit) < const Duration(milliseconds: 1200);
    if (active && !typingNow && tvValue != _text.text) {
      _text.value = TextEditingValue(
        text: tvValue,
        selection: TextSelection.collapsed(offset: tvValue.length),
      );
    }
    setState(() {});
  }

  void _changed(String value) {
    _lastLocalEdit = DateTime.now();
    _typing.changed(value);
  }

  void _enter() {
    final youtube = _typing.youtubeMode;
    _typing.submit(_text.text);
    // YouTube now shows the results with the first video focused: back to the D-pad to pick one.
    if (youtube) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final youtube = _typing.youtubeMode;
    final active = _tv.textFieldActive || youtube;
    final app = _tv.currentApp.isEmpty ? null : appNameFor(_tv.currentApp);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: active ? p.ok : p.muted, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    youtube
                        ? 'Search YouTube'
                        : active
                        ? (app == null ? 'Typing on the TV' : 'Typing in $app')
                        : 'Type on the TV',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              youtube
                  ? 'What you type appears in YouTube’s search. Enter shows the results.'
                  : active
                  ? 'Everything you type appears in the TV’s text box.'
                  : 'Typing goes to the text box selected on the TV. Most apps also open this keyboard '
                        'by themselves when their search box opens; some, like YouTube, don’t.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _text,
              autofocus: true,
              textInputAction: TextInputAction.search,
              autocorrect: false,
              decoration: InputDecoration(
                hintText: 'Type here',
                filled: true,
                fillColor: p.key,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                suffixIcon: _text.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _text.clear();
                          _changed('');
                        },
                      ),
              ),
              onChanged: _changed,
              onSubmitted: (_) => _enter(),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _enter,
                icon: Icon(youtube ? Icons.search_rounded : Icons.keyboard_return),
                label: Text(youtube ? 'Search' : 'Enter'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
