import 'dart:async';

import 'package:hilight/core/motion/torch_animator.dart';

/// Records every native call for assertions in engine tests.
class RecordingOutput implements TorchAnimationOutput {
  final List<String> calls = <String>[];
  bool throwOnSetStrength = false;

  List<int> get strengthCalls => [
        for (final call in calls)
          if (call.startsWith('setStrength:')) int.parse(call.split(':')[1]),
      ];
  int get turnOnCalls => calls.where((c) => c == 'turnOn').length;
  int get turnOffCalls => calls.where((c) => c == 'turnOff').length;

  @override
  Future<void> turnOn() async {
    calls.add('turnOn');
  }

  @override
  Future<void> setStrength(int level) async {
    if (throwOnSetStrength) throw StateError('hardware failure');
    calls.add('setStrength:$level');
  }

  @override
  Future<void> turnOff() async {
    calls.add('turnOff');
  }
}

/// Wraps another output and delays acknowledgements, simulating a sluggish
/// camera HAL for the adaptive-carrier test.
class SlowOutput implements TorchAnimationOutput {
  SlowOutput(this._inner, {required int latencyMs})
      : _latency = Duration(milliseconds: latencyMs);

  final TorchAnimationOutput _inner;
  final Duration _latency;

  @override
  Future<void> turnOn() async {
    await Future<void>.delayed(_latency);
    await _inner.turnOn();
  }

  @override
  Future<void> setStrength(int level) => _inner.setStrength(level);

  @override
  Future<void> turnOff() async {
    await Future<void>.delayed(_latency);
    await _inner.turnOff();
  }
}
