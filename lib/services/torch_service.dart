import 'package:flutter/services.dart';

import '../core/platform/device_info.dart';
import '../core/platform/torch_capability.dart';
import '../core/platform/torch_exception.dart';

/// Dart facade over the native torch layer.
///
/// Channel contract (mirrored in TorchChannel.kt):
///  - getCapabilities -> Map -> TorchCapability
///  - turnOn          -> void
///  - turnOff         -> void
///  - setStrength     -> { level: int } -> void
///  - getStrength     -> int
///
/// Every failure is surfaced as [TorchException]; raw platform exceptions are
/// never rethrown to callers.
class TorchService {
  static const MethodChannel _channel = MethodChannel('hilight/torch');

  /// Reads the rear-flash capability of the running device.
  Future<TorchCapability> getCapabilities() async {
    final map = await _invoke<Map<Object?, Object?>>('getCapabilities');
    return TorchCapability.fromMap(map);
  }

  /// Reads the device identity reported by the OS.
  Future<DeviceInfo> getDeviceInfo() async {
    final map = await _invoke<Map<Object?, Object?>>('getDeviceInfo');
    return DeviceInfo.fromMap(map);
  }

  /// Turns the torch on at the device's default brightness level.
  Future<void> turnOn() => _invoke('turnOn');

  /// Turns the torch off. Safe to call repeatedly.
  Future<void> turnOff() => _invoke('turnOff');

  /// Sets the torch brightness level, turning it on if it was off.
  ///
  /// [level] must be within 1..TorchCapability.maxStrengthLevel; values
  /// outside that range raise a [TorchException] with code `invalidArgument`.
  Future<void> setStrength(int level) =>
      _invoke('setStrength', <String, Object?>{'level': level});

  /// Returns the current torch strength level, or the device default while
  /// the torch is off.
  Future<int> getStrength() => _invoke<int>('getStrength');

  Future<T> _invoke<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      final result = await _channel.invokeMethod<T>(method, arguments);
      return result as T;
    } on PlatformException catch (error) {
      throw TorchException(
        error.code,
        error.message ?? 'Torch operation "$method" failed.',
      );
    } on MissingPluginException {
      throw const TorchException(
        'notSupported',
        'The torch layer is unavailable on this platform.',
      );
    }
  }
}
