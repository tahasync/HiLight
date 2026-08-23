import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../features/home/home_screen.dart';
import '../features/settings/app_settings_controller.dart';
import '../services/preferences_service.dart';
import '../services/update_checker.dart';

/// Root widget of the application. Owns the settings controller (which also
/// drives the theme) and home navigation.
class HilightApp extends StatefulWidget {
  const HilightApp({super.key});

  @override
  State<HilightApp> createState() => _HilightAppState();
}

class _HilightAppState extends State<HilightApp> {
  late final AppSettingsController _settings =
      AppSettingsController(PreferencesService());
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _updateTimer = Timer(const Duration(seconds: 2), _checkForUpdate);
  }

  /// Silent GitHub Releases check (Foam Shop POS flow): only surfaces a
  /// dialog when the installed version is older than the latest tag; every
  /// failure mode is a no-op.
  Future<void> _checkForUpdate() async {
    try {
      final update = await checkForUpdate();
      if (!mounted || update == null) return;
      final pkg = await PackageInfo.fromPlatform();
      if (!mounted || !isNewerVersion(pkg.version, update.tagName)) return;
      await showUpdateDialog(context, update);
    } catch (_) {
      // An update check must never disturb a normal launch.
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    _settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Gate on persisted settings being loaded so screens that snapshot
    // values (home controls) never initialize from defaults first.
    return FutureBuilder<void>(
      future: _settings.ready,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        return ListenableBuilder(
          listenable: _settings,
          builder: (context, _) {
            return MaterialApp(
              title: 'HiLight',
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(
                  seedColor: Colors.blueGrey,
                  brightness: Brightness.dark,
                ),
              ),
              themeMode: _settings.themeMode,
              home: HomeScreen(settings: _settings),
            );
          },
        );
      },
    );
  }
}
