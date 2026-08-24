import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/motion/hilight_animation.dart';
import '../../core/motion/preset_definitions.dart';
import '../../core/theme/glass_theme.dart';
import '../../services/charging_settings.dart';
import '../../services/notification_access_service.dart';
import '../../services/notification_trigger_classifier.dart';
import '../../services/torch_service.dart';
import '../../services/trigger_settings.dart';
import '../animation_editor/stored_custom_animation.dart';
import '../diagnostics/diagnostics_screen.dart';
import 'app_overrides_screen.dart';
import 'app_settings_controller.dart';
import 'contact_overrides_screen.dart';

/// Settings screen covering PRD Â§19 plus the V1.2 additions (prd-v1.2.md
/// Â§5): appearance, animation defaults, triggers, hardware, and advanced
/// options. Every change persists locally (Â§24).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.settings,
    this.customAnimations = const [],
    super.key,
  });

  final AppSettingsController settings;

  /// User-created animations offered alongside built-ins as the default
  /// preset (prd-v1.1.md Â§3/Â§4).
  final List<StoredCustomAnimation> customAnimations;

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
                  onSelectionChanged: (selection) {
                    Haptics.light();
                    settings.setThemeMode(selection.first);
                  },
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
                          for (final preset in kBuiltinPresets)
                            DropdownMenuEntry(
                              value: preset.id,
                              label: preset.name,
                            ),
                          for (final custom in customAnimations)
                            DropdownMenuEntry(
                              value: custom.id,
                              label: custom.animation.name,
                            ),
                        ],
                        onSelected: (value) {
                          if (value != null) {
                            Haptics.selection();
                            settings.setPresetId(value);
                          }
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
                        onChangeEnd: (_) => Haptics.light(),
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
                        onChangeEnd: (_) => Haptics.light(),
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
                        onSelectionChanged: (selection) {
                          Haptics.light();
                          settings.setRepeatCount(selection.first);
                        },
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Haptic feedback'),
                        value: settings.hapticsEnabled,
                        onChanged: (value) {
                          // Buzz before the gate flips so turning the
                          // toggle OFF still confirms.
                          Haptics.light();
                          settings.setHapticsEnabled(value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const _SectionHeader('Triggers'),
              _TriggersSection(settings: settings, customAnimations: customAnimations),
              const _SectionHeader('Charging'),
              _ChargingSection(settings: settings, customAnimations: customAnimations),
              const _SectionHeader('Hardware'),
              GlassSurface(
                blur: false,
                child: Column(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.camera_outlined),
                      title: Text('Selected flash camera'),
                      subtitle:
                          Text('Auto-detected rear flash Â· Camera ID shown below'),
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
                          if (value != null) {
                            Haptics.selection();
                            settings.setUpdateRateMs(value);
                          }
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
                        onChanged: (value) {
                          Haptics.light();
                          settings.setDebugLogging(value);
                        },
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
      Haptics.medium();
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

/// Triggers section (prd-v1.2.md Â§2/Â§5): notification-access status with a
/// direct link to the system screen, plus one configurable row per generic
/// trigger type.
///
/// Permissions discipline: listener access is only ever *requested* from
/// inside the enable flow — when the user flips a trigger on without
/// access. An explanation dialog precedes the hand-off to system settings,
/// and a granted return completes the pending enable automatically.
class _TriggersSection extends StatefulWidget {
  const _TriggersSection({
    required this.settings,
    required this.customAnimations,
  });

  final AppSettingsController settings;
  final List<StoredCustomAnimation> customAnimations;

  @override
  State<_TriggersSection> createState() => _TriggersSectionState();
}

class _TriggersSectionState extends State<_TriggersSection>
    with WidgetsBindingObserver {
  static const _access = NotificationAccessService();

  bool _granted = false;
  TriggerKind? _pendingEnable;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recheckAccess();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Returning from the system notification-access screen re-evaluates the
    // grant and completes any pending enable.
    if (state == AppLifecycleState.resumed) _recheckAccess(applyPending: true);
  }

  Future<void> _recheckAccess({bool applyPending = false}) async {
    final granted = await _access.isGranted();
    if (!mounted) return;
    setState(() => _granted = granted);
    if (!applyPending || !granted) return;
    final pending = _pendingEnable;
    if (pending != null) {
      setState(() => _pendingEnable = null);
      widget.settings.setTriggerEnabled(pending, true);
    }
  }

  Future<void> _onToggle(TriggerKind kind, bool want) async {
    if (!want) {
      widget.settings.setTriggerEnabled(kind, false);
      return;
    }
    if (_granted) {
      widget.settings.setTriggerEnabled(kind, true);
      return;
    }
    // The exact-moment request: explain why first (prd.md Â§23), then hand
    // off to Android's notification-access screen.
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Notification access needed'),
        content: const Text(
          'To flash on this event, Android requires notification access. '
          'HiLight never reads or stores message text or sender details — '
          'it only reacts to notification events.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
    if (proceed ?? false) {
      setState(() => _pendingEnable = kind);
      await _access.openSystemSettings();
      await _recheckAccess(applyPending: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return GlassSurface(
      blur: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: Icon(
              _granted
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_off_outlined,
            ),
            title: const Text('Notification access'),
            subtitle: Text(_granted
                ? 'Granted'
                : (_pendingEnable != null
                    ? 'Not granted — waiting for accessâ€¦'
                    : 'Not granted')),
            trailing: IconButton(
              tooltip: 'Open Android notification settings',
              icon: const Icon(Icons.open_in_new),
              onPressed: () async {
                await _access.openSystemSettings();
                await _recheckAccess(applyPending: true);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(
              'Triggers rely on Android\'s notification listener. Doze mode, '
              'battery optimization, or aggressive OEM battery managers can '
              'delay or suppress them — and some clock apps label timers as '
              'alarms.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const Divider(height: 1),
          for (final kind in kTriggerKinds)
            _TriggerTile(
              kind: kind,
              config: settings.triggerConfigFor(kind),
              presets: _presetOptions(),
              onToggle: (want) => _onToggle(kind, want),
              onPresetSelected: (id) =>
                  settings.setTriggerPresetId(kind, id),
              // Per-contact overrides attach to the call trigger, per-app
              // decisions to app notifications (prd-v1.2.md Â§2/Â§3).
              trailingChild: switch (kind) {
                TriggerKind.incomingCall =>
                  _ContactOverridesEntry(presets: _presetOptions()),
                TriggerKind.appNotification =>
                  _AppOverridesEntry(presets: _presetOptions()),
                _ => null,
              },
            ),
        ],
      ),
    );
  }

  List<HilightAnimation> _presetOptions() => [
        ...kBuiltinPresets,
        for (final custom in widget.customAnimations) custom.animation,
      ];
}

class _TriggerTile extends StatelessWidget {
  const _TriggerTile({
    required this.kind,
    required this.config,
    required this.presets,
    required this.onToggle,
    required this.onPresetSelected,
    this.trailingChild,
  });

  final TriggerKind kind;
  final TriggerConfig config;
  final List<HilightAnimation> presets;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onPresetSelected;

  /// Optional extra content shown when the trigger is enabled (e.g. the
  /// per-contact override entry for calls).
  final Widget? trailingChild;

  String get _description => switch (kind) {
        TriggerKind.incomingCall =>
          'Flash on call notifications while the screen is off',
        TriggerKind.sms =>
          'Flash for SMS/MMS from your messaging app — chat apps like '
              'WhatsApp count as App notifications',
        TriggerKind.alarm =>
          'Alarm notifications — Android labels many clock-app timers this way too',
        TriggerKind.timer =>
          'Timer notifications where the clock app distinguishes them',
        TriggerKind.appNotification =>
          'Other apps\' notifications; ongoing ones like media playback are ignored',
      };

  String? _presetName(String id) {
    for (final preset in presets) {
      if (preset.id == id) return preset.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          title: Text(kind.label),
          subtitle: Text(_description),
          value: config.enabled,
          onChanged: (value) {
            Haptics.light();
            onToggle(value);
          },
        ),
        if (config.enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: DropdownMenu<String>(
              expandedInsets: EdgeInsets.zero,
              initialSelection: _presetName(config.presetId) != null
                  ? config.presetId
                  : null,
              label: const Text('Preset'),
              dropdownMenuEntries: [
                for (final preset in presets)
                  DropdownMenuEntry(value: preset.id, label: preset.name),
              ],
              onSelected: (value) {
                if (value != null) {
                  Haptics.selection();
                  onPresetSelected(value);
                }
              },
            ),
          ),
        if (config.enabled && trailingChild != null) trailingChild!,
      ],
    );
  }
}

/// Entry row opening the per-contact override manager.
class _ContactOverridesEntry extends StatelessWidget {
  const _ContactOverridesEntry({required this.presets});

  final List<HilightAnimation> presets;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      leading: const Icon(Icons.person_pin_circle_outlined),
      title: Text(
        'Contact overrides',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      subtitle: const Text('Assign a preset to specific people'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ContactOverridesScreen(presets: presets),
        ),
      ),
    );
  }
}

/// Entry row opening the per-app override manager.
class _AppOverridesEntry extends StatelessWidget {
  const _AppOverridesEntry({required this.presets});

  final List<HilightAnimation> presets;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      leading: const Icon(Icons.apps_outlined),
      title: Text(
        'App overrides',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      subtitle: const Text(
        'Enable, disable, or re-style every app individually',
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              AppOverridesScreen(presets: presets),
        ),
      ),
    );
  }
}

/// Charging effects section (prd-v1.2.md Â§4, amended spec): master toggle,
/// connect/disconnect animations, and five battery-milestone presets — all
/// independent, no periodic animation while charging.
class _ChargingSection extends StatelessWidget {
  const _ChargingSection({
    required this.settings,
    required this.customAnimations,
  });

  final AppSettingsController settings;
  final List<StoredCustomAnimation> customAnimations;

  List<HilightAnimation> _presets() => [
        ...kBuiltinPresets,
        for (final custom in customAnimations) custom.animation,
      ];

  @override
  Widget build(BuildContext context) {
    final config = settings.chargingConfig;
    final presets = _presets();
    String? presetName(String id) {
      for (final preset in presets) {
        if (preset.id == id) return preset.name;
      }
      return null;
    }

    return GlassSurface(
      blur: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            title: const Text('Charging effects'),
            subtitle:
                const Text('Master switch — everything below is off until '
                    'this is on'),
            value: config.masterEnabled,
            onChanged: (value) {
            Haptics.light();
            settings.setChargingMaster(value);
          },
          ),
          if (config.masterEnabled) ...[
            const Divider(height: 1),
            SwitchListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              title: const Text('Animate on charger connect'),
              value: config.animateOnConnect,
              onChanged: (value) {
            Haptics.light();
            settings.setChargingConnectEnabled(value);
          },
            ),
            if (config.animateOnConnect)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: DropdownMenu<String>(
                  expandedInsets: EdgeInsets.zero,
                  initialSelection: presetName(config.connectPresetId) != null
                      ? config.connectPresetId
                      : null,
                  label: const Text('Connect preset'),
                  dropdownMenuEntries: [
                    for (final preset in presets)
                      DropdownMenuEntry(
                          value: preset.id, label: preset.name),
                  ],
                  onSelected: (value) {
                    if (value != null) {
                      Haptics.selection();
                      settings.setChargingConnectPreset(value);
                    }
                  },
                ),
              ),
            SwitchListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              title: const Text('Animate on charger disconnect'),
              subtitle: const Text(
                  'Any charging animation stops instantly first'),
              value: config.animateOnDisconnect,
              onChanged: (value) {
            Haptics.light();
            settings.setChargingDisconnectEnabled(value);
          },
            ),
            if (config.animateOnDisconnect)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: DropdownMenu<String>(
                  expandedInsets: EdgeInsets.zero,
                  initialSelection:
                      presetName(config.disconnectPresetId) != null
                          ? config.disconnectPresetId
                          : null,
                  label: const Text('Disconnect preset'),
                  dropdownMenuEntries: [
                    for (final preset in presets)
                      DropdownMenuEntry(
                          value: preset.id, label: preset.name),
                  ],
                  onSelected: (value) {
                    if (value != null) {
                      Haptics.selection();
                      settings.setChargingDisconnectPreset(value);
                    }
                  },
                ),
              ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Battery milestones — fire once per charging session when '
                'the level crosses upward:',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            for (final level in kChargingMilestoneLevels)
              _MilestoneTile(
                level: level,
                config: config.milestoneAt(level),
                presets: presets,
                onToggle: (value) => settings.setMilestoneEnabled(
                    level, value),
                onPresetSelected: (id) =>
                    settings.setMilestonePreset(level, id),
              ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _MilestoneTile extends StatelessWidget {
  const _MilestoneTile({
    required this.level,
    required this.config,
    required this.presets,
    required this.onToggle,
    required this.onPresetSelected,
  });

  final int level;
  final MilestoneConfig config;
  final List<HilightAnimation> presets;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onPresetSelected;

  @override
  Widget build(BuildContext context) {
    String? presetName(String id) {
      for (final preset in presets) {
        if (preset.id == id) return preset.name;
      }
      return null;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 8, 2),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text('$level%',
                style: Theme.of(context).textTheme.bodyLarge),
          ),
          Expanded(
            child: DropdownMenu<String>(
              expandedInsets: EdgeInsets.zero,
              initialSelection: presetName(config.presetId) != null
                  ? config.presetId
                  : null,
              enabled: config.enabled,
              label: const Text('Preset'),
              dropdownMenuEntries: [
                for (final preset in presets)
                  DropdownMenuEntry(value: preset.id, label: preset.name),
              ],
              onSelected: (value) {
                if (value != null) {
                  Haptics.selection();
                  onPresetSelected(value);
                }
              },
            ),
          ),
          Switch(
              value: config.enabled,
              onChanged: (value) {
                Haptics.light();
                onToggle(value);
              }),
        ],
      ),
    );
  }
}
