import 'dart:convert';

import 'package:meta/meta.dart';

import 'package:shared_preferences/shared_preferences.dart';

/// A per-contact preset assignment (prd-v1.2.md §2): calls from this contact
/// fire [presetId] instead of the generic incoming-call preset.
@immutable
class ContactOverride {
  const ContactOverride({
    required this.lookupKey,
    required this.displayName,
    required this.number,
    required this.presetId,
  });

  /// ContactsContract lookup key — survives most contact edits.
  final String lookupKey;

  /// Display name shown in Settings only; never used for matching.
  final String displayName;

  /// The picked phone number, stored verbatim; matching normalizes copies.
  final String number;

  final String presetId;

  Map<String, Object?> toJson() => <String, Object?>{
        'lookupKey': lookupKey,
        'displayName': displayName,
        'number': number,
        'presetId': presetId,
      };

  static ContactOverride fromJson(Map<Object?, Object?> json) =>
      ContactOverride(
        lookupKey: json['lookupKey'] as String? ?? '',
        displayName: json['displayName'] as String? ?? '',
        number: json['number'] as String? ?? '',
        presetId: json['presetId'] as String? ?? 'pulse',
      );

  ContactOverride copyWith({
    String? presetId,
    String? displayName,
    String? number,
    String? lookupKey,
  }) =>
      ContactOverride(
        lookupKey: lookupKey ?? this.lookupKey,
        displayName: displayName ?? this.displayName,
        number: number ?? this.number,
        presetId: presetId ?? this.presetId,
      );

  @override
  bool operator ==(Object other) =>
      other is ContactOverride &&
      other.lookupKey == lookupKey &&
      other.number == number &&
      other.presetId == presetId &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(lookupKey, number, presetId, displayName);
}

/// Local-only persistence for per-contact overrides (prd.md §24): one JSON
/// list under a single SharedPreferences key. Malformed entries are skipped,
/// never fatal — mirroring CustomAnimationStore.
class ContactOverrideStore {
  static const storageKey = 'contactOverrides.v1';

  Future<List<ContactOverride>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final result = <ContactOverride>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final override = ContactOverride.fromJson(Map.of(entry));
        // Entries without an identity cannot match anything — drop them.
        if (override.lookupKey.isEmpty || override.number.isEmpty) continue;
        result.add(override);
      }
      return result;
    } catch (_) {
      // A corrupt payload must never take settings down.
      return const [];
    }
  }

  Future<void> saveAll(List<ContactOverride> overrides) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode([for (final o in overrides) o.toJson()]),
    );
  }

  /// Upserts by lookup key, keeping list order stable.
  Future<List<ContactOverride>> upsert(ContactOverride override) async {
    final current = await loadAll();
    final index =
        current.indexWhere((o) => o.lookupKey == override.lookupKey);
    final next = [...current];
    if (index >= 0) {
      next[index] = override;
    } else {
      next.add(override);
    }
    await saveAll(next);
    return next;
  }

  Future<List<ContactOverride>> remove(String lookupKey) async {
    final current = await loadAll();
    final next = [
      for (final o in current)
        if (o.lookupKey != lookupKey) o,
    ];
    await saveAll(next);
    return next;
  }
}
