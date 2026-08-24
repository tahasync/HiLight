package com.tahasync.hilight.torch

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build

/**
 * Charging-trigger bridge (prd-v1.2.md §4 as amended by product decision).
 *
 * Why a RUNTIME receiver: ACTION_POWER_CONNECTED / DISCONNECTED manifest
 * receivers proved undeliverable on modern builds (empirically on Android
 * 16/17: registered, running, real cable transitions, zero delivery), and
 * the platform steers implicit broadcasts to context registration. The
 * bridge is therefore registered from long-lived hosts:
 *
 *  - the notification-listener service (bound while access is granted),
 *  - the Activity while the app is open.
 *
 * All decision logic lives in Dart (same split as notification triggers);
 * this class forwards presence-level events over the shared channel:
 *  - connected / disconnected (plug events)
 *  - level (every ACTION_BATTERY_CHANGED while registered — Dart gates
 *    milestones by its own session state)
 */
object ChargingBridge {

    private const val TAG = "HiLightCharging"

    @Volatile
    private var receiver: BroadcastReceiver? = null

    /**
     * Multiple hosts share one receiver (NLS + Activity). Unregistering must
     * only happen when the LAST host goes away — otherwise closing the app
     * kills the listener-hosted registration (observed live).
     */
    private var hostCount = 0

    @Volatile
    private var registered = false

    @Synchronized
    fun register(context: Context) {
        hostCount++
        android.util.Log.d(TAG, "register hostCount=$hostCount registered=$registered")
        if (registered) return
        val appContext = context.applicationContext
        val bridge = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                val event = when (intent.action) {
                    Intent.ACTION_POWER_CONNECTED -> EVENT_CONNECTED
                    Intent.ACTION_POWER_DISCONNECTED -> EVENT_DISCONNECTED
                    Intent.ACTION_BATTERY_CHANGED -> EVENT_LEVEL
                    else -> return
                }
                // Plug broadcasts carry no battery extras — read the sticky
                // BATTERY_CHANGED intent for the current level.
                val level = if (event == EVENT_LEVEL) {
                    batteryLevel(intent)
                } else {
                    batteryLevel(
                        ctx.registerReceiver(
                            null,
                            IntentFilter(Intent.ACTION_BATTERY_CHANGED),
                        ) ?: intent,
                    )
                }
                android.util.Log.d(TAG, "event=$event level=$level")
                TriggerWakeLock.acquire(ctx)
                if (TileEngineHost.ensureEngine(ctx) == null) {
                    TriggerWakeLock.releaseIfHeld()
                    return
                }
                TileControlChannel.invokeWithRetry(
                    METHOD_CHARGING_EVENT,
                    mapOf(ARG_EVENT to event, ARG_LEVEL to level),
                )
            }
        }
        receiver = bridge
        registered = true
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
            addAction(Intent.ACTION_BATTERY_CHANGED)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // System broadcasts reach NOT_EXPORTED receivers; the flag only
            // governs other apps.
            appContext.registerReceiver(
                bridge,
                filter,
                Context.RECEIVER_NOT_EXPORTED,
            )
        } else {
            appContext.registerReceiver(bridge, filter)
        }
    }

    @Synchronized
    fun unregister(context: Context) {
        if (hostCount > 0) hostCount--
        if (hostCount > 0 || !registered) return
        val bridge = receiver ?: return
        registered = false
        receiver = null
        try {
            context.applicationContext.unregisterReceiver(bridge)
        } catch (_: Throwable) {
            // Never registered on this context; nothing to do.
        }
    }

    private fun batteryLevel(intent: Intent): Int {
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        if (level < 0 || scale <= 0) return -1
        return (level * 100) / scale
    }

    const val METHOD_CHARGING_EVENT = "chargingEvent"
    const val ARG_EVENT = "event"
    const val ARG_LEVEL = "level"
    const val EVENT_CONNECTED = "connected"
    const val EVENT_DISCONNECTED = "disconnected"
    const val EVENT_LEVEL = "level"
}
