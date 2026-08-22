import 'package:flutter/material.dart';

import '../../core/motion/preset_definitions.dart';
import '../../core/theme/glass_theme.dart';
import '../../services/torch_service.dart';
import '../diagnostics/diagnostics_screen.dart';
import '../settings/app_settings_controller.dart';
import '../settings/settings_screen.dart';
import 'home_controller.dart';
import 'widgets/hero_flash_visual.dart';

/// Material 3 Expressive home screen (PRD §15): header with device status,
/// animated hero, large preview action, preset picker, and playback controls.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.settings,
    super.key,
  });

  final AppSettingsController settings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeController _controller = HomeController(TorchService(), widget.settings);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final controller = _controller;
        final hasFlash = controller.capability?.hasFlash ?? false;
        return Scaffold(
          appBar: AppBar(
            title: const Text('HiLight'),
            actions: [
              IconButton(
                icon: const Icon(Icons.bug_report_outlined),
                tooltip: 'Diagnostics',
                onPressed: _openDiagnostics,
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: _openSettings,
              ),
            ],
          ),
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colorScheme.primary.withValues(alpha: 0.07),
                  colorScheme.surface,
                  colorScheme.primary.withValues(alpha: 0.05),
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                _DeviceStatusCard(controller: controller),
                const SizedBox(height: 8),
                GlassSurface(
                  borderRadius: GlassTokens.heroRadius,
                  child: HeroFlashVisual(
                    animation: controller.selectedPreset,
                    playing: controller.isPlaying,
                    brightness: controller.brightness,
                    speed: controller.speed,
                    repeatCount: controller.repeatCount,
                    session: controller.playSession,
                    startedAt: controller.previewStartedAt,
                  ),
                ),
                Text(
                  controller.statusText,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: controller.torchError != null
                            ? colorScheme.error
                            : colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 64,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      shape: const StadiumBorder(),
                      textStyle: Theme.of(context).textTheme.titleMedium,
                    ),
                    icon: Icon(
                      controller.isPlaying
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                      size: 30,
                    ),
                    label: Text(
                      controller.isPlaying ? 'Stop' : 'Preview HiLight',
                    ),
                    onPressed:
                        controller.canPlay && hasFlash
                            ? controller.togglePreview
                            : null,
                  ),
                ),
                const SizedBox(height: 20),
                _PresetPickerCard(controller: controller),
                const SizedBox(height: 12),
                _ControlsCard(controller: controller),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openDiagnostics() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const DiagnosticsScreen()),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(settings: widget.settings),
      ),
    );
  }


}

class _DeviceStatusCard extends StatelessWidget {
  const _DeviceStatusCard({required this.controller});

  final HomeController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final model = controller.deviceInfo?.deviceModel ?? '';
    final ok = controller.capability?.torchAvailable ?? false;
    return GlassSurface(
      child: InkWell(
        borderRadius: BorderRadius.circular(GlassTokens.controlRadius),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const DiagnosticsScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                ok ? Icons.highlight_outlined : Icons.flash_off_outlined,
                size: 22,
                color: ok ? colorScheme.primary : colorScheme.error,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.isEmpty ? 'Detecting device…' : '$model · White light',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      ok ? 'Rear flash ready' : 'Torch unavailable',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetPickerCard extends StatelessWidget {
  const _PresetPickerCard({required this.controller});

  final HomeController controller;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Animation', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '${controller.selectedPreset.name} · '
              '${controller.selectedPreset.duration.inMilliseconds} ms',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in kMvpPresets)
                  FilterChip(
                    label: Text(preset.name),
                    selected: preset.id == controller.selectedPreset.id,
                    onSelected: (_) => controller.selectPreset(preset),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlsCard extends StatelessWidget {
  const _ControlsCard({required this.controller});

  final HomeController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return GlassSurface(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.brightness_6_outlined,
                    size: 20, color: colorScheme.primary),
                const SizedBox(width: 10),
                const Expanded(child: Text('Brightness')),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${(controller.brightness * 100).round()}%',
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            Semantics(
              label: 'Brightness',
              value: '${(controller.brightness * 100).round()} percent',
              child: Slider(
                value: controller.brightness,
                onChanged: controller.setBrightness,
              ),
            ),
            Row(
              children: [
                Icon(Icons.speed_outlined, size: 20, color: colorScheme.primary),
                const SizedBox(width: 10),
                const Expanded(child: Text('Speed')),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${controller.speed.toStringAsFixed(2)}×',
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            Slider(
              value: controller.speed,
              min: 0.25,
              max: 3,
              divisions: 11,
              label: '${controller.speed.toStringAsFixed(2)}×',
              onChanged: controller.setSpeed,
            ),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 1, label: Text('Once')),
                ButtonSegment(value: 2, label: Text('2×')),
                ButtonSegment(value: 3, label: Text('3×')),
                ButtonSegment(value: 0, label: Text('Loop')),
              ],
              selected: {controller.repeatCount},
              onSelectionChanged: (selection) =>
                  controller.setRepeatCount(selection.first),
            ),
          ],
        ),
      ),
    );
  }
}
