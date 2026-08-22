import 'package:flutter/foundation.dart';

/// Hardware capability of the device's rear flash, as reported by the native
/// torch layer over the `hilight/torch` platform channel.
@immutable
class TorchCapability {
  const TorchCapability({
    required this.cameraId,
    required this.hasFlash,
    required this.torchAvailable,
    required this.supportsStrength,
    required this.maxStrengthLevel,
  });

  /// Platform camera ID owning the flash unit, or null when no flash exists.
  final String? cameraId;
  final bool hasFlash;
  final bool torchAvailable;

  /// True only when the device supports adjustable torch strength
  /// (maxStrengthLevel > 1); otherwise only ON/OFF is available.
  final bool supportsStrength;
  final int maxStrengthLevel;

  factory TorchCapability.fromMap(Map<Object?, Object?> map) {
    return TorchCapability(
      cameraId: map['cameraId'] as String?,
      hasFlash: map['hasFlash'] as bool? ?? false,
      torchAvailable: map['torchAvailable'] as bool? ?? false,
      supportsStrength: map['supportsStrength'] as bool? ?? false,
      maxStrengthLevel: map['maxStrengthLevel'] as int? ?? 0,
    );
  }

  @override
  String toString() =>
      'TorchCapability(cameraId: $cameraId, hasFlash: $hasFlash, '
      'torchAvailable: $torchAvailable, supportsStrength: $supportsStrength, '
      'maxStrengthLevel: $maxStrengthLevel)';
}
