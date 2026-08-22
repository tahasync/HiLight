# Changelog

All notable changes to HiLight are documented here.
Format based on Keep a Changelog; versioning follows SemVer.

## v1.0.0 — Initial MVP release

### Added
- Physical white rear-flash animations on Android 13+ phones (Camera2 torch control, no camera permission required).
- Runtime capability detection: rear-flash presence, torch availability, adjustable-strength support and maximum level (diagnostics screen included).
- Five animation presets: Pulse, Breathing, Double Pulse, Soft Glow, Heartbeat — one canonical keyframe definition shared by engine, UI and tests.
- Brightness (0–100%), speed (0.25×–3×) and repeat (Once/2×/3×/Loop) controls with live on-screen preview synchronized to the physical flash from a single shared clock origin.
- ON/OFF-only hardware support: perceptual duty-cycle modulation simulates smooth brightness on devices without strength control; true-off valleys preserved.
- Adaptive PWM carrier that widens automatically on slow camera HALs, with native-call rate capping.
- Material 3 Expressive interface with restrained liquid-glass surfaces; system/light/dark themes.
- Local-only persistence of theme and last-used animation settings; reset-to-defaults in Settings.
- Safety guarantees: torch is force-killed on errors, app backgrounding, screen exit; structured typed errors surfaced instead of raw platform exceptions.
- Offline-first: no account, no cloud, no analytics, no telemetry; requests no sensitive permissions.
- 54 passing unit/widget tests covering the animation engine, presets, serialization, persistence and UI behavior.
