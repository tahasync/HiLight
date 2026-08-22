import 'hilight_animation.dart';
import 'light_keyframe.dart';

LightKeyframe _kf(int ms, double intensity) =>
    LightKeyframe(time: Duration(milliseconds: ms), intensity: intensity);

/// The five MVP presets (PRD §12). This file is their single canonical home
/// (PRD §28): the preset picker UI, the animation engine, and all tests must
/// import these definitions instead of restating keyframe numbers.
///
/// Every table below is normalized intensity (0.0–1.0) against elapsed
/// milliseconds, copied verbatim from PRD §12.

final HilightAnimation kPulsePreset = HilightAnimation(
  id: 'pulse',
  name: 'Pulse',
  duration: const Duration(milliseconds: 800),
  keyframes: [
    _kf(0, 0.00),
    _kf(100, 0.20),
    _kf(300, 1.00),
    _kf(500, 0.30),
    _kf(800, 0.00),
  ],
);

final HilightAnimation kBreathingPreset = HilightAnimation(
  id: 'breathing',
  name: 'Breathing',
  duration: const Duration(milliseconds: 3200),
  keyframes: [
    _kf(0, 0.00),
    _kf(500, 0.15),
    _kf(1200, 0.45),
    _kf(1600, 1.00),
    _kf(2000, 0.45),
    _kf(2700, 0.15),
    _kf(3200, 0.00),
  ],
);

final HilightAnimation kDoublePulsePreset = HilightAnimation(
  id: 'double_pulse',
  name: 'Double Pulse',
  duration: const Duration(milliseconds: 1800),
  keyframes: [
    _kf(0, 0.00),
    _kf(100, 0.20),
    _kf(300, 1.00),
    _kf(500, 0.30),
    _kf(800, 0.00),
    _kf(1000, 0.00),
    _kf(1100, 0.20),
    _kf(1300, 1.00),
    _kf(1500, 0.30),
    _kf(1800, 0.00),
  ],
);

final HilightAnimation kSoftGlowPreset = HilightAnimation(
  id: 'soft_glow',
  name: 'Soft Glow',
  duration: const Duration(milliseconds: 2400),
  keyframes: [
    _kf(0, 0.00),
    _kf(1000, 1.00),
    _kf(1300, 1.00),
    _kf(2400, 0.00),
  ],
);

final HilightAnimation kHeartbeatPreset = HilightAnimation(
  id: 'heartbeat',
  name: 'Heartbeat',
  duration: const Duration(milliseconds: 1100),
  keyframes: [
    _kf(0, 0.00),
    _kf(80, 1.00),
    _kf(180, 0.20),
    _kf(260, 0.00),
    _kf(340, 0.85),
    _kf(440, 0.15),
    _kf(520, 0.00),
    _kf(1100, 0.00),
  ],
);

/// Ordered list of the MVP presets in display order.
final List<HilightAnimation> kMvpPresets = [
  kPulsePreset,
  kBreathingPreset,
  kDoublePulsePreset,
  kSoftGlowPreset,
  kHeartbeatPreset,
];

/// Looks up an MVP preset by its stable [id], or returns null.
HilightAnimation? mvpPresetById(String id) {
  for (final preset in kMvpPresets) {
    if (preset.id == id) return preset;
  }
  return null;
}
