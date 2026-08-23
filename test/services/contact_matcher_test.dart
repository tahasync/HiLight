import 'package:flutter_test/flutter_test.dart';
import 'package:hilight/services/contact_matcher.dart';
import 'package:hilight/services/contact_override_store.dart';

ContactOverride override_({
  String lookupKey = 'lk1',
  String displayName = 'Mom',
  required String number,
  String presetId = 'long_glow',
}) =>
    ContactOverride(
      lookupKey: lookupKey,
      displayName: displayName,
      number: number,
      presetId: presetId,
    );

void main() {
  group('ContactMatcher.normalize', () {
    test('strips scheme, separators, and country-code punctuation', () {
      expect(ContactMatcher.normalize('tel:+1 (555) 123-4567'),
          '15551234567');
      expect(ContactMatcher.normalize('+90-532-000-00-00'), '905320000000');
      expect(ContactMatcher.normalize('0532 000 00 00'), '05320000000');
    });
  });

  group('ContactMatcher.sameNumber', () {
    test('exact normalized equality', () {
      expect(
        ContactMatcher.sameNumber('tel:05321112233', '(0532) 111 22 33'),
        isTrue,
      );
    });

    test('suffix match absorbs country codes for long numbers', () {
      expect(
        ContactMatcher.sameNumber('+905321112233', '05321112233'),
        isTrue,
      );
    });

    test('short numbers never suffix-match (no false hits)', () {
      expect(ContactMatcher.sameNumber('911', '00911'), isFalse);
      expect(
        ContactMatcher.sameNumber('123456', '999123456'),
        isFalse,
      );
    });

    test('local trunk-prefix zero matches its E.164 form (regression)', () {
      // Stored as local format, caller arrives with country code.
      expect(
        ContactMatcher.sameNumber('03146616848', '+923146616848'),
        isTrue,
      );
      expect(
        ContactMatcher.sameNumber('0532 111 22 33', 'tel:+905321112233'),
        isTrue,
      );
      // Trunk-prefix stripping must not create false hits.
      expect(
        ContactMatcher.sameNumber('03146616849', '+923146616848'),
        isFalse,
      );
    });

    test('empty sides never match', () {
      expect(ContactMatcher.sameNumber('', '05321112233'), isFalse);
      expect(ContactMatcher.sameNumber('abc', ''), isFalse);
    });
  });

  group('ContactMatcher.match', () {
    final overrides = [
      override_(lookupKey: 'a', number: '+90 532 111 22 33'),
      override_(lookupKey: 'b', number: '0532 222 33 44', presetId: 'pulse'),
    ];

    test('matches a tel: caller URI against stored numbers', () {
      final match = ContactMatcher.match(
        overrides: overrides,
        callUri: 'tel:+905321112233',
      );
      expect(match?.lookupKey, 'a');
      expect(match?.presetId, 'long_glow');
    });

    test('first matching override wins (deterministic order)', () {
      // Two overrides that both match the caller; list order decides.
      final match = ContactMatcher.match(
        overrides: [
          override_(lookupKey: 'first', number: '5551234567'),
          override_(lookupKey: 'second', number: '+1 555 123 4567'),
        ],
        callUri: 'tel:+15551234567',
      );
      expect(match?.lookupKey, 'first');
    });

    test('returns null for blank or non-tel URIs', () {
      expect(
        ContactMatcher.match(overrides: overrides, callUri: null),
        isNull,
      );
      expect(
        ContactMatcher.match(overrides: overrides, callUri: ''),
        isNull,
      );
      expect(
        ContactMatcher.match(
          overrides: overrides,
          callUri: 'content://contacts/123',
        ),
        isNull,
      );
    });

    test('returns null when no stored number matches', () {
      expect(
        ContactMatcher.match(
          overrides: overrides,
          callUri: 'tel:05329990000',
        ),
        isNull,
      );
    });
  });
}
