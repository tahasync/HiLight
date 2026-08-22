import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/motion/preset_definitions.dart';
import '../../core/theme/glass_theme.dart';
import '../../services/torch_service.dart';
import '../diagnostics/diagnostics_screen.dart';
import 'app_settings_controller.dart';

/// Settings screen covering PRD §19: appearance, animation defaults,
/// hardware, and advanced options. Every change persists locally (§24).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({required this.settings, super.key});

  final AppSettingsController settings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              const _SectionHeader('Appearance'),
              GlassSurface(
                blur: false,
                child: SegmentedButton<ThemeMode>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('System')),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (selection) =>
                      settings.setThemeMode(selection.first),
                ),
              ),
              const _SectionHeader('Animation'),
              GlassSurface(
                blur: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownMenu<String>(
                        expandedInsets: EdgeInsets.zero,
                        initialSelection: settings.presetId,
                        label: const Text('Default preset'),
                        dropdownMenuEntries: [
                          for (final preset in kMvpPresets)
                            DropdownMenuEntry(
                              value: preset.id,
                              label: preset.name,
                            ),
                        ],
                        onSelected: (value) {
                          if (value != null) settings.setPresetId(value);
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Expanded(child: Text('Default brightness')),
                          Text('${(settings.brightness * 100).round()}%'),
                        ],
                      ),
                      Slider(
                        value: settings.brightness,
                        onChanged: settings.setBrightness,
                      ),
                      Row(
                        children: [
                          const Expanded(child: Text('Default speed')),
                          Text('${settings.speed.toStringAsFixed(2)}×'),
                        ],
                      ),
                      Slider(
                        value: settings.speed,
                        min: 0.25,
                        max: 3,
                        divisions: 11,
                        onChanged: settings.setSpeed,
                      ),
                      const SizedBox(height: 4),
                      SegmentedButton<int>(
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        segments: const [
                          ButtonSegment(value: 1, label: Text('Once')),
                          ButtonSegment(value: 2, label: Text('2×')),
                          ButtonSegment(value: 3, label: Text('3×')),
                          ButtonSegment(value: 0, label: Text('Loop')),
                        ],
                        selected: {settings.repeatCount},
                        onSelectionChanged: (selection) =>
                            settings.setRepeatCount(selection.first),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Haptic feedback'),
                        value: settings.hapticsEnabled,
                        onChanged: settings.setHapticsEnabled,
                      ),
                    ],
                  ),
                ),
              ),
              const _SectionHeader('Hardware'),
              GlassSurface(
                blur: false,
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.camera_outlined),
                      title: Text('Selected flash camera'),
                      subtitle:
                          Text('Auto-detected rear flash · Camera ID shown below'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.monitor_heart_outlined),
                      title: const Text('Capability diagnostics'),
                      subtitle: const Text(
                        'Flash details and test torch',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const DiagnosticsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const _SectionHeader('Advanced'),
              GlassSurface(
                blur: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropdownMenu<int>(
                        expandedInsets: EdgeInsets.zero,
                        initialSelection: settings.updateRateMs,
                        label: const Text('Torch update rate'),
                        dropdownMenuEntries: const [
                          DropdownMenuEntry(value: 10, label: 'Fast (10 ms)'),
                          DropdownMenuEntry(value: 16, label: 'Smooth (16 ms)'),
                          DropdownMenuEntry(value: 32, label: 'Eco (32 ms)'),
                        ],
                        onSelected: (value) {
                          if (value != null) settings.setUpdateRateMs(value);
                        },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Debug logging'),
                        subtitle: const Text(
                          'Print playback sync markers to logcat',
                        ),
                        value: settings.debugLogging,
                        onChanged: settings.setDebugLogging,
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).colorScheme.error,
                        ),
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('Reset all settings'),
                        onPressed: () => _confirmReset(context),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset all settings?'),
        content: const Text(
          'Theme, animation defaults, and advanced options return to their '
          'original values.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      // Best-effort safety shutoff, deliberately fire-and-forget so the
      // reset itself is instant and never depends on torch reachability
      // (no flash hardware, channel busy, etc.).
      unawaited(
        TorchService().turnOff().catchError((Object error) {
          debugPrint('HiLight: post-reset torch shutoff failed: $error');
          return null;
        }),
      );
      await settings.reset();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings restored to defaults')),
        );
      }
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
