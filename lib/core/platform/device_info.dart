import 'package:flutter/foundation.dart';

/// Identity of the running device, reported by the OS (PRD §8: the UI must
/// label whichever Android phone it runs on — never a hard-coded model).
@immutable
class DeviceInfo {
  const DeviceInfo({
    required this.deviceModel,
    required this.androidVersion,
  });

  final String deviceModel;
  final String androidVersion;

  factory DeviceInfo.fromMap(Map<Object?, Object?> map) {
    return DeviceInfo(
      deviceModel: map['deviceModel'] as String? ?? 'Unknown device',
      androidVersion: map['androidVersion'] as String? ?? '',
    );
  }
}
