/// A single point in a light animation timeline.
///
/// [intensity] is normalized (PRD §11): 0.0 means fully off, 1.0 means the
/// maximum selected brightness. Values are clamped into that range on
/// construction; negative times are clamped to zero.
class LightKeyframe {
  factory LightKeyframe({required Duration time, required double intensity}) {
    return LightKeyframe._(
      time: time < Duration.zero ? Duration.zero : time,
      intensity: intensity.clamp(0.0, 1.0),
    );
  }

  const LightKeyframe._({required this.time, required this.intensity});

  final Duration time;
  final double intensity;

  @override
  String toString() => 'LightKeyframe(${time.inMilliseconds}ms, $intensity)';
}
