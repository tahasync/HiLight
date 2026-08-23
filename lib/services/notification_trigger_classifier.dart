/// Classification of incoming notifications into HiLight trigger kinds
/// (prd-v1.2.md §2).
///
/// Pure, dependency-free logic so every rule is unit-testable: the native
/// listener only forwards presence-level metadata (category, posting
/// package, ongoing flag) and never message text or sender details
/// (prd-v1.2.md §7).
///
/// Category string values verified against the android.app.Notification
/// reference (API 35): CATEGORY_CALL = "call", CATEGORY_MESSAGE = "msg",
/// CATEGORY_ALARM = "alarm" — documented as "alarm or timer", i.e. the
/// platform itself does not distinguish the two — and
/// CATEGORY_STOPWATCH = "stopwatch" (API 31). There is no dedicated timer
/// category, so the alarm/timer split below is a documented fallback, not a
/// platform guarantee.
library;

enum TriggerKind {
  incomingCall,
  sms,
  alarm,
  timer,
  appNotification,
}

/// Human-readable names used by the Settings UI.
extension TriggerKindLabel on TriggerKind {
  String get label => switch (this) {
        TriggerKind.incomingCall => 'Incoming call',
        TriggerKind.sms => 'SMS',
        TriggerKind.alarm => 'Alarm',
        TriggerKind.timer => 'Timer',
        TriggerKind.appNotification => 'App notifications',
      };
}

/// Presence-level metadata extracted from a status-bar notification.
class NotificationEvent {
  const NotificationEvent({
    this.category,
    required this.packageName,
    required this.isOngoing,
    this.callUri,
    this.hasCallPerson = false,
    this.removed = false,
  });

  /// `Notification.CATEGORY_*` value, or null when the poster set none.
  final String? category;

  /// Package that posted the notification (never HiLight itself; the native
  /// side filters its own notifications out).
  final String packageName;

  /// Whether the notification is ongoing (progress bars, media playback,
  /// foreground services) — never treated as an app-notification trigger.
  final bool isOngoing;

  /// Caller URI (`tel:…`) extracted from a CallStyle ring notification;
  /// used only for per-contact matching (prd-v1.2.md §2/§7).
  final String? callUri;

  /// Whether the notification carried a caller-Person extra at all
  /// (diagnostics only; never exposes its value).
  final bool hasCallPerson;

  /// Removal event: the notification went away (e.g. a ringing call was
  /// answered or declined) — ends any looping playback for it.
  final bool removed;
}

abstract final class NotificationTriggers {
  // Verified android.app.Notification.CATEGORY_* values.
  static const categoryCall = 'call';
  static const categoryMissedCall = 'missed_call';
  static const categoryMessage = 'msg';
  static const categoryAlarm = 'alarm';
  static const categoryStopwatch = 'stopwatch';

  /// Messaging/telephony apps whose "msg"-labeled notifications count as
  /// SMS/MMS. Chat platforms (WhatsApp, Snapchat, Instagram…) also label
  /// messages "msg"; without this restriction the SMS trigger flashed on
  /// every DM even with App-notifications disabled (observed live). Package
  /// names are presence-level data only — no content is read (§7).
  static const knownSmsPackages = <String>{
    'com.google.android.apps.messaging', // Google Messages
    'com.android.mms', // AOSP / many OEMs
    'com.android.messaging', // AOSP Messaging
    'com.samsung.android.messaging', // Samsung
    'com.oneplus.messaging', // OnePlus
    'com.android.contacts', // some OEM SMS handlers
    'com.miui.sms', // Xiaomi
    'com.huawei.msg', // Huawei
  };

  /// Reserved platform categories that describe device state or media
  /// transport rather than an alert worth flashing for.
  static const _silentCategories = <String>{
    categoryMissedCall,
    categoryStopwatch,
    'sys', // CATEGORY_SYSTEM
    'service', // CATEGORY_SERVICE
    'status', // CATEGORY_STATUS
    'transport', // CATEGORY_TRANSPORT (media playback controls)
    'progress', // CATEGORY_PROGRESS
  };

  /// Resolves which trigger [event] fires, honoring which triggers are
  /// enabled via [isEnabled]; returns null when nothing applies.
  ///
  /// Rules — categories decide the kind, packages gate SMS fidelity
  /// (prd-v1.2.md §2):
  ///  - category "call" -> incoming call ("missed_call" deliberately does
  ///    not fire: the flash belongs to the ring moment);
  ///  - category "msg" -> SMS **only for known messaging/telephony apps**;
  ///    any other app's "msg" notification is treated as a generic app
  ///    notification so chat platforms stay silent when that trigger is
  ///    disabled;
  ///  - category "alarm" -> alarm trigger, falling back to the timer trigger
  ///    when alarm is off (the platform merges both under one category —
  ///    surfaced honestly in Settings rather than promised otherwise);
  ///  - "stopwatch" and other reserved state/transport categories -> none;
  ///  - everything else fires the generic app-notification trigger, but
  ///    only for non-ongoing notifications so media playback, downloads,
  ///    and progress bars stay quiet.
  static TriggerKind? resolve(
    NotificationEvent event,
    bool Function(TriggerKind kind) isEnabled,
  ) {
    switch (event.category) {
      case categoryCall:
        return isEnabled(TriggerKind.incomingCall)
            ? TriggerKind.incomingCall
            : null;
      case categoryMessage:
        if (!knownSmsPackages.contains(event.packageName)) {
          break; // chat-app "msg": generic path decides below
        }
        return isEnabled(TriggerKind.sms) ? TriggerKind.sms : null;
      case categoryAlarm:
        if (isEnabled(TriggerKind.alarm)) return TriggerKind.alarm;
        if (isEnabled(TriggerKind.timer)) return TriggerKind.timer;
        return null;
      default:
        break;
    }
    if (_silentCategories.contains(event.category)) return null;
    if (event.isOngoing) return null;
    return isEnabled(TriggerKind.appNotification)
        ? TriggerKind.appNotification
        : null;
  }
}
