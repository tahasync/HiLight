import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:hilight/core/motion/preset_definitions.dart';
import 'package:hilight/features/animation_editor/custom_animation_id.dart';

void main() {
  group('custom_<uuid> id namespacing (prd-v1.1.md §3)', () {
    test('matches RFC 4122 v4 shape with version and variant bits', () {
      final pattern = RegExp(
        r'^custom_[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      for (var i = 0; i < 50; i++) {
        expect(newCustomAnimationId(), matches(pattern),
            reason: 'iteration $i');
      }
    });

    test('generates unique ids', () {
      final ids = {for (var i = 0; i < 500; i++) newCustomAnimationId()};
      expect(ids.length, 500);
    });

    test('is reproducible for a seeded Random and unique across draws', () {
      expect(
        newCustomAnimationId(Random(7)),
        newCustomAnimationId(Random(7)),
      );
      final rng = Random(42);
      final first = newCustomAnimationId(rng);
      final second = newCustomAnimationId(rng);
      expect(first, isNot(second));
    });

    test('never collides with built-in preset ids', () {
      for (var i = 0; i < 200; i++) {
        final id = newCustomAnimationId();
        expect(builtinPresetById(id), isNull, reason: id);
        expect(kBuiltinPresets.map((p) => p.id), isNot(contains(id)));
      }
    });
  });

  group('isCustomAnimationId', () {
    test('recognizes generated ids', () {
      expect(isCustomAnimationId(newCustomAnimationId()), isTrue);
    });

    test('distinguishes built-in ids', () {
      expect(isCustomAnimationId('pulse'), isFalse);
      expect(isCustomAnimationId('long_glow'), isFalse);
      expect(isCustomAnimationId(''), isFalse);
    });
  });
}
