package com.tahasync.hilight

import android.content.Intent
import android.os.Bundle
import com.tahasync.hilight.torch.AppsChannel
import com.tahasync.hilight.torch.ContactsChannel
import com.tahasync.hilight.torch.TorchChannel
import com.tahasync.hilight.torch.TorchController
import com.tahasync.hilight.torch.TileControlChannel
import com.tahasync.hilight.torch.TileEngineHost
import com.tahasync.hilight.torch.TriggerSupportChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        TorchChannel(TorchController(this)).register(flutterEngine)
        TriggerSupportChannel.register(flutterEngine, this)
        ContactsChannel.register(flutterEngine, this)
        AppsChannel.register(flutterEngine, this)
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

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // Route contact-picker results before the framework default.
        ContactsChannel.onActivityResult(requestCode, resultCode, data)
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        ContactsChannel.onRequestPermissionsResult(requestCode, grantResults)
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
