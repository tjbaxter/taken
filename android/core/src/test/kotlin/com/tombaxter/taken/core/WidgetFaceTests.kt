package com.tombaxter.taken.core

import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.ProPlan
import com.tombaxter.taken.core.pro.ProReason
import com.tombaxter.taken.core.pro.ProStatus
import com.tombaxter.taken.core.stack.StackEngine
import com.tombaxter.taken.core.stack.WidgetSnapshot
import com.tombaxter.taken.core.stack.logDose
import com.tombaxter.taken.core.surfaces.StackWidgetFace
import com.tombaxter.taken.core.surfaces.SurfaceLinks
import com.tombaxter.taken.core.surfaces.SurfaceRefresh
import com.tombaxter.taken.core.surfaces.TakeAllTileFace
import com.tombaxter.taken.core.surfaces.TileIcon
import com.tombaxter.taken.core.surfaces.TileState
import com.tombaxter.taken.core.surfaces.TodoWidgetFace
import com.tombaxter.taken.core.surfaces.WidgetBottom
import com.tombaxter.taken.core.surfaces.WidgetCopy
import com.tombaxter.taken.core.surfaces.WidgetTap
import com.tombaxter.taken.core.todo.TodoCaptureRoute
import com.tombaxter.taken.core.todo.TodoDue
import com.tombaxter.taken.core.todo.TodoState
import com.tombaxter.taken.core.todo.TodoTask
import java.time.Duration
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Android's widget, tile and shortcut rules (SPEC-ANDROID 10.1 and 10.2), as pure functions over the snapshot the iPhone's
 * widgets draw (Shared/WidgetViews.swift): the counter block's bottom line, each row's value and tap (never twice in the
 * hour, never un-takes, locked opens the paywall with the log kept), the tile's count, the moments the surfaces refresh at
 * (TakenWidgets/StackWidget.swift `getTimeline`), the to-do widget's list, and the links. London, Mon 12 Oct 2026. Android
 * only: the iPhone's widget views have no unit tests of their own; DayLogicTests and ThemeTests pin the snapshot.
 */
class WidgetFaceTests {
    private val clock = londonClock()
    private val created = at(2026, 10, 1, 8)
    private val vd3 = makeItem("Vitamin D3", "VD3", created = created, sortIndex = 0)
    private val fish = makeItem("Fish Oil", "FSH", Frequency.Daily(2), created = created, sortIndex = 1)
    private val mag = makeItem("Magnesium", "MAG", created = created, sortIndex = 2)

    private fun stack(): StackState = StackState(items = listOf(vd3, fish, mag))

    private fun face(state: StackState, hour: Int, minute: Int = 0, locked: Boolean = false): StackWidgetFace =
        StackWidgetFace(WidgetSnapshot(state, at(2026, 10, 12, hour, minute), london, locked), enUS)

    // MARK: The counter block

    @Test
    fun testTheCounterBlockSaysWhatTakeAllWouldDo() {
        val state = stack()
        val morning = face(state, 7, 30)
        assertEquals("0", morning.counterTaken)
        assertEquals("/4", morning.counterDue, "Fish Oil is two doses")
        assertEquals(WidgetBottom.TakeAll(3), morning.bottom)
        assertEquals("3", (morning.bottom as WidgetBottom.TakeAll).countText)
        assertNull(WidgetBottom.TakeAll(1).countText, "one item: TAKE ALL alone")
        assertEquals("0 of 4 taken. Tap to take all.", morning.spoken)
        assertEquals(WidgetTap.Open(SurfaceLinks.TODAY), morning.tap, "the rest of the widget opens Today")

        state.logDose(vd3.id, at(2026, 10, 12, 7, 42), london)
        state.logDose(fish.id, at(2026, 10, 12, 7, 42), london)
        state.logDose(mag.id, at(2026, 10, 12, 7, 42), london)
        val soon = face(state, 8)
        assertEquals(WidgetBottom.Status("LOGGED 07:42"), soon.bottom, "Fish Oil's second dose waits for the hour to end")

        state.logDose(fish.id, at(2026, 10, 12, 21, 12), london)
        val done = face(state, 21, 20)
        assertTrue(done.allTaken)
        assertEquals(WidgetBottom.Status("LOCKED 21:12"), done.bottom, "the day locked in")
        assertEquals("All taken", done.spoken)
        assertEquals(WidgetBottom.Status("DONE 21:12"), face(state, 21, 20, locked = true).bottom, "without Pro the lock is Taken Pro's")
    }

    @Test
    fun testALockedWidgetIsReadOnlyAndOpensThePaywall() {
        val state = stack()
        state.logDose(vd3.id, at(2026, 10, 12, 7, 42), london)
        val locked = face(state, 9, locked = true)
        assertTrue(locked.locked)
        assertEquals(WidgetBottom.Status("2 PENDING", lit = false), locked.bottom, "no TAKE ALL")
        assertEquals(WidgetTap.Open("taken://pro"), locked.tap)
        assertEquals("1 of 4 taken. Logging needs Taken Pro.", locked.spoken)
        val fishRow = locked.rows.first { it.id == fish.id }
        assertEquals(WidgetTap.Open("taken://pro?then=log&item=${fish.id.toString().uppercase()}"), fishRow.tap, "the log is kept for Pro")
        assertEquals("--:--", fishRow.value, "no TAP while locked")
        assertEquals(WidgetTap.None, locked.rows.first { it.id == vd3.id }.tap, "a taken row stays still")
        assertTrue(locked.rows.first { it.id == fish.id }.spoken.endsWith("Logging needs Taken Pro."))
    }

    @Test
    fun testAnEmptyStackSaysSo() {
        val empty = face(StackState(), 9)
        assertFalse(empty.hasStack)
        assertNull(empty.bottom)
        assertEquals("ADD YOUR STACK IN TAKEN", empty.emptyRows)
        assertEquals(WidgetCopy.EMPTY_SPOKEN, empty.spoken)
        assertFalse(face(StackState(), 9, locked = true).locked, "nothing to lock")
        val nothingDue = StackState(items = listOf(makeItem("Zinc", "ZNC", Frequency.Weekdays(setOf(3)), created = created)))
        assertEquals("NOTHING DUE TODAY", face(nothingDue, 9).emptyRows, "a Tuesday item on a Monday")
    }

    // MARK: Rows

    @Test
    fun testARowLogsOnlyWhilePendingAndNeverTwiceInTheHour() {
        val state = stack()
        state.logDose(vd3.id, at(2026, 10, 12, 7, 42), london)
        state.logDose(fish.id, at(2026, 10, 12, 7, 43), london)
        val morning = face(state, 8)
        assertEquals(listOf(fish.id, mag.id, vd3.id), morning.rows.map { it.id }, "what is still to take comes first")

        val fishRow = morning.rows[0]
        assertEquals("1/2", fishRow.value)
        assertTrue(fishRow.valueLit)
        assertEquals(WidgetTap.None, fishRow.tap, "logged 17 minutes ago: a second tap would log the evening dose too early")
        assertEquals("Fish Oil, 1 of 2 taken. Logged in the last hour.", fishRow.spoken)

        val magRow = morning.rows[1]
        assertEquals("TAP", magRow.value)
        assertFalse(magRow.valueLit)
        assertEquals(WidgetTap.LogNext(mag.id), magRow.tap)
        assertEquals("Magnesium, pending. Tap to log it.", magRow.spoken)

        val vd3Row = morning.rows[2]
        assertTrue(vd3Row.done)
        assertEquals("07:42", vd3Row.value)
        assertEquals(WidgetTap.None, vd3Row.tap, "never un-takes")
        assertEquals("Vitamin D3, taken at 7:42 AM.", vd3Row.spoken)

        val evening = face(state, 19)
        assertEquals(WidgetTap.LogNext(fish.id), evening.rows.first { it.id == fish.id }.tap, "the evening dose, an hour on")
    }

    @Test
    fun testTheRowsASizeHasNoRoomForAreCounted() {
        val state = stack()
        val face = face(state, 9)
        assertEquals("+1 MORE", face.more(2))
        assertNull(face.more(3))
        assertNull(face.more(4))
    }

    @Test
    fun testTheBarKeepsOneSegmentPerDoseUpToTen() {
        val state = stack()
        state.logDose(vd3.id, at(2026, 10, 12, 7, 42), london)
        val face = face(state, 9)
        assertEquals(4, face.segments)
        assertEquals(1, face.litSegments)

        val many = StackState(
            items = (0 until 12).map { makeItem("Item $it", "I$it", created = created, sortIndex = it) },
        )
        for (item in many.items.take(11)) many.logDose(item.id, at(2026, 10, 12, 7, 42), london)
        val twelve = face(many, 9)
        assertEquals(10, twelve.segments, "Glance holds ten children to a row")
        assertEquals(9, twelve.litSegments, "never full before the day is")
        many.logDose(many.items[11].id, at(2026, 10, 12, 7, 43), london)
        assertEquals(10, face(many, 9).litSegments)
        assertEquals(1, face(StackState(), 9).segments, "an empty bar")
    }

    // MARK: The tile

    @Test
    fun testTheTileSaysACountAndNeverAName() {
        val state = stack()
        val ready = TakeAllTileFace(WidgetSnapshot(state, at(2026, 10, 12, 9), london))
        assertEquals(TileState.ACTIVE, ready.state)
        assertEquals("Take all", ready.label)
        assertEquals("3 left", ready.subtitle)
        assertEquals(TileIcon.PILL, ready.icon)
        assertEquals(WidgetTap.TakeAll, ready.tap)
        assertEquals("Take all, 3 left", ready.spoken)
        for (text in listOf(ready.label, ready.subtitle, ready.spoken)) {
            for (item in state.items) assertFalse(text.contains(item.name) || text.contains(item.code), "the lock screen sees it: $text")
        }

        state.logDose(vd3.id, at(2026, 10, 12, 7, 42), london)
        state.logDose(fish.id, at(2026, 10, 12, 7, 42), london)
        state.logDose(mag.id, at(2026, 10, 12, 7, 42), london)
        val held = TakeAllTileFace(WidgetSnapshot(state, at(2026, 10, 12, 8), london))
        assertEquals(TileState.INACTIVE, held.state, "only Fish Oil is left, logged in the last hour")
        assertEquals("1 left", held.subtitle)
        assertEquals(WidgetTap.None, held.tap)

        state.logDose(fish.id, at(2026, 10, 12, 19), london)
        val done = TakeAllTileFace(WidgetSnapshot(state, at(2026, 10, 12, 20), london))
        assertEquals(TileState.INACTIVE, done.state)
        assertEquals("All taken", done.subtitle)
        assertEquals(WidgetTap.None, done.tap)
    }

    @Test
    fun testALockedTileOpensThePaywallWithTheTakeAllKept() {
        val locked = TakeAllTileFace(WidgetSnapshot(stack(), at(2026, 10, 12, 9), london, locked = true))
        assertEquals("Taken Pro", locked.label)
        assertEquals(TileIcon.LOCK, locked.icon)
        assertEquals(TileState.INACTIVE, locked.state)
        assertEquals(WidgetTap.Open("taken://pro?then=take-all"), locked.tap)
        assertEquals("3 left", locked.subtitle)

        val empty = TakeAllTileFace(WidgetSnapshot(StackState(), at(2026, 10, 12, 9), london))
        assertEquals("No stack yet", empty.subtitle)
        assertEquals(WidgetTap.Open("taken://today"), empty.tap, "Taken opens where Add to stack is")
        assertTrue(WidgetCopy.TILE_LABEL.length <= 18 && WidgetCopy.TILE_LOCKED.length <= 18, "a tile label is at most 18 characters")
    }

    // MARK: Refresh

    /** TakenWidgets/StackWidget.swift `getTimeline`: the hour's end, Pro's end and the rollover, whichever comes first. */
    @Test
    fun testTheSurfacesRefreshAtTheHoursEndProsEndOrTheRollover() {
        val state = stack()
        val morning = at(2026, 10, 12, 8)
        state.logDose(vd3.id, morning, london)
        state.logDose(fish.id, morning, london)
        state.logDose(mag.id, morning, london)
        val soon = morning.plusSeconds(600)
        val snapshot = WidgetSnapshot(state, soon, london)
        assertEquals(morning.plus(StackEngine.repeatGuard), SurfaceRefresh.next(snapshot, null, null, soon), "Fish Oil's TAKE ALL returns")

        val evening = at(2026, 10, 12, 19)
        val later = WidgetSnapshot(state, evening, london)
        assertEquals(at(2026, 10, 13, 3), SurfaceRefresh.next(later, null, null, evening), "waking at 07:00, the next day starts at 03:00")

        val ending = ProStatus(
            isPro = true, reason = ProReason.MONTHLY, checkedAt = evening, expiresAt = at(2026, 10, 12, 22), willRenew = false,
            plan = ProPlan.MONTHLY,
        )
        assertEquals(at(2026, 10, 12, 22), SurfaceRefresh.next(later, ending, null, evening), "the widget turns read-only then")
        val lockedAlready = WidgetSnapshot(state, evening, london, locked = true)
        assertEquals(at(2026, 10, 13, 3), SurfaceRefresh.next(lockedAlready, ending, null, evening))

        val todos = TodoState(
            tasks = listOf(
                TodoTask(title = "Take the bins out", due = TodoDue.Time(at(2026, 10, 12, 22, 30)), createdAt = evening, noteId = UUID.randomUUID()),
                TodoTask(title = "Done already", due = TodoDue.Time(at(2026, 10, 12, 20)), createdAt = evening, completedAt = evening, noteId = UUID.randomUUID()),
            ),
        )
        assertEquals(at(2026, 10, 12, 22, 30), SurfaceRefresh.next(later, null, todos, evening), "the to-do row turns overdue")
        assertEquals(Duration.ofHours(1), StackEngine.repeatGuard)
    }

    // MARK: The to-do widget

    @Test
    fun testTheToDoWidgetShowsTheOpenListInTheTabsOrder() {
        val now = at(2026, 10, 12, 21, 41)
        val note = UUID.randomUUID()
        val bins = TodoTask(title = "Take the bins out", due = TodoDue.Time(at(2026, 10, 12, 22, 30)), createdAt = now, noteId = note, order = 1)
        val photos = TodoTask(title = "Send Mum the photos", createdAt = now, noteId = note, order = 2)
        val late = TodoTask(title = "Renew the car insurance", due = TodoDue.Time(at(2026, 10, 12, 18)), createdAt = now, noteId = note, order = 0)
        val done = TodoTask(title = "Buy milk", createdAt = now, completedAt = now, noteId = note, order = 3)
        val face = TodoWidgetFace(TodoState(tasks = listOf(photos, bins, late, done)), now, clock, enUS)
        assertEquals(listOf(late.id, bins.id, photos.id), face.rows.map { it.id }, "due first, soonest first; done ones never")
        assertEquals("To-do · 3", face.header)
        assertEquals("3 to-dos", face.countLine)
        assertEquals("22:30", face.rows[1].due)
        assertTrue(face.rows[0].overdue)
        assertFalse(face.rows[1].overdue)
        assertNull(face.rows[2].due)
        assertEquals("Take the bins out, due at 10:30 PM", face.rows[1].spoken)
        assertEquals(TodoCaptureRoute.revealUrl(bins.id), face.rows[1].url, "a tap opens To-do scrolled to it")
        assertEquals("taken://todo/record", face.micUrl, "the mic opens Taken listening")
        assertEquals("taken://todo", face.listUrl)

        val empty = TodoWidgetFace(TodoState(), now, clock, enUS)
        assertEquals("To-do", empty.header)
        assertEquals("0 to-dos", empty.countLine)
        assertTrue(empty.rows.isEmpty())
        assertEquals("1 to-do", TodoWidgetFace(TodoState(tasks = listOf(photos)), now, clock, enUS).countLine)
    }

    // MARK: Links and copy

    @Test
    fun testTheTakeAllShortcutsLinkIsTodaysOwn() {
        assertTrue(SurfaceLinks.isTakeAll(SurfaceLinks.TAKE_ALL))
        assertFalse(SurfaceLinks.isTakeAll("taken://today"))
        assertFalse(SurfaceLinks.isTakeAll("taken://pro?then=take-all"), "the paywall's own link stays the paywall's")
        assertFalse(SurfaceLinks.isTakeAll("not a link"))
    }

    @Test
    fun testWidgetCopyKeepsTheRules() {
        for (text in WidgetCopy.all) assertCopyRules(text)
        assertTrue(WidgetCopy.SHORTCUT_VOICE_LONG.length <= 25 && WidgetCopy.SHORTCUT_TAKE_ALL.length <= 10)
    }
}
