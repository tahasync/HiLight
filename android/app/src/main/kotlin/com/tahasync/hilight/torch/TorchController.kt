package com.tahasync.hilight.torch

import android.content.Context
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata

/**
 * Discovers the device's rear flash unit through the system [CameraManager]
 * and performs torch operations on it. No camera ID is hard-coded; discovery
 * is performed at runtime against every camera the system exposes.
 *
 * All methods may throw [CameraAccessException] when the flash is busy or
 * unavailable, [IllegalArgumentException] for invalid strength levels, and
 * [IllegalStateException] when no flash unit exists. Callers are expected to
 * translate these into structured errors.
 */
class TorchController(context: Context) {

    private val cameraManager =
        context.getSystemService(Context.CAMERA_SERVICE) as CameraManager

    private var cachedCapabilities: TorchCapability? = null

    /**
     * Queries the flash-capable camera and maps its characteristics onto a
     * [TorchCapability]. Returns a capability with `hasFlash = false` when no
     * flash unit exists on the device.
     */
    fun getCapabilities(): TorchCapability {
        cachedCapabilities?.let { return it }
        val cameraId = findFlashCameraId()
            ?: return TorchCapability(
                cameraId = null,
                hasFlash = false,
                torchAvailable = false,
                supportsStrength = false,
                maxStrengthLevel = DEFAULT_MAX_STRENGTH_LEVEL,
            )
        val characteristics = cameraManager.getCameraCharacteristics(cameraId)
        val hasFlash =
            characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
        val maxLevel = characteristics.get(
            CameraCharacteristics.FLASH_INFO_STRENGTH_MAXIMUM_LEVEL,
        ) ?: DEFAULT_MAX_STRENGTH_LEVEL
        val capability = TorchCapability(
            cameraId = cameraId,
            hasFlash = hasFlash,
            torchAvailable = hasFlash,
            supportsStrength = hasFlash && maxLevel > DEFAULT_MAX_STRENGTH_LEVEL,
            maxStrengthLevel = if (hasFlash) maxLevel else DEFAULT_MAX_STRENGTH_LEVEL,
        )
        if (hasFlash) cachedCapabilities = capability
        return capability
    }

    /** Turns the torch on at the device's default brightness level. */
    fun turnOn() {
        cameraManager.setTorchMode(flashCameraId(), true)
    }

    /** Turns the torch off. */
    fun turnOff() {
        cameraManager.setTorchMode(flashCameraId(), false)
    }

    /**
     * Turns the torch on at the given strength level; per the Android API this
     * also turns the torch on when it was previously off. [level] must be
     * within 1..maxStrengthLevel as reported by [getCapabilities].
     */
    fun setStrength(level: Int) {
        val capability = getCapabilities()
        if (!capability.supportsStrength ||
            level !in DEFAULT_MAX_STRENGTH_LEVEL..capability.maxStrengthLevel
        ) {
            throw IllegalArgumentException(
                "strength level $level outside supported range " +
                    "1..${capability.maxStrengthLevel}",
            )
        }
        cameraManager.turnOnTorchWithStrengthLevel(capability.cameraId!!, level)
    }

    /**
     * Returns the current torch strength level, or the device's default level
     * while the torch is off (per the Android API contract).
     */
    fun getStrength(): Int = cameraManager.getTorchStrengthLevel(flashCameraId())

    private fun flashCameraId(): String =
        getCapabilities().cameraId ?: throw IllegalStateException("No flash unit found")

    /**
     * Finds the back-facing camera with a flash unit; falls back to any
     * flash-capable camera when no back-facing one advertises a flash, and
     * returns null when the device has no usable flash unit.
     */
    private fun findFlashCameraId(): String? {
        var fallbackId: String? = null
        for (id in cameraManager.cameraIdList) {
            val characteristics = runCatching { cameraManager.getCameraCharacteristics(id) }
                .getOrNull() ?: continue
            if (characteristics.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) != true) {
                continue
            }
            if (characteristics.get(CameraCharacteristics.LENS_FACING) ==
                CameraMetadata.LENS_FACING_BACK
            ) {
                return id
            }
            if (fallbackId == null) fallbackId = id
        }
        return fallbackId
    }

    private companion object {
        const val DEFAULT_MAX_STRENGTH_LEVEL = 1
    }
}
