/// Curated app catalog for the trigger selection screens (prd-v1.2.md §2,
/// user spec).
///
/// Package names are presence-level identifiers only — nothing is read from
/// these apps (prd-v1.2.md §7).
abstract final class ChatApps {
  /// Apps whose message notifications can fire the **SMS** trigger —
  /// SMS/MMS apps plus the major chat/DM platforms. Shown in the SMS tab;
  /// nothing is selected by default.
  static const Set<String> smsTabApps = {
    // SMS/MMS
    'com.google.android.apps.messaging', // Google Messages
    'com.android.mms', // AOSP / many OEMs
    'com.android.messaging', // AOSP Messaging
    'com.samsung.android.messaging', // Samsung
    'com.oneplus.messaging', // OnePlus
    'com.miui.sms', // Xiaomi
    'com.huawei.msg', // Huawei
    // Chat / DM platforms
    'com.whatsapp', // WhatsApp
    'com.whatsapp.w4b', // WhatsApp Business
    'com.instagram.android', // Instagram
    'com.snapchat.android', // Snapchat
    'org.telegram.messenger', // Telegram
    'com.facebook.orca', // Facebook Messenger
    'org.thoughtcrime.securesms', // Signal
    'com.viber.voip', // Viber
    'com.discord', // Discord
    'com.tencent.mm', // WeChat
    'jp.naver.line.android', // LINE
  };

  /// The Per-app tab lists EVERY installed app EXCEPT the SMS-tab apps
  /// above (messaging apps belong to the SMS tab; no duplicates).
  static bool inPerAppList(String packageName) =>
      packageName.isNotEmpty && !smsTabApps.contains(packageName);
}
