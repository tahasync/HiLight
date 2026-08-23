package com.tahasync.hilight.torch

import android.content.Context
import android.content.Intent
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Support channel for trigger settings (prd-v1.2.md §2/§5): notification
 * access status and a deep link to the system notification-access screen.
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
 */
object TriggerSupportChannel {

    const val NAME = "hilight/trigger_support"
    private const val METHOD_IS_GRANTED = "isNotificationAccessGranted"
    private const val METHOD_OPEN_SETTINGS = "openNotificationAccessSettings"

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
                    else -> result.notImplemented()
                }
            }
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
