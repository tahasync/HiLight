package com.tahasync.hilight.torch

/**
 * Static hardware capability of the device's rear flash as reported by the
 * Android Camera2 API.
 *
 * [supportsStrength] is true only when the camera HAL advertises a maximum
 * strength level greater than 1; otherwise the torch is ON/OFF only.
 */
data class TorchCapability(
    val cameraId: String?,
    val hasFlash: Boolean,
    val torchAvailable: Boolean,
    val supportsStrength: Boolean,
    val maxStrengthLevel: Int,
) {
    /** Wire format for the hilight/torch platform channel. */
    fun toMap(): Map<String, Any?> = mapOf(
        "cameraId" to cameraId,
        "hasFlash" to hasFlash,
        "torchAvailable" to torchAvailable,
        "supportsStrength" to supportsStrength,
        "maxStrengthLevel" to maxStrengthLevel,
    )
}
