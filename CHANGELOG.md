# Changelog

All notable changes to HiLight are documented here.
Format based on Keep a Changelog; versioning follows SemVer.

## v1.1.0 — Custom animations, Quick Settings tile & three new presets

### Added
- Three new presets: **Quick Flash** (350 ms), **Triple Pulse** (1 050 ms) and **Long Glow** (4 800 ms) — keyframe tables defined once in the canonical preset file.
- **Custom animation editor**: add/remove keyframes (2–20), per-keyframe time and intensity, duration (100 ms–10 s), one easing curve (Linear / Ease In / Ease Out / Ease In Out / Smooth Sine), and live preview through the same engine as built-ins.
- Save, rename and delete custom animations with **local-only persistence** — survives restarts, no account, no cloud.
- Editor-side validation: strictly increasing keyframe times, bounded durations, intensity clamped on input — invalid states are rejected, never silently corrected.
- `custom_<uuid>` id namespace so a user animation can never collide with a future built-in.
- **Quick Settings tile**: one tap starts the default preset at the saved brightness/speed/repeat, a second tap stops it safely. The tile mirrors the engine's actual state — including natural completion — through a single shared Flutter engine (the app's engine when open, a headless one otherwise).
- In-app **update check** against GitHub Releases with an "Update Available" dialog (version pills, changelog preview, direct link); silently skipped when offline or up to date.

### Changed
- Home, Settings and Diagnostics now list all eight built-in presets; the saved default resolves across built-ins and user animations.
- Launcher icon safe-zone (24% inset, sized from measurement) so the logo is never clipped by circular, squircle or rounded-square masks; added a monochrome layer for Android 13+ themed icons.
- `INTERNET` permission added — used exclusively by the optional update check.

### Fixed
- Startup crash when the tile channel attached before the Flutter binding was initialized.
- Cached-app freezer hazard: closing the Quick Settings panel now cancels tile-owned playback so the torch can never be left lit by a frozen process.

### Testing
- 114 passing unit/widget tests (up from 54): exact preset tables, validation limits, store persistence and corruption handling, editor flows, tile playback controller and coordinator ownership routing.

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
