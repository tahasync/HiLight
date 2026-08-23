import 'package:flutter/material.dart' hide Easing;

import '../../core/motion/easing.dart';
import '../../core/motion/hilight_animation.dart';
import '../../core/theme/glass_theme.dart';
import '../../services/torch_service.dart';
import '../animation_editor/animation_editor_screen.dart';
import '../animation_editor/custom_animation_id.dart';
import '../animation_editor/stored_custom_animation.dart';
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
                _PresetPickerCard(
                  controller: controller,
                  onCreate: _openEditor,
                  onEditCustom: (custom) =>
                      _openEditor(initial: custom),
                ),
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
        builder: (_) => SettingsScreen(
          settings: widget.settings,
          customAnimations: _controller.customAnimations,
        ),
      ),
    );
  }

  /// Opens the custom animation editor; a returned entry is persisted and
  /// selected. The list is always refreshed afterwards so deletions made in
  /// the editor are reflected here.
  Future<void> _openEditor({StoredCustomAnimation? initial}) async {
    final result = await Navigator.of(context).push<StoredCustomAnimation>(
      MaterialPageRoute<StoredCustomAnimation>(
        builder: (_) => AnimationEditorScreen(
          settings: widget.settings,
          initial: initial,
        ),
      ),
    );
    await _controller.reloadCustomAnimations();
    if (result != null) {
      await _controller.upsertCustomAnimation(result);
    }
  }}

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
  const _PresetPickerCard({
    required this.controller,
    required this.onCreate,
    required this.onEditCustom,
  });

  final HomeController controller;
  final VoidCallback onCreate;
  final void Function(StoredCustomAnimation custom) onEditCustom;

  @override
  Widget build(BuildContext context) {
    final customs = controller.customAnimations;
    return GlassSurface(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Animation',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Create animation',
                  onPressed: onCreate,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
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
                for (final preset in controller.selectablePresets)
                  GestureDetector(
                    onLongPress: () {
                      // Custom animations edit in place; built-ins are
                      // immutable PRD tables (§28) and open as an editable
                      // copy instead.
                      if (preset.id.startsWith('custom_')) {
                        for (final custom in customs) {
                          if (custom.id == preset.id) {
                            onEditCustom(custom);
                            return;
                          }
                        }
                        return;
                      }
                      onEditCustom(
                        StoredCustomAnimation(
                          animation: HilightAnimation(
                            id: newCustomAnimationId(),
                            name: '${preset.name} copy',
                            duration: preset.duration,
                            keyframes: List.of(preset.keyframes),
                          ),
                          easing: Easing.linear,
                        ),
                      );
                    },
                    child: FilterChip(
                      label: Text(preset.name),
                      selected: preset.id == controller.selectedPreset.id,
                      onSelected: (_) => controller.selectPreset(preset),
                    ),
                  ),
              ],
            ),
            if (customs.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Long-press any animation to edit it — built-ins open as an '
                'editable copy.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
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
