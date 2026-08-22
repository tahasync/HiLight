import 'package:flutter_test/flutter_test.dart';

import 'package:hilight/core/motion/easing.dart';
import 'package:hilight/core/motion/hilight_animation.dart';
import 'package:hilight/core/motion/light_keyframe.dart';

HilightAnimation _anim(List<(int, double)> frames) => HilightAnimation(
      id: 'test',
      name: 'Test',
      duration: Duration(milliseconds: frames.last.$1),
      keyframes: [
        for (final (ms, intensity) in frames)
          LightKeyframe(time: Duration(milliseconds: ms), intensity: intensity),
      ],
    );

void main() {
  group('LightKeyframe normalization', () {
    test('clamps intensities into 0.0–1.0', () {
      expect(LightKeyframe(time: const Duration(), intensity: -0.5).intensity,
          0.0);
      expect(LightKeyframe(time: const Duration(), intensity: 1.5).intensity,
          1.0);
      expect(LightKeyframe(time: const Duration(), intensity: 0.42).intensity,
          0.42);
    });

    test('clamps negative times to zero', () {
      final frame =
          LightKeyframe(time: const Duration(milliseconds: -10), intensity: 1);
      expect(frame.time, Duration.zero);
    });
  });

  group('HilightAnimation', () {
    test('rejects empty keyframes and non-positive durations', () {
      expect(
        () => HilightAnimation(
            id: 'x',
            name: 'x',
            duration: const Duration(milliseconds: 100),
            keyframes: const []),
        throwsArgumentError,
      );
      expect(
        () => HilightAnimation(
          id: 'x',
          name: 'x',
          duration: Duration.zero,
          keyframes: [LightKeyframe(time: Duration.zero, intensity: 1)],
        ),
        throwsArgumentError,
      );
    });

    test('keyframes are sorted by time', () {
      final anim = _anim(const [(200, 0.5), (0, 0.0), (100, 1.0)]);
      expect(anim.keyframes.map((k) => k.time.inMilliseconds).toList(),
          [0, 100, 200]);
    });

    test('samples before first and after last clamp to endpoints', () {
      final anim = _anim(const [(100, 0.2), (300, 1.0)]);
      expect(anim.sampleAt(Duration.zero), 0.2);
      expect(anim.sampleAt(const Duration(milliseconds: 50)), 0.2);
      expect(anim.sampleAt(const Duration(milliseconds: 200)),
          closeTo(0.6, 1e-9));
      expect(anim.sampleAt(const Duration(milliseconds: 999)), 1.0);
    });

    test('linear interpolation between segments', () {
      final anim = _anim(const [(0, 0.0), (100, 1.0), (200, 0.0)]);
      expect(anim.sampleAt(const Duration(milliseconds: 25)),
          closeTo(0.25, 1e-9));
      expect(anim.sampleAt(const Duration(milliseconds: 150)),
          closeTo(0.5, 1e-9));
    });

    test('easing shapes segment progress but preserves endpoints', () {
      final anim = _anim(const [(0, 0.0), (100, 1.0)]);
      for (final easing in Easing.values) {
        expect(anim.sampleAt(Duration.zero, easing: easing), 0.0);
        expect(anim.sampleAt(const Duration(milliseconds: 100), easing: easing),
            1.0);
        final mid = anim.sampleAt(const Duration(milliseconds: 50), easing: easing);
        expect(mid, inInclusiveRange(0.0, 1.0));
      }
      expect(
        anim.sampleAt(const Duration(milliseconds: 25), easing: Easing.easeIn),
        lessThan(0.25),
      );
      expect(
        anim.sampleAt(const Duration(milliseconds: 25), easing: Easing.easeOut),
        greaterThan(0.25),
      );
    });

    test('single keyframe animation is constant', () {
      final anim = HilightAnimation(
        id: 'flat',
        name: 'Flat',
        duration: const Duration(milliseconds: 500),
        keyframes: [LightKeyframe(time: Duration.zero, intensity: 0.7)],
      );
      expect(anim.sampleAt(const Duration(milliseconds: 250)), 0.7);
    });
  });

  group('Easing.transform', () {
    test('all curves map 0→0 and 1→1 monotonically', () {
      for (final easing in Easing.values) {
        var previous = -1.0;
        for (var i = 0; i <= 20; i++) {
          final value = easing.transform(i / 20);
          expect(value, inInclusiveRange(0.0, 1.0));
          expect(value, greaterThanOrEqualTo(previous));
          previous = value;
        }
        expect(easing.transform(-1), 0.0);
        expect(easing.transform(2), 1.0);
      }
    });
  });
}
