package com.tombaxter.taken.core

import com.tombaxter.taken.core.catalog.Catalog
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.model.Dose
import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.ItemDraft
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.reminders.Reminders
import com.tombaxter.taken.core.stack.Adherence
import com.tombaxter.taken.core.stack.DayStatus
import com.tombaxter.taken.core.stack.SiriAnswers
import com.tombaxter.taken.core.stack.StackEngine
import com.tombaxter.taken.core.stack.WidgetSnapshot
import com.tombaxter.taken.core.stack.addItems
import com.tombaxter.taken.core.stack.deleteItem
import com.tombaxter.taken.core.stack.insertDose
import com.tombaxter.taken.core.stack.logActiveDose
import com.tombaxter.taken.core.stack.logDose
import com.tombaxter.taken.core.stack.logNextDoseIfPending
import com.tombaxter.taken.core.stack.moveActiveItems
import com.tombaxter.taken.core.stack.orderedItems
import com.tombaxter.taken.core.stack.removeDoses
import com.tombaxter.taken.core.stack.restore
import com.tombaxter.taken.core.stack.setArchived
import com.tombaxter.taken.core.stack.setDoseTime
import com.tombaxter.taken.core.stack.takeAllPending
import com.tombaxter.taken.core.stack.undoLastDose
import com.tombaxter.taken.core.stack.updateItem
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Ported from TakenTests/DayLogicTests.swift: every case, the same London fixtures and the same expected strings. */
class DayLogicTests {

    // MARK: Day keys

    @Test
    fun testDayKeyRoundTripAndWeekday() {
        val key = DayKey(2026, 10, 12)
        assertEquals(2026, key.ymd.year)
        assertEquals(10, key.ymd.month)
        assertEquals(12, key.ymd.day)
        assertEquals(0, key.mondayIndex, "12 Oct 2026 is a Monday")
        assertEquals(2, key.weekday, "Calendar weekday for Monday is 2")
        assertEquals(1, key.adding(6).weekday, "Sunday is 1")
        assertEquals(29, DayKey(2024, 3, 1).adding(-1).ymd.day, "leap day")
        assertEquals(0, DayKey(1970, 1, 1).ordinal)
    }

    // MARK: Rollover

    @Test
    fun testDayRolloverAtFourAM() {
        val c = londonClock(4)
        val monday = DayKey(2026, 10, 12)
        assertEquals(monday, c.day(at(2026, 10, 13, 1, 0)), "01:00 Tuesday still belongs to Monday")
        assertEquals(monday, c.day(at(2026, 10, 13, 3, 59)))
        assertEquals(monday.adding(1), c.day(at(2026, 10, 13, 4, 0)), "04:00 starts Tuesday")
        assertEquals(monday, c.day(at(2026, 10, 12, 23, 30)))
    }

    @Test
    fun testMidnightRolloverWhenDayStartsAtZero() {
        val c = londonClock(0)
        assertEquals(DayKey(2026, 10, 13), c.day(at(2026, 10, 13, 0, 30)))
    }

    @Test
    fun testRolloverAcrossDaylightSavingStart() {
        // UK clocks go forward at 01:00 GMT on 29 Mar 2026.
        val c = londonClock(4)
        val sunday = DayKey(2026, 3, 29)
        assertEquals(sunday.adding(-1), c.day(at(2026, 3, 29, 3, 30)))
        assertEquals(sunday, c.day(at(2026, 3, 29, 4, 30)), "04:30 BST is after the rollover")
        val start = c.start(sunday)
        assertEquals(4, c.hourMinute(start).hour)
        assertEquals(c.start(sunday.adding(1)), c.end(sunday))
    }

    @Test
    fun testDateOnDayMapsEarlyHoursToNextCalendarDate() {
        val c = londonClock(4)
        val monday = DayKey(2026, 10, 12)
        val late = c.date(monday, hour = 1, minute = 15)
        assertEquals(at(2026, 10, 13, 1, 15), late)
        assertEquals(monday, c.day(late))
        assertEquals(at(2026, 10, 12, 9, 0), c.date(monday, hour = 9, minute = 0))
    }

    // MARK: Frequencies

    @Test
    fun testAlternateDaysDueLogic() {
        val c = londonClock()
        val created = at(2026, 10, 1, 8)
        val zinc = makeItem("Zinc", "ZNC", Frequency.AlternateDays, created = created)
        val monday = DayKey(2026, 10, 12)

        var state = StackState(items = listOf(zinc))
        var engine = StackEngine(state, c)
        assertTrue(engine.isDue(zinc, monday), "never taken: due")

        state.logDose(zinc.id, at(2026, 10, 11, 8), london)
        engine = StackEngine(state, c)
        assertFalse(engine.isDue(zinc, monday), "taken yesterday: not due")
        assertEquals(monday.adding(1), engine.nextDueDay(zinc, after = monday), "next due tomorrow")
        assertEquals("Next: tomorrow", Fmt.next(engine.nextDueDay(zinc, after = monday), monday))
        assertEquals("Next: Thursday", Fmt.next(monday.adding(3), monday), "the Not today group names the day")
        assertEquals("Next: 21 Oct", Fmt.next(monday.adding(9), monday))
        assertTrue(engine.isDue(zinc, monday.adding(1)), "two days after the last dose: due")

        state = StackState(items = listOf(zinc))
        state.logDose(zinc.id, at(2026, 10, 10, 8), london)
        engine = StackEngine(state, c)
        assertTrue(engine.isDue(zinc, monday), "last dose two days ago: due")

        val summary = engine.todaySummary(at(2026, 10, 12, 21))
        assertEquals(1, summary.due.size)
    }

    @Test
    fun testAlternateDayItemTakenYesterdayIsInNotDueGroup() {
        val c = londonClock()
        val created = at(2026, 10, 1, 8)
        val vd3 = makeItem("Vitamin D3", "VD3", created = created, sortIndex = 0)
        val zinc = makeItem("Zinc", "ZNC", Frequency.AlternateDays, created = created, sortIndex = 1)
        val state = StackState(items = listOf(vd3, zinc))
        state.logDose(zinc.id, at(2026, 10, 11, 8), london)
        val today = StackEngine(state, c).todaySummary(at(2026, 10, 12, 10))
        assertEquals(listOf(vd3.id), today.due.map { it.item.id })
        assertEquals(listOf(zinc.id), today.notDue.map { it.item.id })
        assertEquals(1, today.dueDoses)
    }

    @Test
    fun testWeekdayFrequency() {
        val c = londonClock()
        val mwf = makeItem("Minoxidil", "MIN", Frequency.Weekdays(setOf(2, 4, 6)), created = at(2026, 10, 1, 8))
        val engine = StackEngine(StackState(items = listOf(mwf)), c)
        val monday = DayKey(2026, 10, 12)
        assertTrue(engine.isDue(mwf, monday))
        assertFalse(engine.isDue(mwf, monday.adding(1)))
        assertTrue(engine.isDue(mwf, monday.adding(2)))
        assertFalse(engine.isDue(mwf, monday.adding(6)), "Sunday")
        assertEquals(monday.adding(7), engine.nextDueDay(mwf, after = monday.adding(4)), "Friday to next Monday")
        assertEquals("Mon Wed Fri", Fmt.frequency(Frequency.Weekdays(setOf(2, 4, 6))))
        assertEquals("Weekdays", Fmt.frequency(Frequency.Weekdays(setOf(2, 3, 4, 5, 6))))
        assertEquals("Every other day", Fmt.frequency(Frequency.AlternateDays))
        assertEquals("2x daily", Fmt.frequency(Frequency.Daily(2)))
    }

    /** Weekly is a one-day Days set: due, pending and nudged on that day only. */
    @Test
    fun testAWeeklyItemIsPendingOnlyOnItsDayAndNudgedOnlyThen() {
        val shot = makeItem("Semaglutide", "SEM", Frequency.Weekdays(setOf(5)), created = at(2026, 10, 1, 8))
        val state = StackState(items = listOf(shot))
        state.settings.reminderEnabled = true
        state.settings.reminderMinutes = 21 * 60
        val engine = StackEngine(state, londonClock())
        val monday = DayKey(2026, 10, 12)
        val thursday = monday.adding(3)
        for (offset in 0 until 7) {
            val day = monday.adding(offset)
            assertEquals(day == thursday, engine.isDue(shot, day), "due only on Thursday, not ${Fmt.longDay(day)}")
        }
        assertEquals(listOf("Semaglutide"), engine.todaySummary(at(2026, 10, 15, 9)).items.filter { it.isPending }.map { it.item.name })
        assertTrue(engine.todaySummary(at(2026, 10, 12, 9)).items.none { it.isPending })
        assertEquals(listOf("Semaglutide"), engine.todaySummary(at(2026, 10, 12, 9)).notDue.map { it.item.name })
        assertEquals(thursday, engine.nextDueDay(shot, after = monday))

        val plans = Reminders.plan(state, at(2026, 10, 12, 9), london)
        assertEquals(listOf(thursday, thursday.adding(7)), plans.map { it.day }, "the nudge fires on its day, and only then")
        assertEquals("1 pending: SEM", plans.firstOrNull()?.body)

        assertEquals("Weekly · Thu", Fmt.frequency(Frequency.Weekdays(setOf(5))))
        assertEquals("Weekly · Sun", Fmt.frequency(Frequency.Weekdays(setOf(1))))
        assertEquals(
            "Weekly · Next: Thursday",
            Fmt.notDue(Frequency.Weekdays(setOf(5)), Fmt.next(thursday, monday)),
            "the day once, not Weekly · Thu · Next: Thursday",
        )
        assertEquals("Every other day · Next: tomorrow", Fmt.notDue(Frequency.AlternateDays, "Next: tomorrow"))
        assertEquals("Mon Wed Fri · Next: Friday", Fmt.notDue(Frequency.Weekdays(setOf(2, 4, 6)), "Next: Friday"))
    }

    @Test
    fun testMultiDoseCompletion() {
        val c = londonClock()
        val fish = makeItem("Fish Oil", "FSH", Frequency.Daily(2), created = at(2026, 10, 1, 8))
        val state = StackState(items = listOf(fish))
        val now = at(2026, 10, 12, 8)

        var row = StackEngine(state, c).todaySummary(now).items[0]
        assertEquals(2, row.pendingCount)
        assertFalse(row.isDone)

        state.logDose(fish.id, now, london)
        row = StackEngine(state, c).todaySummary(now).items[0]
        assertEquals(1, row.pendingCount)
        assertFalse(row.isDone)

        state.logDose(fish.id, at(2026, 10, 12, 19), london)
        val summary = StackEngine(state, c).todaySummary(at(2026, 10, 12, 20))
        assertTrue(summary.items[0].isDone)
        assertTrue(summary.allTaken)
        assertEquals(2, summary.takenDueDoses)
    }

    // MARK: Take all

    /**
     * Android's writes fix their new ids before the mutation runs (AppModel), so a write replayed onto a file that moved on
     * stores the ids the screen and its Undo hold.
     */
    @Test
    fun testIdsMadeBeforeTheWriteAreTheIdsItStores() {
        val c = londonClock()
        val created = at(2026, 10, 1, 8)
        val vd3 = makeItem("Vitamin D3", "VD3", created = created, sortIndex = 0)
        val fish = makeItem("Fish Oil", "FSH", Frequency.Daily(2), created = created, sortIndex = 1)
        val now = at(2026, 10, 12, 21)

        val dose = com.tombaxter.taken.core.stack.doseAt(vd3.id, now, london)
        val screen = StackState(items = listOf(vd3, fish))
        val file = StackState(items = listOf(vd3, fish))
        file.logDose(fish.id, now.minusSeconds(3_600), london)
        assertEquals(dose, screen.insertDose(dose))
        assertEquals(dose, file.insertDose(dose), "the replay stores the same dose, id and all")
        assertEquals(1, file.doses.count { it.id == dose.id })
        file.insertDose(dose)
        assertEquals(1, file.doses.count { it.id == dose.id }, "a dose already there is never doubled")
        assertNull(StackState(items = listOf(fish)).insertDose(dose), "an item that is gone logs nothing")

        val ids = HashMap<java.util.UUID, java.util.UUID>()
        val idFor = { item: java.util.UUID -> ids.getOrPut(item) { java.util.UUID.randomUUID() } }
        val first = StackState(items = listOf(vd3, fish)).takeAllPending(now, c, idFor)
        val replayed = StackState(items = listOf(vd3, fish)).takeAllPending(now, c, idFor)
        assertEquals(first.map { it.id }, replayed.map { it.id }, "Take all replayed: the same id for each item")

        val drafts = listOf(ItemDraft("Creatine"), ItemDraft("Zinc"))
        val itemIds = drafts.map { java.util.UUID.randomUUID() }
        val added = StackState().addItems(drafts, now) { itemIds[it] }
        assertEquals(itemIds, added.map { it.id })
    }

    @Test
    fun testTakeAllOnlyTouchesPendingDueDoses() {
        val c = londonClock()
        val created = at(2026, 10, 1, 8)
        val vd3 = makeItem("Vitamin D3", "VD3", created = created, sortIndex = 0)
        val fin = makeItem("Finasteride", "FIN", created = created, sortIndex = 1)
        val fish = makeItem("Fish Oil", "FSH", Frequency.Daily(2), created = created, sortIndex = 2)
        val zinc = makeItem("Zinc", "ZNC", Frequency.AlternateDays, created = created, sortIndex = 3)
        val state = StackState(items = listOf(vd3, fin, fish, zinc))
        state.logDose(vd3.id, at(2026, 10, 12, 7, 42), london)
        state.logDose(zinc.id, at(2026, 10, 11, 8), london)

        val now = at(2026, 10, 12, 21)
        val logged = state.takeAllPending(now, c)
        assertEquals(setOf(fin.id, fish.id), logged.map { it.itemId }.toSet(), "one dose each for pending items only")
        assertTrue(logged.all { it.takenAt == now })
        assertEquals(1, state.doses.count { it.itemId == vd3.id }, "already taken: untouched")
        assertEquals(1, state.doses.count { it.itemId == zinc.id }, "not due: untouched")

        assertTrue(state.takeAllPending(now, c).isEmpty(), "a second TAKE ALL at once never logs the 2x item's next dose")
        assertTrue(state.takeAllPending(now.plusSeconds(59 * 60), c).isEmpty(), "nor does one within the hour")
        val later = now.plusSeconds(61 * 60)
        val again = state.takeAllPending(later, c)
        assertEquals(listOf(fish.id), again.map { it.itemId }, "an hour on, the second dose of the 2x item")
        assertTrue(state.takeAllPending(later, c).isEmpty(), "nothing left")
        assertTrue(StackEngine(state, c).todaySummary(later).allTaken)
    }

    @Test
    fun testRepeatedTakeAllNeverStacksDosesOfMultiDoseItems() {
        // The widget, the tile and the nudge can all fire TAKE ALL twice in a row.
        val c = londonClock()
        val created = at(2026, 10, 1, 8)
        val met = makeItem("Metformin", "MET", Frequency.Daily(2), created = created, sortIndex = 0)
        val fish = makeItem("Fish Oil", "FSH", Frequency.Daily(3), created = created, sortIndex = 1)
        val vd3 = makeItem("Vitamin D3", "VD3", created = created, sortIndex = 2)
        val state = StackState(items = listOf(met, fish, vd3))
        val morning = at(2026, 10, 12, 8)
        assertEquals(3, state.takeAllPending(morning, c).size)
        assertTrue(state.takeAllPending(morning.plusSeconds(5), c).isEmpty())
        val engine = StackEngine(state, c)
        val today = engine.todaySummary(morning.plusSeconds(5))
        assertEquals(listOf(met.id, fish.id), today.pendingItems.map { it.item.id }, "their next doses stay pending")
        assertTrue(engine.quickLogRows(today, morning.plusSeconds(5)).isEmpty())
        assertEquals(morning.plus(StackEngine.repeatGuard), engine.quickLogResumes(today.pendingItems[0], morning.plusSeconds(5)))

        // The row in the app is a deliberate tap: never held back.
        assertNotNull(state.logDose(met.id, morning.plusSeconds(10), london))
    }

    @Test
    fun testWidgetLogNeverDoubleLogs() {
        val c = londonClock()
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 1, 8))
        val state = StackState(items = listOf(vd3))
        val now = at(2026, 10, 12, 9)
        assertNotNull(state.logNextDoseIfPending(vd3.id, now, c))
        assertNull(state.logNextDoseIfPending(vd3.id, now, c))
        assertEquals(1, state.doses.size)
    }

    @Test
    fun testWidgetRowNeverLogsTheNextDoseWithinTheHour() {
        val c = londonClock()
        val fish = makeItem("Fish Oil", "FSH", Frequency.Daily(2), created = at(2026, 10, 1, 8))
        val state = StackState(items = listOf(fish))
        val morning = at(2026, 10, 12, 8)
        assertNotNull(state.logNextDoseIfPending(fish.id, morning, c))
        assertNull(state.logNextDoseIfPending(fish.id, morning.plusSeconds(20), c), "a second tap seconds later")
        assertNull(state.logNextDoseIfPending(fish.id, morning.plusSeconds(59 * 60), c))
        assertNotNull(state.logNextDoseIfPending(fish.id, at(2026, 10, 12, 19), c), "the evening dose")
        assertNull(state.logNextDoseIfPending(fish.id, at(2026, 10, 12, 21), c), "done for the day")
        assertEquals(2, state.doses.size)
    }

    @Test
    fun testWidgetSnapshotHoldsTakeAllBackUntilTheHourIsUp() {
        val fish = makeItem("Fish Oil", "FSH", Frequency.Daily(2), created = at(2026, 10, 1, 8), sortIndex = 0)
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 1, 8), sortIndex = 1)
        val state = StackState(items = listOf(fish, vd3))
        val morning = at(2026, 10, 12, 8)
        state.logDose(fish.id, morning, london)
        state.logDose(vd3.id, morning, london)

        val soon = WidgetSnapshot(state, morning.plusSeconds(600), london)
        assertEquals(1, soon.pendingItems)
        assertEquals(0, soon.readyItems, "no TAKE ALL while the only pending item was logged ten minutes ago")
        assertEquals(fish.id, soon.rows.firstOrNull()?.id)
        assertEquals(false, soon.rows.firstOrNull()?.ready)
        assertEquals(morning.plus(StackEngine.repeatGuard), soon.nextReady)

        val evening = WidgetSnapshot(state, at(2026, 10, 12, 19), london)
        assertEquals(1, evening.readyItems)
        assertEquals(true, evening.rows.firstOrNull()?.ready)
        assertNull(evening.nextReady)
    }

    @Test
    fun testTakeAllExplainsAHeldBackItem() {
        val fish = makeItem("Fish Oil", "FSH", Frequency.Daily(2), created = at(2026, 10, 1, 8))
        val state = StackState(items = listOf(fish))
        val morning = at(2026, 10, 12, 8)
        state.logDose(fish.id, morning, london)
        val answer = SiriAnswers.nothingPending(state, morning.plusSeconds(60), london)
        assertTrue(answer.startsWith("Nothing logged. Fish Oil was logged in the last hour."), answer)
    }

    // MARK: Undo and backfill

    @Test
    fun testUndoRemovesOnlyThatDose() {
        val c = londonClock()
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 1, 8))
        val state = StackState(items = listOf(vd3))
        val yesterday = state.logDose(vd3.id, at(2026, 10, 11, 8), london)!!
        val today = state.logDose(vd3.id, at(2026, 10, 12, 8), london)!!
        state.removeDoses(setOf(today.id))
        assertEquals(listOf(yesterday.id), state.doses.map { it.id })

        val again = state.logDose(vd3.id, at(2026, 10, 12, 9), london)!!
        val removed = state.undoLastDose(vd3.id, DayKey(2026, 10, 12), c)
        assertEquals(again.id, removed?.id)
        assertEquals(listOf(yesterday.id), state.doses.map { it.id }, "undo never reaches into another day")
        assertNull(state.undoLastDose(vd3.id, DayKey(2026, 10, 12), c))
    }

    @Test
    fun testBackfillOnPastDay() {
        val c = londonClock()
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 1, 8))
        val state = StackState(items = listOf(vd3))
        val saturday = DayKey(2026, 10, 10)
        assertEquals(DayStatus.MISSED, StackEngine(state, c).summary(saturday).status)

        state.logDose(vd3.id, c.date(saturday, hour = 9, minute = 0), london)
        val engine = StackEngine(state, c)
        assertEquals(DayStatus.COMPLETE, engine.summary(saturday).status)
        assertEquals(at(2026, 10, 10, 9, 0), engine.doses(vd3.id, saturday).firstOrNull()?.takenAt)
    }

    @Test
    fun testBackfillBeforeItemWasAddedExtendsHistory() {
        val c = londonClock()
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 12, 8))
        val state = StackState(items = listOf(vd3))
        val sunday = DayKey(2026, 10, 11)
        assertEquals(DayStatus.NOTHING_DUE, StackEngine(state, c).summary(sunday).status)
        state.logDose(vd3.id, c.date(sunday, hour = 9, minute = 0), london)
        assertEquals(DayStatus.COMPLETE, StackEngine(state, c).summary(sunday).status)
    }

    @Test
    fun testSetDoseTime() {
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 1, 8))
        val state = StackState(items = listOf(vd3))
        val dose = state.logDose(vd3.id, at(2026, 10, 12, 21), london)!!
        state.setDoseTime(dose.id, at(2026, 10, 12, 7), london)
        assertEquals(at(2026, 10, 12, 7), state.doses.firstOrNull()?.takenAt)
    }

    @Test
    fun testUndoPutsADoseBackExactlyAsItWas() {
        val c = londonClock()
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 1, 8))
        val state = StackState(items = listOf(vd3))
        val monday = DayKey(2026, 10, 12)
        val dose = state.logDose(vd3.id, at(2026, 10, 12, 7, 42), london)!!

        // Undo last dose by mistake, then UNDO on its toast.
        val removed = state.undoLastDose(vd3.id, monday, c)!!
        assertTrue(state.doses.isEmpty())
        state.restore(removed)
        assertEquals(listOf(dose), state.doses, "same id, same 07:42")
        state.restore(removed)
        assertEquals(1, state.doses.size, "restoring twice never duplicates")

        // Set time, then UNDO on its toast.
        state.setDoseTime(dose.id, at(2026, 10, 12, 7, 0), london)
        assertEquals(at(2026, 10, 12, 7, 0), state.doses.firstOrNull()?.takenAt)
        state.restore(dose)
        assertEquals(listOf(dose), state.doses, "the replaced time comes back")

        state.deleteItem(vd3.id)
        state.restore(dose)
        assertTrue(state.doses.isEmpty(), "never restores a dose of a deleted item")
    }

    @Test
    fun testDayStatusWordsForTodayAndEarlierDays() {
        val c = londonClock()
        val created = at(2026, 10, 1, 8)
        val vd3 = makeItem("Vitamin D3", "VD3", created = created, sortIndex = 0)
        val mag = makeItem("Magnesium", "MAG", created = created, sortIndex = 1)
        val state = StackState(items = listOf(vd3, mag))
        state.logDose(vd3.id, at(2026, 10, 11, 8), london)
        state.logDose(vd3.id, at(2026, 10, 12, 8), london)
        val engine = StackEngine(state, c)
        val today = engine.sheetSummary(DayKey(2026, 10, 12))
        val sunday = engine.sheetSummary(DayKey(2026, 10, 11))

        assertEquals("1 of 2 taken · 1 pending", Fmt.daySheetStatus(today, isToday = true))
        assertEquals("1 of 2 taken · 1 missed", Fmt.daySheetStatus(sunday, isToday = false))
        assertEquals("Daily · pending", Fmt.dayItemStatus(today.items[1], isToday = true))
        assertEquals("Daily · missed", Fmt.dayItemStatus(sunday.items[1], isToday = false))
        assertEquals("Daily · taken", Fmt.dayItemStatus(today.items[0], isToday = true))
    }

    @Test
    fun testTodaysProgressLineCountsDosesAsTheWidgetsDo() {
        val c = londonClock()
        val created = at(2026, 10, 1, 8)
        val vd3 = makeItem("Vitamin D3", "VD3", created = created, sortIndex = 0)
        val fish = makeItem("Fish Oil", "FSH", Frequency.Daily(2), created = created, sortIndex = 1)
        val zinc = makeItem("Zinc", "ZNC", Frequency.AlternateDays, created = created, sortIndex = 2)
        val state = StackState(items = listOf(vd3, fish, zinc))
        state.logDose(zinc.id, at(2026, 10, 11, 8), london)
        state.logDose(vd3.id, at(2026, 10, 12, 8), london)
        state.logDose(fish.id, at(2026, 10, 12, 8), london)
        val now = at(2026, 10, 12, 21)
        val partly = StackEngine(state, c).todaySummary(now)
        assertEquals("2 of 3 taken", Fmt.progress(partly), "doses: Fish Oil is 1 of 2, the not-due item is not counted")
        assertEquals(2, WidgetSnapshot(state, now, london).takenDue, "the widget says 2/3 too")
        state.logDose(fish.id, at(2026, 10, 12, 19), london)
        assertEquals("All taken", Fmt.progress(StackEngine(state, c).todaySummary(now)))
        val onlyZinc = StackState(items = listOf(zinc))
        onlyZinc.logDose(zinc.id, at(2026, 10, 11, 8), london)
        assertNull(Fmt.progress(StackEngine(onlyZinc, c).todaySummary(now)), "nothing due today")
    }

    // MARK: Stats

    @Test
    fun testStreakSkipsNothingDueDaysAndIgnoresUnfinishedToday() {
        val c = londonClock()
        val created = at(2026, 10, 1, 8)
        val mwf = makeItem("Minoxidil", "MIN", Frequency.Weekdays(setOf(2, 4, 6)), created = created)
        val state = StackState(items = listOf(mwf))
        // Mon 5, Wed 7, Fri 9 Oct taken; Mon 12 is today and not yet taken.
        for (day in listOf(5, 7, 9)) state.logDose(mwf.id, at(2026, 10, day, 8), london)
        var engine = StackEngine(state, c)
        val monday = DayKey(2026, 10, 12)
        assertEquals(3, engine.streak(monday), "weekends and off days do not break it; today pending does not either")

        state.logDose(mwf.id, at(2026, 10, 12, 8), london)
        engine = StackEngine(state, c)
        assertEquals(4, engine.streak(monday), "today counts once complete")
    }

    @Test
    fun testStreakBreaksOnMissedDay() {
        val c = londonClock()
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 1, 8))
        val state = StackState(items = listOf(vd3))
        for (day in listOf(8, 9, 11)) state.logDose(vd3.id, at(2026, 10, day, 8), london)
        val engine = StackEngine(state, c)
        assertEquals(1, engine.streak(DayKey(2026, 10, 12)), "10 Oct was missed")
    }

    @Test
    fun testThirtyDayAdherence() {
        val c = londonClock()
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 9, 1, 8))
        val state = StackState(items = listOf(vd3))
        val today = DayKey(2026, 10, 12)
        for (offset in 1..29) {
            if (offset == 5 || offset == 9) continue
            state.logDose(vd3.id, c.date(today.adding(-offset), hour = 8, minute = 0), london)
        }
        val engine = StackEngine(state, c)
        val pending = engine.adherence(today)
        assertEquals(29, pending.due, "today's untaken dose is not counted yet")
        assertEquals(27, pending.taken)
        assertEquals(93, pending.percent)

        state.logDose(vd3.id, c.date(today, hour = 8, minute = 0), london)
        val done = StackEngine(state, c).adherence(today)
        assertEquals(30, done.due)
        assertEquals(28, done.taken)
        assertEquals(93, done.percent)
        assertNull(Adherence(taken = 0, due = 0).percent)
        assertEquals(99, Adherence(taken = 199, due = 200).percent, "never rounds up to 100")
    }

    @Test
    fun testHistoryGridShape() {
        val c = londonClock()
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 9, 1, 8))
        val state = StackState(items = listOf(vd3))
        state.logDose(vd3.id, at(2026, 10, 11, 8), london)
        val wednesday = DayKey(2026, 10, 14)
        val grid = StackEngine(state, c).history(wednesday)
        assertEquals(5, grid.size)
        assertTrue(grid.all { it.size == 7 })
        assertEquals(DayKey(2026, 10, 12), grid[4][0].day, "last row starts on this Monday")
        assertTrue(grid[4][2].isToday)
        assertEquals(DayStatus.FUTURE, grid[4][3].status)
        assertEquals(DayStatus.COMPLETE, grid[3][6].status, "Sunday 11 Oct was taken")
        assertEquals(DayStatus.MISSED, grid[3][5].status)
    }

    @Test
    fun testArchivedItemKeepsHistoryButLeavesToday() {
        val c = londonClock()
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 1, 8), sortIndex = 0)
        val mag = makeItem("Magnesium", "MAG", created = at(2026, 10, 1, 8), sortIndex = 1)
        val state = StackState(items = listOf(vd3, mag))
        state.logDose(mag.id, at(2026, 10, 5, 21), london)
        state.setArchived(mag.id, archived = true, now = at(2026, 10, 10, 12))
        val engine = StackEngine(state, c)
        assertEquals(listOf(vd3.id), engine.todaySummary(at(2026, 10, 12, 9)).items.map { it.item.id })
        assertEquals(2, engine.summary(DayKey(2026, 10, 5)).items.size)
    }

    @Test
    fun testFrequencyChangeNeverRewritesPastDays() {
        val c = londonClock()
        val fin = makeItem("Finasteride", "FIN", Frequency.AlternateDays, created = at(2026, 9, 1, 8))
        val state = StackState(items = listOf(fin))
        val monday = DayKey(2026, 10, 12)
        // Every other day for three weeks, the last one yesterday.
        for (offset in 21 downTo 1 step 2) {
            state.logDose(fin.id, c.date(monday.adding(-offset), hour = 8, minute = 0), london)
        }
        val before = StackEngine(state, c)
        val offDay = monday.adding(-2)
        assertEquals(DayStatus.NOTHING_DUE, before.summary(offDay).status)

        state.updateItem(fin.id, name = "Finasteride", code = "FIN", frequency = Frequency.onceDaily, now = at(2026, 10, 12, 9))
        val after = StackEngine(state, c)
        assertEquals(DayStatus.NOTHING_DUE, after.summary(offDay).status, "an off day stays off")
        assertEquals(
            before.history(monday).flatten().filter { it.day < monday }.map { it.status },
            after.history(monday).flatten().filter { it.day < monday }.map { it.status },
            "every earlier day in the grid is unchanged",
        )
        assertEquals(before.streak(monday), after.streak(monday))
        assertEquals(before.adherence(monday), after.adherence(monday))
        val today = after.todaySummary(at(2026, 10, 12, 10)).items[0]
        assertTrue(today.isDue, "the new frequency applies from today")
        assertEquals(Frequency.onceDaily, today.frequency)
        assertEquals(Frequency.AlternateDays, after.summary(offDay).items[0].frequency)

        // 1x to 2x: earlier days stay complete at 1/1.
        val fish = makeItem("Fish Oil", "FSH", created = at(2026, 9, 1, 8))
        val oil = StackState(items = listOf(fish))
        for (offset in 1..5) {
            oil.logDose(fish.id, c.date(monday.adding(-offset), hour = 8, minute = 0), london)
        }
        oil.updateItem(fish.id, name = "Fish Oil", code = "FSH", frequency = Frequency.Daily(2), now = at(2026, 10, 12, 9))
        oil.updateItem(fish.id, name = "Fish Oil", code = "FSH", frequency = Frequency.Daily(3), now = at(2026, 10, 12, 9, 5))
        val oilEngine = StackEngine(oil, c)
        assertEquals(DayStatus.COMPLETE, oilEngine.summary(monday.adding(-1)).status)
        assertEquals(3, oilEngine.todaySummary(at(2026, 10, 12, 10)).dueDoses, "two changes on one day: the last wins today")
        assertEquals(1, oilEngine.summary(monday.adding(-1)).dueDoses, "and the first frequency still holds before it")
    }

    @Test
    fun testUnarchiveKeepsTheArchivedDaysOutOfHistory() {
        val c = londonClock()
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 9, 1, 8), sortIndex = 0)
        val mag = makeItem("Magnesium", "MAG", created = at(2026, 9, 1, 8), sortIndex = 1)
        val state = StackState(items = listOf(vd3, mag))
        for (day in 1..11) state.logDose(vd3.id, at(2026, 10, day, 8), london)
        for (day in 1..4) state.logDose(mag.id, at(2026, 10, day, 21), london)
        state.setArchived(mag.id, archived = true, now = at(2026, 10, 5, 7))
        val monday = DayKey(2026, 10, 12)
        val before = StackEngine(state.clone(), c)

        state.setArchived(mag.id, archived = false, now = at(2026, 10, 12, 9))
        val after = StackEngine(state, c)
        val thursday = DayKey(2026, 10, 8)
        assertEquals(DayStatus.COMPLETE, after.summary(thursday).status, "an archived day is not a missed day")
        assertEquals(before.history(monday).flatten().map { it.status }, after.history(monday).flatten().map { it.status })
        assertEquals(before.streak(monday), after.streak(monday))
        assertEquals(before.adherence(monday), after.adherence(monday))
        assertTrue(
            after.todaySummary(at(2026, 10, 12, 10)).pendingItems.any { it.item.id == mag.id },
            "back in today's stack",
        )

        // The day sheet still offers the archived days, and a dose logged there counts.
        val row = after.sheetSummary(thursday).items.firstOrNull { it.item.id == mag.id }
        assertEquals("Daily · archived", row?.let { Fmt.dayItemStatus(it, isToday = false) })
        state.logDose(mag.id, at(2026, 10, 8, 21), london)
        assertEquals(2, StackEngine(state, c).summary(thursday).dueDoses)
    }

    @Test
    fun testDosesKeepTheirDayAfterATimeZoneChange() {
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 1, 8))
        val monday = DayKey(2026, 10, 12)

        // 07:42 BST on Monday in London is 02:42 EDT, before New York's 04:00 day start.
        val west = StackState(items = listOf(vd3))
        west.logDose(vd3.id, at(2026, 10, 12, 7, 42), london)
        val inNewYork = StackEngine(west, londonClock(4, newYork))
        val today = inNewYork.todaySummary(at(2026, 10, 12, 13, 0, newYork))
        assertEquals(monday, today.day)
        assertTrue(today.allTaken, "this morning's dose still belongs to Monday")
        assertEquals(DayStatus.MISSED, inNewYork.summary(monday.adding(-1)).status, "and not to Sunday")
        assertNotNull(west.undoLastDose(vd3.id, monday, londonClock(4, newYork)))

        // 23:30 EDT on Monday is 04:30 BST on Tuesday: it stays Monday's, and Tuesday is still to take.
        val east = StackState(items = listOf(vd3))
        east.logDose(vd3.id, at(2026, 10, 12, 23, 30, newYork), newYork)
        val inLondon = StackEngine(east, londonClock())
        assertEquals(DayStatus.COMPLETE, inLondon.summary(monday).status)
        val tuesday = inLondon.todaySummary(at(2026, 10, 13, 10))
        assertEquals(monday.adding(1), tuesday.day)
        assertEquals(1, tuesday.pendingItems.size)

        // A dose saved before offsets were recorded reads in the current zone, as it always did.
        val legacy = StackState(items = listOf(vd3))
        legacy.doses = legacy.doses + Dose(itemId = vd3.id, takenAt = at(2026, 10, 12, 7, 42))
        assertEquals(DayStatus.COMPLETE, StackEngine(legacy, londonClock(4, newYork)).summary(monday.adding(-1)).status)
    }

    @Test
    fun testLogItemNeverLogsToAnArchivedItem() {
        val cre = makeItem("Creatine", "CRE", created = at(2026, 10, 1, 8))
        val state = StackState(items = listOf(cre))
        state.setArchived(cre.id, archived = true, now = at(2026, 10, 10, 9))
        assertNull(state.logActiveDose(cre.id, at(2026, 10, 12, 18, 5), london))
        assertTrue(state.doses.isEmpty())
        state.setArchived(cre.id, archived = false, now = at(2026, 10, 12, 18))
        assertNotNull(state.logActiveDose(cre.id, at(2026, 10, 12, 18, 5), london))
        assertNull(state.logActiveDose(UUID.randomUUID(), at(2026, 10, 12, 18, 5), london))
    }

    @Test
    fun testDeleteRemovesItemAndItsDoses() {
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 1, 8), sortIndex = 0)
        val mag = makeItem("Magnesium", "MAG", created = at(2026, 10, 1, 8), sortIndex = 1)
        val state = StackState(items = listOf(vd3, mag))
        state.logDose(mag.id, at(2026, 10, 5, 21), london)
        state.logDose(vd3.id, at(2026, 10, 5, 8), london)
        state.deleteItem(mag.id)
        assertEquals(listOf(vd3.id), state.items.map { it.id })
        assertEquals(1, state.doses.size)
        val summary = StackEngine(state, londonClock()).summary(DayKey(2026, 10, 5))
        assertEquals(DayStatus.COMPLETE, summary.status)
    }

    @Test
    fun testReorder() {
        val created = at(2026, 10, 1, 8)
        val state = StackState(
            items = listOf(
                makeItem("A", "AAA", created = created, sortIndex = 0),
                makeItem("B", "BBB", created = created, sortIndex = 1),
                makeItem("C", "CCC", created = created, sortIndex = 2),
            ),
        )
        state.moveActiveItems(setOf(0), 3)
        assertEquals(listOf("BBB", "CCC", "AAA"), state.orderedItems.map { it.code })
        state.moveActiveItems(setOf(2), 0)
        assertEquals(listOf("AAA", "BBB", "CCC"), state.orderedItems.map { it.code })
    }

    @Test
    fun testAddItemsUsesPresetCodesAndDerivesOthers() {
        val state = StackState()
        val added = state.addItems(
            listOf(ItemDraft("Vitamin D3"), ItemDraft("  Lion's Mane "), ItemDraft("   ")),
            at(2026, 10, 12, 9),
        )
        assertEquals(2, added.size)
        assertEquals("VD3", added[0].code)
        assertEquals("Lion's Mane", added[1].name)
        assertEquals("LMN", added[1].code)
        assertEquals(listOf(0, 1), added.map { it.sortIndex })
        assertEquals("ASH", Catalog.code("Ashwagandha"))
        assertEquals("BRB", Catalog.code("Berberine"))
        assertEquals("VD3E", Catalog.sanitizeCode("vd-3 extra"))
    }

    // MARK: Siri (the sentences, kept as a pure test: the nudge and the widgets share the rules)

    @Test
    fun testSiriAnswer() {
        val created = at(2026, 10, 1, 8)
        val vd3 = makeItem("Vitamin D3", "VD3", created = created, sortIndex = 0)
        val fish = makeItem("Fish Oil", "FSH", created = created, sortIndex = 1)
        val zinc = makeItem("Zinc", "ZNC", Frequency.AlternateDays, created = created, sortIndex = 2)
        val state = StackState(items = listOf(vd3, fish, zinc))
        state.logDose(zinc.id, at(2026, 10, 11, 8), london)
        state.logDose(vd3.id, at(2026, 10, 12, 7, 42), london)
        val pending = SiriAnswers.status(state, at(2026, 10, 12, 21), london, enUS)
        assertTrue(pending.startsWith("Not yet: Fish Oil is pending."), pending)
        assertTrue(pending.contains("Zinc is not due today."), pending)

        state.logDose(fish.id, at(2026, 10, 12, 7, 42), london)
        val done = SiriAnswers.status(state, at(2026, 10, 12, 21), london, enUS)
        assertTrue(done.startsWith("Yes. Vitamin D3 at "), done)
    }
}
