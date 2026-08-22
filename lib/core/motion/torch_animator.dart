import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:meta/meta.dart';

import 'easing.dart';
import 'hilight_animation.dart';
import 'strength_mapping.dart';

/// Abstraction over the physical torch used by [TorchAnimator]. Implemented
/// by a thin adapter around TorchService; tests substitute fakes.
abstract class TorchAnimationOutput {
  /// Turns the torch on at its default level (ON/OFF-only fallback).
  Future<void> turnOn();

  /// Lights the torch at the given concrete strength level (1..maxLevel).
  /// Per the Android API this also turns the torch on when it was off.
  Future<void> setStrength(int level);

  Future<void> turnOff();
}

/// Drives a [HilightAnimation] against the physical torch.
///
/// Engine rules (PRD §11):
///  - intensities are normalized and scaled by the selected brightness;
///  - normalized intensity maps onto the device's concrete strength levels;
///  - consecutive identical levels are never sent twice (no unnecessary
///    native calls, PRD §26);
///  - every keyframe time is sampled exactly, so peaks and zero plateaus in
///    the definition always reach the hardware;
///  - near-zero intensity moments turn the torch fully off;
///  - completion always turns the torch off;
///  - starting a new animation cancels any active one first.
class TorchAnimator {
  TorchAnimator({
    required this.output,
    this.tickInterval = const Duration(milliseconds: 10),
    this.offThreshold = 0.002,
    this.logger,
  });

  final TorchAnimationOutput output;

  /// Optional sink for timing diagnostics; kept out of core so this layer
  /// stays dependency-free. The app wires it to debug-gated printing.
  void Function(String message)? logger;

  void _log(String message) => logger?.call(message);

  /// Maximum gap between timeline samples. Native calls happen only when the
  /// mapped level actually changes, so even fast ramps stay within a modest
  /// channel-call rate (PRD §26): the tick refines resolution, the level
  /// dedupe bounds traffic.
  final Duration tickInterval;

  /// Intensities at or below this value are treated as fully-off moments.
  final double offThreshold;

  /// Carrier slot for the ON/OFF-only fallback (PRD §9): intermediate
  /// brightness is simulated by toggling the torch with a duty cycle equal
  /// to the perceptual (gamma-corrected) intensity. Starts at 30 ms ≈ 33 Hz
  /// and widens adaptively (see [_maxPwmSlotMilliseconds]) when the device's
  /// native round-trip is slow, keeping worst-case native traffic well
  /// under hundreds of calls per second (PRD §26).
  static const int _pwmSlotMilliseconds = 30;
  static const int _maxPwmSlotMilliseconds = 60;

  /// Perceptual gamma mapping physical duty to perceived brightness; LEDs
  /// at 50% duty look far brighter than "half brightness" to the eye.
  static const double _perceptualGamma = 2.2;

  /// Rolling-window cap for fallback ON emissions (burst safety); OFF
  /// transitions are never throttled so the torch can always reach dark.
  static const int _pwmOnBurstLimit = 30;
  static const int _pwmBurstWindowMs = 600;

  bool _pwmOn = false;
  int _pwmSlotMs = _pwmSlotMilliseconds;
  final List<int> _pwmOnTimestamps = <int>[];
  double _nativeRoundTripEmaMs = 0;

  Timer? _timer;
  Stopwatch? _clock;
  HilightAnimation? _animation;
  Easing _easing = Easing.linear;
  int _maxLevel = 1;
  double _brightness = 1;
  bool _continuous = false;
  Duration _cycleDuration = Duration.zero;
  Duration? _totalDuration;
  bool _lit = false;
  int? _lastSentLevel;
  bool _active = false;
  void Function()? _onComplete;
  void Function(Object error)? _onError;

  /// First error raised by the output while animating, if any.
  Object? lastError;

  bool get isPlaying => _timer != null;

  /// Starts [animation], cancelling any previously running one (§11.8).
  ///
  /// [brightness] scales the keyframe intensities (0.0–1.0); [speed] divides
  /// durations (> 0, where 2.0 plays twice as fast); [repeatCount] of 0 or
  /// less means continuous until cancelled.
  void play({
    required HilightAnimation animation,
    required int maxStrengthLevel,
    double brightness = 1,
    double speed = 1,
    int repeatCount = 1,
    Easing easing = Easing.linear,
    void Function()? onComplete,
    void Function(Object error)? onError,
  }) {
    _stopTicking();
    if (_lit) {
      _lit = false;
      _pwmOn = false;
      _lastSentLevel = null;
      _fireTurnOff();
    }
    _pwmSlotMs = _pwmSlotMilliseconds;
    _pwmOnTimestamps.clear();
    _animation = animation;
    _easing = easing;
    _maxLevel = maxStrengthLevel < 1 ? 1 : maxStrengthLevel;
    _brightness = brightness.clamp(0.0, 1.0);
    final effectiveSpeed = speed <= 0 ? 1.0 : speed;
    _continuous = repeatCount <= 0;
    _cycleDuration = Duration(
      microseconds:
          (animation.duration.inMicroseconds / effectiveSpeed).round(),
    );
    _totalDuration = _continuous
        ? null
        : Duration(microseconds: _cycleDuration.inMicroseconds * repeatCount);
    _onComplete = onComplete;
    _onError = onError;

    _clock = clock.stopwatch()..start();
    _active = true;
    _applyCurrentState();
    if (_active) _scheduleNextEvent();
  }

  /// Stops the animation immediately and turns the torch off (§17/§36).
  void cancel() {
    final wasActive = _timer != null;
    _stopTicking();
    if (!wasActive && !_lit) return;
    _lit = false;
    _lastSentLevel = null;
    _fireTurnOff();
  }

  void dispose() => cancel();

  void _stopTicking() {
    _active = false;
    _timer?.cancel();
    _timer = null;
    _clock?.stop();
  }

  Duration get _positionInCycle {
    var elapsed = _clock!.elapsed;
    // Use >= so an elapsed time landing exactly on a cycle multiple wraps to
    // zero instead of stalling at the full cycle length.
    if (elapsed >= _cycleDuration && _cycleDuration > Duration.zero) {
      elapsed = Duration(
        microseconds: elapsed.inMicroseconds % _cycleDuration.inMicroseconds,
      );
    }
    return elapsed;
  }

  void _applyCurrentState() {
    final total = _totalDuration;
    if (total != null && _clock!.elapsed >= total) {
      _complete();
      return;
    }
    final sampled =
        _animation!.sampleAt(_positionInCycle, easing: _easing);
    final intensity = (sampled * _brightness).clamp(0.0, 1.0);
    _applyIntensity(intensity);
  }

  /// Schedules the next sample at the nearer of the next fixed tick or the
  /// next keyframe time, guaranteeing keyframes are hit exactly.
  void _scheduleNextEvent() {
    if (!_active) return;
    final position = _positionInCycle;
    var delay = tickInterval;
    Duration? untilKeyframe;
    for (final keyframe in _animation!.keyframes) {
      if (keyframe.time > position) {
        untilKeyframe = keyframe.time - position;
        break;
      }
    }
    untilKeyframe ??=
        (_cycleDuration - position) + _animation!.keyframes.first.time;
    if (untilKeyframe < delay) delay = untilKeyframe;
    _timer = Timer(delay, () {
      _applyCurrentState();
      if (_active) _scheduleNextEvent();
    });
  }

  void _applyIntensity(double intensity) {
    if (intensity <= offThreshold) {
      // Fully-off moment (keyframe valleys and completion): true hardware
      // off regardless of device class.
      if (_lit) {
        _lit = false;
        _pwmOn = false;
        _lastSentLevel = null;
        _fireTurnOff();
      }
      return;
    }
    // ON/OFF-only fallback (PRD §9): simulate intermediate brightness with
    // duty-cycle modulation instead of a solid full-power blob.
    if (_maxLevel <= 1) {
      _applyFallbackPwm(intensity);
      return;
    }
    final level = mapIntensityToLevel(intensity, _maxLevel);
    if (_lit && _lastSentLevel == level) return;
    _lastSentLevel = level;
    _lit = true;
    output.setStrength(level).then(
      (_) {},
      onError: (Object error) {
        lastError = error;
        _onError?.call(error);
      },
    );
  }

  /// Emits on/off transitions so the fraction of each carrier slot spent lit
  /// equals the perceptual intensity. State changes only; the carrier widens
  /// automatically when native round-trips are slow, and ON bursts are
  /// rate-capped while OFF transitions always pass (§17/§36).
  void _applyFallbackPwm(double intensity) {
    final duty =
        math.pow(intensity.clamp(0.0, 1.0), _perceptualGamma).toDouble();
    // Widen the carrier when the HAL is slow: a slot shorter than roughly
    // two round-trips degrades into mush and wastes battery.
    if (_nativeRoundTripEmaMs > 10 && _pwmSlotMs < _maxPwmSlotMilliseconds) {
      _pwmSlotMs += 10;
      _log('PWM slot widened to $_pwmSlotMs ms');
    }
    final elapsedMs = _clock!.elapsed.inMilliseconds;
    final positionInSlot = elapsedMs % _pwmSlotMs;
    final wantOn = positionInSlot < duty * _pwmSlotMs;
    if (wantOn == _pwmOn) return;
    if (wantOn && !_pwmOnBurstAllowance()) return; // hold state this tick
    _pwmOn = wantOn;
    _lit = wantOn;
    _lastSentLevel = null;
    if (wantOn) {
      _emitNative(() => output.turnOn());
    } else {
      _emitNative(() => output.turnOff(), isTurnOff: true);
    }
  }

  bool _pwmOnBurstAllowance() {
    final now = _clock!.elapsed.inMilliseconds;
    _pwmOnTimestamps.removeWhere((t) => now - t > _pwmBurstWindowMs);
    if (_pwmOnTimestamps.length >= _pwmOnBurstLimit) return false;
    _pwmOnTimestamps.add(now);
    return true;
  }

  void _emitNative(Future<void> Function() call, {bool isTurnOff = false}) {
    final watch = clock.stopwatch()..start();
    call().then(
      (_) {
        if (!isTurnOff) _recordNativeRoundTrip(watch.elapsedMilliseconds);
      },
      onError: (Object error) {
        lastError = error;
        _onError?.call(error);
      },
    );
  }

  void _recordNativeRoundTrip(int milliseconds) {
    _nativeRoundTripEmaMs =
        _nativeRoundTripEmaMs == 0
            ? milliseconds.toDouble()
            : _nativeRoundTripEmaMs * 0.7 + milliseconds * 0.3;
    _log('torch round-trip ${milliseconds}ms');
  }

  /// Current fallback carrier width in milliseconds (testing hook).
  @visibleForTesting
  int get debugPwmSlotMs => _pwmSlotMs;

  void _complete() {
    _stopTicking();
    _lit = false;
    _pwmOn = false;
    _lastSentLevel = null;
    // Rule §11.7: always end with the torch off.
    output.turnOff().then(
      (_) => _onComplete?.call(),
      onError: (Object error) {
        lastError = error;
        _onComplete?.call();
      },
    );
  }

  void _fireTurnOff() {
    output.turnOff().then(
      (_) {},
      onError: (Object error) {
        lastError = error;
      },
    );
  }
}
