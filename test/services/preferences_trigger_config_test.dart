import 'package:flutter_test/flutter_test.dart';
import 'package:hilight/features/settings/app_settings_controller.dart';
import 'package:hilight/services/notification_trigger_classifier.dart';
import 'package:hilight/services/preferences_service.dart';
import 'package:hilight/services/trigger_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TriggerConfig persistence (prd-v1.2.md §2/§5)', () {
    test('defaults are disabled with a proposed preset per kind', () async {
      SharedPreferences.setMockInitialValues(const {});
      final config = await PreferencesService().loadTriggerConfig();

      expect(config.keys, containsAll(kTriggerKinds));
      for (final kind in kTriggerKinds) {
        expect(
          config[kind]!.enabled,
          isFalse,
          reason: '${kind.name} must default to disabled',
        );
        expect(builtinIds, contains(config[kind]!.presetId),
            reason: '${kind.name} default preset should be a built-in');
      }
    });

    test('round-trips enabled flag and preset id per kind', () async {
      SharedPreferences.setMockInitialValues(const {});
      final prefs = PreferencesService();

      await prefs.setTriggerEnabled(TriggerKind.sms, true);
      await prefs.setTriggerPresetId(TriggerKind.sms, 'quick_flash');
      await prefs.setTriggerEnabled(TriggerKind.alarm, true);

      final config = await prefs.loadTriggerConfig();
      expect(config[TriggerKind.sms]!.enabled, isTrue);
      expect(config[TriggerKind.sms]!.presetId, 'quick_flash');
      expect(config[TriggerKind.alarm]!.enabled, isTrue);
      // Untouched kinds stay at defaults.
      expect(config[TriggerKind.timer]!.enabled, isFalse);
      expect(
        config[TriggerKind.timer]!.presetId,
        defaultTriggerConfig(TriggerKind.timer).presetId,
      );
    });
  });

  group('AppSettingsController trigger API', () {
    test('setters persist and notify listeners', () async {
      SharedPreferences.setMockInitialValues(const {});
      final controller = AppSettingsController(PreferencesService());
      await controller.ready;

      var notified = 0;
      controller.addListener(() => notified++);

      controller.setTriggerEnabled(TriggerKind.incomingCall, true);
      controller.setTriggerPresetId(TriggerKind.incomingCall, 'long_glow');

      expect(notified, 2);
      final current = controller.triggerConfigFor(TriggerKind.incomingCall);
      expect(current.enabled, isTrue);
      expect(current.presetId, 'long_glow');

      final persisted =
          await PreferencesService().loadTriggerConfig();
      expect(persisted[TriggerKind.incomingCall]!.enabled, isTrue);
      expect(persisted[TriggerKind.incomingCall]!.presetId, 'long_glow');
    });

    test('reset restores every trigger to disabled defaults', () async {
      SharedPreferences.setMockInitialValues(const {});
      final controller = AppSettingsController(PreferencesService());
      await controller.ready;
      controller.setTriggerEnabled(TriggerKind.sms, true);

      await controller.reset();

      expect(controller.triggerConfigFor(TriggerKind.sms).enabled, isFalse);
    });
  });
}

const Set<String> builtinIds = {
  'pulse',
  'breathing',
  'double_pulse',
  'soft_glow',
  'heartbeat',
  'quick_flash',
  'triple_pulse',
  'long_glow',
};
