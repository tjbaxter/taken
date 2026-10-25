package com.tombaxter.taken.core

import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.Item
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.reminders.Reminders
import com.tombaxter.taken.core.stack.CsvExport
import com.tombaxter.taken.core.stack.DaySheetRules
import com.tombaxter.taken.core.stack.DayStatus
import com.tombaxter.taken.core.stack.ProgressCopy
import com.tombaxter.taken.core.stack.RowSpeech
import com.tombaxter.taken.core.stack.SiriAnswers
import com.tombaxter.taken.core.stack.StackEngine
import com.tombaxter.taken.core.stack.TodayRules
import com.tombaxter.taken.core.stack.WidgetSnapshot
import com.tombaxter.taken.core.stack.item
import com.tombaxter.taken.core.stack.logDose
import com.tombaxter.taken.core.stack.logNextDoseIfPending
import com.tombaxter.taken.core.stack.removeDoses
import com.tombaxter.taken.core.stack.restore
import com.tombaxter.taken.core.stack.takeAllPending
import com.tombaxter.taken.core.stack.updateItem
import java.time.ZoneId
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/WeeklyWeekTests.swift: a weekly dose counts for its week (SPEC 3.3, R1 to R5). London clock, the
 * day starting at 04:00. Semaglutide (SEM) is Weekly on Thursday; Vitamin D3 (VD3) is daily and logged on every past day.
 */
class WeeklyWeekTests {

    private val thu15 = DayKey(2026, 10, 15)
    private val fri16 = DayKey(2026, 10, 16)
    private val sat17 = DayKey(2026, 10, 17)
    private val sun18 = DayKey(2026, 10, 18)
    private val tue20 = DayKey(2026, 10, 20)
    private val wed21 = DayKey(2026, 10, 21)
    private val thu22 = DayKey(2026, 10, 22)

    private class Stack(val state: StackState, val vd3: Item, val sem: Item) {
        val engine: StackEngine get() = StackEngine(state, londonClock())

        /** The same Vitamin D3 log without Semaglutide. */
        val vd3Only: StackEngine
            get() = StackEngine(StackState(items = listOf(vd3), doses = state.doses.filter { it.itemId == vd3.id }), londonClock())
    }

    /** Both items added on Thu 1 Oct, Semaglutide logged on Thu 1 and Thu 8 at 08:00, Vitamin D3 at 08:00 from 1 Oct. */
    private fun stack(vd3Through: Int, reminder: Boolean = false): Stack {
        val created = at(2026, 10, 1, 7)
        val vd3 = makeItem("Vitamin D3", "VD3", created = created, sortIndex = 0)
        val sem = makeItem("Semaglutide", "SEM", Frequency.Weekdays(setOf(5)), created = created, sortIndex = 1)
        val state = StackState(items = listOf(vd3, sem))
        for (day in 1..vd3Through) state.logDose(vd3.id, at(2026, 10, day, 8), london)
        state.logDose(sem.id, at(2026, 10, 1, 8), london)
        state.logDose(sem.id, at(2026, 10, 8, 8), london)
        if (reminder) {
            state.settings.reminderEnabled = true
            state.settings.reminderMinutes = 21 * 60
        }
        return Stack(state, vd3, sem)
    }

    // MARK: R1 credit

    @Test
    fun testALateDoseCountsForItsDayAtItsRealTime() {
        val s = stack(vd3Through = 21)
        val without = s.engine
        s.state.logDose(s.sem.id, at(2026, 10, 16, 8, 12), london)
        val engine = s.engine

        assertEquals(DayStatus.COMPLETE, engine.summary(thu15).status)
        assertEquals(DayStatus.COMPLETE, engine.summary(thu15, asOf = sat17).status)
        assertEquals(listOf(at(2026, 10, 16, 8, 12)), engine.doses(s.sem.id, thu15).map { it.takenAt }, "it counts for Thursday at its real time")
        assertTrue(engine.doses(s.sem.id, fri16).isEmpty(), "Friday holds no Semaglutide dose")
        assertFalse(engine.itemDay(s.sem, thu15, asOf = sat17).isOpen)
        assertEquals(17, engine.streak(sat17), "Thu 15 counts: every day from 1 Oct")
        assertEquals(21, engine.streak(thu22), "and still does once the week has closed")
        assertEquals(6, without.streak(thu22), "without it Thursday is missed and the streak starts on Friday")

        val csv = CsvExport.make(s.state, london)
        assertTrue(csv.contains("\n2026-10-16,08:12,Semaglutide,SEM\n"), "CSV keeps the real date and time: $csv")
    }

    // MARK: R2 open week

    @Test
    fun testAnOpenWeekNeitherBreaksNorGrowsTheStreak() {
        val s = stack(vd3Through = 21)
        val engine = s.engine
        for (offset in 1..6) {
            val today = thu15.adding(offset)
            assertEquals(s.vd3Only.streak(today), engine.streak(today), "on ${Fmt.longDay(today)}")
            assertTrue(engine.itemDay(s.sem, thu15, asOf = today).isOpen, "open on ${Fmt.longDay(today)}")
            assertEquals(0, engine.itemDay(s.sem, thu15, asOf = today).dueCount)
            val cell = engine.history(today).flatten().firstOrNull { it.day == thu15 }
            assertEquals(DayStatus.COMPLETE, cell?.status, "the grid cell for Thu 15 on ${Fmt.longDay(today)}")
            assertEquals(100, engine.adherence(today).percent, "the 30-day % neither gains nor loses")
        }
        assertFalse(engine.itemDay(s.sem, thu15, asOf = thu15).isOpen, "on its day it is due and pending")
        assertTrue(engine.itemDay(s.sem, thu15, asOf = null).isPending, "null turns the rule off")
    }

    @Test
    fun testTheWeekClosesOnTheNextDueDay() {
        val s = stack(vd3Through = 21)
        val engine = s.engine
        assertFalse(engine.itemDay(s.sem, thu15, asOf = thu22).isOpen)
        assertEquals(DayStatus.PARTIAL, engine.summary(thu15, asOf = thu22).status, "missed once the next due day comes")
        assertEquals(6, engine.streak(thu22), "the streak counts from Fri 16 only")
        val row = engine.todaySummary(at(2026, 10, 22, 9)).items.firstOrNull { it.item.id == s.sem.id }
        assertEquals(1, row?.pendingCount, "one ring and one pending dose, never 2")
        assertEquals(1, row?.dosesPerDay)
    }

    @Test
    fun testAnEarlyDoseCountsForTheNextDueDayAndItsNudgeGoes() {
        val s = stack(vd3Through = 19, reminder = true)
        s.state.logDose(s.sem.id, at(2026, 10, 15, 8), london)
        s.state.logDose(s.sem.id, at(2026, 10, 20, 8, 12), london)
        val engine = s.engine

        assertEquals(listOf(at(2026, 10, 20, 8, 12)), engine.doses(s.sem.id, thu22).map { it.takenAt })
        assertTrue(engine.doses(s.sem.id, tue20).isEmpty())
        val today = engine.todaySummary(at(2026, 10, 22, 9))
        val row = today.items.firstOrNull { it.item.id == s.sem.id }
        assertEquals(true, row?.isDone, "Thu 22's row is done, showing that dose")
        assertEquals(false, row?.isPending)
        assertEquals("Tue 08:12", row?.lastDose?.let { Fmt.doseClock(it, thu22, londonClock()) })
        assertEquals("1 of 2 taken", Fmt.progress(today), "it counts in today's progress")

        val plans = Reminders.plan(s.state, at(2026, 10, 20, 9), london)
        assertEquals("1 pending: VD3", plans.firstOrNull { it.day == thu22 }?.body, "no nudge that reads as take another")
    }

    @Test
    fun testAnExtraDoseStaysOnItsDay() {
        val s = stack(vd3Through = 16, reminder = true)
        s.state.logDose(s.sem.id, at(2026, 10, 15, 8), london)
        s.state.logDose(s.sem.id, at(2026, 10, 15, 9), london)
        assertEquals(2, s.engine.doses(s.sem.id, thu15).size, "a second dose on the shot day stays there")

        s.state.logDose(s.sem.id, at(2026, 10, 16, 8), london)
        val engine = s.engine
        assertEquals(1, engine.doses(s.sem.id, fri16).size, "6 days before the next due day it stays put")
        assertEquals(2, engine.doses(s.sem.id, thu15).size)
        assertTrue(engine.doses(s.sem.id, thu22).isEmpty())

        val plans = Reminders.plan(s.state, at(2026, 10, 16, 9), london)
        assertEquals("2 pending: VD3, SEM", plans.firstOrNull { it.day == thu22 }?.body, "Thu 22 is still due")
    }

    // MARK: R3 and R4

    @Test
    fun testNoNudgeAfterTheDueDay() {
        val s = stack(vd3Through = 15, reminder = true)
        val plans = Reminders.plan(s.state, at(2026, 10, 16, 9), london)
        for (offset in 0 until 6) {
            val day = fri16.adding(offset)
            assertEquals("1 pending: VD3", plans.firstOrNull { it.day == day }?.body, "no Semaglutide on ${Fmt.longDay(day)}")
        }
        assertEquals("2 pending: VD3, SEM", plans.firstOrNull { it.day == thu22 }?.body)
    }

    @Test
    fun testQuickPathsNeverLogAWeeklyItemOffItsDay() {
        val s = stack(vd3Through = 15)
        val now = at(2026, 10, 16, 9)
        val take = s.state.clone()
        assertEquals(listOf(s.vd3.id), take.takeAllPending(now, londonClock()).map { it.itemId }, "Take all logs VD3 only")
        val widget = s.state.clone()
        assertNull(widget.logNextDoseIfPending(s.sem.id, now, londonClock()))
        assertFalse(s.engine.todaySummary(now).due.any { it.item.id == s.sem.id })
        val snapshot = WidgetSnapshot(s.state, now, london)
        assertFalse(snapshot.rows.any { it.id == s.sem.id }, "the widget leaves the open week out")
    }

    // MARK: Rows and copy

    @Test
    fun testWeekRowAndItsCopy() {
        val s = stack(vd3Through = 16)
        val open = assertNotNull(s.engine.weekRow(s.sem, sat17))
        assertTrue(open.isOpen)
        assertEquals(thu15, open.day)
        assertEquals("Weekly · Thu · Not logged", Fmt.weekNote(open, sat17))
        val sheet = s.engine.sheetSummary(thu15, asOf = sat17)
        val sheetRow = assertNotNull(sheet.items.firstOrNull { it.item.id == s.sem.id })
        assertEquals("Weekly · Thu · not logged", Fmt.dayItemStatus(sheetRow, isToday = false))
        assertEquals("1 of 2 taken · 1 not logged", Fmt.daySheetStatus(sheet, isToday = false))

        val dose = assertNotNull(s.state.logDose(s.sem.id, at(2026, 10, 17, 8, 12), london))
        val logged = assertNotNull(s.engine.weekRow(s.sem, sat17))
        assertFalse(logged.isOpen)
        assertEquals(dose.id, logged.lastDose?.id)
        assertEquals("08:12", Fmt.doseClock(dose, sat17, londonClock()))
        assertEquals("Sat 08:12", Fmt.doseClock(dose, sun18, londonClock()))
        assertEquals("Weekly · Next: Thursday", Fmt.weekNote(logged, sat17))
        assertEquals("Weekly · Next: Thursday", Fmt.weekNote(assertNotNull(s.engine.weekRow(s.sem, sun18)), sun18))
        assertEquals("1d 2h ago", Fmt.agoDetailed(at(2026, 10, 16, 8, 12), at(2026, 10, 17, 10, 12)))
        assertEquals("1d ago", Fmt.agoDetailed(at(2026, 10, 16, 8, 12), at(2026, 10, 17, 8, 40)))
        assertEquals("9h 12m ago", Fmt.agoDetailed(at(2026, 10, 17, 8, 12), at(2026, 10, 17, 17, 24)), "unchanged")

        val early = stack(vd3Through = 19)
        early.state.logDose(early.sem.id, at(2026, 10, 15, 8), london)
        early.state.logDose(early.sem.id, at(2026, 10, 20, 8, 12), london)
        val waiting = assertNotNull(early.engine.weekRow(early.sem, wed21))
        assertEquals(thu22, waiting.day)
        assertEquals("Weekly · Counts for Thursday", Fmt.weekNote(waiting, wed21))
        assertEquals("Tue 08:12", waiting.lastDose?.let { Fmt.doseClock(it, wed21, londonClock()) })
    }

    // MARK: The early dose (R1 b) on Today, its day and its sheet

    /** The 1 to 3 days before the next due day, with this week logged, Today's row is today's quiet ring. */
    @Test
    fun testAnEarlyDoseIsOneTapInTheDaysBeforeTheNextDueDay() {
        val s = stack(vd3Through = 21)
        s.state.logDose(s.sem.id, at(2026, 10, 15, 8), london)
        for (offset in 1..3) {
            assertFalse(s.engine.takesEarlyDose(s.sem, thu15.adding(offset)), "D+$offset: the lit ring stays")
        }
        for (offset in 4..6) {
            assertTrue(s.engine.takesEarlyDose(s.sem, thu15.adding(offset)), "D+$offset: a tap logs")
        }
        val open = stack(vd3Through = 21)
        assertTrue(open.engine.weekRow(open.sem, tue20)?.isOpen ?: false)
        assertFalse(open.engine.takesEarlyDose(open.sem, tue20), "an open week logs from its own ring")
        s.state.logDose(s.sem.id, at(2026, 10, 20, 8, 12), london)
        assertFalse(s.engine.takesEarlyDose(s.sem, wed21), "once it is logged the row is Thu 22's")
        assertEquals(thu22, s.engine.weekRow(s.sem, wed21)?.day)
    }

    /**
     * Thu 15 logged, then a tap on Semaglutide's Not today row on Tue 20 logs a dose that counts for Thu 22. The iPhone
     * test runs it through AppModel; here the rules it calls (TodayRules) run on their own, and the app's TodayRowTests
     * run the tap through Android's AppModel with its toast.
     */
    @Test
    fun testATapOnTheRingLogsAnEarlyDoseFromToday() {
        val zone: ZoneId = london
        fun local(day: Int, hour: Int, minute: Int = 0) = at(2026, 10, day, hour, minute, zone)
        val vd3 = makeItem("Vitamin D3", "VD3", created = local(1, 9), sortIndex = 0)
        val sem = makeItem("Semaglutide", "SEM", Frequency.Weekdays(setOf(5)), created = local(1, 9), sortIndex = 1)
        val state = StackState(items = listOf(vd3, sem))
        state.logDose(sem.id, local(8, 9), zone)
        state.logDose(sem.id, local(15, 9), zone)
        val now = local(20, 10, 30)
        val clock = londonClock(state.settings.dayStartHour)
        var engine = StackEngine(state, clock)
        var today = engine.todaySummary(now)

        val entry = assertNotNull(today.notDue.firstOrNull { it.item.id == sem.id })
        val shown = TodayRules.notTodayRow(engine, entry, today.day)
        assertEquals(tue20, shown.row.day, "today's row, not last Thursday's")
        assertTrue(shown.row.doses.isEmpty(), "a quiet ring")
        assertEquals("Weekly · Next: Thursday", shown.note)
        assertEquals(TodayRules.Tap.LOG, TodayRules.tap(shown.row, editing = false))
        state.logDose(sem.id, now, zone)
        engine = StackEngine(state, clock)
        today = engine.todaySummary(now)

        assertEquals(listOf(now), engine.doses(sem.id, thu22).map { it.takenAt }, "it counts for Thu 22")
        assertTrue(engine.doses(sem.id, tue20).isEmpty())
        val after = TodayRules.notTodayRow(engine, assertNotNull(today.notDue.firstOrNull { it.item.id == sem.id }), today.day)
        assertEquals(thu22, after.row.day)
        assertEquals("Weekly · Counts for Thursday", after.note)
        assertTrue(TodayRules.offersSetTime(after.row, today.day, clock), "logged today: Set time corrects it")
    }

    /** On Thu 22 with the Tue 20 dose credited to it, the row, the progress line, TalkBack and the answers name Tuesday. */
    @Test
    fun testAnEarlyDoseKeepsItsDayOnTheDueDay() {
        val s = stack(vd3Through = 21)
        s.state.logDose(s.sem.id, at(2026, 10, 15, 8), london)
        s.state.logDose(s.sem.id, at(2026, 10, 20, 8, 12), london)
        val now = at(2026, 10, 22, 7)
        val today = s.engine.todaySummary(now)
        val row = assertNotNull(today.items.firstOrNull { it.item.id == s.sem.id })
        assertEquals(thu22, row.day)
        assertEquals(at(2026, 10, 20, 8, 12), today.lastDose?.takenAt, "the only dose counted for today")

        val siri = SiriAnswers.status(s.state, now, london, enUS)
        assertTrue(siri.contains("Semaglutide taken Tuesday at 8:12 AM."), siri)
        assertFalse(siri.contains("Semaglutide at 8:12 AM"), siri)
        val same = SiriAnswers.status(stack(vd3Through = 22).state, at(2026, 10, 22, 9), london, enUS)
        assertTrue(same.contains("Vitamin D3 at 8:00 AM"), "a dose logged today reads as before: $same")
        assertEquals("Semaglutide, taken Tuesday at 8:12 AM.", RowSpeech.label(row, thu22, londonClock(), nextLabel = null, locale = enUS))
        assertEquals("Tue 08:12", ProgressCopy.lastTime(today, londonClock()), "Last Tue 08:12, never 08:12")
        val vd3Row = assertNotNull(stack(vd3Through = 22).engine.todaySummary(at(2026, 10, 22, 9)).items.firstOrNull())
        assertEquals(
            "Vitamin D3, taken at 8:00 AM.",
            RowSpeech.label(vd3Row, thu22, londonClock(), nextLabel = null, locale = enUS),
            "unchanged for a dose logged that day",
        )
    }

    /** "Open Thursday" on the early row opens Thu 22 from Tue 20: a day still to come reads as pending, never missed. */
    @Test
    fun testTheNextDueDaysSheetNeverSaysMissed() {
        val s = stack(vd3Through = 19)
        s.state.logDose(s.sem.id, at(2026, 10, 15, 8), london)
        val dose = assertNotNull(s.state.logDose(s.sem.id, at(2026, 10, 19, 8, 12), london))
        val row = assertNotNull(s.engine.weekRow(s.sem, tue20))
        assertEquals(thu22, row.day, "Mon 19 is 3 days before Thu 22: it counts for it")
        val sheet = s.engine.sheetSummary(thu22, asOf = tue20)
        val live = DaySheetRules.isLive(thu22, tue20)
        assertTrue(live)
        assertFalse(DaySheetRules.isLive(thu15, tue20), "an earlier day is still past")
        val status = Fmt.daySheetStatus(sheet, isToday = live)
        assertEquals("1 of 2 taken · 1 pending", status)
        for (line in listOf(status) + sheet.items.map { Fmt.dayItemStatus(it, isToday = live) }) {
            assertFalse(line.lowercase().contains("missed"), line)
        }
        assertEquals("Mon 08:12", Fmt.doseClock(dose, thu22, londonClock()))
    }

    @Test
    fun testCreditRespectsTheStartAndScheduleChanges() {
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 1, 7), sortIndex = 0)
        val added = makeItem("Semaglutide", "SEM", Frequency.Weekdays(setOf(5)), created = at(2026, 10, 17, 9), sortIndex = 1)
        val fresh = StackState(items = listOf(vd3, added))
        fresh.logDose(added.id, at(2026, 10, 17, 10), london)
        var engine = StackEngine(fresh, londonClock())
        assertEquals(1, engine.doses(added.id, sat17).size, "added on Saturday: the dose stays on Saturday")
        assertTrue(engine.doses(added.id, thu15).isEmpty(), "never for a Thursday before it was added")
        assertNull(engine.weekRow(added, sat17), "the row reads as before")
        assertEquals(true, engine.todaySummary(at(2026, 10, 22, 9)).items.firstOrNull { it.item.id == added.id }?.isPending, "Thu 22 is due")

        val s = stack(vd3Through = 17)
        s.state.updateItem(s.sem.id, name = "Semaglutide", code = "SEM", frequency = Frequency.Weekdays(setOf(7)), now = at(2026, 10, 17, 9))
        s.state.logDose(s.sem.id, at(2026, 10, 17, 10), london)
        engine = s.engine
        assertEquals(1, engine.doses(s.sem.id, sat17).size, "moved to Saturday: a Saturday dose counts for it")
        assertTrue(engine.doses(s.sem.id, thu15).isEmpty(), "never for Thu 15, on the old schedule")

        // Weekly to Every other day after a late dose: the dose still counts for Thu 15, and Every other day reads the day
        // it was really taken, Sat 17, so Sun 18 is not due and the nudge never asks for it a day after a dose.
        val switched = stack(vd3Through = 17, reminder = true)
        switched.state.logDose(switched.sem.id, at(2026, 10, 17, 10), london)
        switched.state.updateItem(switched.sem.id, name = "Semaglutide", code = "SEM", frequency = Frequency.AlternateDays, now = at(2026, 10, 18, 9))
        engine = switched.engine
        val sem = assertNotNull(switched.state.item(switched.sem.id))
        assertEquals(1, engine.doses(sem.id, thu15).size, "the late dose still counts for its week")
        assertEquals(sat17, engine.lastDoseDay(sem.id, before = sun18), "the day it was logged")
        assertFalse(engine.isDue(sem, sun18), "a day after a real dose")
        assertTrue(engine.isDue(sem, sun18.adding(1)))
        assertEquals(sun18.adding(1), engine.nextDueDay(sem, after = sun18))
        val plans = Reminders.plan(switched.state, at(2026, 10, 18, 9), london)
        assertEquals("1 pending: VD3", plans.firstOrNull { it.day == sun18 }?.body, "no Semaglutide on Sun 18")
        assertEquals("2 pending: VD3, SEM", plans.firstOrNull { it.day == sun18.adding(1) }?.body)
    }

    @Test
    fun testOtherSchedulesAreUnchanged() {
        val mwf = makeItem("Minoxidil", "MIN", Frequency.Weekdays(setOf(2, 4, 6)), created = at(2026, 10, 1, 8))
        val state = StackState(items = listOf(mwf))
        state.logDose(mwf.id, at(2026, 10, 13, 8), london)
        val engine = StackEngine(state, londonClock())
        val monday = DayKey(2026, 10, 12)
        assertEquals(DayStatus.MISSED, engine.summary(monday, asOf = monday.adding(1)).status)
        assertEquals(DayStatus.MISSED, engine.summary(monday, asOf = monday.adding(3)).status)
        assertEquals(1, engine.doses(mwf.id, monday.adding(1)).size, "the dose stays on Tuesday")
        assertNull(engine.weekRow(mwf, monday.adding(1)))
        assertFalse(engine.itemDay(mwf, monday, asOf = monday.adding(1)).isOpen)
    }

    @Test
    fun testUndoReopensTheWeek() {
        val s = stack(vd3Through = 17)
        val late = assertNotNull(s.state.logDose(s.sem.id, at(2026, 10, 16, 8, 12), london))
        assertFalse(s.engine.itemDay(s.sem, thu15, asOf = sat17).isOpen)
        s.state.removeDoses(setOf(late.id))
        assertTrue(s.engine.itemDay(s.sem, thu15, asOf = sat17).isOpen, "Thu 15 is open again")
        s.state.restore(late)
        assertEquals(listOf(late.id), s.engine.doses(s.sem.id, thu15).map { it.id }, "and Undo puts it back")
    }

    @Test
    fun testADoseLoggedAbroadCreditsFromItsLoggedDay() {
        val s = stack(vd3Through = 21)
        // 23:30 EDT on Wed 21 is 04:30 BST on Thu 22: logged on Wednesday where it was taken, so it counts for Thu 15.
        s.state.logDose(s.sem.id, at(2026, 10, 21, 23, 30, newYork), newYork)
        val engine = s.engine
        assertEquals(1, engine.doses(s.sem.id, thu15).size)
        assertTrue(engine.doses(s.sem.id, thu22).isEmpty())
        assertEquals(true, engine.todaySummary(at(2026, 10, 22, 9)).items.firstOrNull { it.item.id == s.sem.id }?.isPending)
        val late = assertNotNull(engine.doses(s.sem.id, thu15).firstOrNull())
        assertTrue(
            Fmt.doseClock(late, thu15, londonClock()).startsWith("Wed "),
            "logged on Wednesday where it was taken: the chip names Wednesday, as the engine reads it",
        )

        // On time abroad: 23:30 EDT on Thu 15 is 04:30 BST on Fri 16, after the 04:00 day start. Back in London it reads as
        // Thursday's dose on Thursday, with no day before the time, and the answer says it was taken on its day.
        val onTime = stack(vd3Through = 21)
        val dose = assertNotNull(onTime.state.logDose(onTime.sem.id, at(2026, 10, 15, 23, 30, newYork), newYork))
        assertEquals(listOf(dose.id), onTime.engine.doses(onTime.sem.id, thu15).map { it.id })
        assertEquals("04:30", Fmt.doseClock(dose, thu15, londonClock()), "no Fri before an on-time dose")
        assertEquals("Thu 04:30", Fmt.doseClock(dose, sat17, londonClock()))
        assertEquals("at 4:30 AM", Fmt.spokenDose(dose, thu15, londonClock(), enUS))
        val siri = SiriAnswers.status(onTime.state, at(2026, 10, 17, 10), london, enUS)
        assertTrue(siri.contains("Semaglutide was taken Thursday at 4:30 AM."), siri)
        assertFalse(siri.contains("for Thursday"), "never as taken on another day: $siri")

        // A daily dose logged abroad keeps its plain time on its own day.
        val daily = stack(vd3Through = 14)
        val vd3 = assertNotNull(daily.state.logDose(daily.vd3.id, at(2026, 10, 15, 23, 30, newYork), newYork))
        assertEquals(listOf(vd3.id), daily.engine.doses(daily.vd3.id, thu15).map { it.id })
        assertEquals("04:30", Fmt.doseClock(vd3, thu15, londonClock()))
    }

    @Test
    fun testSiriWeeklySentences() {
        val late = stack(vd3Through = 17)
        late.state.logDose(late.sem.id, at(2026, 10, 16, 8, 12), london)
        val lateAnswer = SiriAnswers.status(late.state, at(2026, 10, 17, 10), london, enUS)
        assertTrue(lateAnswer.contains("Semaglutide was taken Friday at 8:12 AM, for Thursday."), lateAnswer)
        assertFalse(lateAnswer.contains("not due today"), lateAnswer)

        val onDay = stack(vd3Through = 17)
        onDay.state.logDose(onDay.sem.id, at(2026, 10, 15, 8, 12), london)
        val onDayAnswer = SiriAnswers.status(onDay.state, at(2026, 10, 17, 10), london, enUS)
        assertTrue(onDayAnswer.contains("Semaglutide was taken Thursday at 8:12 AM."), onDayAnswer)

        val open = stack(vd3Through = 17)
        val openAnswer = SiriAnswers.status(open.state, at(2026, 10, 17, 10), london, enUS)
        assertTrue(openAnswer.contains("Semaglutide is not logged for Thursday."), openAnswer)

        val row = assertNotNull(open.engine.weekRow(open.sem, sat17))
        assertEquals("Semaglutide is not logged for Thursday.", SiriAnswers.weekSentence(row, sat17, londonClock(), enUS))
    }

    @Test
    fun testWeeklyCopyGivesNoDosingAdvice() {
        val s = stack(vd3Through = 19)
        val open = assertNotNull(s.engine.weekRow(s.sem, sat17))
        val openSheet = s.engine.sheetSummary(thu15, asOf = sat17)
        val openLines = mutableListOf(
            Fmt.weekNote(open, sat17), Fmt.daySheetStatus(openSheet, isToday = false),
            SiriAnswers.weekSentence(open, sat17, londonClock(), enUS),
        )
        openLines += openSheet.items.map { Fmt.dayItemStatus(it, isToday = false) }

        s.state.logDose(s.sem.id, at(2026, 10, 16, 8, 12), london)
        val logged = assertNotNull(s.engine.weekRow(s.sem, sat17))
        s.state.logDose(s.sem.id, at(2026, 10, 20, 8, 12), london)
        val early = assertNotNull(s.engine.weekRow(s.sem, tue20))
        val lines = (openLines + listOf(
            Fmt.weekNote(logged, sat17), Fmt.weekNote(early, tue20), Fmt.MISSED_DOSE_NOTE,
            SiriAnswers.weekSentence(logged, sat17, londonClock(), enUS),
            SiriAnswers.weekSentence(early, wed21, londonClock(), enUS),
        )).toMutableList()
        val openLabel = RowSpeech.label(open, sat17, londonClock(), nextLabel = "Next: Thursday", locale = enUS)
        assertEquals("Semaglutide, Thursday's dose not logged.", openLabel)
        assertEquals("Double tap to mark taken.", RowSpeech.hint(open, quiet = true, locked = false))
        val loggedLabel = RowSpeech.label(logged, sat17, londonClock(), nextLabel = "Next: Thursday", locale = enUS)
        assertEquals("Semaglutide, taken Friday at 8:12 AM.", loggedLabel)
        openLines.add(openLabel)
        lines += listOf(openLabel, loggedLabel, RowSpeech.label(early, wed21, londonClock(), nextLabel = null, locale = enUS))

        for (line in lines) {
            for (word in listOf("late", "overdue", "left", "still", "take it", "skip")) {
                assertFalse(line.lowercase().contains(word), "$word in $line")
            }
            assertCopyRules(line)
        }
        for (line in openLines) {
            assertFalse(line.lowercase().contains("missed"), "never missed while the week is open: $line")
        }
        assertEquals(
            "Missed a dose? Follow your medicine's leaflet, or ask your pharmacist or doctor.",
            Fmt.MISSED_DOSE_NOTE,
        )
    }
}
