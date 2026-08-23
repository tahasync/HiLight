import '../../core/motion/easing.dart';
import '../../core/motion/hilight_animation.dart';

/// A saved user-created animation: the canonical preset schema
/// (`id`/`name`/`durationMs`/`keyframes`, PRD §28) plus the V1.1 addition of
/// one easing curve for the whole animation (prd-v1.1.md §3). No parallel
/// schema — playback goes through the same [HilightAnimation] the built-ins
/// use.
class StoredCustomAnimation {
  const StoredCustomAnimation({
    required this.animation,
    this.easing = Easing.linear,
  });

  final HilightAnimation animation;
  final Easing easing;

  String get id => animation.id;

  Map<String, Object?> toJson() => <String, Object?>{
        ...animation.toJson(),
        'easing': easing.name,
      };

  factory StoredCustomAnimation.fromJson(Map<String, Object?> json) {
    return StoredCustomAnimation(
      animation: HilightAnimation.fromJson(json),
      easing: parseEasingName(json['easing'] as String?),
    );
  }

  static Easing parseEasingName(String? name) {
    if (name == null) return Easing.linear;
    for (final easing in Easing.values) {
      if (easing.name == name) return easing;
    }
    return Easing.linear;
  }
}
