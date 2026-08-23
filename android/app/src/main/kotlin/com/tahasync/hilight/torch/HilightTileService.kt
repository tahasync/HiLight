package com.tahasync.hilight.torch

import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Quick Settings tile for HiLight (prd-v1.1.md §4).
 *
 * Tapping toggles the default animation. The displayed state always mirrors
 * the engine's actual state via `stateChanged` — including when a
 * non-continuous animation finishes on its own — never just the last tap.
 */
class HilightTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        TileEngineHost.stateListener = ::renderTile
        renderTile(TileEngineHost.lastKnownActive)
        if (TileEngineHost.isEngineAlive) {
            TileControlChannel.invokeWithRetry("refreshState")
        }
    }

    override fun onStopListening() {
        // The cached-app freezer can suspend the process once the panel
        // closes; a tile-triggered animation must never outlive it, or the
        // torch could stay lit with no way to complete (§11/§17).
        TileControlChannel.invokeWithRetry("tileStop")
        TileEngineHost.stateListener = null
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        val control = TileEngineHost.ensureEngine(applicationContext)
        if (control == null) {
            // Engine unavailable: stay idle rather than appearing to succeed.
            renderTile(false)
            return
        }
        TileControlChannel.invokeWithRetry("toggle")
    }

    override fun onDestroy() {
        TileEngineHost.stateListener = null
        super.onDestroy()
    }

    private fun renderTile(active: Boolean) {
        val tile = qsTile ?: return
        tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.subtitle = if (active) "Playing…" else "Idle"
        tile.updateTile()
    }
}
