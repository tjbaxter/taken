package com.tombaxter.taken.core

import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.StackCodec
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.retention.RetentionCopy
import com.tombaxter.taken.core.retention.TodayPrompt
import com.tombaxter.taken.core.retention.TodayPrompts
import com.tombaxter.taken.core.stack.DaySummary
import com.tombaxter.taken.core.stack.StackEngine
import com.tombaxter.taken.core.stack.eraseAll
import com.tombaxter.taken.core.stack.logDose
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/RetentionTests.swift: Today's one-time rows, the evening nudge offered once, the honest repair and
 * the widget invite, each shown once and never again. London clock, the day starting at 04:00. The iPhone's Lock Screen
 * widget check is Android's home screen widget check (`widgetPlaced`), read by the app (NEXT 4).
 */
class RetentionTests {

    private val monday = DayKey(2026, 10, 19)

    private fun summary(state: StackState, now: Instant): DaySummary = StackEngine(state, londonClock()).todaySummary(now)

    // MARK: The evening nudge, offered once

    @Test
    fun testTheNudgeOfferShowsRightAfterTheStackIsAddedUntilItIsAnswered() {
        val empty = StackState()
        assertNull(
            TodayPrompts.pick(empty.settings, hasStack = false, today = summary(empty, at(2026, 10, 19, 9)), repairDay = null, locked = false),
            "nothing before there is a stack",
        )

        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 19, 9))
        val state = StackState(items = listOf(vd3))
        val today = summary(state, at(2026, 10, 19, 9))
        assertFalse(state.settings.reminderEnabled, "the nudge stays off by default")
        assertEquals(
            TodayPrompt.NudgeOffer(20 * 60),
            TodayPrompts.pick(state.settings, hasStack = true, today = today, repairDay = null, locked = false),
            "07:00 wake: the nudge at 20:00",
        )
        assertEquals("Nudge me at 20:00 if anything's left", RetentionCopy.nudgeOffer(state.settings.reminderMinutes))
        state.settings.reminderMinutes = 21 * 60 + 30
        assertEquals(
            TodayPrompt.NudgeOffer(21 * 60 + 30),
            TodayPrompts.pick(state.settings, hasStack = true, today = today, repairDay = null, locked = false),
            "the person's own nudge time",
        )
        assertNull(TodayPrompts.pick(state.settings, hasStack = true, today = today, repairDay = null, locked = true), "never while locked")

        val answered = state.settings.copy(nudgeOfferDone = true)
        assertNull(TodayPrompts.pick(answered, hasStack = true, today = today, repairDay = null, locked = false), "Turn on or Not now: it never comes back")
        val on = state.settings.copy(reminderEnabled = true)
        assertNull(TodayPrompts.pick(on, hasStack = true, today = today, repairDay = null, locked = false), "not when the nudge is already on")
    }

    /** Android: until Reminders can deliver the nudge (NEXT 3), the offer stays off Today and the next row shows. */
    @Test
    fun testTheNudgeOfferWaitsForABuildThatCanDeliverIt() {
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 12, 9))
        val state = StackState(items = listOf(vd3))
        val today = summary(state, at(2026, 10, 19, 9))
        assertNull(
            TodayPrompts.pick(state.settings, hasStack = true, today = today, repairDay = null, locked = false, nudgeAvailable = false),
            "no offer to turn on a nudge that cannot come",
        )
        val sunday = monday.adding(-1)
        assertEquals(
            TodayPrompt.Repair(sunday),
            TodayPrompts.pick(state.settings, hasStack = true, today = today, repairDay = sunday, locked = false, nudgeAvailable = false),
            "the repair takes its place",
        )
        assertFalse(state.settings.nudgeOfferDone, "nothing is answered for the person, so the offer can come once the nudge can")
    }

    @Test
    fun testOneTimeAnswersAreKeptInTheFileAndThroughErase() {
        val plain = StackCodec.encode(StackState())
        assertFalse(plain.contains("nudgeOfferDone") || plain.contains("widgetInvite"), "a file with none looks as before")
        val legacy = StackCodec.decode("""{"settings":{"wakeMinutes":420}}""").settings
        assertFalse(legacy.nudgeOfferDone)
        assertNull(legacy.widgetInviteDay)
        assertFalse(legacy.widgetInviteDone)

        val state = StackState(items = listOf(makeItem("Zinc", "ZNC", created = at(2026, 10, 1, 8))))
        state.settings.nudgeOfferDone = true
        state.settings.widgetInviteDay = monday.ordinal
        state.settings.widgetInviteDone = true
        state.settings.reminderEnabled = true
        val text = StackCodec.encode(state)
        assertTrue(text.contains("\"nudgeOfferDone\":true"), text)
        assertTrue(text.contains("\"widgetInviteDay\":${monday.ordinal}"), text)
        assertEquals(state.settings, StackCodec.decode(text).settings)

        state.settings.repairClosedDay = monday.ordinal - 1
        assertTrue(StackCodec.encode(state).contains("\"repairClosedDay\":"))
        state.eraseAll()
        assertTrue(state.items.isEmpty())
        assertFalse(state.settings.reminderEnabled, "settings reset")
        assertTrue(state.settings.nudgeOfferDone, "an answered row never comes back, even after Erase all data")
        assertTrue(state.settings.widgetInviteDone)
        assertNull(state.settings.widgetInviteDay, "a date from the log goes with the log")
        assertNull(state.settings.repairClosedDay)

        // An invite shown but never tapped or closed is kept as answered, without its day.
        val shownOnly = StackState()
        shownOnly.settings.widgetInviteDay = monday.ordinal
        shownOnly.eraseAll()
        assertNull(shownOnly.settings.widgetInviteDay)
        assertTrue(shownOnly.settings.widgetInviteDone)
        val never = StackState()
        never.eraseAll()
        assertFalse(never.settings.widgetInviteDone, "never shown: it can still show once")
        assertFalse(never.settings.nudgeOfferDone)
    }

    /** Profile's Nudge switch answers the offer too. The switch itself is the app's (NEXT 3); the rule is here. */
    @Test
    fun testTheNudgeToggleInProfileAnswersTheOffer() {
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 19, 9))
        val state = StackState(items = listOf(vd3))
        state.settings.reminderEnabled = true
        val today = summary(state, at(2026, 10, 19, 9))
        assertNull(TodayPrompts.pick(state.settings, hasStack = true, today = today, repairDay = null, locked = false))
        state.settings.setReminder(false)
        assertFalse(state.settings.reminderEnabled)
        assertTrue(state.settings.nudgeOfferDone)
        assertNull(
            TodayPrompts.pick(state.settings, hasStack = true, today = today, repairDay = null, locked = false),
            "turned off in Profile: the offer stays away",
        )
        state.settings.setReminder(true)
        state.settings.setReminder(false)
        assertTrue(state.settings.nudgeOfferDone, "on, then off")
    }

    // MARK: The widget invite

    @Test
    fun testTheWidgetInviteShowsOnTheFirstAllTakenDayOnly() {
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 12, 9))
        val state = StackState(items = listOf(vd3))
        state.settings.nudgeOfferDone = true
        val pending = summary(state, at(2026, 10, 19, 9))
        assertNull(TodayPrompts.pick(state.settings, hasStack = true, today = pending, repairDay = null, locked = false))

        state.logDose(vd3.id, at(2026, 10, 19, 8), london)
        val done = summary(state, at(2026, 10, 19, 9))
        assertTrue(done.allTaken)
        assertEquals(TodayPrompt.WidgetInvite, TodayPrompts.pick(state.settings, hasStack = true, today = done, repairDay = null, locked = false), "the first All taken")
        val shown = state.settings.copy(widgetInviteDay = monday.ordinal)
        assertEquals(TodayPrompt.WidgetInvite, TodayPrompts.pick(shown, hasStack = true, today = done, repairDay = null, locked = false), "all that day")
        val shownBefore = state.settings.copy(widgetInviteDay = monday.ordinal - 1)
        assertNull(TodayPrompts.pick(shownBefore, hasStack = true, today = done, repairDay = null, locked = false), "and never again")
        val closed = state.settings.copy(widgetInviteDone = true)
        assertNull(TodayPrompts.pick(closed, hasStack = true, today = done, repairDay = null, locked = false), "gone for good once tapped or closed")
        val unanswered = state.settings.copy(nudgeOfferDone = false)
        assertEquals(
            TodayPrompt.NudgeOffer(20 * 60),
            TodayPrompts.pick(unanswered, hasStack = true, today = done, repairDay = null, locked = false),
            "one row at a time, the nudge offer first",
        )
        assertNull(
            TodayPrompts.pick(state.settings, hasStack = true, today = done, repairDay = null, locked = false, widgetPlaced = true),
            "not for someone with the widget already on the home screen",
        )
        assertEquals("Log from your home screen: add the Taken widget", RetentionCopy.WIDGET_INVITE)
    }

    // MARK: The honest repair

    @Test
    fun testTheRepairLineOffersYesterdayAfterAPartOrMissedDay() {
        val created = at(2026, 10, 1, 8)
        val vd3 = makeItem("Vitamin D3", "VD3", created = created, sortIndex = 0)
        val mag = makeItem("Magnesium", "MAG", created = created, sortIndex = 1)
        val sunday = monday.adding(-1)
        val state = StackState(items = listOf(vd3, mag))
        state.settings.nudgeOfferDone = true
        for (day in 1..17) {
            state.logDose(vd3.id, at(2026, 10, day, 8), london)
            state.logDose(mag.id, at(2026, 10, day, 21), london)
        }
        fun repair(s: StackState): DayKey? = TodayPrompts.repairDay(StackEngine(s, londonClock()), monday)
        assertEquals(sunday, repair(state), "yesterday was missed after a week of logging")

        val partial = state.clone()
        partial.logDose(vd3.id, at(2026, 10, 18, 8), london)
        assertEquals(sunday, repair(partial), "yesterday was partial")
        assertEquals(
            TodayPrompt.Repair(sunday),
            TodayPrompts.pick(partial.settings, hasStack = true, today = summary(partial, at(2026, 10, 19, 9)), repairDay = repair(partial), locked = false),
        )
        assertNull(
            TodayPrompts.pick(partial.settings, hasStack = true, today = summary(partial, at(2026, 10, 19, 9)), repairDay = repair(partial), locked = true),
            "never while locked",
        )

        partial.logDose(mag.id, at(2026, 10, 18, 21), london)
        assertNull(repair(partial), "gone once yesterday is complete")
        assertEquals(
            monday,
            TodayPrompts.repairDay(StackEngine(state, londonClock()), monday.adding(1)),
            "once today ends the line is about Monday, never Sunday again",
        )

        val lapsed = StackState(items = listOf(vd3, mag))
        for (day in 1..9) lapsed.logDose(vd3.id, at(2026, 10, day, 8), london)
        assertNull(repair(lapsed), "nothing logged in the 7 days before yesterday: no line")

        val fresh = StackState(items = listOf(makeItem("Zinc", "ZNC", created = at(2026, 10, 19, 9))))
        assertNull(repair(fresh), "the first day has no yesterday to fill in")

        // A weekly shot due yesterday and not logged yet: its week is open, so yesterday is not partial.
        val sem = makeItem("Semaglutide", "SEM", Frequency.Weekdays(setOf(1)), created = created, sortIndex = 2)
        val weekly = StackState(items = listOf(vd3, sem))
        for (day in 1..18) weekly.logDose(vd3.id, at(2026, 10, day, 8), london)
        for (day in listOf(4, 11)) weekly.logDose(sem.id, at(2026, 10, day, 8), london)
        assertNull(repair(weekly), "an open week is not a missed day")
        assertEquals("Forgot to log yesterday? Fill it in", RetentionCopy.repair)
    }

    /** The repair line's close hides it for the day it was about, and only that day. */
    @Test
    fun testTheRepairLineClosesForItsDay() {
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 1, 8))
        val state = StackState(items = listOf(vd3))
        state.settings.nudgeOfferDone = true
        val today = summary(state, at(2026, 10, 19, 9))
        val sunday = monday.adding(-1)
        assertEquals(TodayPrompt.Repair(sunday), TodayPrompts.pick(state.settings, hasStack = true, today = today, repairDay = sunday, locked = false))
        state.settings.repairClosedDay = sunday.ordinal
        assertNull(TodayPrompts.pick(state.settings, hasStack = true, today = today, repairDay = sunday, locked = false), "closed for Sunday")
        assertEquals(
            TodayPrompt.Repair(monday),
            TodayPrompts.pick(state.settings, hasStack = true, today = today, repairDay = monday, locked = false),
            "a later day's line still shows",
        )
        assertFalse(StackCodec.encode(StackState()).contains("repairClosedDay"), "a file with none looks as before")
    }

    /** The weight offer comes after every other row and never while locked (SPEC 3.12; the offer's own rule is NEXT 6). */
    @Test
    fun testTheWeightOfferComesLast() {
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 1, 8))
        val state = StackState(items = listOf(vd3))
        state.settings.nudgeOfferDone = true
        state.settings.widgetInviteDone = true
        val today = summary(state, at(2026, 10, 19, 9))
        assertEquals(TodayPrompt.WeightOffer, TodayPrompts.pick(state.settings, true, today, null, locked = false, weightOffer = true))
        assertNull(TodayPrompts.pick(state.settings, true, today, null, locked = true, weightOffer = true))
        assertEquals(
            TodayPrompt.Repair(monday.adding(-1)),
            TodayPrompts.pick(state.settings, true, today, monday.adding(-1), locked = false, weightOffer = true),
        )
    }

    // MARK: Copy

    @Test
    fun testTheRetentionCopyKeepsTheRules() {
        for (text in RetentionCopy.all) {
            assertCopyRules(text)
            assertFalse(text.lowercase().contains("streak broken"), text)
            assertFalse(text.contains("Lock Screen") || text.contains("iPhone"), "Android wording: $text")
        }
        assertEquals("Turn on", RetentionCopy.TURN_ON)
        assertEquals("Not now", RetentionCopy.NOT_NOW)
    }
}
