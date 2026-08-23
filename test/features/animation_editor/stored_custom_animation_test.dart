import 'package:flutter_test/flutter_test.dart';

import 'package:hilight/core/motion/easing.dart';
import 'package:hilight/core/motion/hilight_animation.dart';
import 'package:hilight/core/motion/light_keyframe.dart';
import 'package:hilight/features/animation_editor/stored_custom_animation.dart';

StoredCustomAnimation _sample({Easing easing = Easing.easeInOut}) {
  return StoredCustomAnimation(
    animation: HilightAnimation(
      id: 'custom_12345678-1234-4123-8123-123456789abc',
      name: 'My flicker',
      duration: const Duration(milliseconds: 350),
      keyframes: [
        LightKeyframe(time: Duration.zero, intensity: 0.0),
        LightKeyframe(time: const Duration(milliseconds: 60), intensity: 1.0),
        LightKeyframe(time: const Duration(milliseconds: 200), intensity: 0.25),
        LightKeyframe(time: const Duration(milliseconds: 350), intensity: 0.0),
      ],
    ),
    easing: easing,
  );
}

void main() {
  group('serialization (canonical schema + V1.1 additions)', () {
    test('sample serialized custom preset', () {
      expect(_sample().toJson(), <String, Object?>{
        'id': 'custom_12345678-1234-4123-8123-123456789abc',
        'name': 'My flicker',
        'durationMs': 350,
        'keyframes': [
          {'timeMs': 0, 'intensity': 0.0},
          {'timeMs': 60, 'intensity': 1.0},
          {'timeMs': 200, 'intensity': 0.25},
          {'timeMs': 350, 'intensity': 0.0},
        ],
        'easing': 'easeInOut',
      });
    });

    test('round-trips through JSON preserving every field', () {
      final restored = StoredCustomAnimation.fromJson(_sample().toJson());
      expect(restored.id, _sample().id);
      expect(restored.animation.name, 'My flicker');
      expect(restored.animation.duration, const Duration(milliseconds: 350));
      expect(restored.animation.keyframes.length, 4);
      for (var i = 0; i < 4; i++) {
        expect(restored.animation.keyframes[i].time,
            _sample().animation.keyframes[i].time);
        expect(restored.animation.keyframes[i].intensity,
            _sample().animation.keyframes[i].intensity);
      }
      expect(restored.easing, Easing.easeInOut);
    });

    test('defaults to linear easing when absent or unknown', () {
      final json = _sample(easing: Easing.smoothSine).toJson()
        ..remove('easing');
      expect(
        StoredCustomAnimation.fromJson(json).easing,
        Easing.linear,
      );
      final unknown = Map<String, Object?>.from(_sample().toJson())
        ..['easing'] = 'elastic_bounce_v9';
      expect(
        StoredCustomAnimation.fromJson(unknown).easing,
        Easing.linear,
      );
    });

    test('every named easing round-trips', () {
      for (final easing in Easing.values) {
        final restored =
            StoredCustomAnimation.fromJson(_sample(easing: easing).toJson());
        expect(restored.easing, easing, reason: easing.name);
      }
    });
  });
}
