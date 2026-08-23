import '../../core/motion/easing.dart';
import '../../core/motion/hilight_animation.dart';
import '../../core/motion/light_keyframe.dart';
import 'custom_animation_id.dart';
import 'custom_animation_validation.dart';
import 'stored_custom_animation.dart';

/// Mutable editor state for a custom animation under construction
/// (prd-v1.1.md §3).
///
/// Intensity inputs are clamped here, at the editor (§3: clamp on input, do
/// not rely on the engine). Structural problems are surfaced by [validate]
/// and block [build] — an out-of-order draft is refused, not reordered.
class CustomAnimationDraft {
  CustomAnimationDraft({
    this.id,
    this.name = 'My animation',
    this.durationMs = CustomAnimationLimits.minDurationMs * 8,
    this.easing = Easing.linear,
    List<LightKeyframe>? keyframes,
  }) : keyframes = List<LightKeyframe>.of(
          keyframes ??
              [
                LightKeyframe(time: Duration.zero, intensity: 0),
                LightKeyframe(
                  time: const Duration(milliseconds: 800),
                  intensity: 1,
                ),
              ],
        );

  /// Existing id when editing a saved custom animation; null generates a new
  /// namespaced id at [build] time.
  String? id;
  String name;
  int durationMs;
  Easing easing;
  final List<LightKeyframe> keyframes;

  /// Appends a keyframe; intensity is clamped into 0.0–1.0 on input.
  void addKeyframe(Duration time, double intensity) {
    keyframes.add(LightKeyframe(time: time, intensity: intensity));
  }

  void removeKeyframeAt(int index) {
    keyframes.removeAt(index);
  }

  void updateKeyframeAt(int index, {Duration? time, double? intensity}) {
    final current = keyframes[index];
    keyframes[index] = LightKeyframe(
      time: time ?? current.time,
      intensity: intensity ?? current.intensity,
    );
  }

  List<CustomAnimationIssue> validate() => validateCustomAnimation(
        keyframes: [
          for (final keyframe in keyframes)
            KeyframeInput(
              timeMs: keyframe.time.inMilliseconds,
              intensity: keyframe.intensity,
            ),
        ],
        durationMs: durationMs,
      );

  /// Freezes the draft into a persisted entry. Throws
  /// [CustomAnimationValidationException] if [validate] reports anything.
  StoredCustomAnimation build() {
    final issues = validate();
    if (issues.isNotEmpty) {
      throw CustomAnimationValidationException(issues);
    }
    return StoredCustomAnimation(
      animation: HilightAnimation(
        id: id ?? newCustomAnimationId(),
        name: name,
        duration: Duration(milliseconds: durationMs),
        keyframes: List.of(keyframes),
      ),
      easing: easing,
    );
  }
}
