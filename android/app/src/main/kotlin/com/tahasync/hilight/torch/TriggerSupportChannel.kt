package com.tahasync.hilight.torch

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Support channel for trigger settings (prd-v1.2.md §2/§5): notification
 * access status, a deep link to the system notification-access screen, and
 * a charging-state snapshot for the polling fallback.
 *
 * The app never requests listener access through any dialog of its own —
 * Android grants it only in system settings, so "requesting" means opening
 * that screen, which happens strictly when the user enables a trigger
 * without access (permissions discipline, prd-v1.2.md header rule 5).
 *
 * Channel name: `hilight/trigger_support`
 * Methods:
 *  - isNotificationAccessGranted -> Boolean
 *  - openNotificationAccessSettings -> null
 *  - chargingSnapshot -> Map {charging: Boolean, level: Int}
 */
object TriggerSupportChannel {

    const val NAME = "hilight/trigger_support"
    private const val METHOD_IS_GRANTED = "isNotificationAccessGranted"
    private const val METHOD_OPEN_SETTINGS = "openNotificationAccessSettings"
    private const val METHOD_CHARGING_SNAPSHOT = "chargingSnapshot"

    /** Registers the handler on the given engine. */
    fun register(flutterEngine: FlutterEngine, context: Context) {
        appContext = context.applicationContext
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    METHOD_IS_GRANTED -> result.success(
                        HilightNotificationListenerService.isAccessGranted(applicationContext()),
                    )
                    METHOD_OPEN_SETTINGS -> {
                        openSettings(applicationContext())
                        result.success(null)
                    }
                    METHOD_CHARGING_SNAPSHOT -> result.success(
                        chargingSnapshot(applicationContext()),
                    )
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Charging state straight from the sticky battery intent — the polling
     * fallback for devices whose ROM does not deliver power broadcasts.
     */
    private fun chargingSnapshot(context: Context): Map<String, Any?> {
        val sticky = context.registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED),
        )
        val status = sticky?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val plugged = sticky?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
        val level = sticky?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = sticky?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
            status == BatteryManager.BATTERY_STATUS_FULL ||
            plugged != 0
        val pct = if (level < 0 || scale <= 0) -1 else (level * 100) / scale
        return mapOf("charging" to charging, "level" to pct)
    }

    /**
     * Holds an application context captured at registration time; both
     * call sites (Activity engine and headless tile engine) have one handy.
     */
    @Volatile
    private var appContext: Context? = null

    private fun applicationContext(): Context =
        requireNotNull(appContext) { "TriggerSupportChannel registered without a context" }

    private fun openSettings(context: Context) {
        val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }
}
