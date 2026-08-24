package com.tahasync.hilight.torch

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager

/**
 * Charging-trigger bridge (prd-v1.2.md §4 as amended by product decision):
 *
 *  - master toggle, animate-on-connect, animate-on-disconnect, and battery
 *    milestone presets (20/35/50/70/100 %) — all independent, all gated by
 *    the master switch in Dart;
 *  - NO periodic animation while charging;
 *  - disconnect kills any charging-owned animation instantly before the
 *    optional disconnect animation plays (torch-safety rule).
 *
 * POWER_CONNECTED / DISCONNECTED are protected system broadcasts exempt
 * from the implicit-broadcast ban, so a manifest receiver is enough. While
 * a session is live, a runtime receiver tracks ACTION_BATTERY_CHANGED for
 * milestone crossings; it is unregistered on disconnect.
 *
 * All decision logic lives in Dart (same split as notification triggers):
 * this class only forwards presence-level events over the shared channel.
 */
class ChargingReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_POWER_CONNECTED -> {
                TriggerWakeLock.acquire(context)
                if (!ensureEngineAndSend(context, event = EVENT_CONNECTED, level = currentLevel(context))) {
                    TriggerWakeLock.releaseIfHeld()
                    return
                }
                ChargingSession.begin(context)
            }
            Intent.ACTION_POWER_DISCONNECTED -> {
                TriggerWakeLock.acquire(context)
                if (!ensureEngineAndSend(context, event = EVENT_DISCONNECTED, level = currentLevel(context))) {
                    TriggerWakeLock.releaseIfHeld()
                    return
                }
                ChargingSession.end(context)
            }
        }
    }

    private fun currentLevel(context: Context): Int {
        val sticky = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = sticky?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = sticky?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        if (level < 0 || scale <= 0) return -1
        return (level * 100) / scale
    }

    private fun ensureEngineAndSend(
        context: Context,
        event: String,
        level: Int,
    ): Boolean {
        if (TileEngineHost.ensureEngine(context) == null) return false
        TileControlChannel.invokeWithRetry(
            METHOD_CHARGING_EVENT,
            mapOf(
                ARG_EVENT to event,
                ARG_LEVEL to level,
            ),
        )
        return true
    }

    companion object {
        const val METHOD_CHARGING_EVENT = "chargingEvent"
        const val ARG_EVENT = "event"
        const val ARG_LEVEL = "level"
        const val EVENT_CONNECTED = "connected"
        const val EVENT_DISCONNECTED = "disconnected"
        const val EVENT_LEVEL = "level"
    }
}

/**
 * Session state: watches battery level while charging so Dart can fire
 * milestone presets on upward threshold crossings. Process-lifetime only;
 * if the process dies mid-session the milestones resume on the next plug
 * event (documented limitation, surfaced honestly).
 */
object ChargingSession {

    @Volatile
    private var receiver: BroadcastReceiver? = null

    @Synchronized
    fun begin(context: Context) {
        end(context)
        val appContext = context.applicationContext
        val batteryReceiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                if (level < 0 || scale <= 0) return
                if (TileEngineHost.ensureEngine(ctx) == null) return
                TileControlChannel.invokeWithRetry(
                    ChargingReceiver.METHOD_CHARGING_EVENT,
                    mapOf(
                        ChargingReceiver.ARG_EVENT to ChargingReceiver.EVENT_LEVEL,
                        ChargingReceiver.ARG_LEVEL to (level * 100) / scale,
                    ),
                )
            }
        }
        receiver = batteryReceiver
        appContext.registerReceiver(
            batteryReceiver,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED),
        )
    }

    @Synchronized
    fun end(context: Context) {
        receiver?.let {
            try {
                context.applicationContext.unregisterReceiver(it)
            } catch (_: Throwable) {
                // Already unregistered; nothing to do.
            }
        }
        receiver = null
    }
}
