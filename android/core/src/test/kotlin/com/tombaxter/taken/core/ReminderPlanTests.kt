package com.tombaxter.taken.core

import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.model.Item
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.reminders.Reminders
import com.tombaxter.taken.core.stack.logDose
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/ReminderPlanTests.swift: the evening nudge's plan (14 days, what is pending, today skipped once
 * done or past), its body, its day, and which posted nudges are withdrawn. The iPhone's `components.hour` (the calendar
 * trigger iOS gets) is the fire moment's hour in London here: Android's alarm takes the moment itself.
 */
class ReminderPlanTests {

    private fun makeState(enabled: Boolean): Triple<StackState, Item, Item> {
        val created = at(2026, 10, 1, 8)
        val vd3 = makeItem("Vitamin D3", "VD3", created = created, sortIndex = 0)
        val fish = makeItem("Fish Oil", "FSH", created = created, sortIndex = 1)
        val state = StackState(items = listOf(vd3, fish))
        state.settings.reminderEnabled = enabled
        state.settings.reminderMinutes = 21 * 60
        return Triple(state, vd3, fish)
    }

    @Test
    fun testDisabledPlansNothing() {
        val (state, _, _) = makeState(enabled = false)
        assertTrue(Reminders.plan(state, at(2026, 10, 12, 9), london).isEmpty())
    }

    @Test
    fun testFourteenDaysListingWhatIsPending() {
        val (state, vd3, _) = makeState(enabled = true)
        state.logDose(vd3.id, at(2026, 10, 12, 7, 42), london)
        val plans = Reminders.plan(state, at(2026, 10, 12, 9), london)
        assertEquals(14, plans.size)
        assertEquals("1 pending: FSH", plans[0].body, "today lists only what is still pending")
        assertEquals("2 pending: VD3, FSH", plans[1].body)
        assertEquals(at(2026, 10, 12, 21, 0), plans[0].fireDate)
        assertEquals(21, plans[0].fireDate.atZone(london).hour)
        assertEquals(14, plans.map { it.identifier }.toSet().size)
    }

    @Test
    fun testNoNudgeForAFinishedDay() {
        val (state, vd3, fish) = makeState(enabled = true)
        state.logDose(vd3.id, at(2026, 10, 12, 7, 42), london)
        state.logDose(fish.id, at(2026, 10, 12, 7, 42), london)
        val plans = Reminders.plan(state, at(2026, 10, 12, 9), london)
        assertEquals(13, plans.size, "today is done, so it has no nudge")
        assertEquals(DayKey(2026, 10, 13), plans.firstOrNull()?.day)
    }

    @Test
    fun testPastNudgeTimeIsSkippedToday() {
        val (state, _, _) = makeState(enabled = true)
        val plans = Reminders.plan(state, at(2026, 10, 12, 22), london)
        assertEquals(DayKey(2026, 10, 13), plans.firstOrNull()?.day)
        assertEquals(13, plans.size)
    }

    @Test
    fun testLongListIsTrimmed() {
        assertEquals("6 pending: A, B, C, D +2", Reminders.body(listOf("A", "B", "C", "D", "E", "F")))
    }

    @Test
    fun testNudgeKnowsItsDay() {
        val monday = DayKey(2026, 10, 12)
        val identifier = Reminders.REQUEST_PREFIX + monday.ordinal.toString()
        assertEquals(monday, Reminders.nudgeDay(identifier))
        assertEquals(monday, Reminders.nudgeDay("other", dayExtra = monday.ordinal))
        assertNull(Reminders.nudgeDay("taken.nudge.day.x"))
        assertNull(Reminders.nudgeDay(Reminders.STALE_IDENTIFIER))
    }

    @Test
    fun testLastNightsNudgeNeverLogsToday() {
        val (state, _, _) = makeState(enabled = true)
        val monday = DayKey(2026, 10, 12)
        assertTrue(Reminders.isCurrent(monday, state, at(2026, 10, 12, 21, 5), london))
        assertTrue(
            Reminders.isCurrent(monday, state, at(2026, 10, 13, 1, 30), london),
            "01:30 on Tuesday is still Monday with a 04:00 day start",
        )
        assertFalse(
            Reminders.isCurrent(monday, state, at(2026, 10, 13, 8), london),
            "Monday's nudge tapped on Tuesday morning logs nothing",
        )
        assertTrue(Reminders.isCurrent(null, state, at(2026, 10, 13, 8), london))
        assertEquals("Nothing logged. That nudge was for MON 12 OCT. Tap to open that day.", Reminders.staleBody(monday))
    }

    @Test
    fun testDeliveredNudgesAreWithdrawnOnceTheyNoLongerApply() {
        val (state, vd3, fish) = makeState(enabled = true)
        val monday = DayKey(2026, 10, 12)
        val ids = listOf(-2, -1, 0, 1).map { Reminders.REQUEST_PREFIX + monday.adding(it).ordinal.toString() } +
            listOf("something.else", Reminders.STALE_IDENTIFIER)
        val now = at(2026, 10, 12, 21, 30)
        assertEquals(
            listOf(ids[0], ids[1], Reminders.STALE_IDENTIFIER),
            Reminders.staleDelivered(ids, state, now, london),
            "earlier days go; today's stays while something is pending",
        )
        state.logDose(vd3.id, now, london)
        state.logDose(fish.id, now, london)
        assertEquals(
            listOf(ids[0], ids[1], ids[2], Reminders.STALE_IDENTIFIER),
            Reminders.staleDelivered(ids, state, now, london),
            "today's goes once everything is taken",
        )
    }
}
