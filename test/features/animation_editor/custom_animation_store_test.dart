import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hilight/core/motion/easing.dart';
import 'package:hilight/core/motion/hilight_animation.dart';
import 'package:hilight/core/motion/light_keyframe.dart';
import 'package:hilight/features/animation_editor/custom_animation_store.dart';
import 'package:hilight/features/animation_editor/stored_custom_animation.dart';

StoredCustomAnimation entry({
  required String id,
  String name = 'Custom',
  Easing easing = Easing.linear,
}) {
  return StoredCustomAnimation(
    animation: HilightAnimation(
      id: id,
      name: name,
      duration: const Duration(milliseconds: 350),
      keyframes: [
        LightKeyframe(time: Duration.zero, intensity: 0.0),
        LightKeyframe(time: const Duration(milliseconds: 60), intensity: 1.0),
        LightKeyframe(time: const Duration(milliseconds: 350), intensity: 0.0),
      ],
    ),
    easing: easing,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  test('starts empty', () async {
    final store = CustomAnimationStore();
    expect(await store.loadAll(), isEmpty);
  });

  test('save then load round-trips every field', () async {
    final store = CustomAnimationStore();
    await store.save(entry(
      id: 'custom_aaaa0000-0000-4000-8000-000000000001',
      name: 'Flicker',
      easing: Easing.smoothSine,
    ));

    final loaded = await store.loadAll();
    expect(loaded.length, 1);
    expect(loaded.single.id, 'custom_aaaa0000-0000-4000-8000-000000000001');
    expect(loaded.single.animation.name, 'Flicker');
    expect(loaded.single.easing, Easing.smoothSine);
    expect(loaded.single.animation.duration,
        const Duration(milliseconds: 350));
    expect(loaded.single.animation.keyframes.length, 3);
  });

  test('saving the same id replaces in place (rename flow)', () async {
    final store = CustomAnimationStore();
    const id = 'custom_bbbb0000-0000-4000-8000-000000000002';
    await store.save(entry(id: id, name: 'First'));
    await store.save(entry(
      id: 'custom_cccc0000-0000-4000-8000-000000000003',
      name: 'Second',
    ));
    await store.save(entry(id: id, name: 'First renamed'));

    final loaded = await store.loadAll();
    expect(loaded.map((e) => e.id).toList(), [
      'custom_bbbb0000-0000-4000-8000-000000000002',
      'custom_cccc0000-0000-4000-8000-000000000003',
    ]);
    expect(loaded.first.animation.name, 'First renamed');
  });

  test('delete removes only the targeted id', () async {
    final store = CustomAnimationStore();
    const keepId = 'custom_dddd0000-0000-4000-8000-000000000004';
    const killId = 'custom_eeee0000-0000-4000-8000-000000000005';
    await store.save(entry(id: keepId));
    await store.save(entry(id: killId));

    await store.delete(killId);
    var loaded = await store.loadAll();
    expect(loaded.map((e) => e.id), [keepId]);

    await store.delete('custom_does-not-exist');
    loaded = await store.loadAll();
    expect(loaded.map((e) => e.id), [keepId]);
  });

  test('persists across an app restart (fresh instances)', () async {
    final firstRun = CustomAnimationStore();
    const id = 'custom_ffff0000-0000-4000-8000-000000000006';
    await firstRun.save(entry(id: id, name: 'Survivor'));

    final secondRun = CustomAnimationStore();
    final loaded = await secondRun.loadAll();
    expect(loaded.single.id, id);
    expect(loaded.single.animation.name, 'Survivor');

    await secondRun.delete(id);
    expect(await CustomAnimationStore().loadAll(), isEmpty);
  });

  test('a corrupted payload never crashes the load', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(CustomAnimationStore.storageKey, '{not valid json');
    expect(await CustomAnimationStore().loadAll(), isEmpty);

    // One malformed entry among good ones: skip it, keep the rest.
    final mixed = jsonEncode([
      <String, Object?>{'id': 42},
      entry(id: 'custom_abcd0000-0000-4000-8000-000000000007').toJson(),
    ]);
    await prefs.setString(CustomAnimationStore.storageKey, mixed);
    final loaded = await CustomAnimationStore().loadAll();
    expect(loaded.map((e) => e.id),
        ['custom_abcd0000-0000-4000-8000-000000000007']);
  });
}
