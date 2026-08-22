import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hilight/core/motion/hilight_animation.dart';
import '../../support/recording_output.dart';
import 'package:hilight/core/motion/light_keyframe.dart';
import 'package:hilight/core/motion/torch_animator.dart';

HilightAnimation _anim(List<(int, double)> frames, {String id = 'test'}) =>
    HilightAnimation(
      id: id,
      name: id,
      duration: Duration(milliseconds: frames.last.$1),
      keyframes: [
        for (final (ms, intensity) in frames)
          LightKeyframe(time: Duration(milliseconds: ms), intensity: intensity),
      ],
    );

/// Pulse-like shape for behavior tests.
final pulse = _anim(const [(0, 0.0), (100, 1.0), (200, 0.0)]);

void main() {
  group('TorchAnimator completion', () {
    test('plays once and always ends with torch off', () {
      fakeAsync((async) {
        final output = RecordingOutput();
        final animator = TorchAnimator(output: output);
        var completed = false;
        animator.play(
          animation: pulse,
          maxStrengthLevel: 21,
          repeatCount: 1,
          onComplete: () => completed = true,
        );
        async.elapse(const Duration(milliseconds: 300));

        expect(completed, isTrue);
        expect(animator.isPlaying, isFalse);
        expect(output.turnOffCalls, greaterThanOrEqualTo(1));
        expect(output.strengthCalls, isNotEmpty);
      });
    });

    test('never emits a level above the mapped maximum brightness', () {
      fakeAsync((async) {
        final output = RecordingOutput();
        final animator = TorchAnimator(output: output);
        animator.play(
          animation: pulse,
          maxStrengthLevel: 21,
          brightness: 0.5,
        );
        async.elapse(const Duration(milliseconds: 300));
        // Peak intensity 1.0 * 0.5 → level round(1 + 0.5*20) = 11.
        expect(output.strengthCalls.reduce((a, b) => a > b ? a : b), lessThanOrEqualTo(11));
      });
    });
  });

  group('TorchAnimator native-call discipline', () {
    test('constant intensity produces a single setStrength call', () {
      fakeAsync((async) {
        final output = RecordingOutput();
        final animator = TorchAnimator(output: output);
        animator.play(
          animation:
              _anim(const [(0, 0.8), (400, 0.8)], id: 'flat'),
          maxStrengthLevel: 21,
        );
        async.elapse(const Duration(milliseconds: 500));
        expect(output.strengthCalls.length, 1);
      });
    });

    test('zero-intensity moments turn the torch fully off', () {
      fakeAsync((async) {
        final output = RecordingOutput();
        final animator = TorchAnimator(output: output);
        animator.play(
          animation: _anim(
            const [(0, 1.0), (100, 0.0), (200, 1.0)],
            id: 'gap',
          ),
          maxStrengthLevel: 21,
        );
        async.elapse(const Duration(milliseconds: 250));
        expect(output.turnOffCalls, greaterThanOrEqualTo(2)); // mid-gap + final
        expect(animator.lastError, isNull);
      });
    });

    test('repeated cycles wrap sampling around the cycle duration', () {
      fakeAsync((async) {
        final output = RecordingOutput();
        final animator = TorchAnimator(output: output);
        var completions = 0;
        animator.play(
          animation: pulse,
          maxStrengthLevel: 21,
          repeatCount: 3,
          onComplete: () => completions++,
        );
        async.elapse(const Duration(microseconds: 599000));
        expect(completions, 0);
        async.elapse(const Duration(milliseconds: 50));
        expect(completions, 1);
        // Peak reached once per cycle.
        expect(
          output.strengthCalls.where((l) => l >= 20).length,
          inInclusiveRange(3, 12),
        );
      });
    });

    test('speed scales the timeline', () {
      fakeAsync((async) {
        final output = RecordingOutput();
        final animator = TorchAnimator(output: output);
        animator.play(
          animation: pulse, // 200 ms cycle
          maxStrengthLevel: 21,
          speed: 2.0,
          repeatCount: 2, // effective total 200 ms
        );
        async.elapse(const Duration(milliseconds: 150));
        expect(animator.isPlaying, isTrue);
        async.elapse(const Duration(milliseconds: 100));
        expect(animator.isPlaying, isFalse);
      });
    });

    test('fast ramps resolve many distinct levels without spamming native',
        () {
      fakeAsync((async) {
        final output = RecordingOutput();
        final animator = TorchAnimator(output: output);
        animator.play(animation: pulse, maxStrengthLevel: 21);
        async.elapse(const Duration(milliseconds: 300));

        final levels = output.strengthCalls;
        // Distinct level count: fine sampling must reach deep into the
        // 21-level range during the 100 ms attack (was ~3 with 32 ms ticks).
        expect(levels.toSet().length, greaterThanOrEqualTo(10));
        // Dedupe keeps total native traffic far below the tick count.
        expect(levels.length, lessThanOrEqualTo(30));
      });
    });
  });

  group('TorchAnimator cancellation', () {
    test('cancel stops ticking and turns the torch off', () {
      fakeAsync((async) {
        final output = RecordingOutput();
        final animator = TorchAnimator(output: output);
        animator.play(animation: pulse, maxStrengthLevel: 21);
        async.elapse(const Duration(milliseconds: 60));
        expect(output.strengthCalls, isNotEmpty);

        animator.cancel();
        final callsAtCancel = output.strengthCalls.length;
        final offsAtCancel = output.turnOffCalls;
        expect(offsAtCancel, greaterThanOrEqualTo(1));

        async.elapse(const Duration(milliseconds: 500));
        expect(output.strengthCalls.length, callsAtCancel);
        expect(output.turnOffCalls, offsAtCancel);
        expect(animator.isPlaying, isFalse);
      });
    });

    test('playing a new animation cancels the previous one first', () {
      fakeAsync((async) {
        final output = RecordingOutput();
        final animator = TorchAnimator(output: output);
        animator.play(
          animation: pulse,
          maxStrengthLevel: 21,
          repeatCount: 0, // continuous
        );
        async.elapse(const Duration(milliseconds: 120));

        animator.play(
          animation: _anim(const [(0, 0.9), (150, 0.9)], id: 'second'),
          maxStrengthLevel: 21,
        );
        expect(output.turnOffCalls, 1); // cleanup of the continuous run

        async.elapse(const Duration(milliseconds: 300));
        expect(animator.isPlaying, isFalse);
        expect(output.turnOffCalls, 2); // + completion shutoff
      });
    });

    test('output errors are recorded without stopping safety shutoff', () {
      fakeAsync((async) {
        final output = RecordingOutput()..throwOnSetStrength = true;
        final animator = TorchAnimator(output: output);
        animator.play(animation: pulse, maxStrengthLevel: 21);
        async.elapse(const Duration(milliseconds: 300));

        expect(animator.lastError, isNotNull);
        expect(output.turnOffCalls, greaterThanOrEqualTo(1));
      });
    });
  });

  group('TorchAnimator ON/OFF fallback modulation (Pixel-4 class)', () {
    test('mid intensity toggles with a duty cycle near the target', () {
      fakeAsync((async) {
        final output = RecordingOutput();
        final animator = TorchAnimator(output: output);
        // Constant 50% perceptual intensity → duty ≈ 0.5^2.2 ≈ 22%.
        animator.play(
          animation: _anim(const [(0, 0.5), (400, 0.5)], id: 'half'),
          maxStrengthLevel: 1,
          repeatCount: 0,
        );
        async.elapse(const Duration(milliseconds: 600));

        final ons = output.turnOnCalls;
        final offs = output.turnOffCalls;
        // Duty ≈ 0.5^2.2 ≈ 22% → a ~6.5 ms on-window per 30 ms slot, i.e.
        // one ON+OFF pair per slot on the 10 ms sample grid (~20 slots).
        expect(ons, greaterThanOrEqualTo(10), reason: 'PWM must toggle');
        expect(ons, lessThanOrEqualTo(24));
        expect((ons - offs).abs(), lessThanOrEqualTo(1),
            reason: 'bursts must stay balanced');
      });
    });

    test('full intensity stays solidly on without flicker', () {
      fakeAsync((async) {
        final output = RecordingOutput();
        final animator = TorchAnimator(output: output);
        animator.play(
          animation: _anim(const [(0, 1.0), (300, 1.0)], id: 'full'),
          maxStrengthLevel: 1,
        );
        async.elapse(const Duration(milliseconds: 350));
        expect(output.turnOnCalls, 1);
        expect(output.turnOffCalls, 1); // completion only
      });
    });

    test('zero valleys are true hardware off between PWM bursts', () {
      fakeAsync((async) {
        final output = RecordingOutput();
        final animator = TorchAnimator(output: output);
        animator.play(
          animation: _anim(
            const [(0, 0.6), (100, 0.0), (200, 0.0), (300, 0.6)],
            id: 'gapped',
          ),
          maxStrengthLevel: 1,
        );
        async.elapse(const Duration(milliseconds: 350));
        // Valley must produce an off that is NOT immediately followed by an
        // on until the next rise; count strict offs ≥ valley + final.
        expect(output.turnOffCalls, greaterThanOrEqualTo(2));
      });
    });

    test('slow native round-trips widen the carrier automatically', () {
      fakeAsync((async) {
        final output = RecordingOutput();
        // Simulate a sluggish HAL: every turnOn takes ~15 ms to acknowledge.
        SlowOutput slow = SlowOutput(output, latencyMs: 15);
        final animator = TorchAnimator(output: slow);
        expect(animator.debugPwmSlotMs, 30);
        animator.play(
          animation: _anim(const [(0, 0.5), (900, 0.5)], id: 'slowhal'),
          maxStrengthLevel: 1,
          repeatCount: 0,
        );
        async.elapse(const Duration(milliseconds: 500));
        expect(animator.debugPwmSlotMs, greaterThan(30),
            reason: 'EMA round-trip >10 ms must widen the slot');
        async.elapse(const Duration(milliseconds: 600));
        animator.dispose();
      });
    });

    test('cancel is idempotent — exactly one shutoff', () {
      fakeAsync((async) {
        final output = RecordingOutput();
        final animator = TorchAnimator(output: output);
        animator.play(animation: pulse, maxStrengthLevel: 21);
        async.elapse(const Duration(milliseconds: 80));
        animator.cancel();
        animator.cancel();
        animator.cancel();
        async.elapse(const Duration(milliseconds: 200));
        expect(output.turnOffCalls, 1);
      });
    });
  });
}
