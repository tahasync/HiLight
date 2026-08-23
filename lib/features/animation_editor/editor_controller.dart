import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../core/motion/easing.dart';
import '../../core/motion/hilight_animation.dart';
import '../../core/motion/light_keyframe.dart';
import '../../core/motion/torch_animator.dart';
import '../../core/platform/torch_capability.dart';
import '../../core/platform/torch_exception.dart';
import '../../services/animation_service.dart';
import '../../services/torch_service.dart';
import '../settings/app_settings_controller.dart';
import 'custom_animation_draft.dart';
import 'custom_animation_store.dart';
import 'custom_animation_validation.dart';
import 'stored_custom_animation.dart';

/// State holder for the custom animation editor (prd-v1.1.md §3): edits a
/// [CustomAnimationDraft], previews through the same engine path as
/// built-in presets, and persists through [CustomAnimationStore].
class EditorController extends ChangeNotifier with WidgetsBindingObserver {
  EditorController(
    this._torchService,
    this._settings, {
    StoredCustomAnimation? initial,
  }) : _animationService = AnimationService(_torchService) {
    WidgetsBinding.instance.addObserver(this);
    draft = CustomAnimationDraft(
      id: initial?.id,
      name: initial?.animation.name ?? 'My animation',
      durationMs: initial?.animation.duration.inMilliseconds ?? 800,
      easing: initial?.easing ?? Easing.linear,
      keyframes: initial?.animation.keyframes.toList(),
    );
    _load();
  }

  final TorchService _torchService;
  final AnimationService _animationService;
  final AppSettingsController _settings;

  /// Restart debounce while playing so edits do not spam native calls.
  static const Duration _restartDebounce = Duration(milliseconds: 250);

  late final CustomAnimationDraft draft;

  TorchCapability? capability;
  bool isPlaying = false;
  String? torchError;
  int playSession = 0;
  DateTime? previewStartedAt;

  late TorchAnimator _animator = TorchAnimator(output: _animationService);
  Timer? _restartTimer;

  List<CustomAnimationIssue> get issues => draft.validate();
  bool get isValid => issues.isEmpty;
  bool get isEditingExisting => draft.id != null;
  bool get canPlay => capability?.torchAvailable ?? false;

  int get maxStrengthLevel =>
      (capability?.supportsStrength ?? false)
          ? capability!.maxStrengthLevel
          : 1;

  String get statusText {
    if (torchError != null) return torchError!;
    if (capability == null) return 'Reading device capabilities…';
    if (!canPlay) return 'Torch unavailable';
    if (isPlaying) return 'Previewing ${draft.name}';
    return 'Ready';
  }

  /// A playable [HilightAnimation] reflecting the current draft for the
  /// on-screen visual. The factory sorts internally, so the visual stays
  /// live even while the validator flags an out-of-order edit; only valid
  /// drafts reach save or physical playback.
  HilightAnimation get displayAnimation {
    final keyframes = List<LightKeyframe>.of(draft.keyframes);
    if (keyframes.length < 2) {
      keyframes.clear();
      keyframes.add(LightKeyframe(time: Duration.zero, intensity: 0));
      keyframes.add(LightKeyframe(
        time: Duration(milliseconds: draft.durationMs),
        intensity: 1,
      ));
    }
    try {
      return HilightAnimation(
        id: 'editor_preview',
        name: draft.name,
        duration: Duration(milliseconds: draft.durationMs),
        keyframes: keyframes,
      );
    } on ArgumentError {
      final fallback = [
        LightKeyframe(time: Duration.zero, intensity: 0),
        LightKeyframe(time: const Duration(milliseconds: 100), intensity: 0),
      ];
      return HilightAnimation(
        id: 'editor_preview',
        name: draft.name,
        duration: const Duration(milliseconds: 100),
        keyframes: fallback,
      );
    }
  }

  Future<void> _load() async {
    try {
      capability = await _torchService.getCapabilities();
      torchError = null;
    } on TorchException catch (error) {
      torchError = error.message;
    }
    notifyListeners();
  }

  void setName(String value) {
    draft.name = value;
    notifyListeners();
  }

  void setDurationMs(int milliseconds) {
    draft.durationMs = milliseconds.clamp(
      CustomAnimationLimits.minDurationMs,
      CustomAnimationLimits.maxDurationMs,
    );
    notifyListeners();
    _onEditWhilePlaying();
  }

  void setEasing(Easing easing) {
    draft.easing = easing;
    notifyListeners();
    _onEditWhilePlaying();
  }

  void addKeyframeAtEnd() {
    final last = draft.keyframes.isEmpty ? null : draft.keyframes.last;
    final ms = last == null
        ? 0
        : draft.durationMs > last.time.inMilliseconds
            ? draft.durationMs
            : last.time.inMilliseconds + 100;
    draft.addKeyframe(Duration(milliseconds: ms), 1.0);
    notifyListeners();
    _onEditWhilePlaying();
  }

  void removeKeyframeAt(int index) {
    draft.removeKeyframeAt(index);
    notifyListeners();
    _onEditWhilePlaying();
  }

  /// Nudges a keyframe's time by [deltaMs], clamped at zero. Out-of-order
  /// results are flagged by [issues] — never silently reordered.
  void nudgeKeyframeTime(int index, int deltaMs) {
    final current = draft.keyframes[index].time.inMilliseconds;
    final next = (current + deltaMs).clamp(0, 1 << 30);
    draft.updateKeyframeAt(index, time: Duration(milliseconds: next));
    notifyListeners();
    _onEditWhilePlaying();
  }

  void setKeyframeIntensity(int index, double intensity) {
    draft.updateKeyframeAt(index, intensity: intensity);
    notifyListeners();
    _onEditWhilePlaying();
  }

  void _onEditWhilePlaying() {
    if (isPlaying) _scheduleRestart();
  }

  /// Starts or stops the preview of the current draft through the same
  /// animation engine used everywhere else (prd-v1.1.md §3).
  void togglePreview() {
    if (!canPlay || !isValid) return;
    if (isPlaying) {
      _stopPlayback();
      notifyListeners();
      return;
    }
    torchError = null;
    isPlaying = true;
    playSession++;
    previewStartedAt = DateTime.now();
    notifyListeners();
    _startAnimator();
  }

  void _startAnimator() {
    _animator.dispose();
    _animator = TorchAnimator(
      output: _animationService,
      tickInterval: Duration(milliseconds: _settings.updateRateMs),
    );
    _animator.play(
      animation: displayAnimation,
      maxStrengthLevel: maxStrengthLevel,
      brightness: _settings.brightness,
      speed: _settings.speed,
      repeatCount: _settings.repeatCount,
      easing: draft.easing,
      onComplete: () {
        isPlaying = false;
        previewStartedAt = null;
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
  }

  void _scheduleRestart() {
    _restartTimer?.cancel();
    _restartTimer = Timer(_restartDebounce, () {
      if (!isPlaying) return;
      _animator.cancel();
      playSession++;
      previewStartedAt = DateTime.now();
      _startAnimator();
      notifyListeners();
    });
  }

  void _stopPlayback() {
    _restartTimer?.cancel();
    _animator.cancel();
    isPlaying = false;
    previewStartedAt = null;
    playSession++;
  }

  /// Persists the draft and returns the saved entry. Throws
  /// [CustomAnimationValidationException] when called on an invalid draft.
  Future<StoredCustomAnimation> saveTo(CustomAnimationStore store) async {
    final entry = draft.build();
    await store.save(entry);
    return entry;
  }

  /// Deletes the edited animation from local persistence (no-op for a new,
  /// never-saved draft).
  Future<void> deleteFrom(CustomAnimationStore store) async {
    final id = draft.id;
    if (id == null) return;
    await store.delete(id);
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
