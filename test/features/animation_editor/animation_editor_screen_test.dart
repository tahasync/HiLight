import 'package:flutter/material.dart' hide Easing;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hilight/core/motion/easing.dart';
import 'package:hilight/features/animation_editor/animation_editor_screen.dart';
import 'package:hilight/features/animation_editor/custom_animation_store.dart';
import 'package:hilight/features/animation_editor/stored_custom_animation.dart';
import 'package:hilight/features/settings/app_settings_controller.dart';
import '../../support/editor_harness.dart';

Future<void> pumpEditor(
  WidgetTester tester, {
  required AppSettingsController settings,
  StoredCustomAnimation? initial,
}) async {
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(const Size(390, 1900));
  await tester.pumpWidget(MaterialApp(
    home: AnimationEditorScreen(settings: settings, initial: initial),
  ));
  await tester.pumpAndSettle();
}

FilledButton _buttonOf(WidgetTester tester, String label) {
  return tester.widget<FilledButton>(
    find.ancestor(of: find.text(label), matching: find.byType(FilledButton)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(const {});
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(torchChannel, null);
  });

  group('AnimationEditorScreen (prd-v1.1.md §3)', () {
    testWidgets('renders a valid new draft', (tester) async {
      mockTorchChannel();
      await pumpEditor(tester, settings: await makeSettings());

      expect(find.widgetWithText(TextField, 'My animation'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
      expect(find.text('#2'), findsOneWidget);
      // Duration label plus keyframe #2 both show 800 ms.
      expect(find.text('800 ms'), findsWidgets);
      expect(_buttonOf(tester, 'Save').onPressed, isNotNull);
    });

    testWidgets('adds and removes keyframes', (tester) async {
      mockTorchChannel();
      await pumpEditor(tester, settings: await makeSettings());

      await tester.tap(find.text('Add keyframe'));
      await tester.pump();
      expect(find.text('#3'), findsOneWidget);

      await tester.tap(find.byTooltip('Remove keyframe').first,
          warnIfMissed: false);
      await tester.pump();
      expect(find.text('#3'), findsNothing);
    });

    testWidgets('an invalid draft blocks save and preview', (tester) async {
      mockTorchChannel();
      await pumpEditor(tester, settings: await makeSettings());

      for (var i = 0; i < 2; i++) {
        await tester.tap(find.byTooltip('Remove keyframe').first,
            warnIfMissed: false);
        await tester.pump();
      }

      expect(find.textContaining('at least 2 keyframes'), findsOneWidget);
      expect(_buttonOf(tester, 'Save').onPressed, isNull);
      expect(_buttonOf(tester, 'Preview').onPressed, isNull);
    });

    testWidgets('save persists through the local store', (tester) async {
      mockTorchChannel();
      await pumpEditor(tester, settings: await makeSettings());

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('New animation'), findsNothing);
      final loaded = await CustomAnimationStore().loadAll();
      expect(loaded.length, 1);
      expect(loaded.single.animation.name, 'My animation');
      expect(loaded.single.id, startsWith('custom_'));
    });

    testWidgets('editing an existing animation renames in place',
        (tester) async {
      mockTorchChannel();
      final original = seedEntry();
      await pumpEditor(
        tester,
        settings: await makeSettingsWithStore([original]),
        initial: original,
      );

      expect(find.text('Edit animation'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextField, 'Flicker'), 'Flicker renamed');
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final loaded = await CustomAnimationStore().loadAll();
      expect(loaded.single.id, original.id);
      expect(loaded.single.animation.name, 'Flicker renamed');
    });

    testWidgets('delete removes only the confirmed animation',
        (tester) async {
      mockTorchChannel();
      final doomed = seedEntry(name: 'Doomed');
      final kept = seedEntry(
        name: 'Kept',
        id: 'custom_99999999-8888-4777-8666-555555555555',
      );
      await pumpEditor(
        tester,
        settings: await makeSettingsWithStore([doomed, kept]),
        initial: doomed,
      );

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      final loaded = await CustomAnimationStore().loadAll();
      expect(loaded.single.animation.name, 'Kept');
    });

    testWidgets('choosing an easing curve persists with the animation',
        (tester) async {
      mockTorchChannel();
      await pumpEditor(tester, settings: await makeSettings());

      await tester.tap(find.text('Linear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ease In Out').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final loaded = await CustomAnimationStore().loadAll();
      expect(loaded.single.easing, Easing.easeInOut);
    });

    testWidgets('preview drives the torch and stops cleanly', (tester) async {
      mockTorchChannel();
      await pumpEditor(tester, settings: await makeSettings());

      await tester.tap(find.text('Preview'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(recordedCalls, isNotEmpty);

      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(recordedCalls.last, 'turnOff');
    });
  });
}
