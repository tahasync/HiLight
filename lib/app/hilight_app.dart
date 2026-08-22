import 'package:flutter/material.dart';

import '../features/home/home_screen.dart';
import '../features/settings/app_settings_controller.dart';
import '../services/preferences_service.dart';

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

  @override
  void dispose() {
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
