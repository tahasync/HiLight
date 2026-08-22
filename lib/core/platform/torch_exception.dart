/// Typed failure raised by [TorchService] when a native torch operation
/// cannot be completed. Native exceptions never leak past the service as raw
/// platform errors; they are always converted to this type.
class TorchException implements Exception {
  const TorchException(this.code, this.message);

  /// Stable machine-readable error code, e.g. `cameraInUse`, `noFlash`,
  /// `invalidArgument`. Mirrors the codes documented on the native side of
  /// the `hilight/torch` channel.
  final String code;

  /// Human-readable description suitable for diagnostics or UI display.
  final String message;

  @override
  String toString() => 'TorchException($code): $message';
}
