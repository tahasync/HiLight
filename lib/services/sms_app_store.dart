import 'dart:convert';

import 'notification_trigger_classifier.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-app selection for the SMS trigger (prd-v1.2.md §2, user spec):
/// apps whose "msg"-labeled notifications actually fire the trigger.
///
/// The known messaging apps are SHOWN in the selection screen by default,
/// but NOTHING is selected until the user picks apps manually — with an
/// empty selection no SMS flash fires at all. Package names are
/// presence-level data only (prd-v1.2.md §7).
class SmsAppStore {
  static const storageKey = 'smsApps.v1';

  Future<Set<String>> loadSelected() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return {
        for (final entry in decoded)
          if (entry is String && entry.isNotEmpty) entry,
      };
    } catch (_) {
      // A corrupt payload must never take settings down.
      return <String>{};
    }
  }

  Future<void> saveSelected(Set<String> packages) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      jsonEncode(packages.toList()..sort()),
    );
  }

  /// Convenience for the selection screen: whether [packageName] should
  /// start checked. Nothing is selected by default.
  Future<bool> isSelected(String packageName) async {
    if (packageName.isEmpty) return false;
    return loadSelected().then((set) => set.contains(packageName));
  }

  Future<Set<String>> toggle(String packageName, {required bool on}) async {
    final current = await loadSelected();
    final next = {...current};
    on ? next.add(packageName) : next.remove(packageName);
    await saveSelected(next);
    return next;
  }

  /// Whether [packageName] is one of the known messaging apps — used by the
  /// selection screen to group them at the top.
  static bool isKnownMessagingApp(String packageName) =>
      NotificationTriggers.knownSmsPackages.contains(packageName);
}
