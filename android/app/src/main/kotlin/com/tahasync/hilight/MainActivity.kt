package com.tahasync.hilight

import android.os.Bundle
import com.tahasync.hilight.torch.TorchChannel
import com.tahasync.hilight.torch.TorchController
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        TorchChannel(TorchController(this)).register(flutterEngine)
    }
}
