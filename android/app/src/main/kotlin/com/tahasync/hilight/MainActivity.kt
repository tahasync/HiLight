package com.tahasync.hilight

import android.os.Bundle
import com.tahasync.hilight.torch.TorchChannel
import com.tahasync.hilight.torch.TorchController
import com.tahasync.hilight.torch.TileControlChannel
import com.tahasync.hilight.torch.TileEngineHost
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        TorchChannel(TorchController(this)).register(flutterEngine)
        // The tile reuses this engine while the app is open, so a tap in the
        // Quick Settings drives the same Dart isolate as the UI.
        TileEngineHost.activityEngine = flutterEngine
        TileControlChannel.attach(flutterEngine)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (TileEngineHost.activityEngine == flutterEngine) {
            TileEngineHost.activityEngine = null
        }
        TileControlChannel.detachIfBoundTo(flutterEngine)
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
