import 'easing.dart';
import 'light_keyframe.dart';

/// A light animation definition: named, timed keyframes over a fixed cycle
/// (PRD §28 data model). Intensities are normalized 0.0–1.0.
class HilightAnimation {
  factory HilightAnimation({
    required String id,
    required String name,
    required Duration duration,
    required List<LightKeyframe> keyframes,
  }) {
    if (keyframes.isEmpty) {
      throw ArgumentError.value(keyframes, 'keyframes', 'must not be empty');
    }
    if (duration <= Duration.zero) {
      throw ArgumentError.value(duration, 'duration', 'must be positive');
    }
    final sorted = List<LightKeyframe>.of(keyframes)
      ..sort((a, b) => a.time.compareTo(b.time));
    return HilightAnimation._(
      id: id,
      name: name,
      duration: duration,
      keyframes: List.unmodifiable(sorted),
    );
  }

  const HilightAnimation._({
    required this.id,
    required this.name,
    required this.duration,
    required this.keyframes,
  });

  final String id;
  final String name;
  final Duration duration;
  final List<LightKeyframe> keyframes;

  /// Serializes to the canonical schema from PRD §28.
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'name': name,
        'durationMs': duration.inMilliseconds,
        'keyframes': <Map<String, Object?>>[
          for (final keyframe in keyframes)
            <String, Object?>{
              'timeMs': keyframe.time.inMilliseconds,
              'intensity': keyframe.intensity,
            },
        ],
      };

  /// Restores an animation serialized with [toJson].
  factory HilightAnimation.fromJson(Map<String, Object?> json) {
    return HilightAnimation(
      id: json['id'] as String,
      name: json['name'] as String,
      duration: Duration(milliseconds: json['durationMs'] as int),
      keyframes: [
        for (final frame in json['keyframes'] as List)
          LightKeyframe(
            time: Duration(milliseconds: (frame as Map)['timeMs'] as int),
            intensity: (frame['intensity'] as num).toDouble(),
          ),
      ],
    );
  }

  /// Samples the normalized intensity at [time], interpolating linearly
  /// between the surrounding keyframes with the given [easing] applied to
  /// each segment's progress.
  double sampleAt(Duration time, {Easing easing = Easing.linear}) {
    return _sample(time, easing, false);
  }

  /// Smooth variant of [sampleAt]: Catmull-Rom interpolation across
  /// neighboring keyframes produces continuously curved ramps instead of
  /// straight segments with hard corners. Used by the on-screen preview;
  /// the physical engine keeps [sampleAt] so hardware timing stays faithful.
  double sampleSmoothAt(Duration time) {
    return _sample(time, Easing.linear, true);
  }

  double _sample(Duration time, Easing easing, bool smooth) {
    if (time <= keyframes.first.time) return keyframes.first.intensity;
    if (time >= keyframes.last.time) return keyframes.last.intensity;
    for (var i = 0; i < keyframes.length - 1; i++) {
      final k0 = keyframes[i];
      final k1 = keyframes[i + 1];
      if (time >= k0.time && time < k1.time) {
        final segmentLength = k1.time - k0.time;
        final t = segmentLength == Duration.zero
            ? 1.0
            : (time - k0.time).inMicroseconds / segmentLength.inMicroseconds;
        final progress = easing.transform(t);
        if (!smooth) {
          return lerp(k0.intensity, k1.intensity, progress);
        }
        // Catmull-Rom through neighbouring intensities; clamped at ends so
        // the curve passes exactly through every keyframe value.
        double at(int index) => keyframes[
            index.clamp(0, keyframes.length - 1)].intensity;
        final p0 = at(i - 1);
        final p1 = at(i);
        final p2 = at(i + 1);
        final p3 = at(i + 2);
        final u = progress;
        final u2 = u * u;
        final u3 = u2 * u;
        final value = 0.5 *
            ((2 * p1) +
                (-p0 + p2) * u +
                (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2 +
                (-p0 + 3 * p1 - 3 * p2 + p3) * u3);
        return value.clamp(0.0, 1.0);
      }
    }
    return keyframes.last.intensity;
  }

  static double lerp(double a, double b, double t) => a + (b - a) * t;
}
