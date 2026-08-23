/// Raw keyframe input as submitted for validation, before any clamping.
class KeyframeInput {
  const KeyframeInput({required this.timeMs, required this.intensity});

  final int timeMs;
  final double intensity;
}

/// Hard limits for user-created animations (prd-v1.1.md §3).
class CustomAnimationLimits {
  static const int minKeyframes = 2;
  static const int maxKeyframes = 20;
  static const int minDurationMs = 100;
  static const int maxDurationMs = 10000;

  CustomAnimationLimits._();
}

/// Every way a proposed custom animation can be invalid.
enum CustomAnimationIssue {
  tooFewKeyframes,
  tooManyKeyframes,
  unsortedKeyframes,
  durationTooShort,
  durationTooLong,
  intensityOutOfRange,
}

/// Thrown when an invalid custom animation state is submitted for saving
/// (prd-v1.1.md §3): invalid states are rejected outright, never silently
/// corrected or reordered.
class CustomAnimationValidationException implements Exception {
  CustomAnimationValidationException(this.issues);

  final List<CustomAnimationIssue> issues;

  @override
  String toString() =>
      'CustomAnimationValidationException: ${issues.map((i) => i.name).join(', ')}';
}

/// Validates a raw proposal and returns every issue found (empty means
/// valid). Keyframe times must be strictly increasing; duplicates count as
/// unsorted.
List<CustomAnimationIssue> validateCustomAnimation({
  required List<KeyframeInput> keyframes,
  required int durationMs,
}) {
  final issues = <CustomAnimationIssue>[];
  if (keyframes.length < CustomAnimationLimits.minKeyframes) {
    issues.add(CustomAnimationIssue.tooFewKeyframes);
  } else if (keyframes.length > CustomAnimationLimits.maxKeyframes) {
    issues.add(CustomAnimationIssue.tooManyKeyframes);
  }
  for (var i = 1; i < keyframes.length; i++) {
    if (keyframes[i].timeMs <= keyframes[i - 1].timeMs) {
      issues.add(CustomAnimationIssue.unsortedKeyframes);
      break;
    }
  }
  if (durationMs < CustomAnimationLimits.minDurationMs) {
    issues.add(CustomAnimationIssue.durationTooShort);
  } else if (durationMs > CustomAnimationLimits.maxDurationMs) {
    issues.add(CustomAnimationIssue.durationTooLong);
  }
  for (final keyframe in keyframes) {
    final intensity = keyframe.intensity;
    if (intensity.isNaN || intensity < 0.0 || intensity > 1.0) {
      issues.add(CustomAnimationIssue.intensityOutOfRange);
      break;
    }
  }
  return issues;
}

/// Throws [CustomAnimationValidationException] if the proposal is invalid.
void ensureValidCustomAnimation({
  required List<KeyframeInput> keyframes,
  required int durationMs,
}) {
  final issues = validateCustomAnimation(
    keyframes: keyframes,
    durationMs: durationMs,
  );
  if (issues.isNotEmpty) {
    throw CustomAnimationValidationException(issues);
  }
}
