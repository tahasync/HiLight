package com.tahasync.hilight.torch

import android.content.Context
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter engine that backs the Quick Settings tile
 * (prd-v1.1.md §4).
 *
 * When the app's Activity engine is alive it is reused, so a tile tap while
 * the app is open drives the exact same Dart isolate as the UI. Otherwise a
 * headless engine is booted on the `tileMain` entrypoint; it is released
 * once playback returns to idle with no Activity present.
 */
object TileEngineHost {

    const val TILE_ENTRYPOINT = "tileMain"

    /** Set by [com.tahasync.hilight.MainActivity] while its engine lives. */
    @Volatile
    var activityEngine: FlutterEngine? = null

    /** Last state published by Dart; used to render before first contact. */
    @Volatile
    var lastKnownActive: Boolean = false

    /** Tile services subscribe to mirror engine state changes. */
    @Volatile
    var stateListener: ((Boolean) -> Unit)? = null

    @Volatile
    private var headlessEngine: FlutterEngine? = null

    val isEngineAlive: Boolean
        get() = activityEngine != null || headlessEngine != null

    /**
     * Returns the shared engine, booting the headless one when necessary.
     * Returns null when the engine could not be started; the tile then stays
     * in its idle state (§4) instead of appearing to succeed.
     */
    @Synchronized
    fun ensureEngine(context: Context): MethodChannel? {
        activityEngine?.let { return TileControlChannel.attach(it) }
        headlessEngine?.let { return TileControlChannel.attach(it) }
        val engine = try {
            FlutterEngine(context.applicationContext)
        } catch (t: Throwable) {
            return null
        }
        val bundlePath =
            FlutterInjector.instance().flutterLoader().findAppBundlePath()
        engine.dartExecutor.executeDartEntrypoint(
            io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint(
                bundlePath,
                TILE_ENTRYPOINT,
            ),
        )
        TorchChannel(TorchController(context.applicationContext))
            .register(engine)
        TriggerSupportChannel.register(engine, context.applicationContext)
        val control = TileControlChannel.attach(engine)
        headlessEngine = engine
        return control
    }

    /** Called from the tile channel whenever Dart reports a state change. */
    fun onStateChanged(active: Boolean) {
        lastKnownActive = active
        // Trigger playback (notification listener) holds a wake lock for as
        // long as Dart reports active; idle means safe to release.
        if (!active) TriggerWakeLock.releaseIfHeld()
        stateListener?.invoke(active)
        // The headless engine is intentionally kept alive for the process
        // lifetime: a second directly-constructed FlutterEngine cannot run
        // Dart reliably, so recreating it per-toggle is not safe.
    }
}

/**
 * The `hilight/tile_control` channel: Kotlin→Dart requests (`toggle`,
 * `refreshState`) and Dart→Kotlin notifications (`stateChanged`).
 */
object TileControlChannel {

    const val NAME = "hilight/tile_control"

    @Volatile
    private var outbound: MethodChannel? = null

    @Volatile
    private var boundEngine: FlutterEngine? = null

    /** Registers/refreshes both directions for the given engine. */
    fun attach(engine: FlutterEngine): MethodChannel {
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, NAME)
        outbound = channel
        boundEngine = engine
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "stateChanged" -> {
                    val active = call.argument<Boolean>("active") ?: false
                    TileEngineHost.onStateChanged(active)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        return channel
    }

    fun detachIfBoundTo(engine: FlutterEngine) {
        if (boundEngine === engine) {
            outbound?.setMethodCallHandler(null)
            outbound = null
            boundEngine = null
        }
    }

    /**
     * Invokes [method] with optional [arguments] on the Dart side, retrying
     * briefly if the isolate has not installed its handler yet (fresh
     * headless engines need a moment to reach main()/tileMain()). A
     * permanently missing handler leaves the tile in its current state
     * rather than appearing to succeed.
     */
    fun invokeWithRetry(
        method: String,
        arguments: Any? = null,
        attempt: Int = 0,
    ) {
        val channel = outbound ?: return
        channel.invokeMethod(method, arguments, object : MethodChannel.Result {
            override fun success(result: Any?) {}
            override fun error(errorCode: String, message: String?, details: Any?) {
                if (attempt < 5) {
                    android.os.Handler(android.os.Looper.getMainLooper())
                        .postDelayed({ invokeWithRetry(method, attempt + 1) }, 300)
                }
            }
            override fun notImplemented() {
                if (attempt < 5) {
                    android.os.Handler(android.os.Looper.getMainLooper())
                        .postDelayed({ invokeWithRetry(method, attempt + 1) }, 300)
                }
            }
        })
    }
}
