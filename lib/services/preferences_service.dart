import 'package:shared_preferences/shared_preferences.dart';

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

  Future<void> clear() async => (await SharedPreferences.getInstance()).clear();
}
