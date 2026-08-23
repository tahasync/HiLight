package com.tahasync.hilight.torch

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Installed-apps bridge for per-app pattern overrides (prd-v1.2.md §3).
 *
 * Lists launchable apps via PackageManager (MAIN/LAUNCHER query). Visibility
 * on Android 11+ is granted by the matching <queries> entry in the manifest
 * — without it this list silently comes back empty.
 *
 * No permissions required; package names and labels are presence-level
 * data (prd-v1.2.md §7).
 *
 * Channel name: `hilight/apps`
 * Methods:
 *  - listLaunchableApps -> List<Map {packageName, appName}>
 */
object AppsChannel {

    const val NAME = "hilight/apps"
    private const val METHOD_LIST = "listLaunchableApps"

    /** Registers the handler on the given engine. */
    fun register(flutterEngine: FlutterEngine, context: Context) {
        val appContext = context.applicationContext
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    METHOD_LIST -> result.success(listLaunchableApps(appContext))
                    else -> result.notImplemented()
                }
            }
    }

    private fun listLaunchableApps(context: Context): List<Map<String, String>> {
        val packageManager = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolved = try {
            packageManager.queryIntentActivities(intent, 0)
        } catch (_: Throwable) {
            return emptyList()
        }
        val self = context.packageName
        return resolved
            .mapNotNull { info ->
                val pkg = info.activityInfo?.packageName ?: return@mapNotNull null
                if (pkg == self) return@mapNotNull null
                val label = try {
                    info.loadLabel(packageManager)?.toString() ?: pkg
                } catch (_: Throwable) {
                    pkg
                }
                mapOf(KEY_PACKAGE to pkg, KEY_APP_NAME to label)
            }
            .sortedBy { (it[KEY_APP_NAME] ?: it[KEY_PACKAGE] ?: "").lowercase() }
            .distinctBy { it[KEY_PACKAGE] }
    }

    private const val KEY_PACKAGE = "packageName"
    private const val KEY_APP_NAME = "appName"
}
