import 'dart:async';

import 'package:flutter/material.dart';

import 'app/hilight_app.dart';
import 'services/playback_coordinator.dart';
import 'services/tile_playback_controller.dart';
import 'services/trigger_playback_controller.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    // The tile must be able to start/stop the default animation even while
    // the app is open, through this same engine (prd-v1.1.md §4).
    PlaybackCoordinator.instance.attach();
    TilePlaybackController().register();
    // Trigger effects (prd-v1.2.md §2) ride the same engine + channel.
    TriggerPlaybackController().register();
    runApp(const HilightApp());
  }, (error, stackTrace) {
    FlutterError.presentError(FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'hilight',
    ));
  });
}

/// Background entrypoint for the headless engine that backs the Quick
/// Settings tile when the app itself is not running.
@pragma('vm:entry-point')
void tileMain() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    PlaybackCoordinator.instance.attach();
    TilePlaybackController().register();
    TriggerPlaybackController().register();
    // Publish the initial idle state once the platform side is listening.
    Future<void>.delayed(const Duration(milliseconds: 100), () {
      PlaybackCoordinator.instance.refreshState();
    });
  }, (error, stackTrace) {
    FlutterError.presentError(FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'hilight',
    ));
  });
}
