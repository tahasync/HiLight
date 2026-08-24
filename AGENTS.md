# HiLight — AGENTS.md

## Project Summary

HiLight is a production-quality Android application built with Flutter and Kotlin that recreates a HiLight-style experience using the device's physical rear white camera flash. It targets modern Android phones (Android 13+) in general — not limited to any single device model. The app creates smooth, decorative, notification-style animations using the phone's physical white rear camera flash. This is NOT a flashlight app and does NOT attempt to produce RGB colors from a white LED.

## Tech Stack

- Flutter stable
- Dart with sound null safety
- Kotlin for Android native integration
- Android Camera2 API
- Material 3
- Material 3 Expressive design principles
- Subtle liquid-glass surface treatment
- Local persistence only for MVP

## Important Product Constraints

1. No RGB torch effects.
2. No fake claim that the target device has dedicated HiLight hardware.
3. No root requirement.
4. No paid API.
5. No cloud dependency.
6. No unnecessary permissions.
7. No flashlight-app positioning.
8. No excessive liquid-glass styling.
9. Material 3 Expressive is the primary design language.
10. The physical white rear flash is the hero feature.

## Directory Structure

```
lib/
├── app/
├── core/
│   ├── theme/
│   ├── motion/
│   └── platform/
├── features/
│   ├── home/
│   ├── animation_editor/
│   ├── presets/
│   ├── settings/
│   └── diagnostics/
├── services/
│   ├── torch_service.dart
│   ├── animation_service.dart
│   └── preferences_service.dart
└── widgets/
```

Native:
```
android/app/src/main/kotlin/.../
├── MainActivity.kt
├── torch/
│   ├── TorchChannel.kt
│   ├── TorchController.kt
│   ├── TorchCapability.kt
│   ├── TileEngineHost.kt
│   ├── TileControlChannel (in TileEngineHost.kt)
│   ├── HilightTileService.kt
│   ├── HilightNotificationListenerService.kt
│   ├── ChargingBridge.kt
│   ├── ContactsChannel.kt
│   ├── AppsChannel.kt
│   └── TriggerSupportChannel.kt
```

`prd.md` is the single source of truth for requirements, numbers, and acceptance criteria; `prd-v1.1.md` is the source of truth for every V1.1 number (preset tables, validation limits). This file is the single source of truth for how to behave while building. `prd-v1.2.md` governs the V1.2 trigger/per-contact/per-app/charging milestone, **as amended by the product-owner deltas below**.

## V1.2 Additions (shipped)

- **Notification triggers** (`HilightNotificationListenerService.kt` + `lib/services/notification_trigger_classifier.dart` + `trigger_playback_controller.dart`): the Kotlin listener is a dumb pipe — it forwards only presence-level metadata (category, package, ongoing, caller URI) over `hilight/tile_control` (`triggerEvent`); ALL classification and gating lives in Dart so it stays unit-testable. Classification is **category-first with a messaging-app allowlist for SMS** (chat platforms label DMs `"msg"` exactly like SMS — package fallbacks without the allowlist caused false flashes). There is no `CATEGORY_TIMER`: `"alarm"` means "alarm or timer", resolved alarm-first with timer fallback, surfaced honestly in UI. Incoming-call animations **loop while ringing** and stop on the notification's removal (55 s cap inside the wake-lock window).
- **Permissions discipline (hard rule)**: notification-listener access is requested only inside the enable flow (explanation dialog → system screen → pending-enable auto-completes on grant); `READ_CONTACTS` only when *Add contact* is tapped. Manifest must declare `READ_CONTACTS` and `<queries>` entries for the contacts picker AND main/launcher (package visibility) — missing either silently breaks the flow.
- **Per-contact overrides** (`contact_override_store.dart`, `contact_matcher.dart`): stored as one JSON list (`contactOverrides.v1`); matching is digit-normalized with trunk-prefix variants (local `0314…` vs `+92314…`) and a ≥7-digit suffix rule. Caller identity comes from `EXTRA_CALL_PERSON` ("android.callPerson", API 31+ only) — never logged, never stored.
- **Per-app overrides** (`app_override_store.dart` + `app_overrides_screen.dart`): every installed app individually enable/disable + optional preset; unlisted apps follow the App-notifications trigger. Precedence everywhere: **contact > app > generic > none** (fully unit-tested).
- **Charging effects** (`ChargingBridge.kt` + `charging_playback_controller.dart`): master toggle, on-connect, on-disconnect, five battery milestones (20/35/50/70/100 %) fired once per session on upward crossing (plug-in level consumes lower thresholds). **No periodic repeat** — product-owner delta overriding prd-v1.2.md §4. Disconnect kills charging-owned playback instantly before the optional disconnect animation; manual previews are never stomped.
- **Charging delivery — CRITICAL**: manifest receivers for `POWER_CONNECTED/DISCONNECTED` got **zero delivery** on Android 16/17 (empirically, both test devices). Use the runtime-registered `ChargingBridge` (host-counted: NLS + Activity share one receiver; unregistering only when the last host leaves — closing the app must NOT kill the listener-hosted registration). Plug broadcasts carry no level: read the sticky `ACTION_BATTERY_CHANGED`. Devices whose ROM drops these broadcasts entirely (Pixel 4 custom ROM) are covered by a **4 s Dart polling fallback** (`chargingSnapshot` on `hilight/trigger_support`) with a 5 s connect dedupe so broadcast+poll never double-fire.
- **Trigger playback rules**: plays once, skips when torch busy, 1.2 s debounce; concurrent events must never restart playback (busy/debounce gates run after all awaits — atomic start, regression-tested).
- **Update dialog**: `showUpdateDialog` must be given a context UNDER the navigator (`GlobalKey<NavigatorState>` in `HilightApp`) — the root widget's context silently throws and the catch swallows it.
- **Long-press editing**: customs edit in place; built-ins open the editor as an editable copy (built-ins are immutable §28 tables).
- **Launcher icon**: the artwork is a self-contained tile → foreground layer at `adaptive_icon_foreground_inset: 13` (fills circular masks with no black edges; 24 = too small, background-layer = zoom-cropped — both tried on device).

## V1.1 Additions (shipped)

- **Three new presets** (Quick Flash / Triple Pulse / Long Glow): defined once in `lib/core/motion/preset_definitions.dart` — `kBuiltinPresets` is the full ordered set; `builtinPresetById` resolves both built-ins and nothing else. Never restate their keyframe numbers elsewhere.
- **Custom animation editor** (`lib/features/animation_editor/`): validation rules (`custom_animation_validation.dart`, limits 2–20 keyframes, 100–10 000 ms, strictly increasing times, clamp intensity at the editor), `custom_<uuid>` id namespace (`custom_animation_id.dart`, self-rolled v4 — no dependency), storage envelope (`stored_custom_animation.dart` = canonical §28 schema + one `easing`), draft (`custom_animation_draft.dart`), local store (`custom_animation_store.dart`, one JSON list under SharedPreferences key `customAnimations.v1`; malformed entries are skipped, never fatal).
- **Quick Settings tile**: `HilightTileService` + `TileEngineHost` (Kotlin) share ONE Flutter engine — the Activity's when open, otherwise a headless engine on the `tileMain` entrypoint in `lib/main.dart`. The headless engine is intentionally kept alive for the process lifetime (a second directly-constructed FlutterEngine cannot run Dart reliably — do not "optimize" this back).
- **`PlaybackCoordinator`** (`lib/services/playback_coordinator.dart`) is the single ownership point for torch playback: HomeController and `TilePlaybackController` both register ownership; every transition is published to Kotlin (`stateChanged`) so the tile mirrors the engine, including natural completion. `main()` must call `WidgetsFlutterBinding.ensureInitialized()` BEFORE `PlaybackCoordinator.instance.attach()` (channel access before the binding crashes startup).
- **Cached-app freezer safety**: when the QS panel closes (`onStopListening`), Kotlin sends `tileStop`, which cancels only tile-owned playback — a frozen process could otherwise never fire the completion timer and would leave the torch lit.
- Launcher icon: `adaptive_icon_foreground_inset: 24` in pubspec is sized from measurement (artwork max radius 53.6% of source); changing it risks mask clipping on circular launchers. A monochrome layer is generated for Android 13+ themed icons.

## Phase Discipline

Work one phase at a time (§26). Stop and report after each phase's "Done when" checklist is met. Wait for confirmation before starting the next phase. Don't batch multiple phases into one uninterrupted run — smaller verified steps are far more reliable than one long unsupervised pass, and each phase should be reviewable and committable on its own.