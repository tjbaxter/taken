package com.tombaxter.taken.core

import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.weight.GoalReadout
import com.tombaxter.taken.core.weight.WeighIn
import com.tombaxter.taken.core.weight.WeightCopy
import com.tombaxter.taken.core.weight.WeightEntry
import com.tombaxter.taken.core.weight.WeightFigure
import com.tombaxter.taken.core.weight.WeightFold
import com.tombaxter.taken.core.weight.WeightGoalCopy
import com.tombaxter.taken.core.weight.WeightLine
import com.tombaxter.taken.core.weight.WeightMoment
import com.tombaxter.taken.core.weight.WeightUnit
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/WeightEntryTests.swift: what the big number shows, when the range hint shows, which small line
 * wins, where a scroll comes to rest, the digits box's sizing, and the visit line's copy. London clock, the day starting
 * at 04:00.
 */
class WeightEntryTests {

    private val enGB = Locale.UK
    private val deDE = Locale.GERMANY

    private fun weighIn(kg: Double, dayOfMonth: Int, hour: Int = 7, minute: Int = 0): WeighIn {
        val date = at(2026, 10, dayOfMonth, hour, minute)
        return WeighIn(kg = kg, weighedAt = date, utcOffset = london.rules.getOffset(date).totalSeconds)
    }

    // MARK: 1. The big number

    @Test
    fun testTheNumberAlwaysShowsAWeighIn() {
        val clock = londonClock()
        val today = DayKey(2026, 10, 22)
        fun figure(last: WeighIn?, draft: String = "", focused: Boolean = false): WeightFigure =
            WeightEntry.figure(last, today, clock, draft, focused)
        assertEquals(WeightFigure.Empty, figure(null), "never weighed in")
        assertEquals(WeightFigure.Ghost(88.35), figure(weighIn(88.35, 21)), "last weigh-in yesterday: grey")
        assertEquals(WeightFigure.Today(89.3), figure(weighIn(89.3, 22, 7, 6)), "today's: in ink")
        assertEquals(WeightFigure.Ghost(89.3), figure(weighIn(89.3, 22), focused = true), "typing nothing yet: today's included, grey")
        assertEquals(WeightFigure.Ghost(88.35), figure(weighIn(88.35, 21), focused = true))
        assertEquals(WeightFigure.Empty, figure(null, focused = true))
        assertEquals(WeightFigure.Typing("88.1"), figure(weighIn(88.35, 21), draft = "88.1", focused = true))
        assertEquals(
            WeightFigure.Ghost(88.35), figure(weighIn(88.35, 21), draft = "88.1", focused = false),
            "a draft never shows once the keyboard is down",
        )
        assertEquals(WeightFigure.Ghost(88.35), figure(weighIn(88.35, 22, 2, 30)), "02:30 counts for the day before, as a dose does")
        assertEquals("typing", WeightFigure.Typing("8").kind)
    }

    // MARK: 2. The range hint

    @Test
    fun testTheRangeHintWaitsUntilTheNumberLooksFinished() {
        for (draft in listOf("8", "19", "88.1", "", "350", "20")) {
            assertFalse(WeightEntry.showsRangeHint(draft, WeightUnit.KG, enGB), "kg $draft")
        }
        for (draft in listOf("19.5", "883", "1000", "350.5", "883.")) {
            assertTrue(WeightEntry.showsRangeHint(draft, WeightUnit.KG, enGB), "kg $draft")
        }
        assertFalse(WeightEntry.showsRangeHint("19.", WeightUnit.KG, enGB), "a separator with no digit after it")
        for (draft in listOf("40", "195.5")) {
            assertFalse(WeightEntry.showsRangeHint(draft, WeightUnit.LB, enGB), "lb $draft")
        }
        for (draft in listOf("40.5", "800")) {
            assertTrue(WeightEntry.showsRangeHint(draft, WeightUnit.LB, enGB), "lb $draft")
        }
        assertTrue(WeightEntry.showsRangeHint("19,5", WeightUnit.KG, deDE))
        assertEquals("Between 20 and 350 kg", WeightCopy.rangeHint(WeightUnit.KG))
        assertEquals("Between 44 and 770 lb", WeightCopy.rangeHint(WeightUnit.LB))
        assertEquals("Between 20 and 350 kilograms", WeightCopy.spokenRangeHint(WeightUnit.KG))
    }

    // MARK: 3. The small line

    @Test
    fun testTheSmallLinesPriority() {
        val moment = WeightMoment(WeightMoment.Kind.Percent(10), DayKey(2026, 10, 22), 88.0)
        fun line(
            focused: Boolean = false,
            draft: String = "",
            goal: Boolean = true,
            saved: Boolean = true,
            reached: WeightMoment? = null,
            readout: GoalReadout? = GoalReadout.ToGo(1.1),
        ): WeightLine = WeightEntry.line(focused, draft, WeightUnit.KG, enGB, goal, saved, reached, readout)
        assertEquals(WeightLine.Range, line(focused = true, draft = "883", reached = moment), "while typing the hint beats everything")
        assertEquals(WeightLine.Last, line(focused = true, draft = "88.1", reached = moment), "otherwise typing shows the last weigh-in")
        assertEquals(WeightLine.Moment(moment), line(reached = moment), "the moment beats the closing-in line")
        assertEquals(WeightLine.Closing(GoalReadout.ToGo(1.1)), line())
        assertEquals(WeightLine.Last, line(saved = false), "closing needs a save on this visit")
        assertEquals(WeightLine.Last, line(goal = false), "and a goal")
        assertEquals(WeightLine.Last, line(readout = GoalReadout.GoalOnly), "and a reading other than Goal 87.0")
        assertEquals(WeightLine.Last, line(readout = null))
        assertEquals(WeightLine.Closing(GoalReadout.Holding), line(readout = GoalReadout.Holding))
        assertEquals("closing", WeightLine.Closing(GoalReadout.Holding).kind)
    }

    // MARK: 4. The fold

    @Test
    fun testTheFoldSnapsOnlyBetweenTheNumberAndTheTrend() {
        assertEquals(0.0, WeightFold.snap(0.0, 700.0))
        assertEquals(-20.0, WeightFold.snap(-20.0, 700.0), "a bounce at the top is left alone")
        assertEquals(700.0, WeightFold.snap(700.0, 700.0))
        assertEquals(900.0, WeightFold.snap(900.0, 700.0), "below the fold, scrolling is free")
        assertEquals(0.0, WeightFold.snap(200.0, 700.0), "nearer the number")
        assertEquals(0.0, WeightFold.snap(349.0, 700.0))
        assertEquals(700.0, WeightFold.snap(350.0, 700.0), "half way goes on to the trend")
        assertEquals(700.0, WeightFold.snap(600.0, 700.0))
        assertEquals(300.0, WeightFold.snap(300.0, 0.0), "no fold measured yet")
    }

    // MARK: 5. Sizing

    @Test
    fun testTheBoxKeepsTheLongerOfTheGreyValueAndTheDraft() {
        assertEquals("88.35", WeightEntry.sizing("88.35", ""))
        assertEquals("88.35", WeightEntry.sizing("88.35", "88.1"), "nothing re-centres while typing")
        assertEquals("100.55", WeightEntry.sizing("88.35", "100.55"))
        assertEquals("88", WeightEntry.sizing("", "88"))
    }

    // MARK: 6. The visit line

    @Test
    fun testTheVisitLinePutsTrendInFront() {
        fun visit(readout: GoalReadout, unit: WeightUnit = WeightUnit.KG, goal: Double = 87.0): String? =
            WeightGoalCopy.visit(readout, goal, unit, enGB)?.let(WeightGoalCopy::text)
        assertEquals("Trend 4.2 kg closer to 87.0", visit(GoalReadout.Closer(4.2)))
        assertEquals("Trend 1.1 kg to 87.0", visit(GoalReadout.ToGo(1.1)))
        assertEquals("Trend holding near 87.0", visit(GoalReadout.Holding))
        assertEquals("Trend 0.9 kg from 87.0", visit(GoalReadout.From(0.9)))
        assertNull(visit(GoalReadout.GoalOnly))
        // 191.8 lb is 87.0 kg; 2.4 lb to go.
        assertEquals("Trend 2.4 lb to 191.8", visit(GoalReadout.ToGo(2.35 * 0.45359237), WeightUnit.LB, 191.8 * 0.45359237))
        assertEquals("Trend 4.2 kilograms closer to your goal, 87.0", WeightGoalCopy.spokenVisit(GoalReadout.Closer(4.2), 87.0, WeightUnit.KG, enGB))
        assertEquals("Trend 1.1 kilograms to your goal, 87.0", WeightGoalCopy.spokenVisit(GoalReadout.ToGo(1.1), 87.0, WeightUnit.KG, enGB))
        assertEquals("Trend holding near your goal, 87.0", WeightGoalCopy.spokenVisit(GoalReadout.Holding, 87.0, WeightUnit.KG, enGB))
        assertEquals("Trend 0.9 kilograms from your goal, 87.0", WeightGoalCopy.spokenVisit(GoalReadout.From(0.9), 87.0, WeightUnit.KG, enGB))
        assertNull(WeightGoalCopy.spokenVisit(GoalReadout.GoalOnly, 87.0, WeightUnit.KG, enGB))
        for (text in WeightCopy.all) {
            assertFalse(text.lowercase().contains("goal"), "every goal string lives in WeightGoalCopy: $text")
        }
        assertTrue(WeightCopy.all.contains("Weigh in"))
        assertTrue(WeightCopy.all.contains("Your trend starts here."))
        assertTrue(WeightCopy.all.contains("Show trend"))
        assertTrue(WeightGoalCopy.all.contains("Trend 1.1 kg to 87.0"))
    }
}
