import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:hilight/core/motion/easing.dart';
import 'package:hilight/core/motion/hilight_animation.dart';
import 'package:hilight/core/motion/light_keyframe.dart';
import 'package:hilight/core/platform/torch_capability.dart';
import 'package:hilight/features/animation_editor/custom_animation_store.dart';
import 'package:hilight/features/animation_editor/stored_custom_animation.dart';
import 'package:hilight/services/app_override_store.dart';
import 'package:hilight/services/contact_override_store.dart';
import 'package:hilight/services/playback_coordinator.dart';
import 'package:hilight/services/trigger_playback_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/recording_output.dart';

TorchCapability capable() => TorchCapability(
      cameraId: '0',
      hasFlash: true,
      torchAvailable: true,
      supportsStrength: true,
      maxStrengthLevel: 21,
    );

Map<String, Object> prefsWith({
  bool call = false,
  String callPreset = 'quick_flash',
  bool sms = false,
  String smsPreset = 'pulse',
  bool alarm = false,
  String alarmPreset = 'triple_pulse',
  bool timer = false,
  String timerPreset = 'heartbeat',
  bool app = false,
  String appPreset = 'pulse',
}) =>
    {
      'trigger.incomingCall.enabled': call,
      'trigger.incomingCall.presetId': callPreset,
      'trigger.sms.enabled': sms,
      'trigger.sms.presetId': smsPreset,
      'trigger.alarm.enabled': alarm,
      'trigger.alarm.presetId': alarmPreset,
      'trigger.timer.enabled': timer,
      'trigger.timer.presetId': timerPreset,
      'trigger.appNotification.enabled': app,
      'trigger.appNotification.presetId': appPreset,
    };

Map<String, Object?> eventArgs({
  String? category,
  String packageName = 'com.example.app',
  bool isOngoing = false,
}) =>
    {
      'packageName': packageName,
      'category': category,
      'isOngoing': isOngoing,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final published = <bool>[];

  setUp(() {
    PlaybackCoordinator.instance.resetForTest();
    published.clear();
    SharedPreferences.setMockInitialValues(const {});
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
    // Attach after the mock so publishes are recorded, not swallowed.
    PlaybackCoordinator.instance.attach();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('hilight/tile_control'),
            null);
  });

  TriggerPlaybackController makeController(
    RecordingOutput output, {
    bool torchAvailable = true,
  }) =>
      TriggerPlaybackController(
        output: output,
        capabilities: () async =>
            torchAvailable ? capable() : null,
      );

  group('TriggerPlaybackController (prd-v1.2.md §2)', () {
    test('a disabled trigger never touches the torch', () async {
      final output = RecordingOutput();
      final controller = makeController(output);

      await controller.handleEvent(eventArgs(category: 'call'));

      expect(output.calls, isEmpty);
      expect(published, isEmpty);
      expect(PlaybackCoordinator.instance.isActive, isFalse);
    });

    test('an enabled trigger plays its assigned preset once and ends '
        'with the torch off', () {
      SharedPreferences.setMockInitialValues(prefsWith(sms: true));
      fakeAsync((async) async {
        final output = RecordingOutput();
        final controller = makeController(output);

        await controller.handleEvent(eventArgs(category: 'msg'));

        expect(published.last, isTrue);
        expect(PlaybackCoordinator.instance.isActive, isTrue);

        async.elapse(const Duration(milliseconds: 900));
        expect(published, [true, false]);
        expect(output.turnOffCalls, greaterThanOrEqualTo(1));
        expect(PlaybackCoordinator.instance.isActive, isFalse);
      });
    });

    test('skips when the torch is already busy instead of stomping', () async {
      SharedPreferences.setMockInitialValues(prefsWith(call: true));
      final output = RecordingOutput();
      final controller = makeController(output);

      PlaybackCoordinator.instance.beginOwnership('other', () async {});
      expect(PlaybackCoordinator.instance.isActive, isTrue);
      final publishedBeforeSkip = published.length;
      await controller.handleEvent(eventArgs(category: 'call'));
      // The dummy ownership publishes remain; the trigger must add none.
      expect(published.length, publishedBeforeSkip);
      PlaybackCoordinator.instance.endOwnership('other');

      expect(output.calls, isEmpty);
    });

    test('near-simultaneous events start exactly one playback '
        '(regression: both passed the busy check before their awaits)',
        () async {
      SharedPreferences.setMockInitialValues(
          prefsWith(app: true, appPreset: 'quick_flash'));
      final output = RecordingOutput();
      final controller = makeController(output);

      // Fire two events whose async loads overlap; the second must lose.
      final results = await Future.wait([
        controller.handleEvent(eventArgs(packageName: 'com.example.app')),
        controller.handleEvent(
            eventArgs(category: 'social', packageName: 'com.other.app')),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Exactly one begin (true); the loser never stomps the winner.
      expect(published.where((active) => active), hasLength(1));
      // And the torch still ends off (Quick Flash runs 350 ms).
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(published.last, isFalse);
      expect(results, everyElement(isNull));
    });

    test('collapses events arriving within the debounce window', () {
      SharedPreferences.setMockInitialValues(
          prefsWith(sms: true, smsPreset: 'quick_flash'));
      fakeAsync((async) async {
        final output = RecordingOutput();
        final controller = makeController(output);

        await controller.handleEvent(eventArgs(category: 'msg'));
        expect(published.last, isTrue);

        async.elapse(const Duration(milliseconds: 500));
        expect(published, [true, false]);

        // Second message right after the first finished: still inside the
        // debounce window measured from the previous start.
        await controller.handleEvent(eventArgs(category: 'msg'));
        async.elapse(const Duration(milliseconds: 600));

        expect(published, [true, false]);
      });
    });

    test('an unknown preset id falls back to Pulse rather than failing',
        () {
      SharedPreferences.setMockInitialValues(
          prefsWith(sms: true, smsPreset: 'deleted_custom'));
      fakeAsync((async) async {
        final output = RecordingOutput();
        final controller = makeController(output);

        await controller.handleEvent(eventArgs(category: 'msg'));
        expect(published.last, isTrue);

        async.elapse(const Duration(milliseconds: 900));
        expect(published, [true, false]);
        expect(output.strengthCalls, isNotEmpty);
        expect(output.turnOffCalls, greaterThanOrEqualTo(1));
      });
    });

    test('resolves a stored custom preset as a trigger preset', () {
      final custom = StoredCustomAnimation(
        animation: HilightAnimation(
          id: 'custom_aaaabbbb-cccc-4ddd-8eee-ffff00001111',
          name: 'Signal bloom',
          duration: const Duration(milliseconds: 300),
          keyframes: [
            LightKeyframe(time: Duration.zero, intensity: 0),
            LightKeyframe(
              time: const Duration(milliseconds: 150),
              intensity: 1.0,
            ),
            LightKeyframe(time: const Duration(milliseconds: 300), intensity: 0),
          ],
        ),
        easing: Easing.linear,
      );
      SharedPreferences.setMockInitialValues({
        ...prefsWith(sms: true, smsPreset: custom.id),
        CustomAnimationStore.storageKey: jsonEncode([custom.toJson()]),
      });
      fakeAsync((async) async {
        final output = RecordingOutput();
        final controller = makeController(output);

        await controller.handleEvent(eventArgs(category: 'msg'));
        expect(published.last, isTrue);

        async.elapse(const Duration(milliseconds: 400));
        expect(published, [true, false]);
        expect(output.strengthCalls, isNotEmpty);
      });
    });

    test('stays idle when the torch is unavailable', () async {
      SharedPreferences.setMockInitialValues(prefsWith(call: true));
      final output = RecordingOutput();
      final controller =
          makeController(output, torchAvailable: false);

      await controller.handleEvent(eventArgs(category: 'call'));

      expect(output.calls, isEmpty);
      expect(published, isEmpty);
    });

    test('a matching contact override plays its preset instead of the '
        'generic incoming-call preset (prd-v1.2.md §3)', () {
      SharedPreferences.setMockInitialValues({
        ...prefsWith(call: true, callPreset: 'quick_flash'),
        ContactOverrideStore.storageKey: jsonEncode([
          const {
            'lookupKey': 'lkMom',
            'displayName': 'Mom',
            'number': '+90 532 111 22 33',
            'presetId': 'long_glow',
          },
        ]),
      });
      fakeAsync((async) async {
        final output = RecordingOutput();
        final controller = makeController(output);

        // Mom calls (country code differs from the stored number — the
        // suffix match must still hit).
        await controller.handleEvent(eventArgs(
          category: 'call',
          packageName: 'com.google.android.dialer',
        )..['callUri'] = 'tel:+905321112233');
        expect(published.last, isTrue);

        // Long Glow runs 4.8 s; Quick Flash would have finished in 0.35 s.
        async.elapse(const Duration(milliseconds: 600));
        expect(published, [true]);
        async.elapse(const Duration(milliseconds: 4400));
        expect(published, [true, false]);
        expect(output.turnOffCalls, greaterThanOrEqualTo(1));
      });
    });

    test('an unassigned caller keeps the generic incoming-call preset', () {
      SharedPreferences.setMockInitialValues({
        ...prefsWith(call: true, callPreset: 'quick_flash'),
        ContactOverrideStore.storageKey: jsonEncode([
          const {
            'lookupKey': 'lkMom',
            'displayName': 'Mom',
            'number': '+90 532 111 22 33',
            'presetId': 'long_glow',
          },
        ]),
      });
      fakeAsync((async) async {
        final output = RecordingOutput();
        final controller = makeController(output);

        await controller.handleEvent(eventArgs(
          category: 'call',
          packageName: 'com.google.android.dialer',
        )..['callUri'] = 'tel:05329997777');
        expect(published.last, isTrue);

        // Quick Flash finishes inside ~350 ms.
        async.elapse(const Duration(milliseconds: 600));
        expect(published, [true, false]);
      });
    });

    test('precedence: contact override beats an app preset on calls '
        '(prd-v1.2.md §3: contact > app > generic)', () {
      SharedPreferences.setMockInitialValues({
        ...prefsWith(call: true, callPreset: 'quick_flash'),
        ContactOverrideStore.storageKey: jsonEncode([
          const {
            'lookupKey': 'lkMom',
            'displayName': 'Mom',
            'number': '05321112233',
            'presetId': 'long_glow',
          },
        ]),
        AppOverrideStore.storageKey: jsonEncode([
          const {
            'packageName': 'com.google.android.dialer',
            'appName': 'Phone',
            'flashEnabled': true,
            'presetId': 'heartbeat',
          },
        ]),
      });
      fakeAsync((async) async {
        final output = RecordingOutput();
        final controller = makeController(output);

        // Mom calls: contact wins over the dialer's app preset.
        await controller.handleEvent(eventArgs(
          category: 'call',
          packageName: 'com.google.android.dialer',
        )..['callUri'] = 'tel:+905321112233');
        expect(published.last, isTrue);

        async.elapse(const Duration(milliseconds: 600));
        // Long Glow (4.8 s) still playing — not Heartbeat (1.1 s).
        expect(published, [true]);
        async.elapse(const Duration(seconds: 5));
        expect(published, [true, false]);
      });
    });

    test('per-app disable blocks that app even when its trigger is on '
        '(prd-v1.2.md §3: none)', () async {
      SharedPreferences.setMockInitialValues({
        ...prefsWith(app: true),
        AppOverrideStore.storageKey: jsonEncode([
          const {
            'packageName': 'com.example.app',
            'appName': 'Example',
            'flashEnabled': false,
            'presetId': null,
          },
        ]),
      });
      final output = RecordingOutput();
      final controller = makeController(output);

      await controller.handleEvent(
          eventArgs(packageName: 'com.example.app'));

      expect(output.calls, isEmpty);
      expect(published, isEmpty);
    });

    test('per-app preset overrides the generic app-notification preset',
        () {
      SharedPreferences.setMockInitialValues({
        ...prefsWith(app: true, appPreset: 'pulse'),
        AppOverrideStore.storageKey: jsonEncode([
          const {
            'packageName': 'com.example.app',
            'appName': 'Example',
            'flashEnabled': true,
            'presetId': 'heartbeat',
          },
        ]),
      });
      fakeAsync((async) async {
        final output = RecordingOutput();
        final controller = makeController(output);

        await controller.handleEvent(
            eventArgs(packageName: 'com.example.app'));
        expect(published.last, isTrue);

        // Heartbeat runs 1.1 s; Pulse would still be going at 700 ms.
        async.elapse(const Duration(milliseconds: 700));
        expect(published, [true, false]);
      });
    });

    test('unlisted apps keep the generic app-notification preset', () {
      SharedPreferences.setMockInitialValues({
        ...prefsWith(app: true, appPreset: 'quick_flash'),
        AppOverrideStore.storageKey: jsonEncode([
          const {
            'packageName': 'com.other.app',
            'appName': 'Other',
            'flashEnabled': false,
            'presetId': null,
          },
        ]),
      });
      fakeAsync((async) async {
        final output = RecordingOutput();
        final controller = makeController(output);

        await controller.handleEvent(
            eventArgs(packageName: 'com.example.app'));
        expect(published.last, isTrue);

        async.elapse(const Duration(milliseconds: 500));
        expect(published, [true, false]);
      });
    });

    test('call animation repeats while the ring lives, stops on removal',
        () {
      SharedPreferences.setMockInitialValues(
          prefsWith(call: true, callPreset: 'quick_flash'));
      fakeAsync((async) async {
        final output = RecordingOutput();
        final controller = makeController(output);

        await controller.handleEvent(eventArgs(
          category: 'call',
          packageName: 'com.google.android.dialer',
        )..['callUri'] = 'tel:05321112233');
        expect(published, [true]);

        // First cycle ends; the loop replays instead of going idle.
        async.elapse(const Duration(milliseconds: 500));
        expect(published, [true]);
        expect(output.turnOnCalls + output.strengthCalls.length,
            greaterThan(0));

        // Ring answered/declined: removal stops the loop, torch off.
        await controller.handleEvent(eventArgs(
          packageName: 'com.google.android.dialer',
        )..['removed'] = true);
        expect(published.last, isFalse);
        expect(output.turnOffCalls, greaterThanOrEqualTo(1));
        expect(PlaybackCoordinator.instance.isActive, isFalse);
      });
    });

    test('ring loop is hard-capped even if removal never arrives', () {
      SharedPreferences.setMockInitialValues(
          prefsWith(call: true, callPreset: 'quick_flash'));
      fakeAsync((async) async {
        final output = RecordingOutput();
        final controller = makeController(output);

        await controller.handleEvent(eventArgs(
          category: 'call',
          packageName: 'com.google.android.dialer',
        )..['callUri'] = 'tel:05321112233');

        // Outlast the 55 s cap entirely (virtual time).
        async.elapse(const Duration(seconds: 70));
        expect(published.last, isFalse);
        expect(PlaybackCoordinator.instance.isActive, isFalse);
      });
    });
  });

  group('PlaybackCoordinator trigger routing', () {
    test('registered handler receives native trigger events', () async {
      Map<Object?, Object?>? received;
      TriggerPlaybackController(output: RecordingOutput(), capabilities: () async => null)
          .register();
      // Replace with a spy to observe routing without touching prefs.
      PlaybackCoordinator.instance.registerTriggerHandler((args) async {
        received = args;
      });

      // Simulate Kotlin invoking triggerEvent over hilight/tile_control.
      await TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'hilight/tile_control',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('triggerEvent', <String, Object?>{
            'packageName': 'com.example.app',
            'category': 'msg',
            'isOngoing': false,
          }),
        ),
        (_) {},
      );

      expect(received, isNotNull);
      expect(received!['category'], 'msg');
    });
  });
}
