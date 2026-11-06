# Android TV / Google TV phone remote: feasibility research

Research date: 2026-11-03. Scope: a third-party Android app (and, if possible, an iOS app) that does everything the physical remote does, plus features only a phone can offer, on at least 90% of Android TV devices.

Conventions:
- **UNVERIFIED** means I could not confirm the claim from a primary source. Treat it as a hypothesis to test on real hardware.
- Source URLs are inline. Where a fact comes from source code, I link the file.
- "v2" means the Android TV Remote protocol v2, the protocol behind the Google TV and Google Home app remotes.

---

## 1. TL;DR verdict

**Feasible.** A third-party app can control GMS-certified Android TV and Google TV devices over the network, with no software installed on the TV and no developer mode. This has been reverse-engineered and implemented in several open-source projects. The most mature is `tronikos/androidtvremote2`, which ships as a Platinum-quality integration in Home Assistant core. Paid third-party apps on the App Store already use the same flow. The protocol works the same way from Android and iOS.

What v2 gives you: any Android `KeyEvent` keycode (D-pad, OK, back, home, volume, mute, power, channel, input/HDMI, numbers, settings, guide, colour keys, app-button keycodes), long-press, text entry into the focused field, app launch by deep link, power state, current foreground app, volume level/max/mute, and voice (streaming microphone PCM to the Assistant).

What v2 does **not** give you: an installed-app list, screenshots, a mouse pointer, now-playing metadata (title, position), or reliable power-on of TVs that drop off the network in standby.

**The 90% target:**
- **≥90% of GMS-certified Android TV / Google TV devices: very likely**, as long as "works" means "controls the device while it is on." Of the brands named, all ship Google-certified models: Sony, TCL, Hisense (Google TV models only, not VIDAA), Philips (Android/Google TV models only), Xiaomi (global models), Nvidia Shield, Chromecast with Google TV, Google TV Streamer, and operator boxes. The device needs Android TV Remote Service v5 or later. Exact coverage is **UNVERIFIED**; no public data exists.
- **≥90% of all Android-based TV devices: no, not with v2 alone.** Three groups are out of v2's reach:
  - Cheap AOSP/uncertified boxes, which lack Google's Remote Service.
  - Fire TV, which lacks the Remote Service.
  - China-market TVs. Per Omdia, about 96% of China shipments run localized Android forks without Google services.
- To reach these groups, the Android app needs fallbacks: **Bluetooth HID** (phone pretends to be a BT keyboard/remote; Android phones only, works on nearly any box) and **ADB** (power users). Fire TV needs its own add-on (Amazon's REST protocol, or ADB). iOS can use only the network protocols, so iOS coverage tops out at certified devices plus Fire TV.

**Recommended architecture:**
1. v2 as the primary transport, on both platforms.
2. Bluetooth HID as the fallback for uncertified boxes and offline use (Android only).
3. Optional ADB "power mode" for app lists, screenshots, and arbitrary intents.
4. Vendor add-ons: the Fire TV REST protocol, and optionally Sony IRCC/REST and Philips JointSpace for power-on and input switching.
5. Wake-on-LAN and Cast as helpers for power-on.

---

## 2. Coverage matrix

Legend: ✅ works · ⚠️ partial or device-dependent · ❌ no · ? unknown/UNVERIFIED

| Approach | Certified Android TV / Google TV (Sony, TCL, Hisense-GTV, Philips-ATV, Xiaomi global, Shield, CCwGTV, GTV Streamer, operator boxes) | Uncertified AOSP boxes (X96, T95, MXQ…) | Fire TV (Fire OS, Android-based) | Fire TV (Vega OS, 2025+) | iOS client possible? | User setup required |
|---|---|---|---|---|---|---|
| **v2 protocol** (TLS, ports 6466/6467) | ✅ (Remote Service ≥ v5) | ❌ usually missing Remote Service (? some ship it sideloaded) | ❌ no Remote Service | ❌ | ✅ | Enter 6-hex-digit code shown on TV, once |
| **v1 protocol** (old "Android TV Remote Control" app) | ⚠️ only devices stuck on Remote Service < v5 | ❌ | ❌ | ❌ | ✅ | Pairing code |
| **ADB over network** | ⚠️ needs Developer options + USB/network/wireless debugging; behaviour varies by vendor | ✅ often (many ship with adb open) ? | ✅ "ADB debugging" toggle | ❌ (no ADB) | ✅ (pure-TCP ADB client) ? | Developer options, accept RSA prompt; sometimes re-pair after reboot |
| **Bluetooth HID** (phone acts as BT keyboard, mouse, or consumer-control device) | ✅ | ✅ (if box has BT) | ✅ ? | ? | ❌ iOS cannot act as an HID peripheral | Pair phone in the TV's Bluetooth settings |
| **IR blaster** (ConsumerIrManager) | ⚠️ only TVs with an IR receiver; per-brand codes | ⚠️ | ⚠️ (Fire TV Stick has no IR receiver; Fire TV-edition TVs do) ? | ⚠️ | ❌ iPhones have no IR | Phone must have an IR emitter (Xiaomi/Redmi/POCO, some vivo/Honor) |
| **Fire TV REST** (port 8080 + voice WebSocket 9090) | ❌ | ❌ | ✅ (community reverse-engineered) | ? | ✅ | PIN shown on TV |
| **Sony BRAVIA REST/IRCC-IP** | ⚠️ Sony only | ❌ | ❌ | ❌ | ✅ | Enable IP control + Pre-Shared Key on TV |
| **Philips JointSpace** (port 1926) | ⚠️ Philips only | ❌ | ❌ | ❌ | ✅ | Pairing code |
| **Google Cast** | ⚠️ complement only (launch Cast apps, media status for Cast sessions, can wake some devices) | ❌ | ❌ | ❌ | ✅ | None |
| **Wake-on-LAN** | ⚠️ only if NIC/Wi-Fi wake is supported and enabled | ⚠️ | ⚠️ | ? | ⚠️ iOS needs Apple's multicast entitlement for broadcast | Enable network standby / WoL on TV |

### Capability by transport

| Capability | v2 | ADB | BT HID | IR |
|---|---|---|---|---|
| D-pad / OK / Back / Home | ✅ | ✅ | ✅ | ✅ |
| Volume / mute | ✅ (+ level readback) | ✅ | ✅ | ✅ |
| Power off / on | ✅ off; on only if device still on network | ✅ off; on rarely | ⚠️ (wake via BT is device-dependent) | ✅ (TV's IR receiver works in standby) |
| Channel, input, numbers, colour keys | ✅ (any keycode) | ✅ | ⚠️ (only keys with a HID usage → keycode mapping) | ✅ (if code known) |
| Voice / Assistant | ✅ (PCM stream) | ❌ (can only trigger Assistant UI) | ❌ (can trigger; no audio path) | ❌ |
| Text input | ✅ (IME batch edit) | ✅ `input text` | ✅ (keyboard reports) | ❌ |
| Launch app | ✅ deep link only | ✅ any package/intent | ❌ | ❌ |
| Installed app list | ❌ | ✅ `pm list packages` | ❌ | ❌ |
| Current foreground app | ✅ | ✅ (`dumpsys`) | ❌ | ❌ |
| Screenshot / mirroring | ❌ | ✅ `screencap`, scrcpy | ❌ | ❌ |
| Mouse / touchpad cursor | ❌ (swipe → D-pad emulation only) | ⚠️ `input tap/swipe` (absolute, no cursor) | ✅ real mouse pointer | ❌ |
| Works without Wi-Fi | ❌ | ❌ | ✅ | ✅ |

---

## 3. Approach details

### 3.1 Android TV Remote protocol v2 (primary)

**What runs on the TV.** The server side is Google's system app **"Android TV Remote Service"**, package `com.google.android.tv.remote.service`. It is updated through Play Store. APKMirror shows 6.0.x (June 2024), 6.1.x (Oct 2024), and 6.3.726776162 (Feb 2025), targeting API 35 with minimum Android 7.0 ([APKMirror 6.3](https://apkmirror.com/apk/google-inc/android-tv-remote-service-android-tv/android-tv-remote-service-6-3-726776162-release/android-tv-remote-service-6-3-726776162-android-apk-download), [AppGoblin listing](https://appgoblin.info/apps/com.google.android.tv.remote.service/data-flows)). The v2 protocol arrived with **Remote Service 5.0 in Sept 2021**. That update made the Google TV app's remote work, and the old "Android TV Remote Control" app could no longer pair ([9to5Google, 2021-09-24](https://9to5google.com/2021/09/24/googles-new-android-tv-in-app-remote-requires-an-update-on-your-tv/)).
- I found no source tying the protocol to a component called "Android TV Core Services". **UNVERIFIED** whether that package is involved.

**Is it on every certified device?**
- Home Assistant's docs say the Remote Service "is pre-installed on most devices (Fire TV devices are a notable exception)." They also say "the integration doesn't work with Fire TV devices because they are missing the Android TV Remote Service" ([HA androidtv_remote docs](https://www.home-assistant.io/integrations/androidtv_remote/)).
- Google's GMS requirements for Android TV (MADA) are not public. Whether the Remote Service is mandatory on every GMS device is **UNVERIFIED**. "Most devices" is the best public evidence.
- Google officially supports the phone remote (Google TV app and Google Home app, same Wi-Fi) on Android TV, Chromecast, and Google TV Streamer ([Google support: Android TV](https://support.google.com/androidtv/answer/6122465?hl=en), [Google support: Chromecast / Google TV Streamer](https://support.google.com/chromecast/answer/11221499?hl=en)). The Google Home app on iOS gained the remote in v2.48 ([XDA](https://www.xda-developers.com/google-home-ios-android-tv-remote/)).
- **Uncertified AOSP boxes and Fire TV** don't have it, so v2 won't work on them. Some uncertified boxes ship sideloaded Google apps, and whether those include a working Remote Service is **UNVERIFIED**.

**Transport and pairing.** I verified all of this in [`androidtv_remote.py`](https://raw.githubusercontent.com/tronikos/androidtvremote2/main/src/androidtvremote2/androidtv_remote.py), [`pairing.py`](https://raw.githubusercontent.com/tronikos/androidtvremote2/main/src/androidtvremote2/pairing.py), and the [Aymkdn protocol wiki](https://github.com/Aymkdn/assistant-freebox-cloud/wiki/Google-TV-(aka-Android-TV)-Remote-Control-(v2)).
- **Ports (the brief had these reversed):** **6467 = pairing**, **6466 = remote commands**. androidtvremote2 defaults to `api_port=6466` ("port for connecting and sending commands") and `pair_port=6467`. louis49/androidtv-remote uses `pairing_port: 6467, remote_port: 6466` ([README](https://github.com/louis49/androidtv-remote)).
- **TLS with a client certificate.** The client generates a self-signed **RSA** certificate once and presents it on both ports. The library doesn't verify the server's certificate (`CERT_NONE`).
- **Framing.** Each protobuf message is preceded by a varint length prefix (`_EncodeVarint`/`_DecodeVarint` in `base.py`).
- **Pairing (Polo protocol, `polo.proto`):**
  1. The client sends `pairing_request` with a service name and client name.
  2. The client sends `options`, with input encoding HEXADECIMAL, `symbol_length=6`, and role INPUT, then `configuration`.
  3. The TV shows a **6-hex-digit code**.
  4. The client computes the secret as `SHA-256(client_modulus ‖ client_exponent ‖ server_modulus ‖ server_exponent ‖ code[2:6])`.
  5. The first byte of the hash must equal `code[0:2]`. This acts as a typo check before sending.
  6. The client sends `secret` and gets `secret_ack`.

  This derives from Google's own open-source Java implementation in AOSP: [`platform/external/google-tv-pairing-protocol`](https://android.googlesource.com/platform/external/google-tv-pairing-protocol/).
- **Session.**
  - The TV sends `remote_configure` with device info (vendor, model, app version) and a **feature bitmask**.
  - The client replies with the features it wants. Flags in androidtvremote2: PING=1, KEY=2, IME=4, VOICE=8, POWER=32, VOLUME=64, APP_LINK=512 ([`remote.py`](https://raw.githubusercontent.com/tronikos/androidtvremote2/main/src/androidtvremote2/remote.py)).
  - The TV pings every ~5 s, and the connection closes after 3 unanswered pings.

**Messages** ([`remotemessage.proto`](https://raw.githubusercontent.com/tronikos/androidtvremote2/main/src/androidtvremote2/remotemessage.proto)). `RemoteMessage` fields:

| Field | # | Use |
|---|---|---|
| remote_configure / remote_set_active | 1 / 2 | feature negotiation |
| remote_error | 3 | error |
| remote_ping_request / response | 8 / 9 | keepalive |
| remote_key_inject | 10 | `key_code` (RemoteKeyCode enum) + `direction` SHORT / START_LONG / END_LONG |
| remote_ime_key_inject | 20 | TV → client: carries `app_info.app_package` = **current foreground app** |
| remote_ime_batch_edit | 21 | text input both ways (ime_counter, field_counter, edit_info) |
| remote_ime_show_request | 22 | keyboard shown on TV |
| remote_voice_begin / payload / end | 30 / 31 / 32 | voice session |
| remote_start | 40 | `started` = **power state** |
| remote_set_volume_level | 50 | TV → client: volume_level, volume_max, volume_muted, player_model |
| remote_adjust_volume_level | 51 | (semantics UNVERIFIED) |
| remote_set/reset_preferred_audio_device | 60 / 61 | audio output routing (UNVERIFIED) |
| remote_app_link_launch_request | 90 | `app_link` URI → **launch app by deep link** |

- **Keycodes.** The `RemoteKeyCode` enum mirrors Android `KeyEvent` codes up to ~304. That covers `KEYCODE_TV_INPUT_HDMI_1..4`, `KEYCODE_SETTINGS` (176), `KEYCODE_GUIDE`, `KEYCODE_ALL_APPS` (284), `KEYCODE_PROFILE_SWITCH` (288), `KEYCODE_VIDEO_APP_1..8` (289–296), `KEYCODE_FEATURED_APP_1..4` (297–300), `KEYCODE_SLEEP`/`WAKEUP`, and `KEYCODE_ASSIST`/`VOICE_ASSIST`.
  - The keycodes added in API 29 and API 33 do nothing on older TVs ([KeyEvent reference](https://developer.android.com/reference/android/view/KeyEvent)).
  - The device may still ignore a key. HA warns that "commands depend on your Android TV device, its firmware, and the app in the foreground" and that "commands don't work on Netflix" ([HA docs](https://www.home-assistant.io/integrations/androidtv_remote/)).
- **Text input.** `send_text` sends a `remote_ime_batch_edit` with the counters taken from the TV's last batch-edit message.
  - It "may not work as expected if virtual keyboard is present on the Android TV screen."
  - Enabling IME is "Needed for getting current_app," but should be disabled "for devices that show 'Use keyboard on mobile device screen'."
  - Issue #32 (open) reports replace-vs-append inconsistencies ([issue list](https://github.com/tronikos/androidtvremote2/issues?q=is%3Aissue)).
- **App launch.** Only by URI or deep link (e.g. `https://www.youtube.com`, `netflix://`, `https://app.primevideo.com`, `https://www.disneyplus.com`, `plex://`; table in [HA docs](https://www.home-assistant.io/integrations/androidtv_remote/)). **Launching by package name broke because of a Google Play change.**
  - HA says "A change to the Google Play Store is currently preventing this method from working for many apps."
  - In **Aug 2026**, Kodi and Prime Video stopped launching by package on a Sony Bravia 8 and an Onn 4K. The maintainer said "The change is on the Google side" and switched to deep links. Kodi has no deep link, so it can't be launched this way ([issue #46](https://github.com/tronikos/androidtvremote2/issues/46)).
  - So this is a **live breakage vector**: keep a curated, remotely updatable deep-link table.
- **Voice.**
  1. Send `KEYCODE_SEARCH`, then wait ≤2 s for the TV's `remote_voice_begin` (only if the VOICE feature was negotiated).
  2. Echo `remote_voice_begin` back.
  3. Stream `remote_voice_payload` chunks of **16-bit PCM, mono, 8 kHz**. Chunks are ≤20 KB; the minimum is 8 KB because the Shield rejected smaller ones.
  4. Send `remote_voice_end`.

  Source: [`remote.py`](https://raw.githubusercontent.com/tronikos/androidtvremote2/main/src/androidtvremote2/remote.py) and the [README](https://github.com/tronikos/androidtvremote2). Voice support was added in 2025 (issue #28 closed Jun 2025). Issue #49 (opened 2026-10-31) reports that on a Sharp Android TV 11, 8 KB chunks arrive but are recognised as empty, while 20 KB chunks work. **Voice is therefore feasible but device-sensitive.** `is_voice_enabled` reflects what the device advertises.

**Known operational issues** ([HA docs](https://www.home-assistant.io/integrations/androidtv_remote/)):
- Repeated re-pairing prompts. Fix: clear storage of the Remote Service on the TV.
- "Some devices experience disconnects every 15 seconds," usually fixed by rebooting the TV.
- Power-on: "Some devices, like Xiaomi, become unavailable after they are turned off and can't be turned on"; TCL needs the "Screenless service"; Shield needs "Simplified wake buttons" adjusted.
- In androidtvremote2 issue #29, the maintainer said "Some TVs turn off completely and disconnect from the network so you won't be able to turn them back on via the network" ([issue #29](https://github.com/tronikos/androidtvremote2/issues/29)). See §3.7.

**Recent breakage (2024–2026).**
- No protocol-level break was found. The 2021 v5 switch was the last one.
- Breakages found: app launch by package name via the Play change (§ above, re-confirmed Aug 2026); voice chunk-size quirks (2026).
- One user report claims pairing broke on an Android 16 beta; this is **UNVERIFIED** ([search result: r/AndroidTV](https://redlib.ssps.io/r/AndroidTV/comments/1lm1mkl/android_16_beta_remote_broken)).
- The protocol is undocumented, and Google can change it with a Play Store update to the Remote Service. That is the main long-term risk (§5).

**Open-source implementations (protocol references):**

| Project | Lang | Notes |
|---|---|---|
| [tronikos/androidtvremote2](https://github.com/tronikos/androidtvremote2) | Python | Most complete (keys, IME, app links, volume, power state, voice). Used by HA core `androidtv_remote` (manifest pins `androidtvremote2==0.3.2`, Platinum quality, zeroconf `_androidtvremote2._tcp.local.`) ([manifest](https://raw.githubusercontent.com/home-assistant/core/dev/homeassistant/components/androidtv_remote/manifest.json)). Apache-2.0 |
| [louis49/androidtv-remote](https://github.com/louis49/androidtv-remote) | Node.js | Original reverse-engineering, MIT, `.proto` files used by others |
| [kud/androidtv-remote](https://github.com/kud/androidtv-remote) | TypeScript | Rewrite of louis49 |
| [drosocode/atvremote](https://pkg.go.dev/github.com/drosocode/atvremote) | Go | Supports **both v1 and v2**: "v2 is for the newer Google TV app used when your android tv's remote services version is >= 5" |
| [farshid616/Android-TV-Remote-Controller-Python](https://github.com/farshid616/Android-TV-Remote-Controller-Python) | Python | Earlier implementation, tested on Mi Box 4 |
| [Aymkdn wiki](https://github.com/Aymkdn/assistant-freebox-cloud/wiki/Google-TV-(aka-Android-TV)-Remote-Control-(v2)) | Docs | Byte-level protocol description |
| AOSP [google-tv-pairing-protocol](https://android.googlesource.com/platform/external/google-tv-pairing-protocol/) | Java | Google's own Polo pairing code |

**Kotlin, Swift, or Flutter:** I found no maintained open-source library. tronikos answered "No" when asked for a Kotlin port ([issue #18](https://github.com/tronikos/androidtvremote2/issues/18)). Plan to port from the Python and `.proto` sources: protobuf codegen with `protoc`/`swift-protobuf`, TLS with client certificates, and RSA key generation.

### 3.2 Discovery (mDNS / DNS-SD)

- **v2:** `_androidtvremote2._tcp`. Home Assistant uses this for auto-discovery ([manifest](https://raw.githubusercontent.com/home-assistant/core/dev/homeassistant/components/androidtv_remote/manifest.json)).
- **v1 / older:** `_androidtvremote._tcp` (reported in a 2017 Stack Overflow thread: [mirror](https://kaweah.freedombox.rocks/kiwix/stackoverflow.com_en_all_2023-11/questions/46262046/what-protocol-does-android-tv-remote-use)).
- **Cast:** `_googlecast._tcp` ([HA cast manifest](https://raw.githubusercontent.com/home-assistant/core/dev/homeassistant/components/cast/manifest.json)). Useful as a second discovery signal and to get a friendly name.
- **Manual IP entry is also needed**: mDNS fails on many mesh, guest, and "AP isolation" networks.
- **Fire TV**: DIAL/SSDP on port 8009 is reported by community sources (**UNVERIFIED**).

### 3.3 Protocol v1 and Anymote (legacy)

- **Anymote** is the old Google TV (2010–2014) protocol and used port 9552. The old open-source Google TV remote doesn't work with Android TV ([SO mirror](https://kaweah.freedombox.rocks/kiwix/stackoverflow.com_en_all_2023-11/questions/46262046/what-protocol-does-android-tv-remote-use)). Not worth supporting.
- **v1** is the protocol of the old "Android TV Remote Control" app (2014–2021). It uses the same ports and Polo pairing but a different message set, and it can launch apps by intent ([atvremote](https://pkg.go.dev/github.com/drosocode/atvremote)). The app hasn't been updated since 2017 and can't pair with Remote Service ≥5 ([9to5Google](https://9to5google.com/2021/09/24/googles-new-android-tv-in-app-remote-requires-an-update-on-your-tv/)).
- **Who still needs v1:** certified devices whose Remote Service never updated to 5.x. Likely early Android TV 5–7 hardware such as the Nexus Player and 2015–2016 TVs, or boxes without Play updates. The size of that group is **UNVERIFIED**, probably small and shrinking.
- **Recommendation:** detect it and show a "please update Android TV Remote Service" hint. Implement v1 only if telemetry shows demand.

### 3.4 ADB over network (optional "power mode")

**Capabilities.** Anything a shell can do:
- `input keyevent <code>` (any keycode), `input text`, `input tap/swipe`
- `screencap -p` (screenshots), screen mirroring via scrcpy (UNVERIFIED on all TV SoCs)
- `am start -a VIEW -d <uri>` or `am start -n pkg/activity` (launch **any** app, including Kodi)
- `pm list packages` (app list), `dumpsys` (foreground app and media sessions)

([adb docs](https://developer.android.com/tools/adb))

**Requirements and friction:**
- The user must unlock **Developer options** (tap Build 7×) and enable debugging ([dev options](https://developer.android.com/studio/debug/dev-options)).
- On first connect the TV shows an **RSA key authorization dialog**, which protects the device "unless you're able to unlock the device and acknowledge the dialog" ([adb docs](https://developer.android.com/tools/adb)).
- **Wireless debugging with pairing codes** is supported from Android 11 on phones but **only from Android 13 (API 33) on TV** ([adb docs](https://developer.android.com/tools/adb)). Older TVs vary by vendor:
  - Google's Cast docs say "Standard retail Android TV devices do not listen for ADB connections automatically"; you need USB plus `adb tcpip 5555` first ([Cast ATV debugging](https://developers.google.com/cast/docs/android_tv_receiver/debugging)).
  - Many TVs (Shield's "Network debugging"; Chromecast with Google TV after enabling USB debugging) accept `adb connect IP:5555` directly ([HA community](https://community.home-assistant.io/t/controlling-new-chromecast-with-google-tv/236748/17); Shield guides in [stb-tester](https://stb-tester.com/manual/android)).
  - Per-model behaviour is **UNVERIFIED**.
- `adb tcpip 5555` doesn't persist across reboot. Android 11+ also revokes ADB authorizations not used for 7 days unless "Disable adb authorization timeout" is set (per [stb-tester](https://stb-tester.com/manual/android); **UNVERIFIED** against official docs).
- **Fire TV (Fire OS):** Settings → My Fire TV → Developer Options → **ADB Debugging**, then `adb connect IP:5555`. On some versions Developer options is hidden until you click About → Your TV 7 times ([Amazon docs](https://developer.amazon.com/docs/fire-tv/connecting-adb-to-device.html)).

**Downsides for normal users:**
- Scary setup and a security warning.
- Any device on the LAN can try to connect.
- Vendors and Play Protect may nag.
- It breaks after reboots on some devices.
- It doesn't exist on Vega OS Fire TVs.

Use it as an opt-in advanced mode, not the default.

**Libraries for a phone app:**
- [dadb](https://github.com/mobile-dev-inc/dadb): Kotlin/Java, "connect directly to an Android device without an adb binary or an ADB server"; TCP, shell, push/pull, install; Apache-2.0. Android-11 TLS pairing is not mentioned.
- [libadb-android](https://github.com/MuntashirAkon/libadb-android): supports `pair(host, port, code)` for Wireless debugging, plus TLS and TCP connect. GPL-3.0-or-later **or** Apache-2.0, with an LGPL dependency. The README says "never gone through a security audit."
- iOS needs its own ADB-protocol client in Swift: RSA auth over TCP, and SPAKE2 + TLS for Android 11+ pairing. No maintained Swift library was found (**UNVERIFIED**).

### 3.5 Bluetooth HID (offline / uncertified fallback, Android phones only)

- **API.** `BluetoothHidDevice` (API 28+). Register an SDP record and HID descriptor with `registerApp(...)`, then send input reports with `sendReport(...)`. Subclass constants include `SUBCLASS1_KEYBOARD`, `SUBCLASS1_MOUSE`, `SUBCLASS1_COMBO`, `SUBCLASS2_REMOTE_CONTROL`. Requires `BLUETOOTH_CONNECT` on API 31+ ([reference](https://developer.android.com/reference/android/bluetooth/BluetoothHidDevice)).
- **Platform caveats** (same reference):
  - "Only one application can be registered at one time."
  - "The app will be automatically unregistered if it is not foreground," so it can't act as a background or widget-only remote without a visible activity or foreground strategy.
  - Some phone OEMs disable the HID Device profile. Check `getProfileProxy(... HID_DEVICE)` at runtime. Which models disable it is **UNVERIFIED**.
- **Key mapping.** Use a combined descriptor (keyboard + consumer control + mouse). The path is HID usage → Linux key code ([`hid-input.c`](https://raw.githubusercontent.com/torvalds/linux/master/drivers/hid/hid-input.c)) → Android keycode ([AOSP `Generic.kl`](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/data/keyboards/Generic.kl)):

| Button | HID usage (page 0x0C Consumer unless noted) | Linux key | Android keycode |
|---|---|---|---|
| Home | 0x0223 AC Home | KEY_HOMEPAGE (172) | HOME |
| Back | 0x0224 AC Back | KEY_BACK (158) | BACK |
| D-pad / OK | 0x0042–0x0045 Menu Up/Down/Left/Right, 0x0041 Menu Pick (or keyboard arrows/Enter) | KEY_UP… / KEY_SELECT | DPAD_* / (SELECT, UNVERIFIED mapping) |
| Menu | 0x0040 | KEY_MENU | MENU |
| Power | 0x0030 | KEY_POWER | POWER |
| Sleep | 0x0032 / 0x0034 | KEY_SLEEP | SLEEP |
| Vol + / − / Mute | 0x00E9 / 0x00EA / 0x00E2 | KEY_VOLUMEUP/DOWN/MUTE | VOLUME_UP/DOWN/MUTE |
| Play/Pause | 0x00CD | KEY_PLAYPAUSE | MEDIA_PLAY_PAUSE |
| Ch + / − | 0x009C / 0x009D | KEY_CHANNELUP/DOWN | CHANNEL_UP/DOWN |
| Guide | 0x008D | KEY_PROGRAM | GUIDE |
| Search | 0x0221 AC Search | KEY_SEARCH | SEARCH |
| Voice/Assistant | 0x00CF Voice Command | KEY_VOICECOMMAND (582) | VOICE_ASSIST |
| Captions | 0x0061 | KEY_SUBTITLE | (CAPTIONS mapped from KEY 370; check) |
| Settings | 0x019F | — | SETTINGS (fallback usage mapping) |
| All apps | 0x01A2 | KEY_APPSELECT | ALL_APPS (fallback usage mapping) |
| Info | 0x0060 | KEY_INFO (358) | **not mapped** in Generic.kl (commented out) |

- **Limits:**
  - No voice audio. The Google remote's mic uses a separate Google voice-over-BLE spec; whether a phone can emulate it is **UNVERIFIED** and unlikely via public APIs.
  - No app launch, no state readback.
  - TV input switching and number keys work only if the TV maps them.
  - Wake from standby over BT depends on the device (Shield has wake settings).
- **Proof that it works:** open-source Play/F-Droid apps already do this for Android TV:
  - [BtRemote (com.atharok.btremote)](https://f-droid.org/packages/com.atharok.btremote): "No additional app installation required on your Android TV device thanks to HID protocol"; Android 9+; GPL-3.0+ ([source](https://gitlab.com/Atharok/BtRemote)).
  - [jqssun Bluetooth Remote](https://f-droid.org/en/packages/io.github.jqssun.btremote/): keyboard, mouse, trackpad; GPL-3.0-only.
  - Both are GPL, so study them but don't copy code into a closed app.
- **iOS cannot do this.** CoreBluetooth rejects publishing the HID service UUID 0x1812 ("The specified UUID is not allowed for this operation") and there is no Classic HID device API ([Apple forums thread](https://developer.apple.com/forums/thread/725238), [gist](https://gist.github.com/conath/c606d95d58bbcb50e9715864eeeecf07)). That evidence is community-sourced, with no explicit Apple statement found. Treat it as **effectively impossible**.

### 3.6 IR blaster

- `ConsumerIrManager` (API 19): `hasIrEmitter()`, `getCarrierFrequencies()`, `transmit(carrierHz, int[] pattern)`. Patterns must be shorter than 2 s. Requires `FEATURE_CONSUMER_IR` ([reference](https://developer.android.com/reference/android/hardware/ConsumerIrManager)).
- Hardware is now mostly Xiaomi/Redmi/POCO plus some vivo/Honor/Unihertz. Mobility Arena says no current Samsung Galaxy has one ([Mobility Arena](https://mobilityarena.com/how-to-get-an-ir-blaster-on-my-phone/?amp=1)). iPhones have none.
- Codes are per brand and protocol (NEC, Sony SIRC, RC5/RC6…), so you need a code database. Many streaming sticks (e.g. Chromecast with Google TV) are BT-only for navigation and use IR only to control the TV's power/volume (**UNVERIFIED** per model).
- **Value:** the only phone-side way to turn on a TV that is fully off the network, if the phone has IR. It's a niche add-on.

### 3.7 Power-on, HDMI-CEC, and Wake-on-LAN

- **v2 can't wake a device that has left the network.**
  - When a TV is in "network standby," the Remote Service is still reachable, and sending `KEYCODE_POWER`/`WAKEUP` turns it on. This is how Google's own app works.
  - Many TVs (Xiaomi, some TCL and Philips) close their ports when off ([issue #29](https://github.com/tronikos/androidtvremote2/issues/29), [HA core #107649](https://github.com/home-assistant/core/issues/107649)).
- **Workarounds users reported** (HA #107649; all increase standby power):
  - Periodic **Wake-on-LAN** magic packets
  - TCL "Network Standby"
  - TCL Energy Mode → High
  - Philips "WoLAN" + "switch on with Chromecast"
  - Developer "stay awake"
  - Static IP
  - Casting to the TV to wake it
- **Recommendation:** store the MAC address during pairing. androidtvremote2 has `async_get_name_and_mac()`, though issue #34 notes the MAC is not reported on some devices. Send a WoL packet, then retry v2.
- **HDMI-CEC.** Streaming boxes (Shield, Chromecast with Google TV, Google TV Streamer) usually stay network-connected in standby (**UNVERIFIED** per model). When they wake they use CEC One Touch Play to turn on the TV and switch input: "When an HDMI playback device wakes up, it attempts to wake the connected TV and become the current active source" ([AOSP HDMI-CEC](https://source.android.com/docs/devices/tv/hdmi-cec)). Third-party apps can't use `HdmiControlService` directly (restricted to system and priv-apps), so CEC is reached indirectly by waking the box.
- **iOS:** WoL is a UDP broadcast, and iOS requires the **`com.apple.developer.networking.multicast` entitlement** (granted by Apple on request) to send broadcasts ([TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)). Apply for it early, or fall back to unicast WoL, which is unreliable once the TV's ARP entry has expired.

### 3.8 Google Cast (complementary)

- Discoverable via `_googlecast._tcp`.
- Useful for:
  - launching Cast-enabled apps
  - reading **media status / now-playing** for Cast sessions (HA recommends pairing the Cast integration with Android TV Remote for media details: [HA docs](https://www.home-assistant.io/integrations/androidtv_remote/))
  - waking some devices (HA #107649)
- Not a remote: no D-pad or keys. Treat it as an optional enrichment layer. The protocol is implemented by pychromecast; Google's official Cast SDKs are sender SDKs for your own receiver apps.

### 3.9 Vendor-specific add-ons

- **Fire TV (Fire OS & possibly Vega OS).** Amazon's Fire TV app uses an undocumented local protocol, reverse-engineered in [pyfiretvremote](https://github.com/designer-living/pyfiretvremote) (PyPI 1.2.0):
  - **Pairing:** a PIN shown on the TV, exchanged for a `client_token`.
  - **Control:** REST over HTTPS on port 8080 (`/v1/FireTV/pin/display`, `/pin/verify`, key and media commands, app list, `X-Api-Key` and `X-Client-Token` headers). Endpoint details come from [HA forum](https://community.home-assistant.io/t/rest-commands-for-fire-tv/901314).
  - **Alexa voice:** a WebSocket on port 9090 taking 16 kHz mono s16le PCM. The library notes that "the voice socket does not authenticate."
  - Community notes say port 8080 is closed while the device sleeps and DIAL on port 8009 can wake it (**UNVERIFIED**).
  - **Vega OS** (Linux-based; Fire TV Stick 4K Select 2025, and per reports all future Fire TV Sticks) has no Android, no sideloading, and no ADB ([AFTVnews](https://www.aftvnews.com/tag/vega-os/page/2/), [Cordbusters](https://www.cordbusters.co.uk/amazon-no-sideloading-all-new-fire-tv-sticks/)). Whether Vega exposes the same REST remote API is **UNVERIFIED**. Fire OS devices can also use ADB (§3.4).
  - Fire TV volume is usually handled by CEC/IR to the TV, so volume readback is not expected (**UNVERIFIED**).
- **Nvidia Shield.**
  - Fully supports v2; voice needs ≥8 KB chunks per androidtvremote2's comment.
  - Has a "Network debugging" toggle for ADB.
  - Wake can need "Simplified wake buttons" settings ([HA docs](https://www.home-assistant.io/integrations/androidtv_remote/)).
- **Sony BRAVIA.** Official IP control: REST API (JSON-RPC over HTTP), **IRCC-IP** (SOAP, sends IR codes over IP), and Simple IP Control (TCP) ([Sony pro docs](https://pro-bravia.sony.net/develop/integrate/ip-control/index.html)).
  - Auth uses a Pre-Shared Key in the `X-Auth-PSK` header, set under Home Network → IP control (from Sony's docs via search result; page not fetched directly, so partially **UNVERIFIED**).
  - Adds reliable input switching, picture settings, and "Remote start" power-on.
- **Philips (JointSpace).** API v6 over HTTPS port 1926 (e.g. `https://IP:1926/6/system`). Android models need pairing, which uses an HMAC signature with a hardcoded key and then stored user/pass credentials. There's also power-on from deep sleep via `allow_power_on` (Chromecast wake). Input switching is not in the API ([pylips](https://github.com/eslavnov/pylips)). Undocumented and reverse-engineered.
- **Xiaomi China / PatchWall TVs, Hisense VIDAA, Samsung Tizen, LG webOS, Roku:** outside "Android TV" and not covered by v2. Possible future add-ons with their own protocols, not researched here.

---

## 4. Physical remote button → how to emulate

Keycodes from [`remotemessage.proto`](https://raw.githubusercontent.com/tronikos/androidtvremote2/main/src/androidtvremote2/remotemessage.proto), which mirrors [Android KeyEvent](https://developer.android.com/reference/android/view/KeyEvent).

| Physical button | v2 (primary) | ADB fallback | BT HID fallback | Notes |
|---|---|---|---|---|
| D-pad ↑↓←→ | `KEYCODE_DPAD_UP/DOWN/LEFT/RIGHT` (19–22) | `input keyevent 19..22` | Keyboard arrows or Consumer 0x42–0x45 | Use START_LONG/END_LONG for hold-to-scroll |
| OK / Select | `KEYCODE_DPAD_CENTER` (23) | `input keyevent 23` | Keyboard Enter / 0x41 | |
| Back | `KEYCODE_BACK` (4) | 4 | Consumer 0x224 | |
| Home | `KEYCODE_HOME` (3) | 3 | Consumer 0x223 | Long-press Home opens the dashboard on Google TV (START_LONG) (UNVERIFIED per device) |
| Volume + / − | `KEYCODE_VOLUME_UP/DOWN` (24/25) | 24/25 | 0xE9 / 0xEA | v2 reports level/max/muted back (`remote_set_volume_level`); on boxes this is often CEC-forwarded to the TV |
| Mute | `KEYCODE_VOLUME_MUTE` (164) | 164 | 0xE2 | **Not** `KEYCODE_MUTE` (91), which mutes the microphone |
| Power | `KEYCODE_POWER` (26); also `TV_POWER` (177), `SLEEP` (223), `WAKEUP` (224) | 26 / 223 / 224 | 0x30 / 0x32 | Power-on only works if the device is still on the network → add WoL (§3.7) |
| Channel + / − | `KEYCODE_CHANNEL_UP/DOWN` (166/167) | 166/167 | 0x9C / 0x9D | Live TV apps only |
| Last channel | `KEYCODE_LAST_CHANNEL` (229) | 229 | — | |
| Input / Source | `KEYCODE_TV_INPUT` (178); direct `TV_INPUT_HDMI_1..4` (243–246) | same | — (no standard usage) | TV-panel devices only; Philips doesn't honour it via its own API |
| Number keys 0–9 | `KEYCODE_0..9` (7–16) | 7–16 | Keyboard digits | |
| Voice / Assistant / mic | Voice session: `KEYCODE_SEARCH` → stream PCM (§3.1). Trigger only: `KEYCODE_ASSIST` (219) / `VOICE_ASSIST` (231) | Trigger only | Trigger via 0xCF (no audio) | Needs mic permission on the phone; on Fire TV use the 9090 voice socket |
| Settings (gear) | `KEYCODE_SETTINGS` (176) | 176 or `am start -a android.settings.SETTINGS` | 0x19F | |
| Guide / EPG | `KEYCODE_GUIDE` (172) | 172 | 0x8D | |
| Info | `KEYCODE_INFO` (165) | 165 | — (not mapped in Generic.kl) | |
| Captions | `KEYCODE_CAPTIONS` (175) | 175 | — | |
| Red/Green/Yellow/Blue | `KEYCODE_PROG_RED..BLUE` (183–186) | 183–186 | — | |
| Play/Pause, Stop, FF, RW, Next, Prev | `MEDIA_PLAY_PAUSE` (85), `MEDIA_STOP` (86), `MEDIA_FAST_FORWARD` (90), `MEDIA_REWIND` (89), `MEDIA_NEXT/PREVIOUS` (87/88) | same | 0xCD, 0xB7, 0xB5/0xB6 | |
| All apps / Apps button | `KEYCODE_ALL_APPS` (284, API 28+) | 284 | 0x1A2 | |
| Profile button (Google TV Streamer) | `KEYCODE_PROFILE_SWITCH` (288, API 29+) | 288 | — | |
| Netflix / YouTube / Prime / Disney+ buttons | Deep link: `netflix://`, `https://www.youtube.com`, `https://app.primevideo.com`, `https://www.disneyplus.com` ([HA table](https://www.home-assistant.io/integrations/androidtv_remote/)); or OEM-mapped `KEYCODE_VIDEO_APP_1..8` / `FEATURED_APP_1..4` (API 33+) | `am start -a android.intent.action.VIEW -d <uri>` or `monkey -p <pkg> 1` | — | Prefer deep links: package-name launch broke via the Play change (issue #46) |
| Free / starred / bookmark buttons | `KEYCODE_BOOKMARK` (174), `KEYCODE_DVR` (173) | same | — | Device-specific meaning |
| TV (live TV) | `KEYCODE_TV` (170) | 170 | 0x89 → KEY_TV → `TV` | |

---

## 5. Digital-only features

| Feature | Feasible? | How | Caveats |
|---|---|---|---|
| Keyboard text input | ✅ | v2 `remote_ime_batch_edit`; ADB `input text`; BT HID keyboard | v2 conflicts with some OEM on-screen keyboards ("Use keyboard on mobile device screen"); replace-vs-append quirks (issue #32) |
| Live "keyboard appeared" prompt | ✅ | v2 `remote_ime_show_request` / IME messages | Behaviour per device UNVERIFIED |
| Touchpad / swipe navigation | ✅ (emulated) | Translate gestures into D-pad keys over v2 | v2 has no pointer messages (none in the reverse-engineered proto) |
| Real mouse cursor | ⚠️ | BT HID mouse (Android phones only); ADB `input tap/swipe` (no cursor) | Not available over v2 or on iOS |
| Launch app by deep link | ✅ | v2 `remote_app_link_launch_request`; ADB `am start` | Needs a curated deep-link table; apps without deep links (e.g. Kodi) need ADB |
| Installed-app list | ⚠️ | ADB `pm list packages`; Fire TV REST `get_apps()` | Not in v2 → ship a curated catalogue of popular apps + deep links instead |
| Current foreground app | ✅ | v2 (`remote_ime_key_inject.app_info.app_package`, needs IME feature) | |
| Now-playing (title/artwork/position) | ⚠️ | Google Cast media status (Cast sessions only); ADB `dumpsys media_session` | v2 only gives app package and volume |
| Volume level/mute readback | ✅ | v2 `remote_set_volume_level` | Boxes forwarding volume via CEC may report box-side volume (UNVERIFIED) |
| Power state | ✅ | v2 `remote_start.started` | |
| Screenshots / mirroring | ⚠️ | ADB `screencap` / scrcpy only | DRM content renders black (UNVERIFIED per app) |
| Wake from sleep | ⚠️ | v2 POWER if reachable → else WoL → else Cast → else IR | See §3.7 |
| Voice search via phone mic | ✅ / ⚠️ | v2 voice session (8 kHz PCM); Fire TV voice socket (16 kHz) | Device-specific chunk quirks (Shield ≥8 KB; Sharp needs 20 KB, issue #49) |
| Multiple TVs, quick switching | ✅ | Store cert + host per device; Android Quick Settings tile / widgets | BT HID: only one HID app registered at a time, foreground only |
| Home-screen widget / lock-screen remote | ✅ (network) | Foreground service for v2 socket | BT HID widget not possible (auto-unregister when not foreground) |

---

## 6. Platform constraints

### Android client
- `INTERNET` permission. On API 33+, `NEARBY_WIFI_DEVICES` is not needed for plain mDNS via `NsdManager` (UNVERIFIED).
- Wi-Fi multicast lock for discovery.
- `RECORD_AUDIO` for voice.
- `BLUETOOTH_CONNECT`/`BLUETOOTH_SCAN`/`BLUETOOTH_ADVERTISE` (API 31+) for HID mode.
- RSA cert generation: Android Keystore or BouncyCastle.
- TLS client auth is supported in JSSE (`KeyManager`).

### iOS client
- **Local network privacy** (iOS 14+) applies. Outgoing TCP to a LAN address, Bonjour browsing, and UDP unicast/broadcast all need user permission. You need `NSLocalNetworkUsageDescription` and must list every browsed type in `NSBonjourServices` (`_androidtvremote2._tcp`, `_googlecast._tcp`, …) ([TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)).
- **Broadcast and multicast (WoL)** need the `com.apple.developer.networking.multicast` entitlement (same source).
- **TLS client certificates:** fine. Network.framework lets you set a local identity and a custom verify block that accepts the TV's self-signed cert. Generating a self-signed X.509 needs a library such as apple/swift-certificates. That library has not been tested here (**UNVERIFIED**).
- **No Bluetooth HID** (§3.5) and **no IR**. iOS feature parity = v2 + vendor network add-ons.

---

## 7. Market and coverage estimate

| Figure | Value | Source | Comparability |
|---|---|---|---|
| Google TV + Android TV monthly active devices | **>300 M** (May 2026, Google I/O) | [9to5Google](https://9to5google.com/2026/05/21/google-tv-hits-300-million-active-devices/) | Certified/GMS only; monthly active |
| Previous milestone | 270 M (Sept 2024) | [The Desk](https://thedesk.net/2024/09/android-tv-270-million-global-devices/) | |
| Android share of global TV OS shipments | ~42% (2025) → 39% (2029) | Omdia via search snippet ([BusinessWire release](https://www.businesswire.com/news/home/20251029451188/en/), 403 when fetched; **UNVERIFIED** exact wording) | Includes China forks |
| China TV shipments on localized Android forks without Google | ~96% | same Omdia release (**UNVERIFIED** exact wording) | Not reachable by v2 |
| Android (incl. Google TV) share excluding China | ~32% (2025) | same (**UNVERIFIED**) | |
| Uncertified AOSP boxes infected by BadBox 2.0 | >10 M (Google's complaint); HUMAN estimates ~1 M | [Google blog](https://blog.google/innovation-and-ai/technology/safety-security/google-taking-legal-action-against-the-badbox-20-botnet/), [PC Gamer](https://www.pcgamer.com/software/security/google-begins-legal-action-against-badbox-2-0-the-largest-known-botnet-of-internet-connected-tvs-affecting-more-than-10-000-000-android-devices-including-checks-notes-picture-frames) | A lower bound for the size of the uncertified-box population, not a total |
| Fire TV devices sold | >250 M cumulative | [TV Technology](https://www.tvtechnology.com/news/amazon-passes-250-million-fire-devices-sold-expands-fire-tv-lineup) | Units **sold**, not active, so not directly comparable |

**Estimate** (reasoned, **UNVERIFIED**; no source counts uncertified boxes):
- **Denominator = certified Android TV / Google TV:** v2 should cover **~95%+** while devices are on. Exclusions: devices stuck on Remote Service < 5, OEM quirks, a broken Remote Service needing a storage clear. Power-on success is lower and vendor-dependent.
- **Denominator = certified + uncertified AOSP boxes, outside China:** uncertified boxes are probably in the tens of millions against ~300 M certified, so v2 alone is roughly **85–95%**. Adding **BT HID** on Android lifts basic navigation coverage to **~95%+**, assuming the box has Bluetooth and accepts HID keyboards (true for most AOSP boxes; **UNVERIFIED**).
- **Including Fire TV:** you need the Fire TV add-on. With it, Fire OS coverage is good. Vega OS is unknown.
- **Including China domestic market:** v2 coverage collapses. Would need vendor protocols, ADB, or BT HID. Treat China as a separate product decision.

---

## 8. App-store policy and prior art

- **Prior art: apps already doing this.**
  - Google's own Google TV and Google Home apps (Android + iOS).
  - Home Assistant (open source).
  - Paid/free App Store apps such as "Android TV Remote Control" ([App Store id6740451063](https://apps.apple.com/us/app/-/id6740451063)), "Remote Control : Android TV" ([id6751883648](https://apps.apple.com/us/app/id6751883648)), and "Remote control GTV ATV" ([listing](https://mwm.ai/apps/remote-control-gtv-atv/6759204071)). Their on-TV pairing-code flow strongly suggests v2. Their implementation is **UNVERIFIED**.
  - Open-source BT HID remotes on F-Droid (§3.5).
- **Google Play.** I found no policy against controlling devices over the LAN. The relevant rule is the **Impersonation** policy: "Don't imply that your app is related to or authorized by someone that it isn't," and don't copy logos to suggest an official app ([Play policy](https://support.google.com/googleplay/android-developer/answer/9888374?hl=en)).
  - The **Android brand guidelines** say "Android" can't start the app name ("Android TV", "Android Remote"). Use "… for Android TV" style naming with care: "Android TV" itself needs approval, so phrase it as "Remote for Google TV & Android TV devices" in the description, not the title. Include "Android is a trademark of Google LLC" ([brand guidelines](https://developer.android.com/distribute/marketing-tools/brand-guidelines)). Same caution for Netflix and YouTube logos on shortcut buttons.
  - Using an undocumented protocol isn't itself prohibited, but there is no contractual protection if Google changes it.
- **Apple App Store.** Same IP and trademark concerns. App Review Guidelines §5.2 covers intellectual property ([guidelines](https://developer.apple.com/app-store/review/guidelines/)); the exact clause wording was not re-verified here. Also see the multicast entitlement request (§6).
- **Licensing of references.** androidtvremote2 is Apache-2.0 (porting is fine with attribution). louis49 is MIT. BtRemote and jqssun are GPL (don't copy into proprietary code). libadb-android can be used under Apache-2.0.

---

## 9. Risks and unknowns

1. **Undocumented protocol.** Google can change the Remote Service via Play updates (precedent: the 2021 v5 switch broke the old app). Mitigations: feature-negotiation logging, remote config, fast release pipeline.
2. **App launch by package name broke** (Play change, re-confirmed Aug 2026). Deep-link-only launch requires a maintained catalogue; some apps have no deep links.
3. **Power-on reliability** varies by vendor (Xiaomi, TCL, and Philips need settings changes; some can't be woken over the network at all).
4. **Netflix and other apps ignoring injected keys** ("Commands don't work on Netflix", HA docs). Needs real-device verification of which keys fail.
5. **IME conflicts** with OEM keyboards; text replace-vs-append quirks.
6. **Voice quirks** per device (chunk sizes); audio format is not officially confirmed.
7. **Remote Service corruption** on the TV (re-pairing loops), fixed by "clear storage." The app needs in-app guidance for this.
8. **Coverage numbers are estimates.** No public count of uncertified boxes. China excluded.
9. **Vega OS Fire TV:** unknown whether the REST remote API exists there.
10. **BT HID:** foreground-only and one-app-at-a-time constraints; some phone OEMs may lack the HID Device profile; voice impossible.
11. **iOS:** multicast entitlement approval needed for WoL; no BT or IR fallbacks, so iOS can't reach uncertified boxes.
12. **Security:** you store a long-lived client cert/private key that grants TV control. Keep it in Keystore/Keychain. ADB mode opens a powerful channel on the LAN.

**Hardware test matrix (to-do):**
- Chromecast with Google TV (HD/4K)
- Google TV Streamer
- Shield TV
- Sony Bravia (Google TV)
- TCL (Google TV)
- Hisense (Google TV)
- Philips (Android TV)
- Xiaomi Mi Box S / TV Box S
- Onn 4K
- an operator box (e.g. a telco Android TV OTT box)
- a cheap AOSP X96/T95 box
- Fire TV Stick 4K Max (Fire OS)
- Fire TV Stick 4K Select (Vega)

---

## 10. Recommended architecture

```
                         ┌─────────────────────────────────────────┐
                         │  UI layer (remote, keyboard, touchpad,  │
                         │  app shortcuts, voice, multi-TV)        │
                         └───────────────────┬─────────────────────┘
                                             │  abstract commands
                         ┌───────────────────▼─────────────────────┐
                         │  Command router / capability model      │
                         │  (per device: which transport supports  │
                         │   which command; fallback order)        │
                         └─┬───────────┬──────────┬──────────┬─────┘
             ┌─────────────┘           │          │          └──────────────┐
   ┌─────────▼─────────┐   ┌───────────▼──────┐ ┌─▼────────────────┐ ┌──────▼─────────────┐
   │ L1 ATV Remote v2  │   │ L2 BT HID        │ │ L3 ADB (opt-in)  │ │ L4 Vendor add-ons  │
   │ (Android + iOS)   │   │ (Android only)   │ │ (Android + iOS?) │ │ Fire TV REST+voice │
   │ keys, IME, voice, │   │ keys, keyboard,  │ │ app list, any    │ │ Sony REST/IRCC     │
   │ deep links, state │   │ mouse, offline   │ │ intent, screencap│ │ Philips JointSpace │
   └─────────┬─────────┘   └──────────────────┘ └──────────────────┘ └────────────────────┘
             │
   ┌─────────▼────────────────────────────────────────────────────────────────────────┐
   │ Helpers: mDNS discovery (_androidtvremote2, _googlecast, manual IP), WoL (MAC     │
   │ saved at pairing), Google Cast (wake + now-playing), IR blaster (if phone has one)│
   │ Remote-config deep-link catalogue; secure cert storage (Keystore / Keychain)      │
   └──────────────────────────────────────────────────────────────────────────────────┘
```

**Build order:**
1. **MVP (both platforms):**
   - v2 client: pairing, TLS client cert, keys with long-press, IME text, deep-link launch, power and volume state, ping/keepalive, reconnect.
   - mDNS + manual IP discovery.
   - Curated deep-link catalogue for app buttons.
   - WoL on power-on.
2. **Android differentiator:** BT HID mode (keyboard + consumer control + mouse descriptor) for uncertified boxes and offline use.
3. **Voice:** v2 voice session with a per-device chunk-size profile.
4. **Fire TV add-on:** REST + PIN pairing + voice socket. Detect Vega OS.
5. **Power-user mode:** ADB (libadb-android on Android; custom Swift client on iOS if worth it) for app list, any-app launch, screenshots.
6. **Optional:** Sony and Philips native APIs (input switching, reliable power-on), Cast now-playing, IR blaster, v1 legacy if telemetry shows demand.

**Implementation notes:**
- Port protocol logic from androidtvremote2 (Apache-2.0) and generate code from its `.proto` files. Write a shared core in Kotlin Multiplatform, or Kotlin plus Swift. Protobuf + TLS + RSA are the only heavy dependencies.
- Persist per TV: client cert/key, host, MAC, negotiated features, and the device-info vendor/model. Use vendor/model to apply quirks such as the voice chunk size and the "disable IME on this model" toggle.
- In-app troubleshooting:
  - "Clear Android TV Remote Service storage" instructions.
  - Network-standby setting guides per vendor (TCL Screenless service, Shield simplified wake buttons, Philips WoLAN).
