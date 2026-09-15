import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/haptics.dart';
import '../../core/theme/glass_theme.dart';
import '../../services/chat_apps.dart';
import '../../services/sms_app_store.dart';

/// SMS trigger app selection (prd-v1.2.md §2, user spec): the known
/// messaging apps are listed at the top, NOTHING is selected by default —
/// the user picks manually which apps fire the SMS trigger. Any app can be
/// selected (Instagram, Snapchat, …).
class SmsAppsScreen extends StatefulWidget {
  const SmsAppsScreen({super.key});

  @override
  State<SmsAppsScreen> createState() => _SmsAppsScreenState();
}

class _SmsAppsScreenState extends State<SmsAppsScreen> {
  static const _appsChannel = MethodChannel('hilight/apps');

  final SmsAppStore _store = SmsAppStore();
  Set<String>? _selected;
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
    final selected = await _store.loadSelected();
    if (!mounted) return;
    setState(() => _selected = selected);
  }

  Future<void> _loadApps() async {
    try {
      final apps = await _appsChannel
          .invokeListMethod<Map<Object?, Object?>>('listLaunchableApps');
      if (!mounted) return;
      apps?.sort((a, b) => (a['appName'] ?? '').toString().compareTo(
          (b['appName'] ?? '').toString()));
      setState(() => _installedApps = apps);
    } on PlatformException catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error.message ?? 'Could not list apps.');
    } on MissingPluginException {
      if (!mounted) return;
      setState(() => _loadError = 'App listing is unavailable here.');
    }
  }

  bool _isSelected(String packageName) =>
      _selected?.contains(packageName) ?? false;

  Future<void> _toggle(String packageName, bool on) async {
    Haptics.light();
    await _store.toggle(packageName, on: on);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final apps = _installedApps;
    return Scaffold(
      appBar: AppBar(title: const Text('SMS apps')),
      body: _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(_loadError!, textAlign: TextAlign.center),
              ),
            )
          : apps == null || _selected == null
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
                          'Nothing fires until you select apps. Messaging '
                          'apps are listed first — add Instagram, Snapchat '
                          'or anything else you want to flash.',
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
                            if (_matches(app) &&
                                ChatApps.smsTabApps.contains(
                                    app['packageName'] as String))
                              _buildTile(app),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildTile(Map<Object?, Object?> app) {
    final packageName = app['packageName']! as String;
    final appName = app['appName']! as String;
    final isMessaging = SmsAppStore.isKnownMessagingApp(packageName);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassSurface(
        blur: false,
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
          title: Text(
            appName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: isMessaging
              ? const Text('Messaging app',
                  style: TextStyle(fontWeight: FontWeight.w600))
              : null,
          isThreeLine: isMessaging,
          trailing: Switch(
            value: _isSelected(packageName),
            onChanged: (on) => _toggle(packageName, on),
          ),
        ),
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
