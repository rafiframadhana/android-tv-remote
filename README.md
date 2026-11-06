# TV Remote

A phone remote (Android + iOS, Flutter) for Android TV and Google TV devices. It uses Google's
built-in **Android TV Remote Service** (protocol v2, the same one the Google TV app uses), so the
TV needs no extra app and no developer mode.

- Background research: [`docs/research/android-tv-remote-feasibility.md`](docs/research/android-tv-remote-feasibility.md)
- v1 design: [`docs/superpowers/specs/2026-11-03-tv-remote-design.md`](docs/superpowers/specs/2026-11-03-tv-remote-design.md)
- Logo: [`design/logo/README.md`](design/logo/README.md)

## What it does

**Finding and pairing**
- Finds TVs on your Wi-Fi (mDNS `_androidtvremote2._tcp`). The search runs while you watch and then
  stops, with a "Search again" option. You can also add a TV by IP address.
- You pair once with the 6-character code shown on the TV. The phone catches typos, including a
  letter O typed instead of a zero.
- **Several phones on one TV.** Some TVs remember only the last remote paired with them. When a
  second phone pairs, it joins the pairing of a phone that already uses the TV (the code shown on
  the TV unlocks the handover), so both keep working at the same time.
- **Automatic re-pairing.** If the TV forgets the phone (another remote paired, or the TV was
  reset), the app notices within seconds and opens "Pair again". Cancelling also closes the code
  screen on the TV.

**Remote**
- It has every physical-remote key: power, input, settings, D-pad/OK, back, home, volume, mute,
  channel, media, number pad, guide, info, captions, colour keys, live TV and Assistant.
  - A tap is a short press and holding is a long press. Arrows, volume and channel repeat while held.
  - Settings and Input fall back to navigating the TV's home screen on TVs that ignore those keys
    (seen on a Panasonic/Realtek Android TV 9).
- Phone-only extras: a touchpad swipe mode, a live keyboard and hold-to-talk voice search.
- **Live keyboard.** When a text box opens on the TV (search in YouTube, Stremio, Play Store and so
  on), the phone keyboard opens by itself. What you type appears on the TV as you type it, changes
  made on the TV show up on the phone, and it closes when the TV's keyboard closes.
  - YouTube doesn't report its search box, so there you open the keyboard with the keyboard
    button. Typing goes to YouTube's search, and Search shows the results. Because a Backspace in
    an empty YouTube box acts as Back, deletions are sent as a new search instead
    (`lib/core/tv_typing.dart`).
- It shows whether the screen is on, the volume level, and which app is open.
- It reconnects on its own and follows the TV to a new IP address.

**App shortcuts** (Settings → Shortcuts)
- A catalogue of 35 TV apps with icons, including YouTube, Netflix, Prime Video, Disney+, Play Store,
  BitTV, Stremio, Spotify, Vidio, WeTV, Viu and others. You can switch apps on, search, drag them
  into order, change an app's link, or add your own app.
- Apps open by link (`remote_app_link_launch_request`), and the TV confirms when the app is in
  front. Apps without a known link open through their Play Store page.
- The catalogue is in `lib/ui/shortcuts/catalog.dart`. Entries marked `verified` were confirmed on
  a real TV.

**Appearance:** System, Light or Dark theme (Settings → Theme).

**Security:** the TV's certificate is pinned at pairing, so the phone sends nothing to a device that
merely claims the TV's name or address. See the security section of the design doc.

It doesn't work on Fire TV, uncertified AOSP boxes or China-market TVs, because they don't have
Google's Remote Service. A TV that drops off Wi-Fi in standby can't be turned on from the phone.

## Run

```sh
flutter pub get
flutter test                                  # unit, widget and TLS integration tests
flutter run                                   # phone on the same Wi-Fi as the TV
flutter build apk --release --split-per-abi   # about 19 MB per phone type
```

iOS has to be built on a Mac (`flutter build ios`).

## Layout

| Path | What |
|---|---|
| `lib/protocol/` | Pure-Dart port of the protocol (from [tronikos/androidtvremote2](https://github.com/tronikos/androidtvremote2), Apache-2.0): protobuf codec, framing, pairing crypto, pairing and remote session state machines |
| `lib/core/` | Platform glue: TLS client certificate and pinning, connection manager with reconnect and rejection detection, discovery, pairing sharing between phones, settings, app launcher, Settings/Input shortcuts, voice capture |
| `lib/ui/` | Screens and widgets; `lib/ui/shortcuts/` holds the app catalogue, its tiles and the Shortcuts screen |
| `assets/shortcuts/` | Bundled app icons that aren't in Simple Icons (BitTV) |
| `design/logo/` | Logo source (`build_logo.py`) and icon artwork |
| `test/fixtures/vectors.dart` | Byte-exact test vectors generated from the Python reference's protobufs |
| `test/manual/` | Checks against a real TV (tagged `manual`, skipped by default) |
| `tool/tv_e2e.dart` | Command-line driver for testing against a real TV or the Google TV emulator |

## Testing against a real TV from a computer

```sh
# Pair, then write the code shown on the TV to .e2e/code.txt
dart run tool/tv_e2e.dart pair 192.168.1.20 .e2e

# Remote commands: key:<code> long:<code> text:<string> type:<string> link:<uri> voice:<wav> wait:<ms>
#   phone:<text> / phone-enter:<text> run the app's keyboard logic (including the YouTube handling)
# (--raw-ime prints the TV's keyboard messages)
dart run tool/tv_e2e.dart remote 192.168.1.20 .e2e 6466 key:3 wait:1000 key:20 link:tv://
dart run tool/tv_e2e.dart remote 192.168.1.20 .e2e 6466 --novoice key:84   # Search key without voice

# Share a pairing between two clients: A offers it, B joins with the TV's code
dart run tool/tv_e2e.dart share-host 192.168.1.20 .e2e
dart run tool/tv_e2e.dart share-join 192.168.1.20 .e2e-b 127.0.0.1:<port printed by share-host>

# Start pairing and cancel it (the TV should close its code screen)
dart run tool/tv_e2e.dart pair-cancel 192.168.1.20 .e2e

# The app's reconnect logic against a TV that has forgotten this client
REAL_TV=192.168.1.20 REAL_TV_ID=.e2e flutter test --tags manual --run-skipped test/manual/real_tv_rejected_test.dart

# Open catalogue apps from a cold start and print what the app would report (ADB optional)
REAL_TV=192.168.1.20 REAL_TV_ID=.e2e ADB=adb flutter test --tags manual --run-skipped test/manual/real_tv_launch_test.dart
```

`.e2e*/` folders hold client keys and are git-ignored.

Some things can't be checked from the remote protocol. With ADB enabled on the TV
(`adb connect <tv-ip>:5555`):
- `pm list packages` shows which apps are installed.
- `dumpsys package <pkg>` lists the links an app accepts (look at its VIEW filters).
- `am start -a android.intent.action.VIEW -d <link>` opens an app the same way the remote service does.
