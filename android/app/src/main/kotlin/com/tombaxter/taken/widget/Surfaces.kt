package com.tombaxter.taken.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi
import androidx.core.content.edit
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.updateAll
import com.tombaxter.taken.ProSource
import com.tombaxter.taken.TakenApp
import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.demo.DemoData
import com.tombaxter.taken.core.demo.TodoDemo
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.ProGate
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.stack.WidgetSnapshot
import com.tombaxter.taken.core.surfaces.SurfaceRefresh
import com.tombaxter.taken.core.surfaces.TakeAllTileFace
import com.tombaxter.taken.core.surfaces.TodoWidgetFace
import com.tombaxter.taken.core.theme.ThemeID
import com.tombaxter.taken.core.todo.TodoState
import com.tombaxter.taken.data.TakenStores
import com.tombaxter.taken.tile.TakeAllTileService
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.ZoneId
import java.util.Locale

/**
 * Taken's surfaces outside the app on Android (SPEC-ANDROID 10.1 and 10.2): the stack widget, the to-do widget and the Take
 * all tile, kept in line with the files. The iPhone redraws its widgets and its control after every write
 * (`Sync.afterWrite`) and gives WidgetKit a timeline; Android has no timeline, so [refresh] is the one entry point, safe at
 * any moment, from any process part:
 * 1. running widget sessions recompose with the time now (they follow the files themselves), and every placed widget is
 *    asked to update (`GlanceAppWidget.updateAll`, https://developer.android.com/develop/ui/compose/glance/glance-app-widget);
 * 2. the tile is asked to listen again (`TileService.requestListeningState`, which an active tile needs after each change,
 *    https://developer.android.com/develop/ui/views/quicksettings-tiles);
 * 3. one non-waking alarm is armed for the next moment the surfaces change without a write ([SurfaceRefresh.next]: the
 *    rollover, an item's hour ending, cached Pro running out, a to-do's due time), only while a widget or the tile is in
 *    place [Own choice from documented parts: `AlarmManager.set(RTC, ...)`, which "does not wake the device up",
 *    https://developer.android.com/develop/background-work/services/alarms/schedule].
 *
 * Callers: every change to taken.json, pro.json or todos.json (AppContainer), the alarm, a widget's own update, a restart,
 * a clock or time zone change and an update of Taken (the reminders' restart receiver), Taken coming to the front, and Pro
 * changing (`AppContainer.proChanged`, from `AppModel.onProChanged` or a surface's recheck, SPEC-ANDROID 9.7).
 */
class Surfaces(
    context: Context,
    private val stores: TakenStores,
    private val pro: () -> ProSource,
    private val clock: () -> Instant,
    private val zone: () -> ZoneId,
    private val scope: CoroutineScope,
    /**
     * Asks Google Play again when the cached answer is a subscription past its check horizon, before anything is drawn
     * locked (`AppContainer.recheckProIfStale`): on Android that horizon is not the end of the period paid for.
     */
    private val recheckPro: suspend () -> Unit = {},
    /** Whether anything is armed, so the restart receiver is enabled while a surface needs the alarm put back. */
    private val onArmed: (Boolean) -> Unit = {},
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
) {
    private val app: Context = context.applicationContext

    /** What every surface is drawn from: the three files, and a tick that moves the time on. */
    data class Inputs(val stack: StackState, val ledger: ProLedger?, val todos: TodoState, val tick: Long = 0)

    private val ticks = MutableStateFlow(0L)

    /**
     * The look the surfaces last read: what a widget that cannot be drawn shows its card in ([WidgetFallback]), since the
     * files may be what failed. Signal until a first read.
     */
    @Volatile
    var look: ThemeID = ThemeID.SIGNAL
        private set

    /** The files as they change, for widget sessions to follow. A file that cannot be read now stops nothing. */
    val inputs: Flow<Inputs> = combine(stores.stack.data, stores.ledger.data, stores.todos.data, ticks) { stack, ledger, todos, tick ->
        look = stack.settings.theme
        Inputs(stack, ledger.ledger, todos, tick)
    }.catch { }

    suspend fun read(): Inputs = Inputs(
        stores.stack.data.first().also { look = it.settings.theme },
        stores.ledger.data.first().ledger,
        stores.todos.data.first(),
        ticks.value,
    )

    /**
     * Logging needs Taken Pro (PRO.md): Pro's answer is the source's, or pro.json's cached one while the source has none yet
     * (a widget in a fresh process), as the iPhone's surfaces read the ledger. This is how the surfaces are drawn; a tap
     * that logs goes through [com.tombaxter.taken.ProRecheck] in [SurfaceActions], which also asks Google Play once more
     * when a subscription's cached horizon ran out (the iPhone's `ProGate.mayLog`, SPEC-ANDROID 9.3 and 9.4).
     */
    fun locked(inputs: Inputs, now: Instant, source: ProSource = pro()): Boolean {
        val status = source.status ?: inputs.ledger?.status
        val access = ProGate.access(
            status, settled = true, legacyLog = false, hasLogged = ProGate.hasLogged(inputs.stack, inputs.ledger), now = now,
        )
        return !access.allowsLogging
    }

    fun snapshot(inputs: Inputs, now: Instant = clock()): WidgetSnapshot =
        WidgetSnapshot(inputs.stack, now, zone(), locked(inputs, now))

    fun todoFace(inputs: Inputs, now: Instant = clock(), locale: Locale = Locale.getDefault()): TodoWidgetFace =
        TodoWidgetFace(inputs.todos, now, DayClock(inputs.stack.settings.dayStartHour, zone()), locale)

    suspend fun tileFace(): TakeAllTileFace = TakeAllTileFace(snapshot(read()))

    /** The demo stack in the person's look, for previews (the iPhone's `WidgetSnapshot.demo(now:theme:)`). */
    suspend fun demoSnapshot(): WidgetSnapshot {
        val look = runCatching { stores.stack.data.first().settings.theme }.getOrDefault(ThemeID.SIGNAL)
        val zone = zone()
        return WidgetSnapshot.demo(DemoData.referenceNow(clock(), zone), look, zone)
    }

    /** The demo to-dos (a time tonight, a day this week, one with no day) and the person's look. */
    suspend fun demoTodoFace(): Pair<TodoWidgetFace, ThemeID> {
        val look = runCatching { stores.stack.data.first().settings.theme }.getOrDefault(ThemeID.SIGNAL)
        val zone = zone()
        val now = DemoData.referenceNow(clock(), zone)
        val clock = DayClock(DemoData.settings.dayStartHour, zone)
        return TodoWidgetFace(TodoDemo.state(now, recording = false, zone = zone), now, clock, Locale.getDefault()) to look
    }

    // MARK: Refresh

    private val mutex = Mutex()
    private val lock = Any()
    private var requested = 0L
    private var finished = 0L

    /**
     * Redraws every surface and arms the next refresh. One at a time, off the main thread; a caller returns once a refresh
     * that began after its call has finished, and calls that arrive while one runs share the next one.
     */
    suspend fun refresh(): Unit = withContext(dispatcher) {
        val ticket = synchronized(lock) { ++requested }
        mutex.withLock {
            if (synchronized(lock) { finished >= ticket }) return@withContext
            val covers = synchronized(lock) { requested }
            try {
                // An expired horizon means "ask Play", never "ended": the widget's redraw at cached Pro's end asks first.
                recheckPro()
                ticks.value = ticks.value + 1
                redraw()
                armNow()
            } finally {
                synchronized(lock) { finished = covers }
            }
        }
    }

    /** [refresh] on the app's scope, for callers that cannot wait. */
    fun refreshSoon() {
        scope.launch { refresh() }
    }

    /** Arms (or cancels) the next refresh without redrawing: a widget's own update has just drawn it. */
    fun armSoon() {
        scope.launch { withContext(dispatcher) { mutex.withLock { armNow() } } }
    }

    private suspend fun redraw() {
        // Each widget only when one is placed: a call with none placed would still read Glance's own records.
        if (placed(StackWidgetReceiver::class.java) > 0) runCatching { StackWidget().updateAll(app) }
        if (placed(TodoWidgetReceiver::class.java) > 0) runCatching { TodoWidget().updateAll(app) }
        // An active tile is drawn only when it asks to listen. Harmless when it is not in quick settings.
        runCatching { TileService.requestListeningState(app, ComponentName(app, TakeAllTileService::class.java)) }
    }

    private suspend fun armNow() {
        val alarms = app.getSystemService(AlarmManager::class.java) ?: return
        val intent = refreshIntent()
        val needed = placed(StackWidgetReceiver::class.java) + placed(TodoWidgetReceiver::class.java) > 0 || tileAdded
        val inputs = if (needed) runCatching { read() }.getOrNull() else null
        if (inputs == null) {
            alarms.cancel(intent)
            onArmed(false)
            return
        }
        val now = clock()
        val status = pro().status ?: inputs.ledger?.status
        val at = SurfaceRefresh.next(snapshot(inputs, now), status, inputs.todos, now)
        alarms.set(AlarmManager.RTC, at.toEpochMilli(), intent)
        onArmed(true)
    }

    private fun refreshIntent(): PendingIntent = PendingIntent.getBroadcast(
        app,
        0,
        Intent(app, SurfaceRefreshReceiver::class.java).setAction(SurfaceRefreshReceiver.ACTION),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    /** How many of a widget are on the home screen. */
    fun placed(receiver: Class<*>): Int =
        runCatching { AppWidgetManager.getInstance(app)?.getAppWidgetIds(ComponentName(app, receiver))?.size ?: 0 }.getOrDefault(0)

    /** A Taken stack widget is on the home screen: Today's widget invite is answered (SPEC-ANDROID 10.1). */
    suspend fun stackWidgetPlaced(): Boolean = withContext(dispatcher) {
        runCatching { GlanceAppWidgetManager(app).getGlanceIds(StackWidget::class.java).isNotEmpty() }.getOrDefault(false)
    }

    // MARK: The tile's place

    private val prefs: SharedPreferences get() = app.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /**
     * The Take all tile is in quick settings, as its service last heard (`onTileAdded`, `onTileRemoved`). Kept outside Auto
     * Backup's list, so a restored phone asks again.
     */
    var tileAdded: Boolean
        get() = prefs.getBoolean(KEY_TILE_ADDED, false)
        set(value) {
            prefs.edit { putBoolean(KEY_TILE_ADDED, value) }
            armSoon()
        }

    // MARK: Generated previews

    /**
     * Publishes the widget picker's previews on Android 15 and later, in the person's look: when Taken first opens and when
     * the look changes ("Set the preview on first app launch", and the calls are "rate-limited ... approximately two calls
     * per hour", https://developer.android.com/develop/ui/views/appwidgets/previews). A rate-limited call is tried again
     * once Taken next comes to the front, at most every 30 minutes [Own choice].
     */
    fun publishPreviews(look: ThemeID) {
        if (Build.VERSION.SDK_INT >= 35) publishPreviews35(look)
    }

    @RequiresApi(35)
    private fun publishPreviews35(look: ThemeID) {
        if (prefs.getString(KEY_PREVIEW_LOOK, null) == look.raw) return
        val now = System.currentTimeMillis()
        if (now - prefs.getLong(KEY_PREVIEW_TRIED, 0L) < PREVIEW_RETRY_MS) return
        prefs.edit { putLong(KEY_PREVIEW_TRIED, now) }
        scope.launch {
            withContext(Dispatchers.Default) {
                val manager = GlanceAppWidgetManager(app)
                val results = listOf(StackWidgetReceiver::class, TodoWidgetReceiver::class).map { receiver ->
                    runCatching { manager.setWidgetPreviews(receiver) }.getOrDefault(-1)
                }
                if (results.all { it == GlanceAppWidgetManager.SET_WIDGET_PREVIEWS_RESULT_SUCCESS }) {
                    prefs.edit {
                        putString(KEY_PREVIEW_LOOK, look.raw)
                        putLong(KEY_PREVIEW_TRIED, 0L)
                    }
                }
            }
        }
    }

    companion object {
        private const val PREFS = "taken.surfaces"
        private const val KEY_TILE_ADDED = "tileAdded"
        private const val KEY_PREVIEW_LOOK = "previewLook"
        private const val KEY_PREVIEW_TRIED = "previewTried"
        private const val PREVIEW_RETRY_MS = 30L * 60 * 1000
    }
}

/** The surfaces' own alarm: the day rolled over, an item's hour is up, cached Pro ran out, or a to-do came due. */
class SurfaceRefreshReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION) return
        val container = (context.applicationContext as TakenApp).container
        val pending = goAsync()
        container.scope.launch {
            try {
                container.surfaces.refresh()
            } finally {
                pending.finish()
            }
        }
    }

    companion object {
        const val ACTION = "com.tombaxter.taken.surfaces.REFRESH"
    }
}
