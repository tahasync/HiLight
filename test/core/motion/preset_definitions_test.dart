import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hilight/core/motion/hilight_animation.dart';
import 'package:hilight/core/motion/preset_definitions.dart';
import 'package:hilight/core/motion/torch_animator.dart';
import '../../support/recording_output.dart';

void _expectTable(
  HilightAnimation preset,
  int durationMs,
  List<(int, double)> table,
) {
  expect(preset.duration.inMilliseconds, durationMs,
      reason: '${preset.id} duration');
  expect(preset.keyframes.length, table.length,
      reason: '${preset.id} keyframe count');
  for (var i = 0; i < table.length; i++) {
    expect(preset.keyframes[i].time.inMilliseconds, table[i].$1,
        reason: '${preset.id} keyframe $i time');
    expect(preset.keyframes[i].intensity, table[i].$2,
        reason: '${preset.id} keyframe $i intensity');
  }
}

void main() {
  group('MVP preset definitions match PRD §12 exactly', () {
    test('list contains exactly the five MVP presets in order', () {
      expect(
        kMvpPresets.map((p) => p.id).toList(),
        ['pulse', 'breathing', 'double_pulse', 'soft_glow', 'heartbeat'],
      );
      expect(mvpPresetById('heartbeat'), same(kHeartbeatPreset));
      expect(mvpPresetById('nope'), isNull);
    });

    test('Pulse', () {
      _expectTable(kPulsePreset, 800, const [
        (0, 0.00),
        (100, 0.20),
        (300, 1.00),
        (500, 0.30),
        (800, 0.00),
      ]);
    });

    test('Breathing', () {
      _expectTable(kBreathingPreset, 3200, const [
        (0, 0.00),
        (500, 0.15),
        (1200, 0.45),
        (1600, 1.00),
        (2000, 0.45),
        (2700, 0.15),
        (3200, 0.00),
      ]);
    });

    test('Double Pulse', () {
      _expectTable(kDoublePulsePreset, 1800, const [
        (0, 0.00),
        (100, 0.20),
        (300, 1.00),
        (500, 0.30),
        (800, 0.00),
        (1000, 0.00),
        (1100, 0.20),
        (1300, 1.00),
        (1500, 0.30),
        (1800, 0.00),
      ]);
    });

    test('Soft Glow', () {
      _expectTable(kSoftGlowPreset, 2400, const [
        (0, 0.00),
        (1000, 1.00),
        (1300, 1.00),
        (2400, 0.00),
      ]);
    });

    test('Heartbeat', () {
      _expectTable(kHeartbeatPreset, 1100, const [
        (0, 0.00),
        (80, 1.00),
        (180, 0.20),
        (260, 0.00),
        (340, 0.85),
        (440, 0.15),
        (520, 0.00),
        (1100, 0.00),
      ]);
    });
  });

  group('V1.1 preset definitions match prd-v1.1.md §2 exactly', () {
    test('built-in list contains all eight presets in order', () {
      expect(
        kBuiltinPresets.map((p) => p.id).toList(),
        [
          'pulse',
          'breathing',
          'double_pulse',
          'soft_glow',
          'heartbeat',
          'quick_flash',
          'triple_pulse',
          'long_glow',
        ],
      );
      expect(builtinPresetById('long_glow'), same(kLongGlowPreset));
      expect(builtinPresetById('nope'), isNull);
    });

    test('Quick Flash', () {
      _expectTable(kQuickFlashPreset, 350, const [
        (0, 0.00),
        (60, 1.00),
        (200, 0.25),
        (350, 0.00),
      ]);
    });

    test('Triple Pulse', () {
      _expectTable(kTriplePulsePreset, 1050, const [
        (0, 0.00),
        (60, 1.00),
        (150, 0.20),
        (250, 0.00),
        (400, 0.00),
        (460, 1.00),
        (550, 0.20),
        (650, 0.00),
        (800, 0.00),
        (860, 1.00),
        (950, 0.20),
        (1050, 0.00),
      ]);
    });

    test('Long Glow', () {
      _expectTable(kLongGlowPreset, 4800, const [
        (0, 0.00),
        (2000, 1.00),
        (2500, 1.00),
        (4800, 0.00),
      ]);
    });
  });

  group('Preset serialization (PRD §28 schema)', () {
    test('every preset round-trips through JSON', () {
      for (final preset in kBuiltinPresets) {
        final restored = HilightAnimation.fromJson(preset.toJson());
        expect(restored.id, preset.id, reason: preset.id);
        expect(restored.name, preset.name, reason: preset.id);
        expect(restored.duration, preset.duration, reason: preset.id);
        expect(restored.keyframes.length, preset.keyframes.length,
            reason: preset.id);
        for (var i = 0; i < preset.keyframes.length; i++) {
          expect(restored.keyframes[i].time, preset.keyframes[i].time,
              reason: '${preset.id}[$i]');
          expect(restored.keyframes[i].intensity,
              preset.keyframes[i].intensity, reason: '${preset.id}[$i]');
        }
      }
    });
  });

  group('Presets play through the engine', () {
    test('each built-in preset completes and ends with the torch off', () {
      fakeAsync((async) {
        for (final preset in kBuiltinPresets) {
          final output = RecordingOutput();
          final animator = TorchAnimator(output: output);
          var completed = false;
          animator.play(
            animation: preset,
            maxStrengthLevel: 21,
            repeatCount: 1,
            onComplete: () => completed = true,
          );
          async.elapse(preset.duration + const Duration(milliseconds: 200));

          expect(completed, isTrue, reason: '${preset.id} completion');
          expect(output.turnOffCalls, greaterThanOrEqualTo(1),
              reason: '${preset.id} final shutoff');
          if (output.strengthCalls.isNotEmpty) {
            expect(output.strengthCalls.reduce(math.max), lessThanOrEqualTo(21),
                reason: preset.id);
            expect(output.strengthCalls.reduce(math.min), greaterThanOrEqualTo(1),
                reason: preset.id);
          }
          animator.dispose();
        }
      });
    });

    test('Double Pulse goes fully dark during its mid pause', () {
      fakeAsync((async) {
        final output = RecordingOutput();
        final animator = TorchAnimator(output: output);
        animator.play(
          animation: kDoublePulsePreset,
          maxStrengthLevel: 21,
          repeatCount: 1,
        );
        async.elapse(const Duration(milliseconds: 950));
        final turnOffsDuringPauseBefore =
            output.turnOffCalls; // valley at 800ms hit
        expect(turnOffsDuringPauseBefore, greaterThanOrEqualTo(1));

        async.elapse(const Duration(milliseconds: 900));
        // Re-lit for second pulse after the pause.
        expect(output.strengthCalls.last, isNot(0));
        animator.dispose();
      });
    });

    test('Triple Pulse goes fully dark between pulses and re-lights', () {
      fakeAsync((async) {
        final output = RecordingOutput();
        final animator = TorchAnimator(output: output);
        animator.play(
          animation: kTriplePulsePreset,
          maxStrengthLevel: 21,
          repeatCount: 1,
        );
        async.elapse(const Duration(milliseconds: 320));
        expect(output.turnOffCalls, greaterThanOrEqualTo(1),
            reason: 'first inter-pulse hold at 250-400ms hit');

        async.elapse(const Duration(milliseconds: 160)); // ~480ms
        expect(output.strengthCalls.last, isNot(0),
            reason: 're-lit for second pulse');

        async.elapse(const Duration(milliseconds: 400)); // ~880ms
        expect(output.turnOffCalls, greaterThanOrEqualTo(2),
            reason: 'second hold at 650-800ms hit');
        expect(output.strengthCalls.last, isNot(0),
            reason: 'third pulse under way');
        animator.dispose();
      });
    });
  });
}
