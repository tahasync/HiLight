import 'package:flutter/foundation.dart';

import '../core/motion/easing.dart';
import '../core/motion/preset_definitions.dart';
import '../core/motion/torch_animator.dart';
import '../core/platform/torch_capability.dart';
import '../features/animation_editor/custom_animation_store.dart';
import 'animation_service.dart';
import 'playback_coordinator.dart';
import 'preferences_service.dart';
import 'torch_service.dart';

/// Starts and stops the default animation on behalf of the Quick Settings
/// tile (prd-v1.1.md §4): the preset saved as the default (Settings →
/// Animation → Default preset), at the user's saved brightness, speed, and
/// repeat — through the same engine path used everywhere else.
class TilePlaybackController {
  TilePlaybackController({
    PreferencesService? preferences,
    CustomAnimationStore? store,
    TorchAnimationOutput? output,
    Future<TorchCapability?> Function()? capabilities,
  })  : _preferences = preferences ?? PreferencesService(),
        _store = store ?? CustomAnimationStore(),
        _output = output ?? AnimationService(TorchService()),
        _capabilities = capabilities ??
            (() async {
              try {
                return await TorchService().getCapabilities();
              } catch (_) {
                return null;
              }
            });

  final PreferencesService _preferences;
  final CustomAnimationStore _store;
  final TorchAnimationOutput _output;
  final Future<TorchCapability?> Function() _capabilities;

  Object get _token => this;

  TorchAnimator _animator = TorchAnimator(output: _placeholder);
  static final _NeverOutput _placeholder = _NeverOutput();

  /// Registers itself with the [PlaybackCoordinator]; call once per isolate.
  void register() {
    PlaybackCoordinator.instance.registerExternalStart(() => toggle());
    PlaybackCoordinator.instance.registerTileStop(() async {
      await PlaybackCoordinator.instance.requestStop(_token);
    });
  }

  Future<void> toggle() async {
    if (PlaybackCoordinator.instance.isActive) return; // stop hook handles it
    await _startDefault();
  }

  Future<void> _startDefault() async {
    final capability = await _capabilities();
    if (kDebugMode) {
      print('HiLight tile: toggle, torchAvailable='
          '${capability?.torchAvailable}');
    }
    if (capability == null || !capability.torchAvailable) {
      // Torch unavailable or busy: the tile stays idle (§4); the reason is
      // visible in the app's diagnostics screen.
      return;
    }
    final snapshot = await _preferences.loadAll();
    var animation = builtinPresetById(snapshot.presetId) ?? kPulsePreset;
    var easing = Easing.linear;
    try {
      for (final custom in await _store.loadAll()) {
        if (custom.id == snapshot.presetId) {
          animation = custom.animation;
          easing = custom.easing;
        }
      }
    } catch (_) {
      // Custom lookup must never block the built-in default from playing.
    }
    final maxLevel = capability.supportsStrength
        ? capability.maxStrengthLevel
        : 1;
    _animator.dispose();
    _animator = TorchAnimator(output: _output);
    _animator.play(
      animation: animation,
      maxStrengthLevel: maxLevel,
      brightness: snapshot.brightness,
      speed: snapshot.speed,
      repeatCount: snapshot.repeatCount,
      easing: easing,
      onComplete: () => PlaybackCoordinator.instance.endOwnership(_token),
      onError: (Object error) =>
          PlaybackCoordinator.instance.endOwnership(_token),
    );
    PlaybackCoordinator.instance.beginOwnership(_token, () async {
      _animator.cancel();
      PlaybackCoordinator.instance.endOwnership(_token);
    });
  }
}

/// Output that never emits; placeholder while no playback is active.
class _NeverOutput implements TorchAnimationOutput {
  @override
  Future<void> turnOn() async {}

  @override
  Future<void> setStrength(int level) async {}

  @override
  Future<void> turnOff() async {}
}
