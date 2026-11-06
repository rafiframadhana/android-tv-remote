# TV Remote — v1 design

Date: 2026-11-03. Author: Claude (the user delegated every spec decision: "define the spec by yourself… don't add unnecessary features").
Research basis: `docs/research/android-tv-remote-feasibility.md`.

## Intent

A phone app (Android + iOS) that replaces the physical remote of any Google-certified Android TV / Google TV device:
same buttons, same behaviour, plus the few things a phone does better (typing, touchpad swiping, voice through the phone mic).
Nothing to install on the TV, no developer mode.

## Goals

- Works with every device running Google's **Android TV Remote Service** (protocol v2). That covers certified Android TV / Google TV
  devices (Sony, TCL, Hisense, Philips, Xiaomi global, Shield, Chromecast with Google TV, Google TV Streamer, operator boxes).
- Find TVs automatically on Wi-Fi; manual IP as fallback.
- Pair once with the 6-character code shown on the TV; reconnect silently afterwards.
- Every physical remote button available, with real press/hold semantics (holding OK or Home does what holding it does on the remote).
- Phone-only extras: keyboard text input, touchpad swipe mode, hold-to-talk voice.
- Show TV state: power on/off, volume level, current app.

## Non-goals (v1)

- Bluetooth HID mode, ADB "power mode", Fire TV, vendor APIs (Sony/Philips), IR, Wake-on-LAN, Cast, widgets,
  home-screen tiles, now-playing metadata, screenshots, installed-app list, accounts, analytics, ads.
- Remotely-updatable app-link table (hard-coded for v1).

## Anti-goals

- Anything that makes a button press feel slower or less reliable than the physical remote.
- Asking the user to enable developer options.
- Sending anything off the local network.

## Protocol (ported from tronikos/androidtvremote2, Apache-2.0)

- Pairing on TCP **6467**, commands on **6466**, both TLS. The app presents one self-signed RSA-2048 client certificate
  (generated once per install, stored in secure storage). The TV's self-signed certificate is accepted without verification.
- Framing: varint length prefix + protobuf message.
- Pairing (`polo.proto`, proto2, protocol_version 2, status 200): pairing_request → options (HEX, 6, role INPUT) → configuration →
  TV shows code → secret = SHA-256(client n ‖ client e ‖ server n ‖ server e ‖ bytes(code[2..6])); first hash byte must equal code[0..2]
  → secret → secret_ack.
- Remote (`remotemessage.proto`, proto3): answer remote_configure with features PING|KEY|IME|VOICE|POWER|VOLUME|APP_LINK masked by
  what the TV offers; answer remote_set_active; answer pings (val1 echo); track remote_start (power), remote_set_volume_level,
  remote_ime_key_inject (current app), remote_ime_batch_edit (IME counters). Idle timeout 16 s → reconnect with backoff (0.1 s → 30 s).
  A TLS handshake failure means the TV forgot us → "pair again".
- Messages are encoded by a small hand-written protobuf codec (only the fields we use) to avoid a protoc toolchain.

## Button behaviour

- Normal buttons: tap (< 400 ms) → `SHORT`. Hold ≥ 400 ms → `START_LONG` at 400 ms, `END_LONG` on release
  (holding OK opens context menus, holding Home opens the dashboard, exactly like the hardware remote).
- Repeating buttons (arrows, volume, channel): first `SHORT` on touch-down, then after 400 ms another `SHORT` every 100 ms
  until release — mirrors hardware auto-repeat for scrolling and volume ramps, and doesn't depend on the TV
  synthesising repeats for injected long presses (unverified behaviour). **Claude's call.**
- Haptic tick on every press.

## Screens

1. **Devices** — discovered TVs (live mDNS list), paired TVs, "Add by IP". Tap → pair if new, else connect.
2. **Pairing sheet** — "Enter the code shown on your TV", 6 hex chars, validated locally with the checksum byte before sending.
3. **Remote** — top: TV name + status dot + current app, Power, Input. Middle: D-pad ring with OK (or touchpad, toggle).
   Below: Back · Home · Settings; Volume rocker, Mute, Channel rocker; media row (rewind, play/pause, fast-forward);
   app shortcuts (YouTube, Netflix, Prime Video, Disney+ via deep links); bottom bar: Keyboard, Mic (hold to talk), More keys.
4. **More keys sheet** — 0–9, Guide, Info, Captions, Live TV, Stop, Previous, Next, Red/Green/Yellow/Blue.
5. **Keyboard sheet** — text field mirrored to the TV's focused field (full value sent on each change), Enter, Backspace.

## Stack

Flutter (Dart), Material 3, dark-first. Packages: `pointycastle` (RSA, ASN.1), `basic_utils` (X.509 self-signed cert),
`crypto` (SHA-256), `bonsoir` (mDNS via NSD/Bonjour), `flutter_secure_storage` (cert/key), `shared_preferences` (TV list),
`record` (PCM 16-bit 8 kHz mono mic stream; it also requests the mic permission).
State: plain `ChangeNotifier`s, no state-management framework.

Platform config: Android `INTERNET`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_MULTICAST_STATE`, `RECORD_AUDIO`.
iOS `NSLocalNetworkUsageDescription`, `NSBonjourServices` = `_androidtvremote2._tcp`, `NSMicrophoneUsageDescription`.

## Code layout

```
lib/protocol/   pure Dart, no Flutter imports, fully unit-tested
  proto.dart            minimal protobuf writer/reader
  framing.dart          varint length-delimited frame decoder/encoder
  polo_messages.dart    pairing messages
  remote_messages.dart  remote messages
  key_codes.dart        Android KeyEvent codes used by the UI
  pairing_crypto.dart   RSA public key from cert DER, secret computation, code check
  pairing_session.dart  pairing state machine over a byte channel
  remote_session.dart   remote state machine over a byte channel
lib/core/       platform glue: certificate store, TLS connector, discovery, device store, voice capture, connection manager
lib/ui/         screens and widgets
test/           unit tests for lib/protocol (+ fake-TV session tests)
```

## Verification

- Unit tests: codec round-trips against bytes produced by the reference Python protobuf messages, secret computation against a
  vector produced by Python `cryptography`, pairing and remote session flows against a scripted fake TV.
- `flutter analyze` clean, Android debug APK builds.
- End-to-end against a real Remote Service if a Google TV emulator image is obtainable; otherwise documented as untested on hardware.
- iOS cannot be built on this Windows machine: config is written but unverified.

## Verification results (2026-11-03)

- 62 automated tests pass (`flutter test`), `flutter analyze` clean, debug APK builds.
- End-to-end against Google's real **Android TV Remote Service 5.99** on the Google TV (Android 14) emulator:
  - Pairing from the app itself: the code appeared on the TV, was typed in the app, and was accepted.
  - The remote session reported vendor, model, power, volume (3/15 → 6/15 after presses) and the current app (launcher).
  - D-pad presses moved focus on the TV, volume keys changed the TV volume, and the pairing survived an app restart.
  - App link: the TV logged `AtvRemote.AppLinkFeature: Handling an App Link launch request` and fired the VIEW intent.
    The unprovisioned emulator only has a browser stub for it, so no app opened.
  - Emulator note: the Remote Service refuses command-port connections that arrive via `adb forward` on loopback.
    Use `adb emu redir add tcp:6466:6466` and `tcp:6467:6467` (NAT) instead. The Python reference behaves the same way.
- **Not verified:** voice on a real device mic, text entry into a live TV search field, iOS (needs a Mac), and
  physical TVs from other brands.

## Security design (review of 2026-11-03)

- **TV identity pinning.** The TV's TLS certificate seen during pairing is authentic, because pairing binds both public keys into the secret. Its SHA-256 is stored with the TV (`SavedTv.pins`) and checked on every command-port connection before anything is sent (`core/pinning.dart`).
  - The Remote Service presents the same certificate on 6466 and 6467 (verified on 5.99).
  - The first connection after pairing may add one different certificate, for TVs that might use separate certificates per port.
  - On a mismatch the status is `identityChanged`: nothing is sent, and the user is offered "Pair again".
  - Verified end-to-end: corrupting the stored pin produced the refusal, and re-pairing recovered.
- **Following a new IP address.** A TV that moves to a new IP (seen via mDNS by name) is only followed when it already has a verified pin. The new address is saved only after a pinned connection succeeds there; otherwise it's rejected and the app goes back to the saved address.
- **Microphone.** Every await in `VoiceCapture.start` re-checks that the key is still held, so releasing at any moment (including during the permission prompt) stops the mic. The pre-session buffer is capped at about 10 s.
- **Hostile input.**
  - The protobuf length check is overflow-safe.
  - Any decode error is ignored, not thrown.
  - Frames are capped at 1 MB.
  - TLS handshakes are bounded by a timeout.
  - If the TV sends nothing for 60 s, even while keys keep being sent, the connection is closed.
- **Reconnect classification.** A single TLS failure or early close is retried. Only two in a row mean "needs pairing".
- **Not changed:** the pairing checksum is only 8 bits, which is inherent to the protocol. Secure storage resets on a decryption error, so a restored backup leads to re-pairing.

## Known limitations (carried from research)

- Not supported: Fire TV, uncertified AOSP boxes, China-market forks.
- Power-on fails on TVs that drop Wi-Fi in standby.
- Some apps (Netflix) may ignore injected keys; voice chunk sizes are device-sensitive (we send 20 KB chunks, padded to ≥ 8 KB).
