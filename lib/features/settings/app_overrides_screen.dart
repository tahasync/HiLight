import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/motion/hilight_animation.dart';
import '../../core/theme/glass_theme.dart';
import '../../services/app_override_store.dart';

/// Per-app flash decisions (prd-v1.2.md §3): every installed app can be
/// enabled or disabled individually, and enabled apps may carry their own
/// preset instead of the generic one.
///
/// Apps without an entry follow the App-notifications trigger.
class AppOverridesScreen extends StatefulWidget {
  const AppOverridesScreen({required this.presets, super.key});

  /// Built-in + custom presets available for assignment.
  final List<HilightAnimation> presets;

  @override
  State<AppOverridesScreen> createState() => _AppOverridesScreenState();
}

class _AppOverridesScreenState extends State<AppOverridesScreen> {
  static const _appsChannel = MethodChannel('hilight/apps');

  static const _genericValue = '';

  final AppOverrideStore _store = AppOverrideStore();
  List<AppOverride>? _entries;
  List<Map<Object?, Object?>>? _installedApps;
  String _query = '';
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _reload();
    _loadApps();
  }

  Future<void> _reload() async {
    final entries = await _store.loadAll();
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  Future<void> _loadApps() async {
    try {
      final apps = await _appsChannel
          .invokeListMethod<Map<Object?, Object?>>('listLaunchableApps');
      if (!mounted) return;
      setState(() => _installedApps = apps);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error.message ?? 'Could not list apps.');
    } on MissingPluginException {
      if (!mounted) return;
      setState(() => _loadError = 'App listing is unavailable here.');
    }
  }

  AppOverride _effectiveEntry(
    String packageName,
    String appName,
  ) {
    final entries = _entries ?? const [];
    for (final entry in entries) {
      if (entry.packageName == packageName) return entry;
    }
    return AppOverride(packageName: packageName, appName: appName);
  }

  Future<void> _setFlash(Map<Object?, Object?> app, bool enabled) async {
    final packageName = app['packageName']! as String;
    final appName = app['appName']! as String;
    final current = _effectiveEntry(packageName, appName);
    await _store.upsert(current.copyWith(flashEnabled: enabled));
    await _reload();
  }

  Future<void> _pickPreset(Map<Object?, Object?> app) async {
    final packageName = app['packageName']! as String;
    final appName = app['appName']! as String;
    final current = _effectiveEntry(packageName, appName);
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Preset for $appName'),
        children: [
          RadioGroup<String>(
            groupValue: current.presetId ?? _genericValue,
            onChanged: (value) => Navigator.of(dialogContext).pop(value),
            child: Column(
              children: [
                const RadioListTile<String>(
                  value: _genericValue,
                  title: Text('Generic (inherit)'),
                ),
                for (final preset in widget.presets)
                  RadioListTile<String>(
                    value: preset.id,
                    title: Text(preset.name),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected == null) return;
    final presetId = selected.isEmpty ? null : selected;
    await _store.upsert(current.copyWith(presetId: presetId));
    await _reload();
  }

  String? _presetName(String? id) {
    if (id == null) return null;
    for (final preset in widget.presets) {
      if (preset.id == id) return preset.name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final apps = _installedApps;
    return Scaffold(
      appBar: AppBar(title: const Text('App overrides')),
      body: _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(_loadError!, textAlign: TextAlign.center),
              ),
            )
          : apps == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search apps',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Every app follows the App-notifications trigger '
                          'by default. Switch one off to silence it for '
                          'good, or give it a preset of its own.',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding:
                            const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        children: [
                          for (final app in apps)
                            if (_matches(app))
                              Padding(
                                padding:
                                    const EdgeInsets.only(bottom: 8),
                                child: _AppRow(
                                  appName: app['appName']! as String,
                                  packageName:
                                      app['packageName']! as String,
                                  entry: _effectiveEntry(
                                    app['packageName']! as String,
                                    app['appName']! as String,
                                  ),
                                  presetName: _presetName(
                                      _effectiveEntry(
                                    app['packageName']! as String,
                                    app['appName']! as String,
                                  ).presetId),
                                  onToggle: (value) =>
                                      _setFlash(app, value),
                                  onPickPreset: () => _pickPreset(app),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  bool _matches(Map<Object?, Object?> app) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    final name = (app['appName'] ?? '') as String;
    final pkg = (app['packageName'] ?? '') as String;
    return name.toLowerCase().contains(q) || pkg.toLowerCase().contains(q);
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.appName,
    required this.packageName,
    required this.entry,
    required this.presetName,
    required this.onToggle,
    required this.onPickPreset,
  });

  final String appName;
  final String packageName;
  final AppOverride entry;
  final String? presetName;
  final ValueChanged<bool> onToggle;
  final VoidCallback onPickPreset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassSurface(
      blur: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    appName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    presetName ?? 'Generic preset',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Assign preset',
              icon: Icon(
                entry.presetId == null ? Icons.bolt_outlined : Icons.bolt,
                size: 22,
                color: entry.presetId == null
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.primary,
              ),
              onPressed: entry.flashEnabled ? onPickPreset : null,
            ),
            const SizedBox(width: 2),
            Switch(
              value: entry.flashEnabled,
              onChanged: onToggle,
            ),
          ],
        ),
      ),
    );
  }
}
