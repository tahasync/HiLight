# Changelog

All notable changes to HiLight are documented here.
Format based on Keep a Changelog; versioning follows SemVer.

## v1.2.0 — Charging effects, full-app haptics, performance pass

Completes the V1.2 milestone, verified live on Pixel 9 (Android 17) and Pixel 4 (Android 16).

### Added
- **Charging effects**: animate on charger connect and disconnect (each with its own preset), plus five battery-milestone presets (20 / 35 / 50 / 70 / 100 %) that fire once per charging session when the level crosses upward — plug-in level consumes lower thresholds silently. Master toggle gates everything; every control is independent; **no periodic animation while charging** (product decision replacing the prd-v1.2.md §4 repeat model).
- **Charging delivery that actually works**: runtime-registered broadcast bridge (manifest receivers for power events get zero delivery on Android 16/17), sticky-intent level reads, host-counted registration shared between the notification listener and the app, and a 4 s polling fallback with 5 s connect dedupe for ROMs that drop power broadcasts entirely (Pixel 4 custom ROM).
- **Full-app haptics**: tiered feedback — medium for play/stop/save/delete/reset, light for every switch and slider commit, selection ticks for pickers — gated by the existing haptics toggle (the MVP only buzzed preset-select, imperceptibly).
- Disconnect safety: any charging-owned animation is killed instantly and unconditionally on unplug *before* the optional disconnect animation; manual previews are never interrupted.

### Fixed
- **Update dialog never fired**: `showUpdateDialog` was called with a context above the navigator — the throw was silently swallowed. Routed through a `GlobalKey<NavigatorState>`; verified live (1.1.0 → v1.1.5 prompt on Pixel 4).
- **Concurrent-trigger restarts**: near-simultaneous notifications could both pass the busy-check and restart the torch mid-animation; start gating is now atomic (regression-tested).
- Launcher icon: full-bleed foreground at a measured inset — complete logo, no dead padding, no mask cropping.
- Text encoding repairs (2×/3×/speed labels, em-dashes) across settings.

### Changed
- **Performance pass**: removed the per-frame GPU backdrop blur from every card — scrolling is now fluid on all screens; glass look retained via tint + hairline border.
- Long-pressing a built-in preset opens the editor as an editable copy; customs edit in place.
- Dead code removed; `flutter analyze` clean.

### Testing
- 184 passing unit/widget tests (up from 169): charging milestone bookkeeping, controller flows (connect / milestone-once / disconnect-kill / manual-preview safety), polling fallback dedupe, coordinator routing.

## v1.1.7 — Update dialog fix

### Fixed
- The "Update Available" dialog never appeared on device: `showUpdateDialog` received the root widget's context (above the navigator), threw, and the silent catch hid it. Now pushed via a navigator `GlobalKey` — verified live prompting 1.1.0 → v1.1.5.
## v1.1.5 — Notification triggers, per-contact & per-app patterns




First slice of the V1.2 milestone, verified live on Pixel 9 (Android 17) and Pixel 4 (Android 16).

### Added
| :bell: **Notification triggers** | Flash on incoming calls (repeats while ringing, stops on answer), SMS, alarms, timers or app notifications — each mapped to any preset |
- **Ring-looping calls**: the call animation repeats while the phone rings and stops the moment the ring notification disappears (answered / declined), with a hard safety cap inside the wake-lock window.
| :bust_in_silhouette: **Per-contact patterns** | Assign a preset to specific people — their calls flash differently from everyone else's |
| :iphone: **Per-app control** | Enable, disable, or re-style flashing for every installed app individually |
- Deterministic trigger precedence: **contact > app > generic > none** â€” covered by unit tests for every combination.
- Long-pressing a built-in preset now opens the editor as an editable copy; long-pressing a custom animation still edits it in place.

### Fixed
- Concurrent-notification race that could restart the torch mid-animation (start gating is now atomic).
- SMS trigger no longer fires for chat platforms (WhatsApp / Snapchat / Instagram label their messages with the same category as SMS); messaging apps are matched explicitly.
- Launcher icon: full-bleed foreground at a measured inset â€” complete logo, no dead padding, no mask cropping.

### Testing
- 169 passing unit/widget tests (up from 114): trigger classification matrix, contact/app stores and corruption handling, precedence combinations, ring-loop replay/removal/cap, race regression.

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
