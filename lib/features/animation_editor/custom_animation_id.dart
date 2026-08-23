import 'dart:math';

/// Generates ids for user-created animations: `custom_<uuid>` (RFC 4122 v4
/// shape), kept in their own namespace so a future update to the built-in
/// preset set can never collide with something a user made (prd-v1.1.md §3).
String newCustomAnimationId([Random? random]) {
  final rng = random ?? Random.secure();
  String hex(int length) => List.generate(
        length,
        (_) => rng.nextInt(16).toRadixString(16),
      ).join();
  final variant = '89ab'[rng.nextInt(4)];
  return 'custom_${hex(8)}-${hex(4)}-4${hex(3)}-$variant${hex(3)}-${hex(12)}';
}

/// Whether [id] belongs to the user-created namespace.
bool isCustomAnimationId(String id) => id.startsWith('custom_');
