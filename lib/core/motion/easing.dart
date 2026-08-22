import 'dart:math' as math;

/// Easing options for animation segments (PRD §14).
enum Easing {
  linear,
  easeIn,
  easeOut,
  easeInOut,
  smoothSine;

  /// Maps a segment progress value in 0.0–1.0 through this curve.
  double transform(double t) {
    final x = t.clamp(0.0, 1.0);
    return switch (this) {
      Easing.linear => x,
      Easing.easeIn => x * x,
      Easing.easeOut => 1 - (1 - x) * (1 - x),
      Easing.easeInOut =>
        x < 0.5 ? 2 * x * x : 1 - 2 * (1 - x) * (1 - x),
      Easing.smoothSine => 0.5 - 0.5 * math.cos(math.pi * x),
    };
  }
}
