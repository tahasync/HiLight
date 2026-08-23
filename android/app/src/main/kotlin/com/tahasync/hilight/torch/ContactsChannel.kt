package com.tahasync.hilight.torch

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.database.Cursor
import android.net.Uri
import android.provider.ContactsContract
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Contacts bridge for per-contact pattern overrides (prd-v1.2.md §2).
 *
 * Permissions discipline: READ_CONTACTS is a runtime permission and is only
 * requested through [METHOD_REQUEST_READ] — which the Dart side calls at the
 * exact moment the user taps "Add contact", after an explanatory dialog.
 * Nothing contacts-related happens at launch or in bulk.
 *
 * Channel name: `hilight/contacts`
 * Methods:
 *  - isReadContactsGranted -> Boolean
 *  - requestReadContacts   -> Boolean (granted); async via permission dialog
 *  - pickContact           -> String? (picked contact data URI); async
 *  - readPickedContact     -> Map {displayName, number, lookupKey} | null
 *
 * Activity results are routed back here from MainActivity.
 */
object ContactsChannel {

    const val NAME = "hilight/contacts"
    private const val METHOD_IS_GRANTED = "isReadContactsGranted"
    private const val METHOD_REQUEST_READ = "requestReadContacts"
    private const val METHOD_PICK = "pickContact"
    private const val METHOD_READ_PICKED = "readPickedContact"

    @Volatile
    private var appContext: android.content.Context? = null

    @Volatile
    private var activity: Activity? = null

    private var pendingPermission: MethodChannel.Result? = null
    private var pendingPick: MethodChannel.Result? = null

    fun register(flutterEngine: FlutterEngine, activity: Activity) {
        this.activity = activity
        appContext = activity.applicationContext
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    METHOD_IS_GRANTED -> result.success(isGranted())
                    METHOD_REQUEST_READ -> handleRequestRead(result)
                    METHOD_PICK -> handlePick(result)
                    METHOD_READ_PICKED -> {
                        val uri = call.argument<String>(ARG_URI)
                        result.success(
                            if (uri.isNullOrBlank()) null
                            else readPickedContact(Uri.parse(uri)),
                        )
                    }
                    else -> result.notImplemented()
                }
            }
    }

    fun detachIfBoundTo(activity: Activity?) {
        if (this.activity === activity) this.activity = null
    }

    /** Routes the picker result from MainActivity.onActivityResult. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_PICK_CONTACT) return
        val pending = pendingPick ?: return
        pendingPick = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            pending.success(null)
            return
        }
        pending.success(data.data.toString())
    }

    /** Routes the runtime-permission outcome from MainActivity. */
    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ) {
        if (requestCode != REQUEST_READ_CONTACTS) return
        val pending = pendingPermission ?: return
        pendingPermission = null
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pending.success(granted)
    }

    private fun isGranted(): Boolean =
        appContext?.checkSelfPermission(Manifest.permission.READ_CONTACTS) ==
            PackageManager.PERMISSION_GRANTED ||
            activity?.checkSelfPermission(Manifest.permission.READ_CONTACTS) ==
            PackageManager.PERMISSION_GRANTED

    private fun handleRequestRead(result: MethodChannel.Result) {
        if (isGranted()) {
            result.success(true)
            return
        }
        val currentActivity = activity
        if (currentActivity == null || pendingPermission != null) {
            result.success(false)
            return
        }
        pendingPermission = result
        @SuppressLint("InlinedApi")
        currentActivity.requestPermissions(
            arrayOf(Manifest.permission.READ_CONTACTS),
            REQUEST_READ_CONTACTS,
        )
    }

    private fun handlePick(result: MethodChannel.Result) {
        val currentActivity = activity ?: run {
            result.success(null)
            return
        }
        // Picking a phone row returns one concrete number for the contact.
        // No resolveActivity pre-check: package-visibility filtering makes
        // it unreliable; an unresolvable intent throws below and surfaces
        // as null instead.
        pendingPick = result
        try {
            val intent = Intent(Intent.ACTION_PICK)
                .setType(ContactsContract.CommonDataKinds.Phone.CONTENT_TYPE)
            currentActivity.startActivityForResult(intent, REQUEST_PICK_CONTACT)
        } catch (_: Throwable) {
            pendingPick = null
            result.success(null)
        }
    }

    /**
     * Reads display name, raw number, and lookup key from a picked phone-row
     * URI. Requires READ_CONTACTS to already be granted (it is, by flow).
     */
    private fun readPickedContact(uri: Uri): Map<String, String?>? {
        val resolver = appContext?.contentResolver ?: return null
        var cursor: Cursor? = null
        return try {
            cursor = resolver.query(
                uri,
                arrayOf(
                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                    ContactsContract.CommonDataKinds.Phone.NUMBER,
                    ContactsContract.CommonDataKinds.Phone.LOOKUP_KEY,
                ),
                null,
                null,
                null,
            )
            if (cursor != null && cursor.moveToFirst()) {
                mapOf(
                    KEY_DISPLAY_NAME to cursor.getString(0),
                    KEY_NUMBER to cursor.getString(1),
                    KEY_LOOKUP_KEY to cursor.getString(2),
                )
            } else {
                null
            }
        } catch (_: Throwable) {
            null
        } finally {
            try {
                cursor?.close()
            } catch (_: Throwable) {
            }
        }
    }

    // Request codes routed through MainActivity.
    const val REQUEST_READ_CONTACTS = 4201
    const val REQUEST_PICK_CONTACT = 4202
    const val ARG_URI = "uri"
    const val KEY_DISPLAY_NAME = "displayName"
    const val KEY_NUMBER = "number"
    const val KEY_LOOKUP_KEY = "lookupKey"
}
