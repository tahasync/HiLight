import 'package:flutter/services.dart';

/// Central haptics gate. [enabled] is synced from the persisted setting by
/// AppSettingsController so every call site stays one line without dragging
/// the controller through the widget tree.
///
/// MVP shipped only `selectionClick` on preset-select/repeat/slider-commit —
/// imperceptible on many devices, and switches/play never buzzed at all.
/// Feedback is now tiered: medium for play/stop, light for toggles,
/// selection ticks for pickers.
abstract final class Haptics {
  static bool enabled = true;

  /// Light tick for selections and picker changes.
  static void selection() {
    if (enabled) HapticFeedback.selectionClick();
  }

  /// Perceptible tap for switches and slider commits.
  static void light() {
    if (enabled) HapticFeedback.lightImpact();
  }

  /// Confident pulse for play/stop.
  static void medium() {
    if (enabled) HapticFeedback.mediumImpact();
  }
}
