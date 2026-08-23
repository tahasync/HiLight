import 'package:flutter_test/flutter_test.dart';

import 'package:hilight/features/animation_editor/custom_animation_validation.dart';

KeyframeInput kf(int timeMs, double intensity) =>
    KeyframeInput(timeMs: timeMs, intensity: intensity);

void main() {
  group('keyframe count limits (prd-v1.1.md §3)', () {
    test('accepts exactly two keyframes', () {
      final issues = validateCustomAnimation(
        keyframes: [kf(0, 0.0), kf(100, 1.0)],
        durationMs: 100,
      );
      expect(issues, isEmpty);
    });

    test('rejects a single keyframe', () {
      final issues = validateCustomAnimation(
        keyframes: [kf(0, 0.0)],
        durationMs: 100,
      );
      expect(issues, contains(CustomAnimationIssue.tooFewKeyframes));
    });

    test('accepts exactly twenty keyframes', () {
      final keyframes = List.generate(
        20,
        (i) => kf(i * 500, i.isEven ? 0.0 : 1.0),
      );
      final issues = validateCustomAnimation(
        keyframes: keyframes,
        durationMs: 10000,
      );
      expect(issues, isEmpty);
    });

    test('rejects twenty-one keyframes', () {
      final keyframes = List.generate(
        21,
        (i) => kf(i * 100, i.isEven ? 0.0 : 1.0),
      );
      final issues = validateCustomAnimation(
        keyframes: keyframes,
        durationMs: 10000,
      );
      expect(issues, contains(CustomAnimationIssue.tooManyKeyframes));
    });
  });

  group('strictly increasing times (prd-v1.1.md §3)', () {
    test('rejects out-of-order keyframes instead of reordering them', () {
      final issues = validateCustomAnimation(
        keyframes: [kf(200, 1.0), kf(100, 0.0)],
        durationMs: 300,
      );
      expect(issues, contains(CustomAnimationIssue.unsortedKeyframes));
    });

    test('rejects duplicate times as unsorted', () {
      final issues = validateCustomAnimation(
        keyframes: [kf(100, 0.0), kf(100, 1.0)],
        durationMs: 300,
      );
      expect(issues, contains(CustomAnimationIssue.unsortedKeyframes));
    });

    test('accepts strictly increasing times', () {
      final issues = validateCustomAnimation(
        keyframes: [kf(0, 0.0), kf(50, 1.0), kf(300, 0.0)],
        durationMs: 300,
      );
      expect(issues, isEmpty);
    });
  });

  group('duration bounds (prd-v1.1.md §3)', () {
    test('accepts the 100 ms and 10,000 ms boundaries', () {
      for (final durationMs in [100, 10000]) {
        expect(
          validateCustomAnimation(
            keyframes: [kf(0, 0.0), kf(1, 1.0)],
            durationMs: durationMs,
          ),
          isEmpty,
          reason: '$durationMs ms',
        );
      }
    });

    test('rejects below 100 ms', () {
      final issues = validateCustomAnimation(
        keyframes: [kf(0, 0.0), kf(50, 1.0)],
        durationMs: 99,
      );
      expect(issues, contains(CustomAnimationIssue.durationTooShort));
    });

    test('rejects above 10,000 ms', () {
      final issues = validateCustomAnimation(
        keyframes: [kf(0, 0.0), kf(10000, 1.0)],
        durationMs: 10001,
      );
      expect(issues, contains(CustomAnimationIssue.durationTooLong));
    });
  });

  group('intensity range (prd-v1.1.md §3)', () {
    test('rejects values above 1.0', () {
      final issues = validateCustomAnimation(
        keyframes: [kf(0, 0.0), kf(100, 1.5)],
        durationMs: 100,
      );
      expect(issues, contains(CustomAnimationIssue.intensityOutOfRange));
    });

    test('rejects negative values', () {
      final issues = validateCustomAnimation(
        keyframes: [kf(0, -0.1), kf(100, 1.0)],
        durationMs: 100,
      );
      expect(issues, contains(CustomAnimationIssue.intensityOutOfRange));
    });

    test('rejects NaN', () {
      final issues = validateCustomAnimation(
        keyframes: [kf(0, double.nan), kf(100, 1.0)],
        durationMs: 100,
      );
      expect(issues, contains(CustomAnimationIssue.intensityOutOfRange));
    });
  });

  test('aggregates every issue found in one pass', () {
    final issues = validateCustomAnimation(
      keyframes: [kf(500, 2.0)],
      durationMs: 20,
    );
    expect(issues, containsAll([
      CustomAnimationIssue.tooFewKeyframes,
      CustomAnimationIssue.durationTooShort,
      CustomAnimationIssue.intensityOutOfRange,
    ]));
  });

  test('ensureValid throws with the full issue list', () {
    expect(
      () => ensureValidCustomAnimation(
        keyframes: [kf(200, 1.0), kf(100, 0.5)],
        durationMs: 100000,
      ),
      throwsA(isA<CustomAnimationValidationException>().having(
        (e) => e.issues,
        'issues',
        containsAll([
          CustomAnimationIssue.unsortedKeyframes,
          CustomAnimationIssue.durationTooLong,
        ]),
      )),
    );
  });

  test('ensureValid accepts a valid proposal silently', () {
    expect(
      () => ensureValidCustomAnimation(
        keyframes: [kf(0, 0.0), kf(350, 1.0)],
        durationMs: 350,
      ),
      returnsNormally,
    );
  });
}
