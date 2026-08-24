import 'package:flutter/foundation.dart';

import '../core/motion/easing.dart';
import '../core/motion/preset_definitions.dart';
import '../core/motion/torch_animator.dart';
import '../core/platform/torch_capability.dart';
import '../features/animation_editor/custom_animation_store.dart';
import 'animation_service.dart';
import 'charging_settings.dart';
import 'playback_coordinator.dart';
import 'preferences_service.dart';
import 'torch_service.dart';

/// Plays charging effects (prd-v1.2.md §4, amended spec):
///
///  - **connected**: optionally plays the connect preset once; records the
///    plug-in level so milestones at or below it are consumed silently;
///  - **level**: fires each enabled milestone preset once per session on
///    upward crossing;
///  - **disconnected**: kills any charging-owned playback instantly and
///    unconditionally (torch-safety rule), then optionally plays the
///    disconnect preset once — deliberate, bounded, ends with torch off.
///
/// No periodic animation while charging. All plays skip when the torch is
/// busy; the disconnect kill only ever cancels charging-owned playback, so
/// a manual preview survives an unplug.
class ChargingPlaybackController {
  ChargingPlaybackController({
    PreferencesService? preferences,
    CustomAnimationStore? store,
    TorchAnimationOutput? output,
    Future<TorchCapability?> Function()? capabilities,
  })  : _preferences = preferences ?? PreferencesService(),
        _store = store ?? CustomAnimationStore(),
        _output = output ?? AnimationService(TorchService()),
        _capabilities = capabilities ??
            (() async {
              try {
                return await TorchService().getCapabilities();
              } catch (_) {
                return null;
              }
            });

  final PreferencesService _preferences;
  final CustomAnimationStore _store;
  final TorchAnimationOutput _output;
  final Future<TorchCapability?> Function() _capabilities;

  Object get _token => this;

  TorchAnimator _animator = TorchAnimator(output: _placeholder);
  static final _NeverOutput _placeholder = _NeverOutput();

  bool _sessionActive = false;
  int _connectLevel = 0;
  Set<int> _consumed = <int>{};

  /// Registers as the coordinator's charging handler; call once per isolate.
  void register() {
    PlaybackCoordinator.instance.registerChargingHandler(handleEvent);
  }

  /// Entry point for native charging events. Public for tests.
  Future<void> handleEvent(Map<Object?, Object?> arguments) async {
    final event = arguments['event'];
    if (event is! String) return;
    final level = arguments['level'];
    switch (event) {
      case 'connected':
        await _onConnected(level is int ? level : -1);
      case 'level':
        await _onLevel(level is int ? level : -1);
      case 'disconnected':
        await _onDisconnected();
    }
  }

  Future<void> _onConnected(int level) async {
    final config = await _preferences.loadChargingConfig();
    if (!config.masterEnabled || level < 0) {
      _sessionActive = false;
      return;
    }
    _sessionActive = true;
    _connectLevel = level;
    _consumed = ChargingMilestones.consumedAtConnect(level);
    _debugLog('charging session start at $level%');
    if (config.animateOnConnect) {
      await _playIfIdle(config.connectPresetId, label: 'connect');
    }
  }

  Future<void> _onLevel(int level) async {
    if (!_sessionActive) return;
    final config = await _preferences.loadChargingConfig();
    if (!config.masterEnabled) {
      _sessionActive = false;
      return;
    }
    final milestoneLevel = ChargingMilestones.nextToFire(
      connectLevel: _connectLevel,
      consumed: _consumed,
      currentLevel: level,
    );
    if (milestoneLevel == null) return;
    _consumed = {..._consumed, milestoneLevel};
    final milestone = config.milestoneAt(milestoneLevel);
    if (!milestone.enabled) {
      _debugLog('milestone $milestoneLevel% consumed (disabled)');
      return;
    }
    _debugLog('milestone $milestoneLevel% crossed');
    await _playIfIdle(milestone.presetId, label: 'milestone $milestoneLevel%');
  }

  Future<void> _onDisconnected() async {
    final wasActive = _sessionActive;
    _sessionActive = false;
    _consumed = <int>{};
    _debugLog('charging ended');
    // Safety first: kill charging-owned playback instantly and
    // unconditionally (manual previews are left untouched).
    await PlaybackCoordinator.instance.requestStop(_token);
    if (!wasActive) return;
    final config = await _preferences.loadChargingConfig();
    if (config.masterEnabled && config.animateOnDisconnect) {
      await _playIfIdle(config.disconnectPresetId, label: 'disconnect');
    }
  }

  Future<void> _playIfIdle(String presetId, {required String label}) async {
    if (PlaybackCoordinator.instance.isActive) {
      _debugLog('charging $label skipped: torch busy');
      return;
    }
    final capability = await _capabilities();
    if (capability == null || !capability.torchAvailable) return;

    var animation = builtinPresetById(presetId) ?? kPulsePreset;
    var easing = Easing.linear;
    try {
      for (final custom in await _store.loadAll()) {
        if (custom.id == presetId) {
          animation = custom.animation;
          easing = custom.easing;
        }
      }
    } catch (_) {
      // Custom lookup must never block a built-in from playing.
    }
    final snapshot = await _preferences.loadAll();

    _animator.dispose();
    _animator = TorchAnimator(output: _output);
    _animator.play(
      animation: animation,
      maxStrengthLevel:
          capability.supportsStrength ? capability.maxStrengthLevel : 1,
      brightness: snapshot.brightness,
      speed: snapshot.speed,
      repeatCount: 1,
      easing: easing,
      onComplete: () => PlaybackCoordinator.instance.endOwnership(_token),
      onError: (Object error) =>
          PlaybackCoordinator.instance.endOwnership(_token),
    );
    _debugLog('charging $label -> ${animation.id}');
    PlaybackCoordinator.instance.beginOwnership(_token, () async {
      _animator.cancel();
      PlaybackCoordinator.instance.endOwnership(_token);
    });
  }

  void _debugLog(String message) {
    if (kDebugMode) print('HiLight charging: $message');
  }
}

/// Output that never emits; placeholder while no playback is active.
class _NeverOutput implements TorchAnimationOutput {
  @override
  Future<void> turnOn() async {}

  @override
  Future<void> setStrength(int level) async {}

  @override
  Future<void> turnOff() async {}
}
