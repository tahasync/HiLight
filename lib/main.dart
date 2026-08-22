import 'dart:async';

import 'package:flutter/material.dart';

import 'app/hilight_app.dart';

void main() {
  runZonedGuarded(() {
    runApp(const HilightApp());
  }, (error, stackTrace) {
    FlutterError.presentError(FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'hilight',
    ));
  });
}
