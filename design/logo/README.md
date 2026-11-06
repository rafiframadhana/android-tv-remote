# TV Remote logo

**Idea:** the app's ring D-pad with one key pressed. The right key splits away from the ring and lights up amber,
the same "standby LED" glow the remote shows when you press it. The disc in the centre is OK.

All artwork is generated from `build_logo.py`, which uses pure geometry on a 256-unit grid:

- The ring spans r 58–104.
- The cuts are 11 units wide.
- The OK dot has r 34.

`lib/ui/widgets/brand_mark.dart` draws the same geometry in the app.

| File | Use |
|---|---|
| `tv-remote-symbol.svg` | Full-colour mark on a dark background |
| `tv-remote-symbol-black.svg` / `-white.svg` | One-colour versions |
| `app-icon.svg` | Square app icon: the mark at 62% on the body colour |
| `adaptive-foreground.svg` / `adaptive-monochrome.svg` | Android adaptive and themed-icon layers. `flutter_launcher_icons` adds a 16% inset. |
| `png/` | 1024 px renders used to generate the platform icons |
| `concepts/` | Explored directions: A (chosen, v1 → v2), B and C, plus `concepts.png` |

**Colours:**
- Body: `#1A2030`
- Light: `#E8EBF2`
- LED amber: `#F0B23E`. Use it only for the pressed key, never for the whole mark.

**Regenerate the icons:**
1. Run `python design/logo/build_logo.py`.
2. Render the PNGs, using the logo-design skill's `render_png.py --size 1024`.
3. Run `dart run flutter_launcher_icons`.

**Rules:**
- The mark must stay readable at 48 px, and was checked at that size.
- Don't add a TV outline or text inside the icon.

A professional trademark search hasn't been done.
