import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hilight/core/motion/easing.dart';
import 'package:hilight/core/motion/hilight_animation.dart';
import 'package:hilight/core/motion/light_keyframe.dart';
import 'package:hilight/core/platform/torch_capability.dart';
import 'package:hilight/features/animation_editor/custom_animation_store.dart';
import 'package:hilight/features/animation_editor/stored_custom_animation.dart';
import 'package:hilight/services/playback_coordinator.dart';
import 'package:hilight/services/tile_playback_controller.dart';

import '../support/recording_output.dart';

TorchCapability capable() => TorchCapability(
      cameraId: '0',
      hasFlash: true,
      torchAvailable: true,
      supportsStrength: true,
      maxStrengthLevel: 21,
    );

StoredCustomAnimation longCustom() => StoredCustomAnimation(
      animation: HilightAnimation(
        id: 'custom_aaaabbbb-cccc-4ddd-8eee-ffff00001111',
        name: 'Slow bloom',
        duration: const Duration(milliseconds: 1200),
        keyframes: [
          LightKeyframe(time: Duration.zero, intensity: 0),
          LightKeyframe(
            time: const Duration(milliseconds: 600),
            intensity: 1.0,
          ),
          LightKeyframe(
            time: const Duration(milliseconds: 1200),
            intensity: 0,
          ),
        ],
      ),
      easing: Easing.easeInOut,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final published = <bool>[];

  void capturePublishes() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('hilight/tile_control'),
      (call) async {
        if (call.method == 'stateChanged') {
          published.add(call.arguments['active'] as bool);
        }
        return null;
      },
    );
  }

  setUp(() async {
    PlaybackCoordinator.instance.resetForTest();
    published.clear();
    SharedPreferences.setMockInitialValues(const {});
    capturePublishes();
    // Attach after the mock so publishes are recorded, not swallowed.
    PlaybackCoordinator.instance.attach();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('hilight/tile_control'),
            null);
  });

  TilePlaybackController makeController(RecordingOutput output) {
    final controller = TilePlaybackController(output: output)
      ..register();
    return controller;
  }

  group('TilePlaybackController (prd-v1.1.md §4)', () {
    test('plays the saved default preset and returns to idle on '
        'natural completion', () {
      SharedPreferences.setMockInitialValues({
        'presetId': 'quick_flash',
        'brightness': 0.5,
        'speed': 1.0,
        'repeatCount': 1,
      });
      fakeAsync((async) async {
        final output = RecordingOutput();
        makeController(output);
        await PlaybackCoordinator.instance.toggle();
        expect(output.strengthCalls, isNotEmpty);
        expect(published.last, isTrue);

        async.elapse(const Duration(milliseconds: 500));
        expect(published, [true, false]);
        expect(output.turnOffCalls, greaterThanOrEqualTo(1));
        expect(PlaybackCoordinator.instance.isActive, isFalse);
      });
    });

    test('a second toggle stops the running default immediately', () async {
      SharedPreferences.setMockInitialValues({'presetId': 'long_glow'});
      final output = RecordingOutput();
      TilePlaybackController(
        output: output,
        capabilities: () async => capable(),
      ).register();

      await PlaybackCoordinator.instance.toggle();
      expect(published.last, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await PlaybackCoordinator.instance.toggle();

      expect(published, contains(false));
      expect(output.turnOffCalls, greaterThanOrEqualTo(1));
      expect(PlaybackCoordinator.instance.isActive, isFalse);
    });

    test('resolves a saved custom preset as the default', () {
      final custom = longCustom();
      SharedPreferences.setMockInitialValues({
        'presetId': custom.id,
        CustomAnimationStore.storageKey:
            jsonEncode([custom.toJson()]),
      });
      fakeAsync((async) async {
        final output = RecordingOutput();
        makeController(output);
        await PlaybackCoordinator.instance.toggle();
        expect(published.last, isTrue);
        async.elapse(const Duration(milliseconds: 1400));
        expect(published, [true, false]);
        expect(output.turnOffCalls, greaterThanOrEqualTo(1));
      });
    });

    test('stays idle when the torch is unavailable', () async {
      final output = RecordingOutput();
      final controller = TilePlaybackController(
        output: output,
        capabilities: () async => null,
      );
      controller.register();

      await PlaybackCoordinator.instance.toggle();

      expect(output.calls, isEmpty);
      expect(published.where((a) => a), isEmpty);
      expect(PlaybackCoordinator.instance.isActive, isFalse);
    });
  });

  group('PlaybackCoordinator ownership routing', () {
    test('toggle stops the current owner before starting anew', () async {
      var stoppedOwner = false;
      var startedExternal = false;
      PlaybackCoordinator.instance.registerExternalStart(() async {
        startedExternal = true;
      });

      PlaybackCoordinator.instance.beginOwnership('owner', () async {
        stoppedOwner = true;
        // Real owners end their own ownership as part of stopping.
        PlaybackCoordinator.instance.endOwnership('owner');
      });
      expect(PlaybackCoordinator.instance.isActive, isTrue);

      await PlaybackCoordinator.instance.toggle();
      expect(stoppedOwner, isTrue);
      expect(startedExternal, isFalse);

      await PlaybackCoordinator.instance.toggle();
      expect(startedExternal, isTrue);
    });

    test('endOwnership ignores stale owners', () async {
      PlaybackCoordinator.instance
          .beginOwnership('first', () async {});
      PlaybackCoordinator.instance.endOwnership('second');
      expect(PlaybackCoordinator.instance.isActive, isTrue);
      PlaybackCoordinator.instance.endOwnership('first');
      expect(PlaybackCoordinator.instance.isActive, isFalse);
    });
  });
}
