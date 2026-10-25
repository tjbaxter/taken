package com.tombaxter.taken.tile

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import com.tombaxter.taken.R
import com.tombaxter.taken.TakenApp
import com.tombaxter.taken.core.surfaces.TakeAllTileFace
import com.tombaxter.taken.core.surfaces.TileIcon
import com.tombaxter.taken.core.surfaces.TileState
import com.tombaxter.taken.core.surfaces.WidgetTap
import com.tombaxter.taken.widget.SurfaceActions
import com.tombaxter.taken.widget.takenIntent
import kotlinx.coroutines.launch

/**
 * The Quick Settings tile "Take all" (SPEC-ANDROID 10.2), the iPhone's Control Center control: one tap logs every pending
 * dose, from the lock screen too and with no unlock, as the iPhone's control does. It says a count ("2 left"), never an
 * item's name, because tiles show over the lock screen. Locked: "Taken Pro" with a lock, and a tap opens the paywall with
 * the Take all kept, after the person unlocks ("If the tile action is unsafe, use unlockAndRun()").
 *
 * Active mode (https://developer.android.com/develop/ui/views/quicksettings-tiles): the system binds it when Taken asks
 * (`requestListeningState`, after every write, [com.tombaxter.taken.widget.Surfaces.refresh]) and when it is tapped, and
 * it draws itself once per listening. Opening Taken uses `startActivityAndCollapse(PendingIntent)` from Android 14, where
 * the Intent form throws for apps targeting it (https://developer.android.com/about/versions/14/behavior-changes-14).
 */
class TakeAllTileService : TileService() {
    private val container get() = (application as TakenApp).container

    @Volatile
    private var listening = false

    override fun onTileAdded() {
        container.surfaces.tileAdded = true
    }

    override fun onTileRemoved() {
        container.surfaces.tileAdded = false
    }

    override fun onStartListening() {
        listening = true
        // The tile is there: whatever added it, Profile stops offering it.
        if (!container.surfaces.tileAdded) container.surfaces.tileAdded = true
        container.scope.launch {
            val face = runCatching { container.surfaces.tileFace() }.getOrNull() ?: return@launch
            if (listening) draw(face)
        }
    }

    override fun onStopListening() {
        listening = false
    }

    override fun onClick() {
        container.scope.launch {
            val face = runCatching { container.surfaces.tileFace() }.getOrNull() ?: return@launch
            when (val tap = face.tap) {
                WidgetTap.TakeAll -> {
                    SurfaceActions.takeAll(container)
                    runCatching { container.surfaces.tileFace() }.getOrNull()?.let { if (listening) draw(it) }
                }
                is WidgetTap.Open -> open(tap.url)
                else -> Unit
            }
        }
    }

    private fun draw(face: TakeAllTileFace) {
        val tile = qsTile ?: return
        tile.label = face.label
        tile.contentDescription = face.spoken
        tile.state = when (face.state) {
            TileState.ACTIVE -> Tile.STATE_ACTIVE
            TileState.INACTIVE -> Tile.STATE_INACTIVE
        }
        tile.icon = Icon.createWithResource(this, if (face.icon == TileIcon.LOCK) R.drawable.ic_widget_lock else R.drawable.ic_stat_taken)
        if (Build.VERSION.SDK_INT >= 29) tile.subtitle = face.subtitle
        if (Build.VERSION.SDK_INT >= 30) tile.stateDescription = face.subtitle
        tile.updateTile()
    }

    /** Taken opened on a link, the panel collapsed; over the lock screen, once the person has unlocked. */
    private fun open(url: String) {
        val start = Runnable { startTaken(url) }
        if (isLocked) unlockAndRun(start) else start.run()
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    private fun startTaken(url: String) {
        val intent = takenIntent(this, url)
        if (Build.VERSION.SDK_INT >= 34) {
            val pending = PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            startActivityAndCollapse(pending)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
