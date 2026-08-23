import 'package:flutter/services.dart';

/// Dart facade over the trigger-support platform channel
/// (`hilight/trigger_support`, mirrored in TriggerSupportChannel.kt).
///
/// Notification-listener access is granted exclusively in Android's system
/// settings — there is no runtime dialog API. "Requesting" therefore means
/// opening that screen, which this app does only at the moment the user
/// enables a trigger without access (prd-v1.2.md §2 and the header
/// permissions discipline).
class NotificationAccessService {
  const NotificationAccessService();

  static const MethodChannel _channel = MethodChannel('hilight/trigger_support');

  /// Whether HiLight currently holds notification-listener access.
  ///
  /// Returns false (never throws) when the platform side is missing, so UI
  /// state degrades to "not granted" instead of crashing.
  Future<bool> isGranted() async {
    try {
      return await _channel.invokeMethod<bool>(
            'isNotificationAccessGranted',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens Android's notification-access settings screen.
  Future<void> openSystemSettings() async {
    try {
      await _channel.invokeMethod<void>('openNotificationAccessSettings');
    } on PlatformException {
      // Nothing sensible to do if the settings activity cannot launch; the
      // status tile keeps showing the last known state.
    } on MissingPluginException {
      // Same: non-fatal by contract.
    }
  }
}
