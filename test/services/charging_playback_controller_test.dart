import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:hilight/core/platform/torch_capability.dart';
import 'package:hilight/services/charging_playback_controller.dart';
import 'package:hilight/services/playback_coordinator.dart';
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
  bool master = true,
  bool connect = true,
  String connectPreset = 'soft_glow',
  bool disconnect = false,
  String disconnectPreset = 'quick_flash',
  bool m50 = false,
  String m50Preset = 'heartbeat',
}) =>
    {
      'charging.enabled': master,
      'charging.connect.enabled': connect,
      'charging.connect.presetId': connectPreset,
      'charging.disconnect.enabled': disconnect,
      'charging.disconnect.presetId': disconnectPreset,
      'charging.milestone.50.enabled': m50,
      'charging.milestone.50.presetId': m50Preset,
    };

Map<String, Object?> event(String name, {int? level}) =>
    {'event': name, 'level': level};

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
    PlaybackCoordinator.instance.attach();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('hilight/tile_control'),
            null);
  });

  ChargingPlaybackController makeController(RecordingOutput output) =>
      ChargingPlaybackController(
        output: output,
        capabilities: () async => capable(),
      );

  group('ChargingPlaybackController (prd-v1.2.md §4, amended spec)', () {
    test('master off: connect event does nothing', () async {
      SharedPreferences.setMockInitialValues(prefsWith(master: false));
      final output = RecordingOutput();
      final controller = makeController(output);

      await controller.handleEvent(event('connected', level: 40));

      expect(output.calls, isEmpty);
      expect(published, isEmpty);
    });

    test('connect plays the configured preset once, ends torch off', () {
      SharedPreferences.setMockInitialValues(prefsWith());
      fakeAsync((async) async {
        final output = RecordingOutput();
        final controller = makeController(output);

        await controller.handleEvent(event('connected', level: 40));
        expect(published.last, isTrue);

        async.elapse(const Duration(milliseconds: 2600));
        expect(published, [true, false]);
        expect(output.turnOffCalls, greaterThanOrEqualTo(1));
      });
    });

    test('milestone fires once on upward crossing, not at plug-in', () {
      SharedPreferences.setMockInitialValues(
          prefsWith(connect: false, m50: true));
      fakeAsync((async) async {
        final output = RecordingOutput();
        final controller = makeController(output);

        // Plugged in at 40%: 50% is above, so it may still fire.
        await controller.handleEvent(event('connected', level: 40));
        async.elapse(const Duration(milliseconds: 100));
        expect(published, isEmpty); // connect animation disabled

        await controller.handleEvent(event('level', level: 45));
        async.elapse(const Duration(milliseconds: 100));
        expect(published, isEmpty); // below threshold

        await controller.handleEvent(event('level', level: 52));
        async.elapse(const Duration(milliseconds: 100));
        expect(published, [true]); // Heartbeat playing

        // Same session, level wobbles back and forth: no second fire.
        await controller.handleEvent(event('level', level: 51));
        await controller.handleEvent(event('level', level: 55));
        async.elapse(const Duration(milliseconds: 1300));
        expect(published, [true, false]);
      });
    });

    test('milestone at or below plug-in level is consumed silently', () async {
      SharedPreferences.setMockInitialValues(
          prefsWith(connect: false, m50: true));
      final output = RecordingOutput();
      final controller = makeController(output);

      // Plugged in at 60%: 50% already passed — silent.
      await controller.handleEvent(event('connected', level: 60));
      await controller.handleEvent(event('level', level: 65));

      expect(output.calls, isEmpty);
      expect(published, isEmpty);
    });

    test('disconnect instantly kills charging playback, then plays the '
        'disconnect animation when enabled', () {
      SharedPreferences.setMockInitialValues(
          prefsWith(connectPreset: 'long_glow', disconnect: true,
              disconnectPreset: 'quick_flash'));
      fakeAsync((async) async {
        final output = RecordingOutput();
        final controller = makeController(output);

        await controller.handleEvent(event('connected', level: 40));
        expect(published.last, isTrue);

        // Unplug mid-Long-Glow: kill first, then Quick Flash plays.
        await controller.handleEvent(event('disconnected'));
        async.elapse(const Duration(milliseconds: 100));
        expect(output.turnOffCalls, greaterThanOrEqualTo(1));
        expect(published.last, isTrue); // disconnect animation running

        async.elapse(const Duration(milliseconds: 500));
        expect(published.last, isFalse); // Quick Flash done, torch off
      });
    });

    test('disconnect with the toggle off leaves the torch off and idle',
        () {
      SharedPreferences.setMockInitialValues(
          prefsWith(connectPreset: 'long_glow', disconnect: false));
      fakeAsync((async) async {
        final output = RecordingOutput();
        final controller = makeController(output);

        await controller.handleEvent(event('connected', level: 40));
        expect(published.last, isTrue);

        await controller.handleEvent(event('disconnected'));
        async.elapse(const Duration(milliseconds: 100));
        expect(published.last, isFalse);
        expect(PlaybackCoordinator.instance.isActive, isFalse);
      });
    });

    test('a manual preview is never killed by an unplug', () async {
      SharedPreferences.setMockInitialValues(prefsWith());
      final output = RecordingOutput();
      final controller = makeController(output);

      // Someone else owns the torch (manual preview).
      PlaybackCoordinator.instance.beginOwnership('manual', () async {});
      await controller.handleEvent(event('disconnected'));

      expect(PlaybackCoordinator.instance.isActive, isTrue);
      PlaybackCoordinator.instance.endOwnership('manual');
    });
  });

  group('PlaybackCoordinator charging routing', () {
    test('registered handler receives chargingEvent', () async {
      Map<Object?, Object?>? received;
      ChargingPlaybackController(output: RecordingOutput()).register();
      PlaybackCoordinator.instance.registerChargingHandler((args) async {
        received = args;
      });

      await TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .handlePlatformMessage(
        'hilight/tile_control',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('chargingEvent', <String, Object?>{
            'event': 'connected',
            'level': 42,
          }),
        ),
        (_) {},
      );

      expect(received, isNotNull);
      expect(received!['level'], 42);
    });
  });
}
