import 'package:flutter/material.dart';

import '../../services/preferences_service.dart';

/// Owns every persisted setting (PRD §19) and notifies listeners on change.
/// Also backs the app-wide theme, replacing the earlier theme-only
/// controller. Persistence is local-only (PRD §24).
class AppSettingsController extends ChangeNotifier {
  AppSettingsController(this._prefs) {
    _ready = load();
  }

  final PreferencesService _prefs;
  late final Future<void> _ready;

  /// Completes once persisted values have been applied.
  Future<void> get ready => _ready;

  ThemeMode themeMode = ThemeMode.system;
  String presetId = 'pulse';
  double brightness = 1.0;
  double speed = 1.0;
  int repeatCount = 1; // 0 means continuous.
  bool hapticsEnabled = true;

  /// Torch update cadence in milliseconds (§19 Advanced: frame/update rate).
  int updateRateMs = 10;
  bool debugLogging = false;

  Future<void> load() async {
    final snapshot = await _prefs.loadAll();
    themeMode = switch (snapshot.themeModeName) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    presetId = snapshot.presetId;
    brightness = snapshot.brightness.clamp(0.0, 1.0);
    speed = snapshot.speed.clamp(0.25, 3.0);
    repeatCount = snapshot.repeatCount < 0 ? 0 : snapshot.repeatCount;
    hapticsEnabled = snapshot.hapticsEnabled;
    updateRateMs = snapshot.updateRateMs;
    debugLogging = snapshot.debugLogging;
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    if (mode == themeMode) return;
    themeMode = mode;
    notifyListeners();
    _prefs.setThemeModeName(mode.name);
  }

  void setPresetId(String id) {
    if (id == presetId) return;
    presetId = id;
    notifyListeners();
    _prefs.setPresetId(id);
  }

  void setBrightness(double value) {
    brightness = value.clamp(0.0, 1.0);
    notifyListeners();
    _prefs.setBrightness(brightness);
  }

  void setSpeed(double value) {
    speed = value.clamp(0.25, 3.0);
    notifyListeners();
    _prefs.setSpeed(speed);
  }

  void setRepeatCount(int count) {
    repeatCount = count < 0 ? 0 : count;
    notifyListeners();
    _prefs.setRepeatCount(repeatCount);
  }

  void setHapticsEnabled(bool enabled) {
    hapticsEnabled = enabled;
    notifyListeners();
    _prefs.setHapticsEnabled(enabled);
  }

  void setUpdateRateMs(int ms) {
    updateRateMs = ms;
    notifyListeners();
    _prefs.setUpdateRateMs(ms);
  }

  void setDebugLogging(bool enabled) {
    debugLogging = enabled;
    notifyListeners();
    _prefs.setDebugLogging(enabled);
  }

  /// Restores every setting to its default and clears stored values.
  Future<void> reset() async {
    await _prefs.clear();
    await load();
  }
}
