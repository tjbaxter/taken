package com.tombaxter.taken

import android.app.StatusBarManager
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.graphics.drawable.Icon
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.glance.appwidget.GlanceAppWidgetManager
import com.tombaxter.taken.core.theme.ThemeID
import com.tombaxter.taken.tile.TakeAllTileService
import com.tombaxter.taken.widget.StackWidget
import com.tombaxter.taken.widget.StackWidgetReceiver
import com.tombaxter.taken.widget.Surfaces
import com.tombaxter.taken.widget.WidgetSizes
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * What Today and Profile need from Taken's widgets and tile (SPEC-ANDROID 10.1 and 10.2): whether a stack widget is on the
 * home screen (Today's widget invite), the launcher's pin dialog, Profile's offer of the tile, and a redraw when Taken
 * comes to the front or its look changes. The app's is [AndroidSurfaceHost]; tests and demo captures use their own.
 */
interface SurfaceHost {
    /** Reads whether a Taken stack widget is placed, and answers on the main thread. */
    fun checkStackWidget(answer: (Boolean) -> Unit)

    /** The launcher can pin a widget from inside Taken (`AppWidgetManager.isRequestPinAppWidgetSupported`). */
    val canPinWidget: Boolean

    /** Asks the launcher to pin the stack widget; the launcher shows its own dialog. */
    fun requestPinStackWidget()

    /** Profile offers the tile: Android 13 and later (`requestAddTileService`), until it is in quick settings. */
    val offersTile: Boolean

    /** Asks Android to add the tile; `answer` hears whether it is now in quick settings. */
    fun requestAddTile(answer: (Boolean) -> Unit)

    /** Taken came to the front: the surfaces catch up, and the widget picker's previews are published if they need to be. */
    fun didBecomeActive(look: ThemeID)

    /** The look changed: the widgets, the tile and the picker's previews follow it. */
    fun lookChanged(look: ThemeID)

    companion object {
        /** Nothing placed, nothing pinnable, no tile: for tests. */
        val none: SurfaceHost = fake()

        fun fake(placed: Boolean = false, canPin: Boolean = false, offersTile: Boolean = false): SurfaceHost = object : SurfaceHost {
            override fun checkStackWidget(answer: (Boolean) -> Unit) = answer(placed)
            override val canPinWidget = canPin
            override fun requestPinStackWidget() = Unit
            override val offersTile = offersTile
            override fun requestAddTile(answer: (Boolean) -> Unit) = answer(false)
            override fun didBecomeActive(look: ThemeID) = Unit
            override fun lookChanged(look: ThemeID) = Unit
        }
    }
}

/** The app's surfaces, through Android's AppWidgetManager, Glance and StatusBarManager. */
class AndroidSurfaceHost(context: Context, private val surfaces: Surfaces, private val scope: CoroutineScope) : SurfaceHost {
    private val app: Context = context.applicationContext

    override fun checkStackWidget(answer: (Boolean) -> Unit) {
        scope.launch { answer(surfaces.stackWidgetPlaced()) }
    }

    override val canPinWidget: Boolean
        get() = runCatching { AppWidgetManager.getInstance(app)?.isRequestPinAppWidgetSupported == true }.getOrDefault(false)

    /**
     * Glance's pin request, with the widget drawn from the person's own stack as its preview at the default 4x2
     * (https://developer.android.com/develop/ui/compose/glance/pin-in-app).
     */
    override fun requestPinStackWidget() {
        scope.launch {
            runCatching {
                GlanceAppWidgetManager(app).requestPinGlanceAppWidget(
                    receiver = StackWidgetReceiver::class.java,
                    preview = StackWidget(),
                    previewSize = WidgetSizes.MEDIUM,
                )
            }
        }
    }

    override val offersTile: Boolean
        get() = Build.VERSION.SDK_INT >= 33 && !surfaces.tileAdded

    override fun requestAddTile(answer: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT >= 33) requestAddTile33(answer) else answer(false)
    }

    /**
     * Android's own prompt to add the tile, in context, from Profile's row ("calling requestAddTileService() only in
     * context", https://developer.android.com/develop/ui/views/quicksettings-tiles). Added, or there already, ends the offer.
     */
    @RequiresApi(33)
    private fun requestAddTile33(answer: (Boolean) -> Unit) {
        val bar = app.getSystemService(StatusBarManager::class.java)
        if (bar == null) {
            answer(false)
            return
        }
        runCatching {
            bar.requestAddTileService(
                ComponentName(app, TakeAllTileService::class.java),
                app.getString(R.string.tile_take_all),
                Icon.createWithResource(app, R.drawable.ic_stat_taken),
                app.mainExecutor,
            ) { result ->
                val added = result == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ADDED ||
                    result == StatusBarManager.TILE_ADD_REQUEST_RESULT_TILE_ALREADY_ADDED
                if (added) surfaces.tileAdded = true
                answer(added)
            }
        }.onFailure { answer(false) }
    }

    override fun didBecomeActive(look: ThemeID) {
        surfaces.refreshSoon()
        surfaces.publishPreviews(look)
    }

    override fun lookChanged(look: ThemeID) {
        surfaces.publishPreviews(look)
    }
}
