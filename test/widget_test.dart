import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hilight/app/hilight_app.dart';
import 'package:hilight/core/motion/strength_mapping.dart';
import 'package:hilight/core/platform/torch_capability.dart';
import 'package:hilight/core/platform/torch_exception.dart';
import 'package:hilight/features/diagnostics/diagnostics_screen.dart';
import 'package:hilight/features/home/home_screen.dart';
import 'package:hilight/features/settings/app_settings_controller.dart';
import 'package:hilight/features/settings/settings_screen.dart';
import 'package:hilight/services/preferences_service.dart';

const MethodChannel _torchChannel = MethodChannel('hilight/torch');

const Map<String, Object?> _fakeCapabilities = <String, Object?>{
  'cameraId': '0',
  'hasFlash': true,
  'torchAvailable': true,
  'supportsStrength': true,
  'maxStrengthLevel': 21,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Fresh settings controller backed by an empty (or seeded) mock store.
  /// Awaits the controller's real load future — no artificial timers (those
  /// deadlock inside testWidgets' fake-async zone).
  Future<AppSettingsController> makeSettings({
    Map<String, Object> initial = const {},
  }) async {
    SharedPreferences.setMockInitialValues(initial);
    final settings = AppSettingsController(PreferencesService());
    await settings.ready;
    return settings;
  }

  /// Pumps the home screen on a phone-proportioned surface so every home
  /// test shares one realistic viewport instead of ad-hoc sizes.
  Future<void> pumpHome(WidgetTester tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 844));
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(settings: await makeSettings()),
    ));
    await tester.pumpAndSettle();
  }

  /// Pumps the settings screen on a tall surface so all §19 sections build.
  Future<void> pumpSettings(
    WidgetTester tester,
    AppSettingsController settings,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(390, 1600));
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(settings: settings),
    ));
    await tester.pumpAndSettle();
  }

  /// Mocks the torch channel; appends non-setup methods to [calls].
  void mockChannel(List<String> calls, {bool flash = true}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_torchChannel, (call) async {
      if (call.method != 'getCapabilities' &&
          call.method != 'getDeviceInfo') {
        calls.add(call.method);
      }
      if (call.method == 'getCapabilities') {
        return flash
            ? _fakeCapabilities
            : <String, Object?>{
                'cameraId': null,
                'hasFlash': false,
                'torchAvailable': false,
                'supportsStrength': false,
                'maxStrengthLevel': 0,
              };
      }
      if (call.method == 'getDeviceInfo') {
        return <String, Object?>{
          'deviceModel': 'Pixel 9',
          'androidVersion': '17',
        };
      }
      return null;
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_torchChannel, null);
  });

  group('HilightApp', () {
    testWidgets('renders home screen', (tester) async {
      SharedPreferences.setMockInitialValues(const {});
      await tester.pumpWidget(const HilightApp());
      await tester.pumpAndSettle();
      expect(find.text('HiLight'), findsOneWidget);
      expect(find.byTooltip('Diagnostics'), findsOneWidget);
    });
  });

  group('DiagnosticsScreen', () {
    testWidgets('shows real capability values', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_torchChannel, (call) async {
        if (call.method == 'getCapabilities') return _fakeCapabilities;
        return null;
      });
      await tester.pumpWidget(const MaterialApp(home: DiagnosticsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Rear flash'), findsOneWidget);
      expect(find.text('Variable power'), findsOneWidget);
      expect(find.text('Supported'), findsOneWidget);
      expect(find.text('21'), findsOneWidget);
      expect(find.text('HiLight animations available.'), findsOneWidget);
    });

    testWidgets('shows fallback explanation without strength support',
        (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_torchChannel, (call) async {
        if (call.method == 'getCapabilities') {
          return <String, Object?>{
            'cameraId': '0',
            'hasFlash': true,
            'torchAvailable': true,
            'supportsStrength': false,
            'maxStrengthLevel': 1,
          };
        }
        return null;
      });
      await tester.pumpWidget(const MaterialApp(home: DiagnosticsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Not supported'), findsOneWidget);
      expect(
        find.text('Basic flash effects available.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Smooth intensity effects are unavailable on this hardware.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('test torch toggles on then off', (tester) async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_torchChannel, (call) async {
        calls.add(call.method);
        if (call.method == 'getCapabilities') return _fakeCapabilities;
        return null;
      });
      await tester.pumpWidget(const MaterialApp(home: DiagnosticsScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Test torch'));
      await tester.pump();
      expect(calls, contains('turnOn'));

      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(calls.indexOf('turnOn'), lessThan(calls.indexOf('turnOff')));
      expect(find.text('Testing…'), findsNothing);
    });

    testWidgets('capability failure shows error card', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_torchChannel, (call) async {
        if (call.method == 'getCapabilities') {
          throw PlatformException(code: 'cameraError', message: 'boom');
        }
        return null;
      });
      await tester.pumpWidget(const MaterialApp(home: DiagnosticsScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Could not read torch capability'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('HomeScreen preview', () {
    testWidgets('preview plays the torch and returns to ready',
        (tester) async {
      final calls = <String>[];
      mockChannel(calls);
      await pumpHome(tester);

      expect(find.text('Pixel 9 · White light'), findsOneWidget);
      await tester.ensureVisible(find.text('Preview HiLight'));
      await tester.tap(find.text('Preview HiLight'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(calls, contains('setStrength'));
      expect(find.text('Stop'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(calls.last, 'turnOff');
      expect(find.text('Preview HiLight'), findsOneWidget);
    });

    testWidgets('backgrounding during playback stops the torch',
        (tester) async {
      final calls = <String>[];
      mockChannel(calls);
      await pumpHome(tester);

      await tester.ensureVisible(find.text('Preview HiLight'));
      await tester.tap(find.text('Preview HiLight'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(calls, contains('setStrength'));

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pumpAndSettle();
      expect(calls.last, 'turnOff');
      expect(find.text('Preview HiLight'), findsOneWidget);
    });

    testWidgets('preset chips select the animation', (tester) async {
      final calls = <String>[];
      mockChannel(calls);
      await pumpHome(tester);

      final breathingChip = find.widgetWithText(FilterChip, 'Breathing');
      await tester.ensureVisible(breathingChip);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(breathingChip).selected, isFalse);
      await tester.tap(breathingChip);
      await tester.pump();
      expect(tester.widget<FilterChip>(breathingChip).selected, isTrue);
      expect(find.textContaining('3200 ms'), findsOneWidget);
    });

    testWidgets('repeat control switches to loop', (tester) async {
      final calls = <String>[];
      mockChannel(calls);
      await pumpHome(tester);

      final loop = find.text('Loop');
      // The V1.1 presets lengthen the chip row, pushing the repeat control
      // below the lazily-built viewport range on a phone-sized surface.
      await tester.scrollUntilVisible(loop, 160);
      await tester.pumpAndSettle();
      // Nudge further up so the segment is fully clear of the viewport edge
      // (ensureVisible only aligns minimally, which can leave it clipped).
      await tester.drag(find.byType(ListView), const Offset(0, -80));
      await tester.pumpAndSettle();
      await tester.tap(loop);
      await tester.pump();
      expect(
        tester
            .widget<SegmentedButton<int>>(
                find.byType(SegmentedButton<int>))
            .selected,
        contains(0),
      );
    });

    testWidgets('preview disabled without flash', (tester) async {
      final calls = <String>[];
      mockChannel(calls, flash: false);
      await pumpHome(tester);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Preview HiLight'),
      );
      expect(button.onPressed, isNull);
      expect(find.text('No rear flash detected'), findsOneWidget);
    });
  });

  group('StrengthMapping', () {
    test('maps normalized intensity across a multi-level range', () {
      expect(mapIntensityToLevel(0.0, 21), 1);
      expect(mapIntensityToLevel(1.0, 21), 21);
      expect(mapIntensityToLevel(0.5, 21), 11); // 1 + round(0.5 * 20)
    });

    test('clamps out-of-range intensities', () {
      expect(mapIntensityToLevel(-0.5, 21), 1);
      expect(mapIntensityToLevel(1.5, 21), 21);
    });

    test('ON/OFF-only devices always map to level 1', () {
      expect(mapIntensityToLevel(0.0, 1), 1);
      expect(mapIntensityToLevel(1.0, 1), 1);
    });
  });

  group('HomeScreen brightness', () {
    int? levelFrom(MethodCall call) => call.method == 'setStrength'
        ? call.arguments['level'] as int
        : null;

    testWidgets('brightness scales the played strength', (tester) async {
      final levels = <int>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_torchChannel, (call) async {
        final level = levelFrom(call);
        if (level != null) levels.add(level);
        if (call.method == 'getCapabilities') return _fakeCapabilities;
        if (call.method == 'getDeviceInfo') {
          return <String, Object?>{
            'deviceModel': 'Pixel 9',
            'androidVersion': '17',
          };
        }
        return null;
      });
      await pumpHome(tester);

      // Tap the brightness slider at a low-but-nonzero position before
      // playing, so the animation's peak maps to a low strength level.
      final slider = find.byType(Slider).first;
      // V1.1 presets lengthen the chip row, pushing the controls card below
      // the lazily-built viewport range on a phone-sized surface; scroll the
      // list explicitly instead of relying on lazy build extent.
      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      await tester.ensureVisible(slider);
      final topLeft = tester.getTopLeft(slider);
      final size = tester.getSize(slider);
      await tester.tapAt(Offset(
        topLeft.dx + size.width * 0.15,
        topLeft.dy + size.height / 2,
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Preview HiLight'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview HiLight'));
      await tester.pumpAndSettle();
      expect(levels, isNotEmpty);
      expect(levels.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(7));
    });

    testWidgets('ON/OFF-only device plays via plain turnOn', (tester) async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_torchChannel, (call) async {
        if (call.method != 'getCapabilities' &&
            call.method != 'getDeviceInfo') {
          calls.add(call.method);
        }
        if (call.method == 'getCapabilities') {
          return <String, Object?>{
            'cameraId': '0',
            'hasFlash': true,
            'torchAvailable': true,
            'supportsStrength': false,
            'maxStrengthLevel': 1,
          };
        }
        if (call.method == 'getDeviceInfo') {
          return <String, Object?>{
            'deviceModel': 'Basic Flash Phone',
            'androidVersion': '13',
          };
        }
        return null;
      });
      await tester.pumpWidget(MaterialApp(
        home: HomeScreen(settings: await makeSettings()),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Preview HiLight'));
      await tester.pump(const Duration(milliseconds: 150));
      expect(calls, contains('turnOn'));
      expect(calls, isNot(contains('setStrength')));

      await tester.pumpAndSettle();
      expect(calls.last, 'turnOff');
    });
  });

  group('Settings persistence (PRD §19)', () {
    testWidgets('settings screen renders every section', (tester) async {
      await pumpSettings(tester, await makeSettings());
      // Scroll the full length so every section builds and is visible.
      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pumpAndSettle();

      for (final section in [
        'Appearance',
        'Animation',
        'Hardware',
        'Advanced',
      ]) {
        expect(find.text(section), findsOneWidget);
      }
      expect(find.text('Default preset'), findsOneWidget);
      expect(find.text('Haptic feedback'), findsOneWidget);
      expect(find.text('Capability diagnostics'), findsOneWidget);
      expect(find.text('Torch update rate'), findsOneWidget);
      expect(find.text('Debug logging'), findsOneWidget);
      expect(find.text('Reset all settings'), findsOneWidget);
    });

    testWidgets('changes persist to the local store', (tester) async {
      await pumpSettings(tester, await makeSettings());

      // Change theme to light.
      await tester.tap(find.text('Light'));
      await tester.pump();

      // Change default preset via the dropdown.
      await tester.tap(find.text('Default preset'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Heartbeat').last);
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('themeMode'), 'light');
      expect(prefs.getString('presetId'), 'heartbeat');
    });

    testWidgets('a fresh controller loads persisted values', (tester) async {
      final first = await makeSettings();
      first.setThemeMode(ThemeMode.dark);
      first.setPresetId('soft_glow');
      first.setBrightness(0.6);
      first.setSpeed(1.5);
      first.setRepeatCount(0);
      first.setHapticsEnabled(false);
      first.setUpdateRateMs(16);
      first.setDebugLogging(true);

      // Simulates a full restart: a brand-new controller over the SAME
      // on-device store, without re-seeding it.
      final second = AppSettingsController(PreferencesService());
      await second.ready;
      expect(second.themeMode, ThemeMode.dark);
      expect(second.presetId, 'soft_glow');
      expect(second.brightness, closeTo(0.6, 1e-9));
      expect(second.speed, closeTo(1.5, 1e-9));
      expect(second.repeatCount, 0);
      expect(second.hapticsEnabled, isFalse);
      expect(second.updateRateMs, 16);
      expect(second.debugLogging, isTrue);
    });

    testWidgets('reset restores defaults', (tester) async {
      final settings = await makeSettings(initial: {
        'themeMode': 'dark',
        'presetId': 'heartbeat',
        'brightness': 0.4,
      });
      await pumpSettings(tester, settings);
      // Bring the reset control into view before tapping.
      await tester.drag(find.byType(ListView), const Offset(0, -1200));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reset all settings'));
      await tester.pumpAndSettle();
      // ignore: avoid_print
      print(
        'DEBUG dialog buttons: '
        '${find.widgetWithText(FilledButton, 'Reset').evaluate().length} '
        'filled / cancel=${find.text('Cancel').evaluate().length}',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
      await tester.pumpAndSettle();
      // ignore: avoid_print
      print(
        'DEBUG dialog still open: '
        '${find.text('Reset all settings?').evaluate().length}',
      );
      final store = await SharedPreferences.getInstance();
      // ignore: avoid_print
      print('DEBUG keys after reset: ${store.getKeys()}');
      // ignore: avoid_print
      print('DEBUG controller theme: ${settings.themeMode}');
      await tester.pumpAndSettle();

      expect(settings.themeMode, ThemeMode.system);
      expect(settings.presetId, 'pulse');
      expect(settings.brightness, 1.0);
    });
  });

  group('TorchCapability model', () {
    test('parses from platform map', () {
      final capability = TorchCapability.fromMap(_fakeCapabilities);
      expect(capability.cameraId, '0');
      expect(capability.hasFlash, isTrue);
      expect(capability.torchAvailable, isTrue);
      expect(capability.supportsStrength, isTrue);
      expect(capability.maxStrengthLevel, 21);
    });

    test('toString includes fields', () {
      const exception = TorchException('noFlash', 'none');
      expect(exception.toString(), contains('noFlash'));
    });
  });
}
