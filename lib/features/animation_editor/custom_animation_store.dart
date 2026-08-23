import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'stored_custom_animation.dart';

/// Local-only persistence for user-created animations (prd-v1.1.md §3),
/// using the same mechanism as settings (PRD §19/§24): a JSON list under one
/// SharedPreferences key. No account, no cloud.
class CustomAnimationStore {
  static const storageKey = 'customAnimations.v1';

  Future<List<StoredCustomAnimation>> loadAll() async {
    final raw =
        (await SharedPreferences.getInstance()).getString(storageKey);
    if (raw == null || raw.isEmpty) return const [];
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
    if (decoded is! List) return const [];
    final entries = <StoredCustomAnimation>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      try {
        entries.add(StoredCustomAnimation.fromJson(
          Map<String, Object?>.from(item),
        ));
      } catch (_) {
        // A malformed entry is skipped rather than taking down the load.
      }
    }
    return entries;
  }

  /// Saves [entry], replacing an existing entry with the same id in place.
  Future<void> save(StoredCustomAnimation entry) async {
    final entries = [...await loadAll()];
    final index = entries.indexWhere((e) => e.id == entry.id);
    if (index >= 0) {
      entries[index] = entry;
    } else {
      entries.add(entry);
    }
    await _writeAll(entries);
  }

  Future<void> delete(String id) async {
    final entries = [...await loadAll()]..removeWhere((e) => e.id == id);
    await _writeAll(entries);
  }

  Future<void> _writeAll(List<StoredCustomAnimation> entries) async {
    final raw = jsonEncode(<Object?>[for (final e in entries) e.toJson()]);
    await (await SharedPreferences.getInstance()).setString(storageKey, raw);
  }
}
