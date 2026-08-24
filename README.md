<p align="center">
  <img src="assets/icon/hilight_logo.png" width="128" alt="HiLight logo"/>
</p>

<h1 align="center">HiLight</h1>

<p align="center">
  <a href="https://github.com/tahasync/HiLight/actions/workflows/build.yml">
    <img src="https://github.com/tahasync/HiLight/actions/workflows/build.yml/badge.svg" alt="Build status"/>
  </a>
  <a href="https://github.com/tahasync/HiLight/releases">
    <img src="https://img.shields.io/github/v/release/tahasync/HiLight?include_prereleases" alt="Release"/>
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/license-Apache--2.0-blue.svg" alt="License"/>
  </a>
</p>

---

**Pixel-inspired dynamic rear-flash effects for Android — built with Flutter, Kotlin and Material 3 Expressive.**

HiLight recreates a HiLight-style notification-light experience using the phone's physical white rear camera flash. It is **not a flashlight app**: the flash plays smooth, decorative animations — pulses, breathing, heartbeats — synchronized with an on-screen preview.

Works on modern Android phones (Android 13+), including devices **without** adjustable torch brightness: on those, HiLight simulates smooth intensity through perceptual duty-cycle modulation of the LED.

## ✨ Features

| | |
|---|---|
| 🎞️ **Eight presets** | Pulse · Breathing · Double Pulse · Soft Glow · Heartbeat · Quick Flash · Triple Pulse · Long Glow |
| 🎨 **Custom animation editor** | Add/remove keyframes (2–20), per-keyframe time & intensity, duration, easing curve — with live preview and editor-side validation |
| 💾 **Save · rename · delete** | Custom animations persist locally (`custom_<uuid>` namespace) — no account, no cloud |
| :bell: **Notification triggers** | Flash on incoming calls (repeats while ringing, stops on answer), SMS, alarms, timers or app notifications — each mapped to any preset |
| :bust_in_silhouette: **Per-contact patterns** | Assign a preset to specific people — their calls flash differently from everyone else's |
| :iphone: **Per-app control** | Enable, disable, or re-style flashing for every installed app individually |
| :battery: **Charging effects** | Animate on charger connect and disconnect, plus battery-milestone presets at 20 / 35 / 50 / 70 / 100 % — once per session, fully independent |
| 🎛️ **Controls** | Brightness · Speed (0.25×–3×) · Repeat (Once / 2× / 3× / Loop) |
| 👁️ **Live preview** | On-screen glow driven by the exact same animation definition as the physical flash, from one shared clock origin |
| ⚡ **Quick Settings tile** | Start/stop the default animation from the tile — its state mirrors the engine, even after natural completion |
| 🔍 **Capability detection** | Rear-flash presence, torch availability, adjustable-strength support and maximum level |
| 🌗 **Graceful fallback** | ON/OFF-only hardware gets simulated smoothness via a 33 Hz duty-cycle carrier with perceptual gamma |
| 🧠 **Adaptive carrier** | Widens automatically when the camera HAL is slow; native call rate capped |
| 🛡️ **Safety-first** | Torch force-killed on errors, backgrounding or screen exit; typed structured errors |
| ⚙️ **Persistence** | Theme and last-used animation settings survive restarts (local-only) |
| 🔄 **Update checks** | Optional GitHub Releases check with an in-app "Update Available" dialog |
| 🎨 **Material 3 Expressive** | Restrained liquid-glass surfaces · system / light / dark themes · dynamic color |

## 📲 Installation

Grab the latest APK from the [Releases](https://github.com/tahasync/HiLight/releases) page and install it directly (sideloading). Requires Android 13 or newer.

## 🔒 Privacy & permissions

- Your data never leaves the device — animations and settings are stored **locally only**, no account, no cloud, no analytics, no telemetry
- The **only** network request is an optional update check against the [GitHub Releases API](https://github.com/tahasync/HiLight/releases); it fails silently offline
- **Opt-in permission model**: notification-listener access is requested only when you enable a trigger; contacts permission only when you add a per-contact pattern; nothing is requested at launch
- Trigger configuration (contacts, apps, presets) is stored **locally only** â€” notification content is never read, parsed, logged or stored

Camera2 torch APIs deliberately operate without the CAMERA permission.

## 🛠️ Building from source

```bash
flutter pub get
flutter test          # 114 tests
flutter build apk --release
```

Release CI lives in [`.github/workflows/build.yml`](.github/workflows/build.yml):

- pushes to `main` → signed APK build artifacts
- pushing a `v*` tag → GitHub Release with APK + changelog notes from [`CHANGELOG.md`](CHANGELOG.md)

Signing material is supplied exclusively via repository secrets — never committed.

## 📱 Device support

| Hardware | Behavior |
|---|---|
| Adjustable torch strength (e.g., recent Pixels) | True variable-brightness animations across the device's level range |
| ON/OFF-only torch (older devices) | Simulated smoothness via duty-cycle modulation |

Verified across **Pixel 9** (Android 17, adjustable-strength path) and **Pixel 4** (Android 13, ON/OFF-class) — including the Quick Settings tile and the full custom-animation flow on both. Torch behavior varies by OEM — runtime capability detection, not device model, decides the code path.

## 🗺️ Roadmap

- Notification & charging triggers
- Per-segment easing, JSON import/export & preset sharing
- Broader OEM device matrix

See [`CHANGELOG.md`](CHANGELOG.md) for release history.

## License

[Apache-2.0](LICENSE)
