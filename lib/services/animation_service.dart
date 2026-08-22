import '../core/motion/torch_animator.dart';
import 'torch_service.dart';

/// Adapter that lets the animation engine drive the physical torch through
/// the platform channel.
class AnimationService implements TorchAnimationOutput {
  AnimationService(this._torchService);

  final TorchService _torchService;

  @override
  Future<void> turnOn() => _torchService.turnOn();

  @override
  Future<void> setStrength(int level) => _torchService.setStrength(level);

  @override
  Future<void> turnOff() => _torchService.turnOff();
}
