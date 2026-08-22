# HiLight
<<<<<<< HEAD
HiLight — Pixel-inspired dynamic rear flash effects for Android, built with Flutter and Material 3 Expressive.
=======

<p align="center">
  <img src="assets/icon/hilight_logo.png" width="128" alt="HiLight logo"/>
</p>

**Pixel-inspired dynamic rear-flash effects for Android — built with Flutter, Kotlin and Material 3 Expressive.**

HiLight recreates a HiLight-style notification-light experience using the phone's physical white rear camera flash. It is **not a flashlight app**: the flash plays smooth, decorative animations — pulses, breathing, heartbeats — synchronized with an on-screen preview.

Works on modern Android phones (Android 13+), including devices **without** adjustable torch brightness: on those, HiLight simulates smooth intensity through perceptual duty-cycle modulation of the LED.

## Features

- 🎞️ **Five presets** — Pulse · Breathing · Double Pulse · Soft Glow · Heartbeat
- 🎛️ **Controls** — Brightness, Speed (0.25×–3×), Repeat (Once / 2× / 3× / Loop)
- 👁️ **Live preview** — on-screen glow driven by the exact same animation definition as the physical flash, from one shared clock origin
- 🔍 **Capability detection** — rear-flash presence, torch availability, adjustable-strength support and maximum level (diagnostics screen)
- 🌗 **Graceful fallback** — ON/OFF-only hardware gets simulated brightness via a 33 Hz duty-cycle carrier with perceptual gamma; keyframe valleys stay true-off
- 🧠 **Adaptive carrier** — widens automatically when the camera HAL is slow; native call rate capped well below jank territory
- 🛡️ **Safety-first** — torch force-killed on errors, backgrounding or screen exit; typed structured errors instead of raw platform exceptions
- ⚙️ **Persistence** — theme and last-used animation settings survive restarts (local-only); reset-to-defaults in Settings
- 🎨 **Material 3 Expressive UI** — restrained liquid-glass surfaces; system / light / dark themes; dynamic color

## Privacy & permissions

- 100% offline — no account, no cloud, no analytics, no telemetry
- Requests **no sensitive permissions**: no camera, microphone, location or storage access
  (Camera2 torch APIs deliberately operate without the CAMERA permission)

## Building

```bash
flutter pub get
flutter test          # 54 tests
flutter build apk --release
```

Release CI lives in [.github/workflows/build.yml](.github/workflows/build.yml):
pushes to `main` produce signed APK artifacts; pushing a tag `v*` additionally
creates a GitHub Release with the APK and changelog notes from
[CHANGELOG.md](CHANGELOG.md). Signing material is supplied exclusively via
repository secrets — never committed.

## Device support

| Capability | Behavior |
|---|---|
| Adjustable torch strength (e.g., recent Pixels) | True variable-brightness animations across the device's level range |
| ON/OFF-only torch (older devices) | Simulated smoothness via duty-cycle modulation |

Verified across Pixel 9 (Android 17) and Pixel 4 (ON/OFF-class). Torch behavior varies by OEM — runtime capability detection, not device model, decides the path.

## License

See [LICENSE](LICENSE).
>>>>>>> 04b7daa (docs: project README)
