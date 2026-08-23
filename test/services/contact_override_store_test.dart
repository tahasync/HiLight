import 'package:flutter_test/flutter_test.dart';
import 'package:hilight/services/contact_override_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const key = ContactOverrideStore.storageKey;

  group('ContactOverrideStore (prd-v1.2.md §2, prd.md §24)', () {
    test('empty when nothing stored', () async {
      SharedPreferences.setMockInitialValues(const {});
      expect(await ContactOverrideStore().loadAll(), isEmpty);
    });

    test('upsert adds then updates by lookup key', () async {
      SharedPreferences.setMockInitialValues(const {});
      final store = ContactOverrideStore();

      await store.upsert(const ContactOverride(
        lookupKey: 'lk1',
        displayName: 'Mom',
        number: '+90 532 111 22 33',
        presetId: 'long_glow',
      ));
      await store.upsert(const ContactOverride(
        lookupKey: 'lk2',
        displayName: 'Dad',
        number: '0532 222 33 44',
        presetId: 'pulse',
      ));

      var all = await store.loadAll();
      expect(all, hasLength(2));

      // Same lookup key replaces in place.
      await store.upsert(const ContactOverride(
        lookupKey: 'lk1',
        displayName: 'Mom',
        number: '+90 532 111 22 33',
        presetId: 'quick_flash',
      ));
      all = await store.loadAll();
      expect(all, hasLength(2));
      expect(all.firstWhere((o) => o.lookupKey == 'lk1').presetId,
          'quick_flash');
    });

    test('remove deletes only the target entry', () async {
      SharedPreferences.setMockInitialValues({
        key: '''
[
  {"lookupKey":"lk1","displayName":"Mom","number":"05321112233","presetId":"pulse"},
  {"lookupKey":"lk2","displayName":"Dad","number":"05322223344","presetId":"breathing"}
]
''',
      });
      final store = ContactOverrideStore();

      final next = await store.remove('lk1');

      expect(next, hasLength(1));
      expect(next.single.lookupKey, 'lk2');
      expect((await store.loadAll()).single.displayName, 'Dad');
    });

    test('malformed entries are skipped, never fatal', () async {
      SharedPreferences.setMockInitialValues({
        key: '''
[
  {"lookupKey":"ok1","displayName":"A","number":"1234567890","presetId":"pulse"},
  {"displayName":"missing lookup and number"},
  "not even an object",
  {"lookupKey":"ok2","displayName":"B","number":"0987654321","presetId":"breathing"}
]
''',
      });

      final all = await ContactOverrideStore().loadAll();

      expect(all.map((o) => o.lookupKey), ['ok1', 'ok2']);
    });

    test('a corrupt payload yields an empty list instead of throwing',
        () async {
      SharedPreferences.setMockInitialValues({key: '{not json['});
      expect(await ContactOverrideStore().loadAll(), isEmpty);
    });
  });
}
