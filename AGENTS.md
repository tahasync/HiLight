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
│   └── TorchCapability.kt
```

`prd.md` is the single source of truth for requirements, numbers, and acceptance criteria. This file is the single source of truth for how to behave while building.

## Phase Discipline

Work one phase at a time (§26). Stop and report after each phase's "Done when" checklist is met. Wait for confirmation before starting the next phase. Don't batch multiple phases into one uninterrupted run — smaller verified steps are far more reliable than one long unsupervised pass, and each phase should be reviewable and committable on its own.