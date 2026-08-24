import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

  /// Dedupe for delayed duplicate connect events (a ROM may deliver the
  /// broadcast seconds after the poll already handled the transition).
  static DateTime? _lastConnectedAt;

  /// Polling fallback (per-isolate): some ROMs (Pixel 4 custom Android 16)
  /// never deliver power broadcasts, so while any engine lives we diff a
  /// cheap sticky-battery snapshot every [_pollInterval]. Broadcast events
  /// update the same last-state, so healthy devices never double-fire.
  static const MethodChannel _supportChannel =
      MethodChannel('hilight/trigger_support');
  static const Duration _pollInterval = Duration(seconds: 4);
  static Timer? _pollTimer;
  static bool? _lastCharging;
  static int? _lastLevel;

  void _startPolling() {
    if (_pollTimer != null) return;
    _pollTimer = Timer.periodic(_pollInterval, (_) => _pollTick());
  }

  Future<void> _pollTick() async {
    final snapshot = await _readSnapshot();
    if (snapshot == null) return;
    final charging = snapshot['charging'] == true;
    final level = snapshot['level'] as int? ?? -1;
    final lastCharging = _lastCharging;
    final lastLevel = _lastLevel;
    _lastCharging = charging;
    _lastLevel = level;
    if (lastCharging == null) return; // first tick: baseline only
    if (charging && !lastCharging) {
      await handleEvent({'event': 'connected', 'level': level});
    } else if (!charging && lastCharging) {
      await handleEvent({'event': 'disconnected'});
    } else if (charging && level != lastLevel && level >= 0) {
      await handleEvent({'event': 'level', 'level': level});
    }
  }

  Future<Map<Object?, Object?>?> _readSnapshot() async {
    try {
      return await _supportChannel
          .invokeMethod<Map<Object?, Object?>>('chargingSnapshot');
    } catch (_) {
      return null;
    }
  }

  /// Registers as the coordinator's charging handler; call once per isolate.
  void register() {
    PlaybackCoordinator.instance.registerChargingHandler(handleEvent);
    _startPolling();
  }

  /// Entry point for native charging events. Public for tests.
  Future<void> handleEvent(Map<Object?, Object?> arguments) async {
    final event = arguments['event'];
    if (event is! String) return;
    final level = arguments['level'];
    // Keep the polling fallback's last-state in sync so healthy devices
    // never double-fire a transition the broadcast already delivered.
    switch (event) {
      case 'connected':
        _lastCharging = true;
      case 'disconnected':
        _lastCharging = false;
      case 'level':
        if (level is int) _lastLevel = level;
    }
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
    final now = DateTime.now();
    final lastConnected = _lastConnectedAt;
    if (lastConnected != null &&
        now.difference(lastConnected) < const Duration(seconds: 5)) {
      _debugLog('duplicate connect ignored');
      return;
    }
    _lastConnectedAt = now;
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
    _debugLog('charging $label: capability='
        '${capability == null ? "null" : (capability.torchAvailable ? "ok" : "no-torch")}');
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
