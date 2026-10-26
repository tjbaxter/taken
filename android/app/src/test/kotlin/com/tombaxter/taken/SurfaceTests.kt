package com.tombaxter.taken

import android.app.AlarmManager
import android.content.ComponentName
import android.content.pm.PackageManager
import android.content.res.XmlResourceParser
import androidx.compose.ui.unit.dp
import androidx.glance.action.actionParametersOf
import androidx.glance.appwidget.testing.unit.hasRunCallbackClickAction
import androidx.glance.appwidget.testing.unit.hasStartActivityClickAction
import androidx.glance.appwidget.testing.unit.runGlanceAppWidgetUnitTest
import androidx.glance.testing.unit.hasTestTag
import androidx.test.core.app.ApplicationProvider
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.Item
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.pro.ProPendingAction
import com.tombaxter.taken.core.profile.Profile
import com.tombaxter.taken.core.retention.TodayPrompt
import com.tombaxter.taken.core.stack.WidgetSnapshot
import com.tombaxter.taken.core.stack.logDose
import com.tombaxter.taken.core.surfaces.StackWidgetFace
import com.tombaxter.taken.core.surfaces.SurfaceLinks
import com.tombaxter.taken.core.surfaces.TodoWidgetFace
import com.tombaxter.taken.core.surfaces.WidgetCopy
import com.tombaxter.taken.core.theme.Looks
import com.tombaxter.taken.core.theme.ThemeID
import com.tombaxter.taken.core.todo.TodoCaptureRoute
import com.tombaxter.taken.core.todo.TodoState
import com.tombaxter.taken.core.todo.TodoTask
import com.tombaxter.taken.data.LedgerFile
import com.tombaxter.taken.data.MemoryPersistence
import com.tombaxter.taken.notify.RescheduleReceiver
import com.tombaxter.taken.widget.LogNextAction
import com.tombaxter.taken.widget.StackWidgetContent
import com.tombaxter.taken.widget.SurfaceActions
import com.tombaxter.taken.widget.SurfaceOutcome
import com.tombaxter.taken.widget.SurfaceRefreshReceiver
import com.tombaxter.taken.widget.TakeAllAction
import com.tombaxter.taken.widget.TodoWidgetContent
import com.tombaxter.taken.widget.WidgetSizes
import com.tombaxter.taken.widget.takenIntent
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Android's widgets, tile and shortcuts through the app's real container and files (SPEC-ANDROID 10.1 and 10.2): a widget
 * row logs that item's next dose only while it is pending and never twice in the hour (Shared/Intents.swift
 * `LogNextDoseIntent`), TAKE ALL from a widget or the tile logs at one moment (`TakeAllIntent`), locked logs nothing and
 * keeps the Take all for Taken; the widgets' content carries the right actions (Glance's own unit test library); the
 * refresh alarm is armed only while a surface needs it; the shortcuts and the widget infos; Today's widget invite; the
 * Take all link; and Profile's tile row. London, Mon 12 Oct 2026, as ReminderTests.
 */
@RunWith(RobolectricTestRunner::class)
class SurfaceTests {
    private val app: TakenApp get() = ApplicationProvider.getApplicationContext()
    private val london: ZoneId = ZoneId.of("Europe/London")
    private var now: Instant = at(2026, 10, 12, 8)

    private fun at(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0, second: Int = 0): Instant =
        ZonedDateTime.of(year, month, day, hour, minute, second, 0, london).toInstant()

    private val container: AppContainer
        get() = app.container.also { c ->
            c.clock = { now }
            c.zone = { london }
        }

    private val created = at(2026, 10, 1, 8)
    private val vd3 = Item(name = "Vitamin D3", code = "VD3", frequency = Frequency.Daily(1), createdAt = created, sortIndex = 0)
    private val fish = Item(name = "Fish Oil", code = "FSH", frequency = Frequency.Daily(2), createdAt = created, sortIndex = 1)

    private fun seed(vararg doses: Pair<Item, Instant>): StackState = runBlocking {
        val state = StackState(items = listOf(vd3, fish))
        for ((item, moment) in doses) state.logDose(item.id, moment, london)
        container.stores.stack.updateData { state }
    }

    private fun doses(): List<com.tombaxter.taken.core.model.Dose> = runBlocking { container.stores.stack.data.first() }.doses

    // MARK: Logging from a widget or the tile

    @Test
    fun testAWidgetRowLogsItsNextDoseOnceAndNeverTwiceInTheHour() {
        seed()
        assertEquals(SurfaceOutcome.Logged(1), runBlocking { SurfaceActions.logNext(container, fish.id) })
        now = at(2026, 10, 12, 8, 0, 20)
        assertEquals(SurfaceOutcome.Nothing, runBlocking { SurfaceActions.logNext(container, fish.id) }, "a second tap seconds later")
        now = at(2026, 10, 12, 8, 59)
        assertEquals(SurfaceOutcome.Nothing, runBlocking { SurfaceActions.logNext(container, fish.id) }, "a widget drawn before the tap")
        now = at(2026, 10, 12, 19)
        assertEquals(SurfaceOutcome.Logged(1), runBlocking { SurfaceActions.logNext(container, fish.id) }, "the evening dose")
        now = at(2026, 10, 12, 21)
        assertEquals(SurfaceOutcome.Nothing, runBlocking { SurfaceActions.logNext(container, fish.id) }, "done for the day")
        assertEquals(2, doses().count { it.itemId == fish.id })

        assertEquals(SurfaceOutcome.Logged(1), runBlocking { SurfaceActions.logNext(container, vd3.id) })
        assertEquals(SurfaceOutcome.Nothing, runBlocking { SurfaceActions.logNext(container, vd3.id) }, "a taken row never un-takes")
        assertEquals(1, doses().count { it.itemId == vd3.id })
    }

    @Test
    fun testTakeAllFromAWidgetOrTheTileLogsEveryPendingDoseAtOneMoment() {
        seed()
        assertEquals(SurfaceOutcome.Logged(2), runBlocking { SurfaceActions.takeAll(container) })
        assertEquals(listOf(now, now), doses().map { it.takenAt }, "one moment")
        now = at(2026, 10, 12, 8, 0, 5)
        assertEquals(SurfaceOutcome.Nothing, runBlocking { SurfaceActions.takeAll(container) }, "Fish Oil's second dose waits for the hour")
        now = at(2026, 10, 12, 19)
        assertEquals(SurfaceOutcome.Logged(1), runBlocking { SurfaceActions.takeAll(container) })
        assertEquals("All taken", runBlocking { container.surfaces.tileFace() }.subtitle)
    }

    @Test
    fun testALockedTakeAllWritesNothingAndKeepsItForTaken() {
        val before = seed(vd3 to at(2026, 10, 12, 7, 42))
        runBlocking { container.stores.ledger.updateData { LedgerFile(ProLedger(firstSeenAt = at(2026, 9, 1, 9))) } }
        val outcome = runBlocking { SurfaceActions.takeAll(container, pro = ProSource.locked) }
        assertEquals(SurfaceOutcome.Locked, outcome)
        assertEquals(before.doses, doses(), "nothing is written")
        val pending = runBlocking { container.stores.ledger.data.first() }.ledger?.pending
        assertEquals(ProPendingAction.TakeAll, pending?.action, "kept for Taken to offer with the paywall when it opens")
        assertEquals(now, pending?.at)

        assertEquals(SurfaceOutcome.Locked, runBlocking { SurfaceActions.logNext(container, fish.id, pro = ProSource.locked) })
        assertEquals(before.doses, doses(), "a widget drawn before Pro ran out logs nothing")
        val inputs = runBlocking { container.surfaces.read() }
        assertTrue(container.surfaces.locked(inputs, now, ProSource.locked), "and is drawn again read-only")
        assertFalse(container.surfaces.locked(inputs, now, ProSource.untilBilling))
    }

    /** Runs the main looper until `done` holds: DataStore reads on its own thread and hands back to the main one. */
    private fun awaitMain(what: String, done: () -> Boolean) {
        val end = System.currentTimeMillis() + 10_000
        while (true) {
            shadowOf(android.os.Looper.getMainLooper()).idle()
            if (done()) return
            check(System.currentTimeMillis() < end) { "never: $what" }
            Thread.sleep(10)
        }
    }

    /**
     * The Take all tile on Android's own service (Robolectric's TileService): it draws a count and never a name, and a tap
     * logs every pending dose with no unlock, as the iPhone's Control Center control does.
     */
    @Test
    fun testTheTileSaysACountAndItsTapTakesAll() {
        seed()
        val service = org.robolectric.Robolectric.buildService(com.tombaxter.taken.tile.TakeAllTileService::class.java).create().get()
        service.onStartListening()
        awaitMain("the tile drawn") { service.qsTile.label?.toString() == WidgetCopy.TILE_LABEL }
        assertEquals(android.service.quicksettings.Tile.STATE_ACTIVE, service.qsTile.state)
        assertEquals("2 left", service.qsTile.subtitle?.toString())
        assertEquals("Take all, 2 left", service.qsTile.contentDescription?.toString())
        assertTrue(container.surfaces.tileAdded, "a tile that listens is in quick settings")

        service.onClick()
        awaitMain("the tap logged") { doses().size == 2 }
        assertEquals(listOf(now, now), doses().map { it.takenAt })
        awaitMain("the tile drawn again") { service.qsTile.state == android.service.quicksettings.Tile.STATE_INACTIVE }
        assertEquals("1 left", service.qsTile.subtitle?.toString(), "Fish Oil's second dose waits for its hour")
        service.onStopListening()
    }

    // MARK: What the widgets carry

    @Test
    fun testTheStackWidgetsRowsLogAndItsTakeAllTakesAll() = runGlanceAppWidgetUnitTest {
        val state = StackState(items = listOf(vd3, fish)).also { it.logDose(vd3.id, at(2026, 10, 12, 7, 42), london) }
        val face = StackWidgetFace(WidgetSnapshot(state, at(2026, 10, 12, 9), london), Locale.US)
        setContext(app)
        setAppWidgetSize(WidgetSizes.MEDIUM)
        provideComposable { StackWidgetContent(face, Looks.SIGNAL) }
        onNode(hasTestTag("widget-row-FSH"))
            .assert(hasRunCallbackClickAction<LogNextAction>(actionParametersOf(LogNextAction.ITEM to fish.id.toString())))
        onNode(hasTestTag("widget-row-VD3")).assert(androidx.glance.testing.unit.hasNoClickAction())
        onNode(hasTestTag("widget-take-all")).assert(hasRunCallbackClickAction<TakeAllAction>())
        onNode(hasTestTag("stack-widget")).assert(hasStartActivityClickAction(takenIntent(app, SurfaceLinks.TODAY)))
    }

    @Test
    fun testALockedStackWidgetOpensThePaywallWithTheLogKept() = runGlanceAppWidgetUnitTest {
        val state = StackState(items = listOf(vd3, fish)).also { it.logDose(vd3.id, at(2026, 10, 12, 7, 42), london) }
        val face = StackWidgetFace(WidgetSnapshot(state, at(2026, 10, 12, 9), london, locked = true), Locale.US)
        setContext(app)
        setAppWidgetSize(WidgetSizes.MEDIUM)
        provideComposable { StackWidgetContent(face, Looks.SIGNAL) }
        val url = "taken://pro?then=log&item=${fish.id.toString().uppercase()}"
        onNode(hasTestTag("widget-row-FSH")).assert(hasStartActivityClickAction(takenIntent(app, url)))
        onNode(hasTestTag("widget-take-all")).assertDoesNotExist()
        onNode(hasTestTag("stack-widget")).assert(hasStartActivityClickAction(takenIntent(app, "taken://pro")))
    }

    @Test
    fun testTheToDoWidgetsMicOpensTakenListening() = runGlanceAppWidgetUnitTest {
        val task = TodoTask(title = "Take the bins out", createdAt = at(2026, 10, 12, 9), noteId = UUID.randomUUID())
        val face = TodoWidgetFace(TodoState(tasks = listOf(task)), at(2026, 10, 12, 9), com.tombaxter.taken.core.day.DayClock(3, london), Locale.US)
        setContext(app)
        setAppWidgetSize(WidgetSizes.TALL)
        provideComposable { TodoWidgetContent(face, Looks.BLUSH) }
        onNode(hasTestTag("widget-mic")).assert(hasStartActivityClickAction(takenIntent(app, TodoCaptureRoute.RECORD_URL)))
        onNode(hasTestTag("todo-widget")).assert(hasStartActivityClickAction(takenIntent(app, TodoCaptureRoute.LIST_URL)))
    }

    // MARK: The refresh

    private val alarmManager get() = app.getSystemService(AlarmManager::class.java)

    @Suppress("DEPRECATION")
    private fun refreshAlarm() = shadowOf(alarmManager).scheduledAlarms.firstOrNull {
        shadowOf(it.operation).savedIntent.action == SurfaceRefreshReceiver.ACTION
    }

    private fun restartReceiverOn(): Boolean = app.packageManager.getComponentEnabledSetting(ComponentName(app, RescheduleReceiver::class.java)) ==
        PackageManager.COMPONENT_ENABLED_STATE_ENABLED

    @Test
    fun testTheRefreshIsArmedOnlyWhileAWidgetOrTheTileNeedsIt() {
        seed(vd3 to at(2026, 10, 12, 7, 42), fish to at(2026, 10, 12, 7, 42))
        now = at(2026, 10, 12, 7, 50)
        runBlocking { container.surfaces.refresh() }
        assertNull(refreshAlarm(), "nothing on the home screen or in quick settings: no alarm")

        container.surfaces.tileAdded = true
        runBlocking { container.surfaces.refresh() }
        val armed = assertNotNull(refreshAlarm(), "the tile is in quick settings")
        assertEquals(at(2026, 10, 12, 8, 42).toEpochMilli(), armed.triggerAtMs, "when Fish Oil's hour is up, TAKE ALL returns")
        assertEquals(AlarmManager.RTC, armed.getType(), "never wakes the phone")
        assertTrue(restartReceiverOn(), "a restart or a clock change puts it back")

        now = at(2026, 10, 12, 19)
        runBlocking { SurfaceActions.takeAll(container) }
        assertEquals(at(2026, 10, 13, 3).toEpochMilli(), refreshAlarm()?.triggerAtMs, "all taken: the next day, at 03:00")

        container.surfaces.tileAdded = false
        runBlocking { container.surfaces.refresh() }
        assertNull(refreshAlarm(), "the tile went: the alarm goes too")
    }

    /** The 4x4's rows share the height left under its counter, so no empty band sits under the last one. */
    @Test
    fun testTheLargeWidgetsRowsShareTheHeightLeft() {
        val left = 271.dp
        assertEquals(left / 5, com.tombaxter.taken.widget.spreadRowHeight(left, shown = 5, count = 5), "five rows fill it")
        assertEquals(60.dp, com.tombaxter.taken.widget.spreadRowHeight(left, shown = 2, count = 2), "never taller than 60 dp")
        assertEquals(WidgetSizes.TOUCH, com.tombaxter.taken.widget.spreadRowHeight(left, shown = 5, count = 7), "with +n MORE they stay 48 dp")
        assertEquals(WidgetSizes.TOUCH, com.tombaxter.taken.widget.spreadRowHeight(200.dp, shown = 5, count = 5), "never under the touch target")
    }

    // MARK: Shortcuts and widget infos

    private fun attributes(parser: XmlResourceParser, tag: String): List<Map<String, String>> {
        val found = ArrayList<Map<String, String>>()
        while (parser.next() != XmlResourceParser.END_DOCUMENT) {
            if (parser.eventType != XmlResourceParser.START_TAG || parser.name != tag) continue
            found.add((0 until parser.attributeCount).associate { parser.getAttributeName(it) to parser.getAttributeValue(it) })
        }
        return found
    }

    @Test
    fun testTheShortcutsOpenToDoListeningAndTakeAllInThisBuildsPackage() {
        val intents = attributes(app.resources.getXml(R.xml.shortcuts), "intent")
        assertEquals(listOf(TodoCaptureRoute.RECORD_URL, SurfaceLinks.TAKE_ALL), intents.map { it["data"] })
        for (intent in intents) {
            assertEquals("android.intent.action.VIEW", intent["action"])
            assertEquals(app.packageName, intent["targetPackage"], "the shortcut opens this build, debug or release")
            assertEquals(MainActivity.INTERNAL_LINK, intent["targetClass"], "Taken's own, unexported way in (SPEC-ANDROID 10.3)")
        }
        val shortcuts = attributes(app.resources.getXml(R.xml.shortcuts), "shortcut")
        assertEquals(listOf("voice-todo", "take-all"), shortcuts.map { it["shortcutId"] })

        // The release build's copy says the same, in the release package.
        val main = File("src/main/res/xml/shortcuts.xml").readText().substringAfter("<shortcuts")
        val debug = File("src/debug/res/xml/shortcuts.xml").readText().substringAfter("<shortcuts")
        assertTrue(main.contains("android:targetPackage=\"com.tombaxter.taken\""))
        assertFalse(main.contains("com.tombaxter.taken.debug"), "the release build's shortcuts open the release build")
        assertEquals(main, debug.replace("com.tombaxter.taken.debug", "com.tombaxter.taken"), "the two copies differ only in their package")
        assertEquals(WidgetCopy.SHORTCUT_VOICE_LONG, app.getString(R.string.shortcut_voice_long))
        assertEquals(WidgetCopy.SHORTCUT_VOICE_SHORT, app.getString(R.string.shortcut_voice_short))
        assertEquals(WidgetCopy.SHORTCUT_TAKE_ALL, app.getString(R.string.shortcut_take_all_short))
    }

    @Test
    fun testTheWidgetsNeverAskForAPeriodicUpdateAndSayWhatTheyDo() {
        for (info in listOf(R.xml.widget_stack_info, R.xml.widget_todo_info)) {
            val provider = attributes(app.resources.getXml(info), "appwidget-provider").single()
            assertEquals("0", provider["updatePeriodMillis"], "Taken redraws them itself")
            assertNotNull(provider["previewLayout"], "Android 12 to 14")
            assertNotNull(provider["previewImage"], "Android 9 to 11, and the fallback")
            assertNotNull(provider["description"])
        }
        assertEquals(WidgetCopy.STACK_NAME, app.getString(R.string.widget_stack_name))
        assertEquals(WidgetCopy.STACK_DESCRIPTION, app.getString(R.string.widget_stack_description))
        assertEquals(WidgetCopy.TODO_NAME, app.getString(R.string.widget_todo_name))
        assertEquals(WidgetCopy.TODO_DESCRIPTION, app.getString(R.string.widget_todo_description))
        assertEquals(WidgetCopy.TILE_LABEL, app.getString(R.string.tile_take_all))
    }

    // MARK: Today and Profile

    /** A surface host that remembers what Taken asked of it. */
    private class RecordingHost(
        var placed: Boolean = false,
        override val canPinWidget: Boolean = true,
        offers: Boolean = false,
    ) : SurfaceHost {
        var pinRequests = 0
        var tileRequests = 0
        val looks = ArrayList<ThemeID>()
        override fun checkStackWidget(answer: (Boolean) -> Unit) = answer(placed)
        override fun requestPinStackWidget() {
            pinRequests += 1
        }
        override var offersTile: Boolean = offers
        override fun requestAddTile(answer: (Boolean) -> Unit) {
            tileRequests += 1
            offersTile = false
            answer(true)
        }
        override fun didBecomeActive(look: ThemeID) = Unit
        override fun lookChanged(look: ThemeID) {
            looks.add(look)
        }
    }

    /** Vitamin D3, taken this morning: the first day that reaches All taken. */
    private fun allTakenModel(host: SurfaceHost): AppModel {
        val today = at(2026, 10, 19, 9)
        val item = vd3.copy(createdAt = at(2026, 10, 12, 9))
        val state = StackState(items = listOf(item))
        state.settings.nudgeOfferDone = true
        state.logDose(item.id, at(2026, 10, 19, 8), london)
        return AppModel(
            MemoryPersistence(stack = state), state, ProLedger(firstSeenAt = today), Profile(), null, ProSource.untilBilling,
            clockNow = { today }, zone = { london }, locale = { Locale.US }, surfaceHost = host,
        )
    }

    /** RetentionTests' widget invite through the model: it waits for Android's answer, then asks the launcher to pin. */
    @Test
    fun testTheWidgetInviteAsksTheLauncherToPinTheStackWidget() {
        val host = RecordingHost()
        val model = allTakenModel(host)
        assertTrue(model.today.allTaken)
        assertNull(model.todayPrompt, "until Android says whether a widget is placed, the invite waits")
        model.didBecomeActive()
        assertEquals(TodayPrompt.WidgetInvite, model.todayPrompt)
        model.noteWidgetInviteShown()
        assertEquals(DayKey(2026, 10, 19).ordinal, model.settings.widgetInviteDay, "it shows on this day only")
        model.closeWidgetInvite(pin = true)
        assertEquals(1, host.pinRequests, "the launcher's own dialog")
        assertTrue(model.settings.widgetInviteDone)
        assertNull(model.todayPrompt, "gone for good")

        val closed = RecordingHost()
        val other = allTakenModel(closed)
        other.didBecomeActive()
        other.closeWidgetInvite(pin = false)
        assertEquals(0, closed.pinRequests)
        assertNull(other.todayPrompt)
    }

    @Test
    fun testAPlacedStackWidgetOrALauncherThatCannotPinMeansNoInvite() {
        val placed = allTakenModel(RecordingHost(placed = true))
        placed.didBecomeActive()
        assertNull(placed.todayPrompt)
        assertTrue(placed.settings.widgetInviteDone, "a placed widget answers the invite for good")

        val cannot = allTakenModel(RecordingHost(canPinWidget = false))
        cannot.didBecomeActive()
        assertNull(cannot.todayPrompt, "Android's launcher dialog is the only way Taken offers the widget")
    }

    /**
     * Semaglutide logged every day for a week and All taken today: the weight offer (SPEC 3.12) waits for the widget
     * invite's day where the launcher can pin, and does not wait for an invite that can never show where it cannot.
     */
    @Test
    fun testTheWeightOfferDoesNotWaitForAnInviteTheLauncherCannotShow() {
        fun glp1Model(host: SurfaceHost): AppModel {
            val today = at(2026, 10, 19, 9)
            val shot = Item(name = "Semaglutide", code = "SEM", frequency = Frequency.Daily(1), createdAt = at(2026, 10, 12, 7), sortIndex = 0)
            val state = StackState(items = listOf(shot))
            state.settings.nudgeOfferDone = true
            for (day in 12..19) state.logDose(shot.id, at(2026, 10, day, 8), london)
            return AppModel(
                MemoryPersistence(stack = state), state, ProLedger(firstSeenAt = at(2026, 10, 12, 7)), Profile(), null,
                ProSource.untilBilling, clockNow = { today }, zone = { london }, locale = { Locale.US }, surfaceHost = host,
            )
        }
        val cannot = glp1Model(RecordingHost(canPinWidget = false))
        cannot.didBecomeActive()
        assertTrue(cannot.today.allTaken)
        assertEquals(TodayPrompt.WeightOffer, cannot.todayPrompt, "no invite can show, so the offer does not wait for one")
        assertFalse(cannot.settings.widgetInviteDone, "nothing marks the invite answered, for a later launcher that can pin")

        val can = glp1Model(RecordingHost(canPinWidget = true))
        can.didBecomeActive()
        assertEquals(TodayPrompt.WidgetInvite, can.todayPrompt, "a launcher that can pin: the widget invite has its day first")
    }

    @Test
    fun testProfileOffersTheTileUntilItIsAdded() {
        val host = RecordingHost(offers = true)
        val model = allTakenModel(host)
        assertTrue(model.tileOffered)
        model.addTile()
        assertEquals(1, host.tileRequests)
        assertFalse(model.tileOffered, "in quick settings: the row goes")
        model.setLook(ThemeID.BLUSH)
        assertEquals(listOf(ThemeID.BLUSH), host.looks, "the widgets' previews follow the look")
    }

    /** SPEC-ANDROID 10.2's "Take all" shortcut: Today, Take all with its snackbar and Undo; locked, the paywall. */
    @Test
    fun testTheTakeAllShortcutTakesAllWithItsSnackbarOrOpensThePaywall() {
        val model = DemoScreens.make("today-pending")
        val ready = model.takeAllCount
        assertTrue(ready >= 2)
        model.tab = AppTab.HISTORY
        model.handle(SurfaceLinks.TAKE_ALL)
        assertEquals(AppTab.TODAY, model.tab)
        assertEquals("$ready taken at", model.toast?.message)
        assertIs<UndoStep.Remove>(model.toast?.undo)

        val locked = DemoScreens.make("locked")
        val before = locked.state.doses
        locked.handle(SurfaceLinks.TAKE_ALL)
        assertNotNull(locked.paywall, "the paywall, with the Take all kept")
        assertEquals(before, locked.state.doses)
    }
}
