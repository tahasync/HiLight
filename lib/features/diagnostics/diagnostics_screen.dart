import 'package:flutter/material.dart';

import '../../core/motion/hilight_animation.dart';
import '../../core/motion/preset_definitions.dart';
import '../../core/motion/torch_animator.dart';
import '../../core/platform/torch_capability.dart';
import '../../core/platform/torch_exception.dart';
import '../../core/theme/glass_theme.dart';
import '../../services/animation_service.dart';
import '../../services/torch_service.dart';

/// Shows the real torch capability values reported by the native layer
/// (PRD §10/§11) and offers a physical Test Torch button.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen>
    with WidgetsBindingObserver {
  final TorchService _torchService = TorchService();
  late final TorchAnimator _presetAnimator =
      TorchAnimator(output: AnimationService(_torchService));

  TorchCapability? _capability;
  TorchException? _error;
  bool _loading = true;
  bool _testingTorch = false;
  String? _playingPresetId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCapability();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    const shuttingDownStates = [
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ];
    if (shuttingDownStates.contains(state) && _playingPresetId != null) {
      _stopPreset();
    }
  }

  void _playPreset(HilightAnimation preset) {
    final capability = _capability;
    if (capability == null || !capability.torchAvailable) return;
    setState(() => _playingPresetId = preset.id);
    _presetAnimator.play(
      animation: preset,
      maxStrengthLevel:
          capability.supportsStrength ? capability.maxStrengthLevel : 1,
      repeatCount: 1,
      onComplete: () {
        if (mounted) setState(() => _playingPresetId = null);
      },
    );
  }

  void _stopPreset() {
    _presetAnimator.cancel();
    if (mounted) setState(() => _playingPresetId = null);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presetAnimator.dispose();
    super.dispose();
  }

  Future<void> _loadCapability() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final capability = await _torchService.getCapabilities();
      if (!mounted) return;
      setState(() {
        _capability = capability;
        _loading = false;
      });
    } on TorchException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _testTorch() async {
    if (_testingTorch || !(_capability?.torchAvailable ?? false)) return;
    setState(() => _testingTorch = true);
    const testDuration = Duration(milliseconds: 700);
    Object? failure;
    try {
      await _torchService.turnOn();
      await Future<void>.delayed(testDuration);
      await _torchService.turnOff();
    } on TorchException catch (error) {
      failure = error;
      // Safety rule (§17): never leave the flash enabled after an error.
      try {
        await _torchService.turnOff();
      } on TorchException catch (shutdownError) {
        failure = shutdownError;
      }
    } finally {
      if (mounted) {
        setState(() => _testingTorch = false);
        if (failure != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Torch test failed: $failure')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Torch diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadCapability,
          ),
        ],
      ),
      body: _buildBody(context, colorScheme),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme colorScheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorCard(
        error: _error!,
        onRetry: _loadCapability,
      );
    }
    final capability = _capability!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Torch Capability',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        GlassSurface(
          child: Column(
            children: [
              _CapabilityRow(
                label: 'Rear flash',
                ok: capability.hasFlash,
                valueOk: 'Available',
                valueBad: 'Not available',
              ),
              _CapabilityRow(
                label: 'Torch control',
                ok: capability.torchAvailable,
                valueOk: 'Available',
                valueBad: 'Unavailable',
              ),
              _CapabilityRow(
                label: 'Variable power',
                ok: capability.supportsStrength,
                valueOk: 'Supported',
                valueBad: 'Not supported',
              ),
              ListTile(
                leading: Icon(
                  Icons.brightness_6_outlined,
                  color: colorScheme.primary,
                ),
                title: const Text('Maximum level'),
                trailing: Text(
                  '${capability.maxStrengthLevel}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SummaryBanner(capability: capability),
        const SizedBox(height: 24),
        FilledButton.icon(
          icon: _testingTorch
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.highlight_outlined),
          label: Text(_testingTorch ? 'Testing…' : 'Test torch'),
          onPressed:
              capability.torchAvailable && !_testingTorch ? _testTorch : null,
        ),
        const SizedBox(height: 16),
        _PresetPlaybackCard(
          enabled: capability.torchAvailable,
          playingPresetId: _playingPresetId,
          onPlay: _playPreset,
          onStop: _stopPreset,
        ),
        const SizedBox(height: 16),
        GlassSurface(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Technical details', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                _DetailLine(label: 'Camera ID', value: capability.cameraId ?? '—'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.label,
    required this.ok,
    required this.valueOk,
    required this.valueBad,
  });

  final String label;
  final bool ok;
  final String valueOk;
  final String valueBad;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        ok ? Icons.check_circle_outline : Icons.cancel_outlined,
        color: ok ? Colors.green.shade600 : colorScheme.error,
        semanticLabel: ok ? 'Supported' : 'Not supported',
      ),
      title: Text(label),
      trailing: Text(
        ok ? valueOk : valueBad,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: ok ? Colors.green.shade700 : colorScheme.error,
            ),
      ),
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({required this.capability});

  final TorchCapability capability;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final (IconData icon, Color iconColor, String title, String subtitle) =
        switch (capability) {
          TorchCapability(hasFlash: false) => (
            Icons.flash_off_outlined,
            colorScheme.error,
            'No rear flash detected on this device.',
            'Physical light effects are disabled.',
          ),
          TorchCapability(hasFlash: true, supportsStrength: false) => (
            Icons.info_outline,
            Colors.amber.shade800,
            'Basic flash effects available.',
            'Smooth intensity effects are unavailable on this hardware.',
          ),
          _ => (
            Icons.verified_outlined,
            Colors.green.shade600,
            'HiLight animations available.',
            '',
          ),
        };
    return GlassSurface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleSmall),
                  if (subtitle.isNotEmpty)
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        SelectableText(value, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onRetry});

  final TorchException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text('Could not read torch capability',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(error.message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetPlaybackCard extends StatelessWidget {
  const _PresetPlaybackCard({
    required this.enabled,
    required this.playingPresetId,
    required this.onPlay,
    required this.onStop,
  });

  final bool enabled;
  final String? playingPresetId;
  final void Function(HilightAnimation) onPlay;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Preset playback', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Plays each preset once through the animation engine.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in kMvpPresets)
                  OutlinedButton(
                    onPressed:
                        enabled && playingPresetId == null
                            ? () => onPlay(preset)
                            : null,
                    child: Text(preset.name),
                  ),
              ],
            ),
            if (playingPresetId != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Playing $playingPresetId…')),
                  TextButton(onPressed: onStop, child: const Text('Stop')),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
