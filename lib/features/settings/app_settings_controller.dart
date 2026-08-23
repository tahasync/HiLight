import 'package:flutter/material.dart';

import '../../services/notification_trigger_classifier.dart';
import '../../services/preferences_service.dart';
import '../../services/trigger_settings.dart';

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

  /// Per-trigger configuration (prd-v1.2.md §2/§5). Empty until [load]
  /// completes; every entry defaults to disabled.
  Map<TriggerKind, TriggerConfig> triggerConfig = const {};

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
    triggerConfig = await _prefs.loadTriggerConfig();
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

  TriggerConfig triggerConfigFor(TriggerKind kind) =>
      triggerConfig[kind] ?? defaultTriggerConfig(kind);

  /// Enables or disables one trigger kind (prd-v1.2.md §2). The caller is
  /// responsible for having verified notification access first — the
  /// Settings UI gates this behind the access flow so listener access is
  /// only requested at this exact moment.
  void setTriggerEnabled(TriggerKind kind, bool enabled) {
    final current = triggerConfigFor(kind);
    if (current.enabled == enabled) return;
    triggerConfig = {
      ...triggerConfig,
      kind: current.copyWith(enabled: enabled),
    };
    notifyListeners();
    _prefs.setTriggerEnabled(kind, enabled);
  }

  void setTriggerPresetId(TriggerKind kind, String presetId) {
    final current = triggerConfigFor(kind);
    if (current.presetId == presetId) return;
    triggerConfig = {
      ...triggerConfig,
      kind: current.copyWith(presetId: presetId),
    };
    notifyListeners();
    _prefs.setTriggerPresetId(kind, presetId);
  }

  /// Restores every setting to its default and clears stored values.
  Future<void> reset() async {
    await _prefs.clear();
    await load();
  }
}
