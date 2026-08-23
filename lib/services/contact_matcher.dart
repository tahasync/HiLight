import 'contact_override_store.dart';

/// Pure caller-to-contact matching for per-contact overrides
/// (prd-v1.2.md §2). Dependency-free so every rule is unit-testable.
abstract final class ContactMatcher {
  /// Strips everything but digits (country codes, spaces, dashes, and the
  /// `tel:` scheme all collapse away).
  static String normalize(String raw) =>
      raw.replaceAll(RegExp(r'[^0-9]'), '');

  /// Whether [a] and [b] refer to the same phone number.
  ///
  /// Exact normalized equality, or a suffix match where the shorter side has
  /// at least [_minSuffixDigits] digits — enough to absorb country-code
  /// differences without risking short-code false hits (e.g. "911").
  ///
  /// Trunk prefixes are also handled: many users store local-format numbers
  /// ("0314…") while callers arrive as E.164 ("+92314…"), so a single
  /// leading zero is ignored on either side before comparing.
  static bool sameNumber(String a, String b) {
    for (final va in _digitVariants(normalize(a))) {
      for (final vb in _digitVariants(normalize(b))) {
        if (_sameDigits(va, vb)) return true;
      }
    }
    return false;
  }

  /// Shortest digit count eligible for suffix matching.
  static const int minSuffixDigits = 7;

  static Iterable<String> _digitVariants(String digits) sync* {
    if (digits.isEmpty) return;
    yield digits;
    if (digits.startsWith('0') && digits.length > minSuffixDigits) {
      yield digits.substring(1);
    }
  }

  static bool _sameDigits(String na, String nb) {
    if (na.isEmpty || nb.isEmpty) return false;
    if (na == nb) return true;
    final shorter = na.length < nb.length ? na : nb;
    final longer = na.length < nb.length ? nb : na;
    if (shorter.length < minSuffixDigits) return false;
    return longer.endsWith(shorter);
  }

  /// Finds the override matching a caller URI from a CallStyle notification
  /// (`tel:…` or blank). First match in list order wins — deterministic.
  static ContactOverride? match({
    required List<ContactOverride> overrides,
    required String? callUri,
  }) {
    if (callUri == null || callUri.isEmpty) return null;
    // A tel: URI carries the number; anything else cannot be matched here.
    if (!callUri.startsWith('tel:')) return null;
    for (final override in overrides) {
      if (override.number.isEmpty) continue;
      if (sameNumber(callUri.substring(4), override.number)) {
        return override;
      }
    }
    return null;
  }
}
