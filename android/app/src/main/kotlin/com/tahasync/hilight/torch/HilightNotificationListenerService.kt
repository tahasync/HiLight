package com.tahasync.hilight.torch

import android.content.ComponentName
import android.content.Context
import android.os.PowerManager
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Notification-listener bridge for trigger effects (prd-v1.2.md §2).
 *
 * The service deliberately stays a dumb pipe: it extracts only presence-level
 * metadata (category, posting package, ongoing flag — never message text or
 * sender details, prd-v1.2.md §7) and forwards it to the shared Flutter
 * engine, which owns all decision logic (classification, enable flags,
 * preset resolution) so it stays unit-testable in Dart.
 *
 * Playback runs through the same engine host as the Quick Settings tile:
 * the Activity's engine when open, otherwise a headless engine on `tileMain`.
 *
 * Wake lock: a notification can arrive while the screen is off and the
 * cached-app freezer could suspend Dart mid-animation and strand the torch.
 * A partial wake lock (with a hard timeout backstop) covers each trigger
 * playback; [TileEngineHost.onStateChanged] releases it as soon as Dart
 * reports idle. WAKE_LOCK is a normal install-time permission — no prompt.
 */
class HilightNotificationListenerService : NotificationListenerService() {

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        super.onNotificationRemoved(sbn)
        if (sbn == null) return
        val packageName = sbn.packageName ?: return
        if (packageName == this.packageName) return
        // A ringing call ends when its CallStyle notification goes away
        // (answered, declined, or missed) — tell Dart so a looping ring
        // animation stops immediately (prd-v1.2.md §2 + user requirement).
        val category = sbn.notification?.category
        val isCall = category == android.app.Notification.CATEGORY_CALL ||
            packageName in callLikePackages
        if (!isCall) return
        TriggerWakeLock.acquire(this)
        if (TileEngineHost.ensureEngine(this) == null) {
            TriggerWakeLock.releaseIfHeld()
            return
        }
        TileControlChannel.invokeWithRetry(
            METHOD_TRIGGER_EVENT,
            mapOf(
                ARG_PACKAGE_NAME to packageName,
                ARG_REMOVED to true,
            ),
        )
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        super.onNotificationPosted(sbn)
        if (sbn == null) return
        val packageName = sbn.packageName ?: return
        // Never react to our own notifications; that would feed back loops.
        if (packageName == this.packageName) return
        // Category is a direct field on Notification (there is no extras
        // key for it); null when the poster set none.
        val category = sbn.notification?.category
        val isOngoing = sbn.isOngoing
        // Presence flag only (never the value) — helps Dart debug why a
        // ring notification carried no caller identity.
        val hasCallPerson = run {
            if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.S) {
                false
            } else {
                try {
                    sbn.notification?.extras
                        ?.containsKey(android.app.Notification.EXTRA_CALL_PERSON) == true
                } catch (_: Throwable) {
                    false
                }
            }
        }
        val callUri = extractCallerUri(sbn)

        TriggerWakeLock.acquire(this)
        TileEngineHost.ensureEngine(this) ?: run {
            TriggerWakeLock.releaseIfHeld()
            return
        }
        TileControlChannel.invokeWithRetry(
            METHOD_TRIGGER_EVENT,
            mapOf(
                ARG_PACKAGE_NAME to packageName,
                ARG_CATEGORY to category,
                ARG_IS_ONGOING to isOngoing,
                ARG_HAS_CALL_PERSON to hasCallPerson,
                ARG_CALL_URI to callUri,
            ),
        )
    }

    /**
     * Extracts the caller URI (usually `tel:…`) from a CallStyle ring
     * notification so Dart can match per-contact overrides. Only the URI is
     * forwarded — matching data allowed by prd-v1.2.md §7, never logged and
     * never stored by the native layer.
     *
     * Uses [android.app.Notification.EXTRA_CALL_PERSON] ("android.callPerson",
     * API 31) exclusively; there is no framework EXTRA_PERSON constant, and
     * unverified keys are off-limits per project rules.
     */
    private fun extractCallerUri(sbn: StatusBarNotification): String? {
        if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.S) {
            return null // EXTRA_CALL_PERSON requires API 31.
        }
        val extras = sbn.notification?.extras ?: return null
        val person = try {
            extras.get(android.app.Notification.EXTRA_CALL_PERSON)
                as? android.app.Person
        } catch (_: Throwable) {
            null
        }
        return person?.uri?.toString()?.takeIf { it.isNotBlank() }
    }    companion object {
        const val METHOD_TRIGGER_EVENT = "triggerEvent"
        const val ARG_PACKAGE_NAME = "packageName"
        const val ARG_CATEGORY = "category"
        const val ARG_IS_ONGOING = "isOngoing"
        const val ARG_HAS_CALL_PERSON = "hasCallPerson"
        const val ARG_CALL_URI = "callUri"
        const val ARG_REMOVED = "removed"

        /// Packages treated as call sources for removal events even when a
        /// notification lacks CATEGORY_CALL (presence-level names only).
        private val callLikePackages = setOf(
            "com.google.android.dialer",
            "com.android.dialer",
            "com.samsung.android.dialer",
            "com.samsung.android.app.telephonyui",
            "com.android.incallui",
            "com.whatsapp",
            "com.whatsapp.w4b",
        )

        /**
         * Whether this app currently holds notification-listener access.
         *
         * Reads the framework's `enabled_notification_listeners` secure
         * setting and matches this service's component — the canonical
         * check, stable across OEM skins. (The androidx
         * NotificationManagerCompat helper would also work but is avoided
         * here to keep the native layer dependency-free.)
         */
        fun isAccessGranted(context: Context): Boolean {
            val cn = ComponentName(context, HilightNotificationListenerService::class.java)
            val flat = Settings.Secure.getString(
                context.contentResolver,
                SETTING_ENABLED_LISTENERS,
            ) ?: return false
            for (entry in flat.split(":")) {
                if (ComponentName.unflattenFromString(entry) == cn) return true
            }
            return false
        }

        private const val SETTING_ENABLED_LISTENERS = "enabled_notification_listeners"
    }
}

/**
 * Process-wide partial wake lock for trigger playback. Reference counting is
 * disabled so acquire/release pairs from overlapping triggers stay balanced;
 * the hard timeout guarantees the lock can never be held indefinitely even
 * if the idle callback were lost.
 */
object TriggerWakeLock {

    private const val TAG = "hilight:trigger"
    private const val TIMEOUT_MS = 60_000L

    private var lock: PowerManager.WakeLock? = null

    @Synchronized
    fun acquire(context: Context) {
        val existing = lock
        if (existing != null && existing.isHeld) return
        val powerManager =
            context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
        val wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, TAG)
        wakeLock.setReferenceCounted(false)
        // acquire(timeout) is the backstop: even if releaseIfHeld were never
        // reached, the lock expires on its own.
        wakeLock.acquire(TIMEOUT_MS)
        lock = wakeLock
    }

    @Synchronized
    fun releaseIfHeld() {
        val wakeLock = lock ?: return
        try {
            if (wakeLock.isHeld) wakeLock.release()
        } catch (_: Throwable) {
            // A fully-expired lock can no longer be released; harmless.
        }
    }
}
