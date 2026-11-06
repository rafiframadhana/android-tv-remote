import 'package:flutter/material.dart';

import '../core/tv_connection.dart';
import '../protocol/key_codes.dart';
import 'theme.dart';
import 'widgets/remote_key.dart';

/// Keys found on fuller remotes: number pad, guide, colour keys, transport.
Future<void> showMoreKeysSheet(BuildContext context, TvConnection connection) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => RemoteScope(connection: connection, child: const _MoreKeys()),
  );
}

class _MoreKeys extends StatelessWidget {
  const _MoreKeys();

  @override
  Widget build(BuildContext context) {
    Widget row(List<Widget> keys) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: keys),
    );
    RemoteKey digit(int n) => RemoteKey(keyCode: Keys.digit(n), label: '$n', width: 84);
    Widget color(int code, Color c, String label) =>
        RemoteKey(keyCode: code, label: label, icon: Icons.circle, color: c, width: 64, height: 44);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          children: [
            row([digit(1), digit(2), digit(3)]),
            row([digit(4), digit(5), digit(6)]),
            row([digit(7), digit(8), digit(9)]),
            row([
              const RemoteKey(keyCode: Keys.guide, label: 'Guide', width: 84),
              digit(0),
              const RemoteKey(keyCode: Keys.info, label: 'Info', width: 84),
            ]),
            const SizedBox(height: 4),
            row([
              color(Keys.progRed, const Color(0xFFE5484D), 'Red'),
              color(Keys.progGreen, const Color(0xFF46A758), 'Green'),
              color(Keys.progYellow, const Color(0xFFFFC53D), 'Yellow'),
              color(Keys.progBlue, const Color(0xFF3E83F8), 'Blue'),
            ]),
            row(const [
              RemoteKey(keyCode: Keys.mediaPrevious, label: 'Previous', icon: Icons.skip_previous_rounded),
              RemoteKey(keyCode: Keys.mediaStop, label: 'Stop', icon: Icons.stop_rounded),
              RemoteKey(keyCode: Keys.mediaNext, label: 'Next', icon: Icons.skip_next_rounded),
              RemoteKey(keyCode: Keys.captions, label: 'Captions', icon: Icons.closed_caption_outlined),
            ]),
            row(const [
              RemoteKey(keyCode: Keys.tv, label: 'Live TV', width: 100),
              RemoteKey(keyCode: Keys.menu, label: 'Menu', width: 100),
              RemoteKey(keyCode: Keys.assist, label: 'Assistant', icon: Icons.assistant_outlined, width: 100),
            ]),
            Text(
              'Some keys only work on TVs with a tuner or in apps that support them.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: RemoteColors.muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
