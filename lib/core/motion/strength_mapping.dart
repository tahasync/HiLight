import 'dart:math' as math;

/// Maps a normalized intensity (0.0–1.0, where 1.0 is the maximum selected
/// brightness) onto the device's concrete torch strength range (1..maxLevel).
///
/// Devices advertising a maximum of 1 are ON/OFF-only; this function returns
/// 1 for them so callers can treat them uniformly.
int mapIntensityToLevel(double normalizedIntensity, int maxLevel) {
  final clamped = normalizedIntensity.clamp(0.0, 1.0);
  final effectiveMax = math.max(1, maxLevel);
  final level = 1 + (clamped * (effectiveMax - 1)).round();
  return level.clamp(1, effectiveMax);
}
