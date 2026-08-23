import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/motion/easing.dart';
import '../../core/motion/hilight_animation.dart';
import '../../core/motion/preset_definitions.dart';
import '../../core/motion/torch_animator.dart';
import '../../core/platform/device_info.dart';
import '../../core/platform/torch_capability.dart';
import '../../core/platform/torch_exception.dart';
import '../../services/animation_service.dart';
import '../../services/playback_coordinator.dart';
import '../../services/torch_service.dart';
import '../animation_editor/custom_animation_store.dart';
import '../animation_editor/stored_custom_animation.dart';
import '../settings/app_settings_controller.dart';

/// State of the home screen (PRD §15): capability, device identity, the
/// selected preset, playback controls, and the preview lifecycle.
///
/// Control values seed from the persisted settings and every change is
/// written back through [AppSettingsController], so the last configuration
/// becomes the next launch's defaults (§19).
///
/// Safety rules (§17/§18): any error or lifecycle shutdown turns the
/// physical torch off immediately.
class HomeController extends ChangeNotifier with WidgetsBindingObserver {
  HomeController(this._torchService, this._settings)
      : _animationService = AnimationService(_torchService) {
    WidgetsBinding.instance.addObserver(this);
    PlaybackCoordinator.instance.attach();
    selectedPreset = _resolvePreset(_settings.presetId);
    brightness = _settings.brightness;
    speed = _settings.speed;
    repeatCount = _settings.repeatCount;
    _load();
  }

  final TorchService _torchService;
  final AnimationService _animationService;
  final AppSettingsController _settings;
  final CustomAnimationStore _customStore = CustomAnimationStore();

  /// Restart debounce while playing so slider drags do not spam native calls.
  static const Duration _restartDebounce = Duration(milliseconds: 250);

  TorchCapability? capability;
  DeviceInfo? deviceInfo;

  /// User-created animations, loaded from local persistence (prd-v1.1.md §3).
  List<StoredCustomAnimation> customAnimations = const [];

  late HilightAnimation selectedPreset;
  late double brightness;
  late double speed;
  late int repeatCount; // 0 means continuous.

  bool isPlaying = false;
  String? torchError;

  /// Increments on every preview start/restart so the visual can re-sync.
  int playSession = 0;

  /// Shared clock origin: the instant both the physical animation engine and
  /// the on-screen visual treat as t=0 (PRD §27). Set together with
  /// [playSession] on every start and debounced restart.
  DateTime? previewStartedAt;

  /// Marks a fresh shared origin for the physical engine and the visual.
  void _markStart() {
    previewStartedAt = DateTime.now();
    if (_settings.debugLogging) {
      debugPrint('HiLight: preview#$playSession start');
    }
  }

  late TorchAnimator _animator =
      TorchAnimator(output: _animationService);
  Timer? _restartTimer;

  bool get canPlay => capability?.torchAvailable ?? false;
  int get maxStrengthLevel =>
      (capability?.supportsStrength ?? false) ? capability!.maxStrengthLevel : 1;

  String get statusText {
    if (torchError != null) return torchError!;
    if (capability == null) return 'Reading device capabilities…';
    if (!capability!.hasFlash) return 'No rear flash detected';
    if (isPlaying) return 'Playing ${selectedPreset.name}';
    if (!capability!.supportsStrength) return 'Variable brightness unavailable';
    return 'Ready';
  }

  Future<void> _load() async {
    try {
      final results =
          await Future.wait<Object?>([_torchService.getCapabilities(), _torchService.getDeviceInfo()]);
      capability = results[0] as TorchCapability;
      deviceInfo = results[1] as DeviceInfo;
      torchError = null;
    } on TorchException catch (error) {
      torchError = error.message;
    }
    try {
      customAnimations = await _customStore.loadAll();
      // A saved custom preset may only be resolvable now that the store has
      // been read (e.g. after selecting it in a previous session).
      selectedPreset = _resolvePreset(_settings.presetId);
    } catch (_) {
      // Custom animations are additive; never block capability reporting.
    }
    notifyListeners();
  }

  HilightAnimation _resolvePreset(String id) =>
      builtinPresetById(id) ?? _customById(id)?.animation ?? kPulsePreset;

  StoredCustomAnimation? _customById(String id) {
    for (final custom in customAnimations) {
      if (custom.id == id) return custom;
    }
    return null;
  }

  /// Every preset selectable on this screen: built-ins first, then
  /// user-created ones.
  List<HilightAnimation> get selectablePresets => [
        ...kBuiltinPresets,
        for (final custom in customAnimations) custom.animation,
      ];

  /// The easing a custom animation carries; built-ins play linearly.
  Easing get selectedEasing =>
      _customById(selectedPreset.id)?.easing ?? Easing.linear;

  /// Persists [entry] (new or renamed) and makes it the current selection.
  Future<void> upsertCustomAnimation(StoredCustomAnimation entry) async {
    await _customStore.save(entry);
    final index = customAnimations.indexWhere((c) => c.id == entry.id);
    if (index >= 0) {
      customAnimations = [...customAnimations]..[index] = entry;
    } else {
      customAnimations = [...customAnimations, entry];
    }
    if (selectedPreset.id != entry.id) {
      selectPreset(entry.animation);
    } else {
      selectedPreset = entry.animation;
      notifyListeners();
    }
  }

  /// Re-reads user-created animations from persistence and falls back to
  /// Pulse when the current selection no longer exists.
  Future<void> reloadCustomAnimations() async {
    try {
      customAnimations = await _customStore.loadAll();
    } catch (_) {
      return;
    }
    if (builtinPresetById(selectedPreset.id) == null &&
        _customById(selectedPreset.id) == null) {
      selectedPreset = kPulsePreset;
      _settings.setPresetId(kPulsePreset.id);
    }
    notifyListeners();
  }

  void selectPreset(HilightAnimation preset) {
    if (preset.id == selectedPreset.id) return;
    selectedPreset = preset;
    _hapticFeedback();
    _settings.setPresetId(preset.id);
    notifyListeners();
    if (isPlaying) _scheduleRestart();
  }

  void setBrightness(double value) {
    brightness = value.clamp(0.0, 1.0);
    notifyListeners();
    _settings.setBrightness(brightness);
    if (isPlaying) _scheduleRestart();
  }

  /// Haptic confirmation after a slider gesture finishes (not per tick).
  void commitControlAdjustment() => _hapticFeedback();

  void setSpeed(double value) {
    speed = value.clamp(0.25, 3.0);
    notifyListeners();
    _settings.setSpeed(speed);
    if (isPlaying) _scheduleRestart();
  }

  void setRepeatCount(int count) {
    repeatCount = count < 0 ? 0 : count;
    _hapticFeedback();
    _settings.setRepeatCount(repeatCount);
    notifyListeners();
    if (isPlaying) _scheduleRestart();
  }

  void _hapticFeedback() {
    if (!_settings.hapticsEnabled) return;
    HapticFeedback.selectionClick();
  }

  /// Starts or stops the preview: the physical torch plays through the
  /// animation engine while the visual mirrors the same definition.
  void togglePreview() {
    if (!canPlay) return;
    if (isPlaying) {
      _stopPlayback();
      notifyListeners();
      return;
    }
    torchError = null;
    isPlaying = true;
    playSession++;
    _markStart();
    _hapticFeedback();
    notifyListeners();
    _startAnimator();
  }

  void _startAnimator() {
    _animator.dispose();
    _animator = TorchAnimator(
      output: _animationService,
      tickInterval: Duration(milliseconds: _settings.updateRateMs),
      logger: (message) {
        if (_settings.debugLogging) debugPrint('HiLight: $message');
      },
    );
    _animator.play(
      animation: selectedPreset,
      maxStrengthLevel: maxStrengthLevel,
      brightness: brightness,
      speed: speed,
      repeatCount: repeatCount,
      easing: selectedEasing,
      onComplete: () {
        isPlaying = false;
        previewStartedAt = null;
        PlaybackCoordinator.instance.endOwnership(this);
        _surfaceLastError();
        notifyListeners();
      },
      onError: (Object error) {
        if (error is TorchException) {
          torchError = error.message;
          _stopPlayback();
          notifyListeners();
        }
      },
    );
    PlaybackCoordinator.instance.beginOwnership(this, () async {
      _stopPlayback();
      notifyListeners();
    });
  }

  void _scheduleRestart() {
    _restartTimer?.cancel();
    _restartTimer = Timer(_restartDebounce, () {
      if (!isPlaying) return;
      _animator.cancel();
      playSession++;
      _markStart();
      _startAnimator();
      notifyListeners();
    });
  }

  void _stopPlayback() {
    PlaybackCoordinator.instance.endOwnership(this);
    _restartTimer?.cancel();
    _animator.cancel();
    isPlaying = false;
    previewStartedAt = null;
    playSession++;
  }

  void _surfaceLastError() {
    final error = _animator.lastError;
    if (error is TorchException && torchError == null) {
      torchError = error.message;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    const shuttingDownStates = [
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ];
    if (shuttingDownStates.contains(state) && isPlaying) {
      _stopPlayback();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _restartTimer?.cancel();
    _animator.dispose();
    super.dispose();
  }
}
