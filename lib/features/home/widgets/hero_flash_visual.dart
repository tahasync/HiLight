import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/motion/hilight_animation.dart';

/// Large expressive visual representing the physical white rear flash.
///
/// Smoothness strategy:
///  - the timeline is sampled through [HilightAnimation.sampleSmoothAt]
///    (Catmull-Rom), removing hard corners at keyframes;
///  - an exponential smoother relaxes the displayed intensity toward the
///    sampled target each frame, hiding any residual stepping;
///  - only the glow subtree repaints (RepaintBoundary + ValueNotifier), and
///    shadow parameters are recomputed once per frame instead of rebuilding
///    the surrounding screen.
///
/// Respects the system reduced-motion preference by showing a static
/// representation (§13/§23).
class HeroFlashVisual extends StatefulWidget {
  const HeroFlashVisual({
    required this.animation,
    required this.playing,
    required this.brightness,
    required this.speed,
    required this.repeatCount,
    required this.session,
    required this.startedAt,
    super.key,
  });

  final HilightAnimation animation;
  final bool playing;
  final double brightness;
  final double speed;
  final int repeatCount;

  /// Shared clock origin from the controller — the instant the physical
  /// engine started. The visual positions itself on this timeline rather
  /// than its own, keeping preview and torch aligned (PRD §27).
  final DateTime? startedAt;

  /// Changes on every preview start/restart; forces a full re-sync.
  final int session;

  @override
  State<HeroFlashVisual> createState() => _HeroFlashVisualState();
}

class _HeroFlashVisualState extends State<HeroFlashVisual>
    with SingleTickerProviderStateMixin {
  static const double _smoothingRate = 26;

  late final Ticker _ticker = createTicker(_onTick);
  final ValueNotifier<double> _notifier = ValueNotifier(0);

  double _display = 0;
  Duration _lastFrameElapsed = Duration.zero;
  bool _reducedMotion = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncTicker();
  }

  @override
  void didUpdateWidget(HeroFlashVisual oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session ||
        oldWidget.animation.id != widget.animation.id) {
      _resetTimeline();
    }
    _syncTicker();
  }

  void _resetTimeline() {
    if (_ticker.isActive) _ticker.stop();
    _display = 0;
    _lastFrameElapsed = Duration.zero;
    _notifier.value = 0;
  }

  void _syncTicker() {
    final shouldRun = widget.playing && !_reducedMotion;
    if (shouldRun) {
      if (!_ticker.isActive) {
        _resetTimeline();
        _ticker.start();
      }
    } else {
      if (_ticker.isActive) _ticker.stop();
      _display = widget.playing && _reducedMotion ? widget.brightness * 0.6 : 0;
      _notifier.value = _display;
    }
  }

  void _onTick(Duration frameElapsed) {
    final dtMs = (frameElapsed - _lastFrameElapsed).inMicroseconds /
        Duration.microsecondsPerMillisecond;
    _lastFrameElapsed = frameElapsed;
    final dtSeconds = math.max(dtMs, 1) / 1000;

    // Position on the shared timeline: wall-clock time since the controller
    // started the engine, so visual and torch share one origin (§27).
    final startedAt = widget.startedAt;
    if (startedAt == null) return;
    final totalMs = (DateTime.now().difference(startedAt).inMilliseconds *
            widget.speed)
        .round();
    var cycleMs = 0;
    if (widget.repeatCount == 0) {
      cycleMs = totalMs % widget.animation.duration.inMilliseconds;
    } else {
      final planned =
          widget.animation.duration.inMilliseconds * widget.repeatCount;
      cycleMs = totalMs >= planned
          ? widget.animation.duration.inMilliseconds
          : totalMs % widget.animation.duration.inMilliseconds;
    }
    final sampled = widget.animation.sampleSmoothAt(
      Duration(milliseconds: math.max(0, cycleMs)),
    );
    final target = (sampled * widget.brightness).clamp(0.0, 1.0);

    // Exponential smoothing toward the sampled target.
    final factor = 1 - math.exp(-dtSeconds * _smoothingRate);
    var next = _display + (target - _display) * factor;
    if ((next - target).abs() < 0.0005) next = target;
    _display = next;

    if ((next - _notifier.value).abs() > 0.002 ||
        (next == 0 && _notifier.value != 0)) {
      _notifier.value = next;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final idleCore = isDark ? Colors.white38 : Colors.grey.shade300;
    final ringColor = colorScheme.primary;
    return SizedBox(
      height: 240,
      width: double.infinity,
      child: Center(
        child: RepaintBoundary(
          child: ValueListenableBuilder<double>(
            valueListenable: _notifier,
            builder: (context, i, _) {
              final coreColor = Color.lerp(idleCore, Colors.white, i)!;
              final glowColor = isDark
                  ? Colors.white
                  : Color.lerp(Colors.grey.shade400, ringColor, i)!;
              return Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 216,
                    height: 216,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        width: 2,
                        color: ringColor.withValues(alpha: 0.10 + 0.22 * i),
                      ),
                    ),
                  ),
                  Container(
                    width: 62 + 58 * i,
                    height: 62 + 58 * i,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: coreColor,
                      border: i < 0.05
                          ? Border.all(
                              width: 1,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.35),
                            )
                          : null,
                      boxShadow: [
                        if (i > 0)
                          BoxShadow(
                            color: glowColor.withValues(alpha: 0.75 * i),
                            blurRadius: 16 + 96 * i,
                            spreadRadius: 4 + 26 * i,
                          ),
                        if (i > 0)
                          BoxShadow(
                            color: glowColor.withValues(alpha: 0.30 * i),
                            blurRadius: 140 * i + 8,
                            spreadRadius: 40 * i,
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
