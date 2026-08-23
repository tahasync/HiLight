import 'dart:convert';

import 'package:meta/meta.dart';

import 'package:shared_preferences/shared_preferences.dart';

/// A per-app decision (prd-v1.2.md §3): the user can enable or disable
/// flashing for every single installed app individually, and optionally
/// assign that app its own preset.
///
/// Apps without an entry follow the App-notifications trigger (allowed,
/// generic preset). An entry exists only once the user changes something.
@immutable
class AppOverride {
  const AppOverride({
    required this.packageName,
    required this.appName,
    this.flashEnabled = true,
    this.presetId,
  });

  final String packageName;

  /// Display label captured at listing time; never used for matching.
  final String appName;

  /// Whether this app may flash at all — the per-app enable/disable switch.
  final bool flashEnabled;

  /// Preset assigned to this app; null inherits the generic one.
  final String? presetId;

  Map<String, Object?> toJson() => <String, Object?>{
        'packageName': packageName,
        'appName': appName,
        'flashEnabled': flashEnabled,
        'presetId': presetId,
      };

  static AppOverride fromJson(Map<Object?, Object?> json) => AppOverride(
        packageName: json['packageName'] as String? ?? '',
        appName: json['appName'] as String? ?? '',
        flashEnabled: json['flashEnabled'] as bool? ?? true,
        presetId: json['presetId'] as String?,
      );

  AppOverride copyWith({String? appName, bool? flashEnabled, String? presetId}) =>
      AppOverride(
        packageName: packageName,
        appName: appName ?? this.appName,
        flashEnabled: flashEnabled ?? this.flashEnabled,
        presetId: presetId,
      );

  @override
  bool operator ==(Object other) =>
      other is AppOverride &&
      other.packageName == packageName &&
      other.appName == appName &&
      other.flashEnabled == flashEnabled &&
      other.presetId == presetId;

  @override
  int get hashCode => Object.hash(packageName, appName, flashEnabled, presetId);
}

/// Outcome of matching a notification's package against the table.
@immutable
class AppResolution {
  const AppResolution({required this.allowed, required this.presetId});

  /// Whether this app may flash at all.
  final bool allowed;

  /// App-specific preset, or null to inherit the generic preset.
  final String? presetId;
}

/// Pure gating logic — every rule unit-testable (prd-v1.2.md §3).
abstract final class AppOverrideResolver {
  /// Unlisted apps default to allowed with the generic preset.
  static const defaultResolution = AppResolution(allowed: true, presetId: null);

  static AppResolution resolve({
    required List<AppOverride> overrides,
    required String packageName,
  }) {
    for (final override in overrides) {
      if (override.packageName != packageName) continue;
      if (!override.flashEnabled) {
        return const AppResolution(allowed: false, presetId: null);
      }
      return AppResolution(allowed: true, presetId: override.presetId);
    }
    return defaultResolution;
  }
}

/// Local-only persistence (prd.md §24): entries as one JSON list. Only apps
/// the user explicitly changed get an entry. Malformed entries are skipped,
/// never fatal.
class AppOverrideStore {
  static const storageKey = 'appOverrides.v1';

  Future<List<AppOverride>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final result = <AppOverride>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final override = AppOverride.fromJson(Map.of(entry));
        // Entries without a package cannot match anything — drop them.
        if (override.packageName.isEmpty) continue;
        result.add(override);
      }
      return result;
    } catch (_) {
      // A corrupt payload must never take settings down.
      return const [];
    }
  }

  Future<void> saveAll(List<AppOverride> overrides) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode([for (final o in overrides) o.toJson()]),
    );
  }

  /// Upserts by package name, keeping list order stable.
  Future<List<AppOverride>> upsert(AppOverride override) async {
    final current = await loadAll();
    final index =
        current.indexWhere((o) => o.packageName == override.packageName);
    final next = [...current];
    if (index >= 0) {
      next[index] = override;
    } else {
      next.add(override);
    }
    await saveAll(next);
    return next;
  }

  /// Removes the entry entirely — the app returns to default behavior.
  Future<List<AppOverride>> reset(String packageName) async {
    final current = await loadAll();
    final next = [
      for (final o in current)
        if (o.packageName != packageName) o,
    ];
    await saveAll(next);
    return next;
  }
}
