/// Charging-effect configuration (prd-v1.2.md §4 as amended by product
/// decision): master toggle, animate-on-connect, animate-on-disconnect,
/// and five battery-milestone presets — all independent, no periodic
/// repeat while charging.
library;

/// Milestone levels, ascending. Each fires once per charging session when
/// the battery level crosses upward past it; plugging in already above a
/// threshold consumes it silently.
const List<int> kChargingMilestoneLevels = <int>[20, 35, 50, 70, 100];

class MilestoneConfig {
  const MilestoneConfig({
    required this.enabled,
    required this.presetId,
  });

  final bool enabled;
  final String presetId;

  MilestoneConfig copyWith({bool? enabled, String? presetId}) =>
      MilestoneConfig(
        enabled: enabled ?? this.enabled,
        presetId: presetId ?? this.presetId,
      );

  @override
  bool operator ==(Object other) =>
      other is MilestoneConfig &&
      other.enabled == enabled &&
      other.presetId == presetId;

  @override
  int get hashCode => Object.hash(enabled, presetId);
}

class ChargingConfig {
  const ChargingConfig({
    required this.masterEnabled,
    required this.animateOnConnect,
    required this.connectPresetId,
    required this.animateOnDisconnect,
    required this.disconnectPresetId,
    required this.milestones,
  });

  final bool masterEnabled;

  final bool animateOnConnect;
  final String connectPresetId;

  final bool animateOnDisconnect;
  final String disconnectPresetId;

  /// Keyed by milestone level (20/35/50/70/100).
  final Map<int, MilestoneConfig> milestones;

  MilestoneConfig milestoneAt(int level) =>
      milestones[level] ??
      const MilestoneConfig(enabled: false, presetId: 'pulse');

  ChargingConfig copyWith({
    bool? masterEnabled,
    bool? animateOnConnect,
    String? connectPresetId,
    bool? animateOnDisconnect,
    String? disconnectPresetId,
  }) =>
      ChargingConfig(
        masterEnabled: masterEnabled ?? this.masterEnabled,
        animateOnConnect: animateOnConnect ?? this.animateOnConnect,
        connectPresetId: connectPresetId ?? this.connectPresetId,
        animateOnDisconnect: animateOnDisconnect ?? this.animateOnDisconnect,
        disconnectPresetId: disconnectPresetId ?? this.disconnectPresetId,
        milestones: milestones,
      );

  @override
  bool operator ==(Object other) =>
      other is ChargingConfig &&
      other.masterEnabled == masterEnabled &&
      other.animateOnConnect == animateOnConnect &&
      other.connectPresetId == connectPresetId &&
      other.animateOnDisconnect == animateOnDisconnect &&
      other.disconnectPresetId == disconnectPresetId &&
      other.milestones.length == milestones.length;

  @override
  int get hashCode => Object.hash(masterEnabled, animateOnConnect,
      connectPresetId, animateOnDisconnect, disconnectPresetId);
}

ChargingConfig defaultChargingConfig() => ChargingConfig(
      masterEnabled: false,
      animateOnConnect: false,
      connectPresetId: 'soft_glow',
      animateOnDisconnect: false,
      disconnectPresetId: 'pulse',
      milestones: {
        for (final level in kChargingMilestoneLevels)
          level: const MilestoneConfig(enabled: false, presetId: 'pulse'),
      },
    );

/// Pure milestone bookkeeping — unit-testable without Android.
abstract final class ChargingMilestones {
  /// Thresholds at or below the plug-in level are consumed silently (no
  /// double-fire with the connect animation).
  static Set<int> consumedAtConnect(int connectLevel) => {
        for (final level in kChargingMilestoneLevels)
          if (connectLevel >= level) level,
      };

  /// The next threshold to fire for [currentLevel], or null. Only
  /// thresholds strictly above the plug-in level can fire — crossing
  /// upward during the session.
  static int? nextToFire({
    required int connectLevel,
    required Set<int> consumed,
    required int currentLevel,
  }) {
    for (final level in kChargingMilestoneLevels) {
      if (currentLevel >= level &&
          level > connectLevel &&
          !consumed.contains(level)) {
        return level;
      }
    }
    return null;
  }
}
