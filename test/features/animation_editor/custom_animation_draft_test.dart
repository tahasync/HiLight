import 'package:flutter_test/flutter_test.dart';

import 'package:hilight/core/motion/easing.dart';
import 'package:hilight/features/animation_editor/custom_animation_draft.dart';
import 'package:hilight/features/animation_editor/custom_animation_validation.dart';

void main() {
  group('draft input handling (prd-v1.1.md §3: clamp at the editor)', () {
    test('default draft is a valid two-keyframe animation', () {
      final draft = CustomAnimationDraft();
      expect(draft.validate(), isEmpty);
    });

    test('addKeyframe clamps out-of-range intensities on input', () {
      final draft = CustomAnimationDraft()
        ..addKeyframe(const Duration(milliseconds: 850), 1.5)
        ..addKeyframe(const Duration(milliseconds: 900), -0.5);
      expect(draft.keyframes[2].intensity, 1.0);
      expect(draft.keyframes[3].intensity, 0.0);
      expect(draft.validate(), isEmpty);
    });

    test('updateKeyframeAt clamps too', () {
      final draft = CustomAnimationDraft()..updateKeyframeAt(0, intensity: 2.0);
      expect(draft.keyframes[0].intensity, 1.0);
      draft.updateKeyframeAt(1, time: const Duration(milliseconds: 500));
      expect(draft.keyframes[1].time, const Duration(milliseconds: 500));
    });

    test('removeKeyframeAt shrinks the timeline', () {
      final draft = CustomAnimationDraft()
        ..addKeyframe(const Duration(milliseconds: 400), 0.0)
        ..removeKeyframeAt(1);
      expect(draft.keyframes.length, 2);
    });
  });

  group('draft rejects invalid states instead of fixing them', () {
    test('removing down to one keyframe blocks build', () {
      final draft = CustomAnimationDraft()..removeKeyframeAt(1);
      expect(draft.validate(), contains(CustomAnimationIssue.tooFewKeyframes));
      expect(
        () => draft.build(),
        throwsA(isA<CustomAnimationValidationException>()),
      );
    });

    test('an out-of-order edit is refused, not reordered', () {
      final draft = CustomAnimationDraft()
        ..updateKeyframeAt(0, time: const Duration(milliseconds: 900));
      expect(
        draft.validate(),
        contains(CustomAnimationIssue.unsortedKeyframes),
      );
      expect(
        () => draft.build(),
        throwsA(isA<CustomAnimationValidationException>().having(
          (e) => e.issues,
          'issues',
          contains(CustomAnimationIssue.unsortedKeyframes),
        )),
      );
      // The stored order was never touched by the validator.
      expect(draft.keyframes[0].time, const Duration(milliseconds: 900));
      expect(draft.keyframes[1].time, const Duration(milliseconds: 800));
    });

    test('duration edits outside bounds are flagged', () {
      final draft = CustomAnimationDraft()..durationMs = 50;
      expect(
        draft.validate(),
        contains(CustomAnimationIssue.durationTooShort),
      );
      draft.durationMs = 20000;
      expect(
        draft.validate(),
        contains(CustomAnimationIssue.durationTooLong),
      );
    });
  });

  group('build produces engine-playable entries', () {
    test('generates a namespaced id and keeps editor fields', () {
      final entry = CustomAnimationDraft(name: 'Strobe')
        ..durationMs = 350
        ..easing = Easing.easeOut
        ..updateKeyframeAt(1, time: const Duration(milliseconds: 350))
        ..addKeyframe(const Duration(milliseconds: 500), 0.0);
      final built = entry.build();

      expect(built.id, startsWith('custom_'));
      expect(built.animation.name, 'Strobe');
      expect(built.easing, Easing.easeOut);
      expect(built.animation.duration, const Duration(milliseconds: 350));
      // Plays through the same engine model as built-ins.
      expect(built.animation.sampleAt(const Duration(milliseconds: 175)),
          greaterThan(0.0));
    });

    test('keeps an explicit id across rebuilds (rename flow)', () {
      final draft = CustomAnimationDraft(id: 'custom_fixed-id')..name = 'v2';
      expect(draft.build().id, 'custom_fixed-id');
      draft.name = 'v3';
      expect(draft.build().id, 'custom_fixed-id');
      expect(draft.build().animation.name, 'v3');
    });
  });
}
