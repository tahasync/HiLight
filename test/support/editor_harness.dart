import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hilight/core/motion/easing.dart';
import 'package:hilight/core/motion/hilight_animation.dart';
import 'package:hilight/core/motion/light_keyframe.dart';
import 'package:hilight/features/animation_editor/custom_animation_store.dart';
import 'package:hilight/features/animation_editor/stored_custom_animation.dart';
import 'package:hilight/features/settings/app_settings_controller.dart';
import 'package:hilight/services/preferences_service.dart';

const torchChannel = MethodChannel('hilight/torch');

/// Recorded non-setup native calls (turnOn/setStrength/turnOff).
final recordedCalls = <String>[];

void mockTorchChannel() {
  recordedCalls.clear();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(torchChannel, (call) async {
    if (call.method != 'getCapabilities' &&
        call.method != 'getDeviceInfo') {
      recordedCalls.add(call.method);
    }
    if (call.method == 'getCapabilities') {
      return <String, Object?>{
        'cameraId': '0',
        'hasFlash': true,
        'torchAvailable': true,
        'supportsStrength': true,
        'maxStrengthLevel': 21,
      };
    }
    return null;
  });
}

StoredCustomAnimation seedEntry({
  String name = 'Flicker',
  String id = 'custom_11111111-2222-4333-8444-555555555555',
}) {
  return StoredCustomAnimation(
    animation: HilightAnimation(
      id: id,
      name: name,
      duration: const Duration(milliseconds: 350),
      keyframes: [
        LightKeyframe(time: Duration.zero, intensity: 0.0),
        LightKeyframe(time: const Duration(milliseconds: 60), intensity: 1.0),
        LightKeyframe(time: const Duration(milliseconds: 350), intensity: 0.0),
      ],
    ),
    easing: Easing.easeInOut,
  );
}

Future<AppSettingsController> makeSettings({
  Map<String, Object> initial = const {},
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final settings = AppSettingsController(PreferencesService());
  await settings.ready;
  return settings;
}

/// Seeds the custom store's backing preferences directly.
Future<void> seedStore(List<StoredCustomAnimation> entries) async {
  SharedPreferences.setMockInitialValues({
    CustomAnimationStore.storageKey:
        jsonEncode([for (final e in entries) e.toJson()]),
  });
}

/// Settings controller whose preference store already contains [entries].
/// Use this instead of seeding separately — a later setMockInitialValues()
/// would otherwise wipe the store key.
Future<AppSettingsController> makeSettingsWithStore(
  List<StoredCustomAnimation> entries,
) async {
  await seedStore(entries);
  final settings = AppSettingsController(PreferencesService());
  await settings.ready;
  return settings;
}
