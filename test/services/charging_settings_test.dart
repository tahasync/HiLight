import 'package:flutter_test/flutter_test.dart';
import 'package:hilight/services/charging_settings.dart';
import 'package:hilight/services/preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChargingMilestones (prd-v1.2.md §4, amended spec)', () {
    test('plug-in above a threshold consumes it silently', () {
      final consumed = ChargingMilestones.consumedAtConnect(30);
      expect(consumed, containsAll(<int>[20]));
      expect(consumed, isNot(contains(35)));
    });

    test('plug-in exactly at a threshold consumes that threshold', () {
      expect(ChargingMilestones.consumedAtConnect(50), contains(50));
    });

    test('nextToFire fires upward crossings above the plug-in level', () {
      // Plugged in at 30%: 20 consumed; 35 fires at 36%.
      final consumed = ChargingMilestones.consumedAtConnect(30);
      expect(
        ChargingMilestones.nextToFire(
          connectLevel: 30,
          consumed: consumed,
          currentLevel: 36,
        ),
        35,
      );
      // Still at 34%: nothing fires.
      expect(
        ChargingMilestones.nextToFire(
          connectLevel: 30,
          consumed: consumed,
          currentLevel: 34,
        ),
        isNull,
      );
    });

    test('each threshold fires exactly once per session', () {
      var consumed = ChargingMilestones.consumedAtConnect(10);
      final fired = <int>[];
      // Simulate the level rising through the whole charge.
      for (final level in const [15, 21, 30, 36, 51, 65, 71, 90, 100]) {
        final next = ChargingMilestones.nextToFire(
          connectLevel: 10,
          consumed: consumed,
          currentLevel: level,
        );
        if (next != null) {
          fired.add(next);
          consumed = {...consumed, next};
        }
      }
      expect(fired, const <int>[20, 35, 50, 70, 100]);
    });

    test('a full session from 0 fires all five milestones in order', () {
      var consumed = ChargingMilestones.consumedAtConnect(0);
      final fired = <int>[];
      for (final level in kChargingMilestoneLevels) {
        final next = ChargingMilestones.nextToFire(
          connectLevel: 0,
          consumed: consumed,
          currentLevel: level,
        );
        if (next != null) {
          fired.add(next);
          consumed = {...consumed, next};
        }
      }
      expect(fired, kChargingMilestoneLevels);
    });
  });

  group('ChargingConfig persistence (prd.md §24)', () {
    test('defaults: everything disabled, presets proposed', () async {
      SharedPreferences.setMockInitialValues(const {});
      final config = await PreferencesService().loadChargingConfig();
      expect(config.masterEnabled, isFalse);
      expect(config.animateOnConnect, isFalse);
      expect(config.animateOnDisconnect, isFalse);
      for (final level in kChargingMilestoneLevels) {
        expect(config.milestoneAt(level).enabled, isFalse);
      }
    });

    test('round-trips every knob', () async {
      SharedPreferences.setMockInitialValues(const {});
      final prefs = PreferencesService();
      await prefs.setChargingMaster(true);
      await prefs.setChargingConnectEnabled(true);
      await prefs.setChargingConnectPreset('long_glow');
      await prefs.setChargingDisconnectEnabled(true);
      await prefs.setChargingDisconnectPreset('quick_flash');
      await prefs.setMilestoneEnabled(50, true);
      await prefs.setMilestonePreset(50, 'heartbeat');

      final config = await prefs.loadChargingConfig();
      expect(config.masterEnabled, isTrue);
      expect(config.animateOnConnect, isTrue);
      expect(config.connectPresetId, 'long_glow');
      expect(config.animateOnDisconnect, isTrue);
      expect(config.disconnectPresetId, 'quick_flash');
      expect(config.milestoneAt(50).enabled, isTrue);
      expect(config.milestoneAt(50).presetId, 'heartbeat');
      // Untouched milestones stay default.
      expect(config.milestoneAt(20).enabled, isFalse);
    });
  });
}
