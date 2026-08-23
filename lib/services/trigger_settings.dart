import 'notification_trigger_classifier.dart';

/// Per-trigger persisted configuration (prd-v1.2.md §2/§5).
class TriggerConfig {
  const TriggerConfig({
    required this.enabled,
    required this.presetId,
  });

  final bool enabled;
  final String presetId;

  TriggerConfig copyWith({bool? enabled, String? presetId}) => TriggerConfig(
        enabled: enabled ?? this.enabled,
        presetId: presetId ?? this.presetId,
      );

  @override
  bool operator ==(Object other) =>
      other is TriggerConfig &&
      other.enabled == enabled &&
      other.presetId == presetId;

  @override
  int get hashCode => Object.hash(enabled, presetId);
}

/// Proposed default preset per trigger (prd-v1.2.md §2 leaves the choice to
/// the user; these are starting values only). Rhythms chosen so adjacent
/// triggers are distinguishable by ear-free pattern: short burst for calls,
/// single swell for messages, triple beat for alarms, heartbeat for timers.
TriggerConfig defaultTriggerConfig(TriggerKind kind) => switch (kind) {
      TriggerKind.incomingCall =>
        const TriggerConfig(enabled: false, presetId: 'quick_flash'),
      TriggerKind.sms =>
        const TriggerConfig(enabled: false, presetId: 'pulse'),
      TriggerKind.alarm =>
        const TriggerConfig(enabled: false, presetId: 'triple_pulse'),
      TriggerKind.timer =>
        const TriggerConfig(enabled: false, presetId: 'heartbeat'),
      TriggerKind.appNotification =>
        const TriggerConfig(enabled: false, presetId: 'pulse'),
    };

/// Every trigger in stable Settings display order.
const List<TriggerKind> kTriggerKinds = <TriggerKind>[
  TriggerKind.incomingCall,
  TriggerKind.sms,
  TriggerKind.alarm,
  TriggerKind.timer,
  TriggerKind.appNotification,
];
