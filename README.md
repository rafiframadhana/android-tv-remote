# TV Remote

A phone remote (Android + iOS, Flutter) for Android TV and Google TV devices. It uses Google's
built-in **Android TV Remote Service** (protocol v2, the same one the Google TV app uses), so the
TV needs no extra app and no developer mode.

- Background research: [`docs/research/android-tv-remote-feasibility.md`](docs/research/android-tv-remote-feasibility.md)
- v1 design: [`docs/superpowers/specs/2026-11-03-tv-remote-design.md`](docs/superpowers/specs/2026-11-03-tv-remote-design.md)

## What it does

- Finds TVs on your Wi-Fi (mDNS `_androidtvremote2._tcp`), or you add one by IP address.
- Pairs once with the 6-character code shown on the TV. Typos are caught on the phone.
- Includes every physical-remote key: power, input, settings, D-pad/OK, back, home, volume, mute,
  channel, media, number pad, guide, info, captions, colour keys, live TV and Assistant.
  - Tapping a key is a short press, and holding it is a long press (holding OK opens context menus).
  - Arrows, volume and channel keys repeat while held.
- Phone-only extras: a touchpad swipe mode, typing into the TV's search box, hold-to-talk voice
  search, and shortcuts for YouTube, Netflix, Prime Video and Disney+.
- Shows whether the screen is on, the volume level, and which app is open.
- Reconnects on its own and follows the TV to a new IP address.

It doesn't work on Fire TV, uncertified AOSP boxes or China-market TVs, because they don't have
Google's Remote Service. A TV that drops off Wi-Fi in standby can't be turned on from the phone.

## Run

```sh
flutter pub get
flutter test          # protocol, sessions, TLS integration
flutter run           # phone on the same Wi-Fi as the TV
```

iOS has to be built on a Mac (`flutter build ios`).

## Layout

| Path | What |
|---|---|
| `lib/protocol/` | Pure-Dart port of the protocol (from [tronikos/androidtvremote2](https://github.com/tronikos/androidtvremote2), Apache-2.0): protobuf codec, framing, pairing crypto, pairing and remote session state machines |
| `lib/core/` | Platform glue: TLS client certificate, connection manager with reconnect, discovery, storage, key timing, voice capture |
| `lib/ui/` | Screens and widgets |
| `test/fixtures/vectors.dart` | Byte-exact test vectors generated from the Python reference's protobufs |
| `tool/tv_e2e.dart` | Command-line driver for testing against a real TV or the Google TV emulator |

## Testing against a real TV from a computer

```sh
dart run tool/tv_e2e.dart pair   192.168.1.20 .e2e      # then write the TV's code to .e2e/code.txt
dart run tool/tv_e2e.dart remote 192.168.1.20 .e2e 6466 key:3 wait:1000 key:20 text:hello
```
