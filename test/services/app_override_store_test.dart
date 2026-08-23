import 'package:flutter_test/flutter_test.dart';
import 'package:hilight/services/app_override_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppOverride entry({
  String packageName = 'com.example.app',
  String appName = 'Example',
  bool flashEnabled = true,
  String? presetId,
}) =>
    AppOverride(
      packageName: packageName,
      appName: appName,
      flashEnabled: flashEnabled,
      presetId: presetId,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppOverrideResolver (prd-v1.2.md §3)', () {
    test('unlisted apps follow the trigger: allowed, generic preset', () {
      final resolution = AppOverrideResolver.resolve(
        overrides: const [],
        packageName: 'com.whatsapp',
      );
      expect(resolution.allowed, isTrue);
      expect(resolution.presetId, isNull);
    });

    test('a disabled app is blocked even when its trigger is enabled', () {
      final resolution = AppOverrideResolver.resolve(
        overrides: [entry(packageName: 'com.whatsapp', flashEnabled: false)],
        packageName: 'com.whatsapp',
      );
      expect(resolution.allowed, isFalse);
    });

    test('an enabled app with its own preset resolves that preset', () {
      final resolution = AppOverrideResolver.resolve(
        overrides: [
          entry(
            packageName: 'com.whatsapp',
            presetId: 'heartbeat',
          ),
        ],
        packageName: 'com.whatsapp',
      );
      expect(resolution.allowed, isTrue);
      expect(resolution.presetId, 'heartbeat');
    });

    test('an enabled app without a preset inherits the generic one', () {
      final resolution = AppOverrideResolver.resolve(
        overrides: [entry(packageName: 'com.whatsapp')],
        packageName: 'com.whatsapp',
      );
      expect(resolution.allowed, isTrue);
      expect(resolution.presetId, isNull);
    });

    test('matching is exact by package name', () {
      final resolution = AppOverrideResolver.resolve(
        overrides: [entry(packageName: 'com.whatsapp')],
        packageName: 'com.whatsapp.w4b',
      );
      expect(resolution.allowed, isTrue);
      expect(resolution.presetId, isNull);
    });
  });

  group('AppOverrideStore (prd.md §24)', () {
    test('round-trips entries and skips malformed ones', () async {
      SharedPreferences.setMockInitialValues(const {
        AppOverrideStore.storageKey: '''
[
  {"packageName":"com.a","appName":"A","flashEnabled":false,"presetId":null},
  {"appName":"missing package"},
  {"packageName":"com.b","appName":"B","flashEnabled":true,"presetId":"pulse"}
]
''',
      });
      final all = await AppOverrideStore().loadAll();
      expect(all.map((o) => o.packageName), ['com.a', 'com.b']);
      expect(all.first.flashEnabled, isFalse);
    });

    test('upsert updates in place; reset removes the entry', () async {
      SharedPreferences.setMockInitialValues(const {});
      final store = AppOverrideStore();

      await store.upsert(entry(packageName: 'com.a', presetId: 'pulse'));
      await store.upsert(entry(packageName: 'com.a', presetId: 'breathing'));
      expect((await store.loadAll()).single.presetId, 'breathing');

      await store.reset('com.a');
      expect(await store.loadAll(), isEmpty);
    });

    test('a corrupt payload yields an empty list', () async {
      SharedPreferences.setMockInitialValues(
          const {AppOverrideStore.storageKey: 'nope['});
      expect(await AppOverrideStore().loadAll(), isEmpty);
    });
  });
}
