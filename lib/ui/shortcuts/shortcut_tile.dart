import 'package:flutter/material.dart';

import '../theme.dart';
import 'catalog.dart';

/// The square app icon for a shortcut: brand glyph, bundled image, or initials.
class ShortcutIconTile extends StatelessWidget {
  const ShortcutIconTile({super.key, required this.shortcut, this.size = 56});

  final TvShortcut shortcut;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.26);
    final icon = shortcut.icon;
    if (icon is AssetIcon) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.asset(icon.path, width: size, height: size, fit: BoxFit.cover),
      );
    }
    final fg = _foregroundOn(shortcut.color);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: shortcut.color,
        borderRadius: radius,
        // Dark brand tiles would vanish on the dark theme without an edge.
        border: Border.all(color: context.palette.keyEdge.withValues(alpha: 0.6)),
      ),
      child: switch (icon) {
        GlyphIcon(:final data) => Icon(data, size: size * 0.5, color: fg),
        BadgeIcon(:final letters) => Text(
          letters,
          maxLines: 1,
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w800,
            fontSize: size * (letters.length > 2 ? 0.26 : 0.34),
            letterSpacing: -0.5,
          ),
        ),
        AssetIcon() => const SizedBox.shrink(),
      },
    );
  }

  static Color _foregroundOn(Color bg) => bg.computeLuminance() > 0.55 ? const Color(0xFF111111) : Colors.white;
}

/// A shortcut on the remote: icon tile with the app's name under it.
class ShortcutButton extends StatelessWidget {
  const ShortcutButton({super.key, required this.shortcut, required this.onTap, this.busy = false});

  final TvShortcut shortcut;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: 'Open ${shortcut.name}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 76,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: onTap == null ? 0.4 : 1,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ShortcutIconTile(shortcut: shortcut),
                      if (busy)
                        SizedBox.square(
                          dimension: 56,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(56 * 0.26),
                            ),
                            child: const Center(
                              child: SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  shortcut.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: p.muted, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
