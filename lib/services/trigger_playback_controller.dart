import 'package:flutter/foundation.dart';

import '../core/motion/easing.dart';
import '../core/motion/hilight_animation.dart';
import '../core/motion/preset_definitions.dart';
import '../core/motion/torch_animator.dart';
import '../core/platform/torch_capability.dart';
import '../features/animation_editor/custom_animation_store.dart';
import 'animation_service.dart';
import 'app_override_store.dart';
import 'contact_matcher.dart';
import 'contact_override_store.dart';
import 'notification_trigger_classifier.dart';
import 'playback_coordinator.dart';
import 'preferences_service.dart';
import 'torch_service.dart';

/// Plays the preset assigned to a trigger (prd-v1.2.md §2) on behalf of
/// native event sources (the notification listener today; charging in §4).
///
/// Deterministic playback rules, all documented and tested:
///  - a trigger plays its assigned preset exactly once (repeat counts are a
///    manual-playback concern);
///  - when the torch is already busy (manual preview, tile animation, or
///    another trigger), the event is skipped rather than interrupting;
///  - events arriving within [_debounce] of a started trigger are collapsed
///    so grouped notifications cannot machine-gun the torch.
class TriggerPlaybackController {
  TriggerPlaybackController({
    PreferencesService? preferences,
    CustomAnimationStore? store,
    TorchAnimationOutput? output,
    Future<TorchCapability?> Function()? capabilities,
    Future<List<ContactOverride>> Function()? contactOverrides,
    Future<List<AppOverride>> Function()? appOverrides,
  })  : _preferences = preferences ?? PreferencesService(),
        _store = store ?? CustomAnimationStore(),
        _output = output ?? AnimationService(TorchService()),
        _contactOverrides = contactOverrides ??
            (() => ContactOverrideStore().loadAll()),
        _appOverrides =
            appOverrides ?? (() => AppOverrideStore().loadAll()),
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
  final Future<List<ContactOverride>> Function() _contactOverrides;
  final Future<List<AppOverride>> Function() _appOverrides;
  final Future<TorchCapability?> Function() _capabilities;

  /// Minimum gap between two started triggers (grouped notifications,
  /// message storms).
  static const Duration debounce = Duration(milliseconds: 1200);

  /// How long a ring-loop may keep replaying the call animation. Bounded so
  /// the wake-lock window (60 s) can never expire mid-loop with the torch
  /// lit; a ring that outlasts this simply stops flashing.
  static const Duration ringLoopCap = Duration(seconds: 55);

  DateTime? _lastStartedAt;

  /// Active ring session: the loop replays the call animation until the
  /// ring notification is removed (answered/declined) or the cap hits.
  bool _ringLoopActive = false;
  DateTime? _ringLoopStartedAt;
  HilightAnimation? _ringAnimation;
  Easing _ringEasing = Easing.linear;
  int? _ringMaxLevel;
  double? _ringBrightness;
  double? _ringSpeed;

  Object get _token => this;

  TorchAnimator _animator = TorchAnimator(output: _placeholder);
  static final _NeverOutput _placeholder = _NeverOutput();

  /// Registers itself as the coordinator's trigger handler; call once per
  /// isolate. Both app entrypoints register one instance so events work
  /// with the app open and from the headless engine.
  void register() {
    PlaybackCoordinator.instance.registerTriggerHandler(handleEvent);
  }

  /// Entry point for every native trigger event. Public for tests.
  ///
  /// Ordering matters: every await happens up front; the busy/debounce gates
  /// and the actual start run back-to-back with no suspension in between, so
  /// two near-simultaneous events can never both start (a race that was
  /// observed live and caused mid-animation restarts).
  Future<void> handleEvent(Map<Object?, Object?> arguments) async {
    final event = _parseEvent(arguments);
    if (event == null) return;

    // Ring ended (answered / declined / missed): stop the loop at once and
    // guarantee the torch ends off — this overrides everything else.
    if (event.removed) {
      if (_ringLoopActive) {
        _debugLog('ring ended -> stopping loop');
        _stopRingLoop();
        PlaybackCoordinator.instance.requestStop(_token);
      }
      return;
    }

    final snapshot = await _preferences.loadAll();
    final config = await _preferences.loadTriggerConfig();
    final kind = NotificationTriggers.resolve(
      event,
      (triggerKind) => config[triggerKind]?.enabled ?? false,
    );
    // Disabled or unmatched: nothing to do (no access side effects).
    if (kind == null) return;

    // Per-app gate (prd-v1.2.md §3): the user can disable flashing for
    // every single app; unlisted apps follow the trigger.
    final appOverrides = await _appOverrides();
    final appResolution = AppOverrideResolver.resolve(
      overrides: appOverrides,
      packageName: event.packageName,
    );
    if (!appResolution.allowed) {
      _debugLog('app ${event.packageName} skipped: per-app off');
      return;
    }

    final capability = await _capabilities();
    if (capability == null || !capability.torchAvailable) return;

    final presetId = await _resolvePresetId(kind, event, appOverrides);
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
      // Custom lookup must never block the built-in default from playing.
    }

    // --- No awaits beyond this point: the gates below are atomic. ---
    // Busy torch: never stomp an existing playback.
    if (PlaybackCoordinator.instance.isActive) {
      _debugLog('trigger ${kind.name} skipped: torch busy');
      return;
    }
    // Debounce grouped/storming notifications.
    final now = DateTime.now();
    final last = _lastStartedAt;
    if (last != null && now.difference(last) < debounce) {
      _debugLog('trigger ${kind.name} skipped: debounced');
      return;
    }

    _lastStartedAt = now;
    _animator.dispose();
    _animator = TorchAnimator(output: _output);
    final isCallRing = kind == TriggerKind.incomingCall;
    if (isCallRing) {
      // Ring session: the completion handler replays until the ring ends.
      _ringLoopActive = true;
      _ringLoopStartedAt = now;
      _ringAnimation = animation;
      _ringEasing = easing;
      _ringMaxLevel =
          capability.supportsStrength ? capability.maxStrengthLevel : 1;
      _ringBrightness = snapshot.brightness;
      _ringSpeed = snapshot.speed;
    }
    _animator.play(
      animation: animation,
      maxStrengthLevel:
          capability.supportsStrength ? capability.maxStrengthLevel : 1,
      brightness: snapshot.brightness,
      speed: snapshot.speed,
      repeatCount: 1,
      easing: easing,
      onComplete: () {
        if (isCallRing && _continueRingLoop()) {
          _debugLog('ring loop -> replay ${animation.id}');
          _replayRing();
          return;
        }
        _ringLoopActive = false;
        PlaybackCoordinator.instance.endOwnership(_token);
      },
      onError: (Object error) {
        _ringLoopActive = false;
        PlaybackCoordinator.instance.endOwnership(_token);
      },
    );
    _debugLog('trigger ${kind.name} -> ${animation.id}');
    PlaybackCoordinator.instance.beginOwnership(_token, () async {
      _ringLoopActive = false;
      _animator.cancel();
      PlaybackCoordinator.instance.endOwnership(_token);
    });
  }

  /// Whether the ring loop should keep going (removal signal or cap not hit).
  bool _continueRingLoop() {
    if (!_ringLoopActive) return false;
    final startedAt = _ringLoopStartedAt;
    if (startedAt == null) return false;
    return DateTime.now().difference(startedAt) < ringLoopCap;
  }

  /// Replays the ring animation back-to-back. No awaits: the loop runs
  /// inside the animator's completion callback on the existing ownership.
  void _replayRing() {
    final animation = _ringAnimation;
    if (animation == null) {
      _ringLoopActive = false;
      PlaybackCoordinator.instance.endOwnership(_token);
      return;
    }
    _animator.dispose();
    _animator = TorchAnimator(output: _output);
    _animator.play(
      animation: animation,
      maxStrengthLevel: _ringMaxLevel ?? 1,
      brightness: _ringBrightness ?? 1,
      speed: _ringSpeed ?? 1,
      repeatCount: 1,
      easing: _ringEasing,
      onComplete: () {
        if (_continueRingLoop()) {
          _replayRing();
          return;
        }
        _ringLoopActive = false;
        PlaybackCoordinator.instance.endOwnership(_token);
      },
      onError: (Object error) {
        _ringLoopActive = false;
        PlaybackCoordinator.instance.endOwnership(_token);
      },
    );
  }

  void _stopRingLoop() {
    _ringLoopActive = false;
    _ringAnimation = null;
    _ringLoopStartedAt = null;
  }

  /// Precedence (prd-v1.2.md §3): per-contact override first (calls only),
  /// then the per-app preset, then the generic per-trigger-type preset.
  Future<String> _resolvePresetId(
    TriggerKind kind,
    NotificationEvent event,
    List<AppOverride> appOverrides,
  ) async {
    final config = await _preferences.loadTriggerConfig();
    if (kind == TriggerKind.incomingCall && event.callUri != null) {
      try {
        final overrides = await _contactOverrides();
        final match = ContactMatcher.match(
          overrides: overrides,
          callUri: event.callUri,
        );
        if (match != null) {
          // Name and preset only — the caller number is never logged (§7).
          _debugLog('contact override ${match.displayName} '
              '-> ${match.presetId}');
          return match.presetId;
        }
      } catch (_) {
        // Override lookup must never break the generic path.
      }
      // Diagnostics for per-contact matching; the number is never logged.
      _debugLog('call from ${event.packageName} '
          '(personExtra=${event.hasCallPerson}, uri=${event.callUri != null})'
          ' -> no contact match');
    }
    // 2. Per-app preset (any kind — the switch belongs to the app).
    for (final override in appOverrides) {
      if (override.packageName == event.packageName &&
          override.flashEnabled &&
          override.presetId != null) {
        _debugLog('app preset ${override.appName} '
            '-> ${override.presetId}');
        return override.presetId!;
      }
    }
    // 3. Generic per-trigger-type preset.
    return config[kind]?.presetId ?? 'pulse';
  }

  NotificationEvent? _parseEvent(Map<Object?, Object?> arguments) {
    final packageName = arguments['packageName'];
    if (packageName is! String || packageName.isEmpty) return null;
    final category = arguments['category'];
    final isOngoing = arguments['isOngoing'];
    final callUri = arguments['callUri'];
    final hasCallPerson = arguments['hasCallPerson'];
    final removed = arguments['removed'];
    return NotificationEvent(
      category: category is String ? category : null,
      packageName: packageName,
      isOngoing: isOngoing == true,
      callUri: callUri is String ? callUri : null,
      hasCallPerson: hasCallPerson == true,
      removed: removed == true,
    );
  }

  void _debugLog(String message) {
    if (kDebugMode) print('HiLight trigger: $message');
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
