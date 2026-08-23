import 'package:shared_preferences/shared_preferences.dart';

import 'notification_trigger_classifier.dart';
import 'trigger_settings.dart';

/// Snapshot of every persisted setting (PRD §19), with defaults applied.
class PreferencesSnapshot {
  const PreferencesSnapshot({
    required this.themeModeName,
    required this.presetId,
    required this.brightness,
    required this.speed,
    required this.repeatCount,
    required this.hapticsEnabled,
    required this.updateRateMs,
    required this.debugLogging,
  });

  final String themeModeName;
  final String presetId;
  final double brightness;
  final double speed;
  final int repeatCount;
  final bool hapticsEnabled;
  final int updateRateMs;
  final bool debugLogging;
}

/// Thin typed wrapper over local key-value storage. No account, no cloud —
/// plain on-device persistence only (PRD §24).
class PreferencesService {
  static const _keyThemeMode = 'themeMode';
  static const _keyPresetId = 'presetId';
  static const _keyBrightness = 'brightness';
  static const _keySpeed = 'speed';
  static const _keyRepeatCount = 'repeatCount';
  static const _keyHaptics = 'hapticsEnabled';
  static const _keyUpdateRateMs = 'updateRateMs';
  static const _keyDebugLogging = 'debugLogging';

  Future<PreferencesSnapshot> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    return PreferencesSnapshot(
      themeModeName: prefs.getString(_keyThemeMode) ?? 'system',
      presetId: prefs.getString(_keyPresetId) ?? 'pulse',
      brightness: prefs.getDouble(_keyBrightness) ?? 1.0,
      speed: prefs.getDouble(_keySpeed) ?? 1.0,
      repeatCount: prefs.getInt(_keyRepeatCount) ?? 1,
      hapticsEnabled: prefs.getBool(_keyHaptics) ?? true,
      updateRateMs: prefs.getInt(_keyUpdateRateMs) ?? 10,
      debugLogging: prefs.getBool(_keyDebugLogging) ?? false,
    );
  }

  Future<void> setThemeModeName(String value) async =>
      (await SharedPreferences.getInstance()).setString(_keyThemeMode, value);

  Future<void> setPresetId(String value) async =>
      (await SharedPreferences.getInstance()).setString(_keyPresetId, value);

  Future<void> setBrightness(double value) async =>
      (await SharedPreferences.getInstance()).setDouble(_keyBrightness, value);

  Future<void> setSpeed(double value) async =>
      (await SharedPreferences.getInstance()).setDouble(_keySpeed, value);

  Future<void> setRepeatCount(int value) async =>
      (await SharedPreferences.getInstance()).setInt(_keyRepeatCount, value);

  Future<void> setHapticsEnabled(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_keyHaptics, value);

  Future<void> setUpdateRateMs(int value) async =>
      (await SharedPreferences.getInstance()).setInt(_keyUpdateRateMs, value);

  Future<void> setDebugLogging(bool value) async =>
      (await SharedPreferences.getInstance()).setBool(_keyDebugLogging, value);

  /// Loads per-trigger configuration (prd-v1.2.md §2), defaults applied for
  /// anything not persisted yet. Every trigger starts disabled.
  Future<Map<TriggerKind, TriggerConfig>> loadTriggerConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final kind in kTriggerKinds)
        kind: TriggerConfig(
          enabled: prefs.getBool(_triggerEnabledKey(kind)) ??
              defaultTriggerConfig(kind).enabled,
          presetId: prefs.getString(_triggerPresetKey(kind)) ??
              defaultTriggerConfig(kind).presetId,
        ),
    };
  }

  Future<void> setTriggerEnabled(TriggerKind kind, bool enabled) async =>
      (await SharedPreferences.getInstance())
          .setBool(_triggerEnabledKey(kind), enabled);

  Future<void> setTriggerPresetId(TriggerKind kind, String presetId) async =>
      (await SharedPreferences.getInstance())
          .setString(_triggerPresetKey(kind), presetId);

  static String _triggerEnabledKey(TriggerKind kind) => 'trigger.${kind.name}.enabled';

  static String _triggerPresetKey(TriggerKind kind) => 'trigger.${kind.name}.presetId';

  Future<void> clear() async => (await SharedPreferences.getInstance()).clear();
}
