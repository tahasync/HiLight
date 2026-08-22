package com.tahasync.hilight.torch

import android.hardware.camera2.CameraAccessException
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Platform-channel bridge between the Dart TorchService and [TorchController].
 *
 * Channel name: `hilight/torch`
 *
 * Methods:
 *  - getCapabilities -> Map: cameraId/hasFlash/torchAvailable/supportsStrength/maxStrengthLevel
 *  - getDeviceInfo   -> Map: deviceModel/androidVersion
 *  - turnOn          -> null
 *  - turnOff         -> null
 *  - setStrength     -> args { level: Int }, returns null
 *  - getStrength     -> Int
 *
 * Error codes surfaced through result.error:
 *  noFlash, cameraInUse, maxCamerasInUse, cameraDisconnected,
 *  cameraDisabled, cameraError, invalidArgument, unknown
 */
class TorchChannel(private val controller: TorchController) {

    /** Registers this channel's handler on the given engine. */
    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        METHOD_GET_CAPABILITIES -> {
                            result.success(controller.getCapabilities().toMap())
                        }
                        METHOD_TURN_ON -> {
                            controller.turnOn()
                            result.success(null)
                        }
                        METHOD_TURN_OFF -> {
                            controller.turnOff()
                            result.success(null)
                        }
                        METHOD_SET_STRENGTH -> {
                            val level = call.argument<Int>(ARG_LEVEL)
                                ?: throw IllegalArgumentException(
                                    "Missing '$ARG_LEVEL' argument",
                                )
                            controller.setStrength(level)
                            result.success(null)
                        }
                        METHOD_GET_STRENGTH -> {
                            result.success(controller.getStrength())
                        }
                        METHOD_GET_DEVICE_INFO -> {
                            result.success(
                                mapOf(
                                    "deviceModel" to android.os.Build.MODEL,
                                    "androidVersion" to android.os.Build.VERSION.RELEASE,
                                ),
                            )
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: CameraAccessException) {
                    result.error(errorCodeFor(e), e.message, null)
                } catch (e: IllegalArgumentException) {
                    result.error(ERROR_INVALID_ARGUMENT, e.message, null)
                } catch (e: IllegalStateException) {
                    result.error(ERROR_NO_FLASH, e.message, null)
                } catch (e: Exception) {
                    result.error(ERROR_UNKNOWN, e.message, null)
                }
            }
    }

    private fun errorCodeFor(e: CameraAccessException): String = when (e.reason) {
        CameraAccessException.CAMERA_IN_USE -> ERROR_CAMERA_IN_USE
        CameraAccessException.MAX_CAMERAS_IN_USE -> ERROR_MAX_CAMERAS_IN_USE
        CameraAccessException.CAMERA_DISCONNECTED -> ERROR_CAMERA_DISCONNECTED
        CameraAccessException.CAMERA_DISABLED -> ERROR_CAMERA_DISABLED
        else -> ERROR_CAMERA_ERROR
    }

    companion object {
        const val CHANNEL_NAME = "hilight/torch"
        const val METHOD_GET_CAPABILITIES = "getCapabilities"
        const val METHOD_TURN_ON = "turnOn"
        const val METHOD_TURN_OFF = "turnOff"
        const val METHOD_SET_STRENGTH = "setStrength"
        const val METHOD_GET_STRENGTH = "getStrength"
        const val METHOD_GET_DEVICE_INFO = "getDeviceInfo"
        const val ARG_LEVEL = "level"
        const val ERROR_NO_FLASH = "noFlash"
        const val ERROR_CAMERA_IN_USE = "cameraInUse"
        const val ERROR_MAX_CAMERAS_IN_USE = "maxCamerasInUse"
        const val ERROR_CAMERA_DISCONNECTED = "cameraDisconnected"
        const val ERROR_CAMERA_DISABLED = "cameraDisabled"
        const val ERROR_CAMERA_ERROR = "cameraError"
        const val ERROR_INVALID_ARGUMENT = "invalidArgument"
        const val ERROR_UNKNOWN = "unknown"
    }
}
