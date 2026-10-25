package com.tombaxter.taken.core

import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.weight.GoalDirection
import com.tombaxter.taken.core.weight.GoalReadout
import com.tombaxter.taken.core.weight.HeightUnit
import com.tombaxter.taken.core.weight.WeighIn
import com.tombaxter.taken.core.weight.WeightAxis
import com.tombaxter.taken.core.weight.WeightChangeLine
import com.tombaxter.taken.core.weight.WeightCodec
import com.tombaxter.taken.core.weight.WeightCopy
import com.tombaxter.taken.core.weight.WeightGoal
import com.tombaxter.taken.core.weight.WeightGoalCopy
import com.tombaxter.taken.core.weight.WeightGoals
import com.tombaxter.taken.core.weight.WeightMoment
import com.tombaxter.taken.core.weight.WeightPoint
import com.tombaxter.taken.core.weight.WeightRange
import com.tombaxter.taken.core.weight.WeightState
import com.tombaxter.taken.core.weight.WeightTrend
import com.tombaxter.taken.core.weight.WeightUnit
import com.tombaxter.taken.core.weight.WeightWindow
import java.util.Locale
import kotlin.math.abs
import kotlin.math.pow
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/WeightGoalTests.swift, the pure cases: the start, the direction, the floor, the lit points, the
 * slot's reading, which point a save just lit, the y axis and the goal in it, the change line, the copy, storage and the
 * Goal sheet's start rule. Saving through the model, Clear with Undo and the demo screens are :app's WeightGoalTests.
 * London clock, the day starting at 04:00.
 */
class WeightGoalTests {

    private val enGB = Locale.UK
    private val kg = WeightUnit.KG
    private val lb = WeightUnit.LB

    private fun day(dayOfMonth: Int, month: Int = 10, year: Int = 2026): DayKey = DayKey(year, month, dayOfMonth)

    /** A trend, one value a day from `start`. */
    private fun points(values: List<Double>, start: DayKey = DayKey(2026, 10, 1)): List<WeightPoint> =
        values.mapIndexed { offset, value -> WeightPoint(start.adding(offset), value) }

    private fun everyDay(trend: List<WeightPoint>): Set<DayKey> = trend.map { it.day }.toSet()

    private fun weighIn(kg: Double, dayOfMonth: Int, hour: Int = 7, minute: Int = 0): WeighIn {
        val date = at(2026, 10, dayOfMonth, hour, minute)
        return WeighIn(kg = kg, weighedAt = date, utcOffset = london.rules.getOffset(date).totalSeconds)
    }

    private fun slot(readout: GoalReadout, goal: Double, unit: WeightUnit = kg): String =
        WeightGoalCopy.text(WeightGoalCopy.slot(readout, goal, unit, enGB))

    private fun assertClose(expected: Double, actual: Double?, accuracy: Double = 1e-9, message: String? = null) {
        assertNotNull(actual, message)
        assertTrue(abs(expected - actual) <= accuracy, "${message ?: ""}: expected $expected, got $actual")
    }

    // MARK: 1. The start

    @Test
    fun testTheStartIsTheFirstWeighInUnlessTheTrendHasBeenAtTheGoal() {
        val trend = points(listOf(97.8, 97.0, 96.0, 95.0))
        assertEquals(day(1), WeightGoals.defaultStartDay(87.0, trend), "outside the trend's range")
        assertEquals(day(1), WeightGoals.defaultStartDay(99.0, trend))
        assertEquals(
            day(4), WeightGoals.defaultStartDay(96.5, trend),
            "the trend has been at 96.5 already: the last weigh-in day, so a regain is never a finished goal",
        )
        assertNull(WeightGoals.defaultStartDay(87.0, emptyList()))

        assertEquals(WeightPoint(day(2), 97.0), WeightGoals.start(WeightGoal(87.0, day(2)), trend))
        assertEquals(day(1), WeightGoals.start(WeightGoal(87.0, day(20, month = 9)), trend)?.day, "clamped to the first weigh-in day")
        assertEquals(day(4), WeightGoals.start(WeightGoal(87.0, day(9)), trend)?.day, "clamped to the last weigh-in day")
        assertNull(WeightGoals.start(WeightGoal(87.0, day(1)), emptyList()), "it waits for a weigh-in")

        // Deleting the first weigh-in moves the start to the new first one.
        val state = WeightState(weighIns = listOf(weighIn(97.8, 1), weighIn(97.0, 2), weighIn(96.0, 3)))
        state.goal = WeightGoal(87.0, day(1))
        state.delete(state.weighIns[0].id)
        val after = WeightTrend.trend(state.weighIns, londonClock())
        assertEquals(WeightPoint(day(2), 97.0), WeightGoals.start(state.goal!!, after))
    }

    // MARK: 2. Direction

    @Test
    fun testTheDirectionIsInferredWithAHoldBandOf068Kilograms() {
        assertEquals(GoalDirection.NEAR, WeightGoals.direction(90.0, 90.0))
        assertEquals(GoalDirection.NEAR, WeightGoals.direction(90.0, 89.32), "0.68 below is still near")
        assertEquals(GoalDirection.LOWER, WeightGoals.direction(90.0, 89.31))
        assertEquals(GoalDirection.NEAR, WeightGoals.direction(90.0, 90.68), "0.68 above is still near")
        assertEquals(GoalDirection.HIGHER, WeightGoals.direction(90.0, 90.69))
    }

    // MARK: 3. The floor

    @Test
    fun testTheFloorIsBMI185AndNeverBlocksAGainGoal() {
        assertClose(18.5 * 1.8 * 1.8, WeightGoals.floorKg(180.0))
        assertClose(59.94, WeightGoals.floorKg(180.0))
        assertClose(182.88, HeightUnit.centimetres(6, 0))
        assertClose(170.18, HeightUnit.centimetres(5, 7))
        assertEquals(5, HeightUnit.feetInches(180.0).first)
        assertEquals(11, HeightUnit.feetInches(180.0).second)
        assertEquals(6, HeightUnit.feetInches(182.88).first)
        assertEquals(0, HeightUnit.feetInches(182.88).second)
        assertEquals(HeightUnit.FEET_INCHES, HeightUnit.preferred(Locale.US))
        assertEquals(HeightUnit.FEET_INCHES, HeightUnit.preferred(enGB))
        assertEquals(HeightUnit.CENTIMETRES, HeightUnit.preferred(Locale.GERMANY))
        assertEquals(HeightUnit.CENTIMETRES, HeightUnit.preferred(Locale.FRANCE), "metres show as centimetres")

        assertTrue(WeightGoals.floorBlocks(55.0, 97.8, 180.0), "a lower goal below BMI 18.5")
        assertFalse(WeightGoals.floorBlocks(59.94, 97.8, 180.0), "the floor itself is allowed")
        assertFalse(WeightGoals.floorBlocks(60.0, 97.8, 180.0))
        assertTrue(WeightGoals.floorBlocks(59.5, 59.8, 180.0), "a near goal below the floor")
        assertFalse(WeightGoals.floorBlocks(58.0, 50.0, 180.0), "gaining towards a healthier weight")
        assertTrue(WeightGoals.floorBlocks(55.0, 97.8, HeightUnit.centimetres(5, 11)))
    }

    // MARK: 4. Points

    @Test
    fun testPointsLandOnTheFirstWeighInDayAtOrPastEachThresholdAndStay() {
        // Start 100: 5% is 95.0, 10% is 90.0. Day 4 (index 3) crosses 95 but is a day the trend filled in.
        val trend = points(listOf(100.0, 96.0, 95.5, 94.9, 94.0, 92.0, 89.9, 91.0, 92.0))
        val days = everyDay(trend) - day(4)
        val goal = WeightGoal(80.0, day(1))
        val moments = WeightGoals.moments(goal, trend, days, 180.0)
        assertEquals(listOf("pct5", "pct10"), moments.map { it.id })
        assertEquals(day(5), moments[0].day, "a crossing inside a gap lands on the next weigh-in day")
        assertEquals(94.0, moments[0].trendKg)
        assertEquals(day(7), moments[1].day)
        assertEquals(89.9, moments[1].trendKg, "and it stays after the trend rises again")

        // Only between the start and the goal, and more than 0.05 kg from the goal.
        val fall = points(listOf(100.0, 96.0, 94.9, 93.0, 91.0))
        fun ids(goalKg: Double): List<String> =
            WeightGoals.moments(WeightGoal(goalKg, day(1)), fall, everyDay(fall), 180.0).map { it.id }
        assertEquals(listOf("pct5", "goal"), ids(94.9), "95.0 lies 0.1 above the goal: marked")
        assertEquals(listOf("goal"), ids(94.98), "95.0 lies within 0.05 of the goal: nothing past your own goal")
        assertEquals(listOf("pct5", "goal"), ids(92.0), "10% lies past the goal: never marked")

        // The start must be at BMI 25 or more for 5% and 10%: 100 kg at 2 m is 25.0, 99.6 kg is 24.9.
        val at25 = points(listOf(100.0, 94.0, 89.0, 80.0))
        assertEquals(listOf("pct5", "pct10", "goal"), WeightGoals.moments(WeightGoal(80.0, day(1)), at25, everyDay(at25), 200.0).map { it.id })
        val at249 = points(listOf(99.6, 94.0, 89.0, 80.0))
        assertEquals(listOf("goal"), WeightGoals.moments(WeightGoal(80.0, day(1)), at249, everyDay(at249), 200.0).map { it.id })
        assertEquals(
            listOf("goal"), WeightGoals.moments(WeightGoal(80.0, day(1)), at25, everyDay(at25), null).map { it.id },
            "no height, no percent points",
        )

        // A near goal gets none; a higher goal only its own.
        val flat = points(listOf(90.0, 89.8, 89.6))
        assertTrue(WeightGoals.moments(WeightGoal(89.5, day(1)), flat, everyDay(flat), 180.0).isEmpty())
        val rise = points(listOf(60.0, 62.0, 64.96, 63.0))
        assertEquals(
            listOf("goal"), WeightGoals.moments(WeightGoal(65.0, day(1)), rise, everyDay(rise), 180.0).map { it.id },
            "within 0.05 of a higher goal",
        )

        // The 0.05 kg reach tolerance.
        val near80 = points(listOf(100.0, 90.0, 80.04))
        assertEquals(listOf("goal"), WeightGoals.moments(WeightGoal(80.0, day(1)), near80, everyDay(near80), null).map { it.id })
        val short = points(listOf(100.0, 90.0, 80.06))
        assertTrue(WeightGoals.moments(WeightGoal(80.0, day(1)), short, everyDay(short), null).isEmpty())
    }

    // MARK: 5. The slot

    @Test
    fun testTheSlotSaysHowCloseTheTrendIsInTheUnitShown() {
        val goal = WeightGoal(90.0, day(1))
        fun readout(values: List<Double>, unit: WeightUnit = kg, goal: WeightGoal = goal): GoalReadout {
            val trend = points(values)
            val moments = WeightGoals.moments(goal, trend, everyDay(trend), 180.0)
            return WeightGoals.readout(goal, trend, moments, unit)
        }
        assertEquals(GoalReadout.GoalOnly, readout(listOf(100.0, 99.95)), "less than 0.1 covered")
        assertEquals("Goal 90.0", slot(readout(listOf(100.0, 99.95)), 90.0))
        assertEquals(GoalReadout.GoalOnly, readout(listOf(100.0, 100.5)), "on the far side of the start: no number, no words")
        assertEquals("3.0 kg closer to 90.0", slot(readout(listOf(100.0, 97.0)), 90.0))
        assertEquals("3.0 kg closer to 90.0", slot(readout(listOf(100.0, 96.96)), 90.0), "closer rounds down")
        assertEquals("4.9 kg closer to 90.0", slot(readout(listOf(100.0, 95.01)), 90.0))
        assertEquals(GoalReadout.ToGo(5.0), readout(listOf(100.0, 95.0)), "exactly half covered: to go")
        assertEquals("5.0 kg to 90.0", slot(readout(listOf(100.0, 95.0)), 90.0))
        assertEquals("1.1 kg to 90.0", slot(readout(listOf(100.0, 91.04)), 90.0), "to go rounds up")

        assertEquals(GoalReadout.Holding, readout(listOf(100.0, 95.0, 90.0)), "reached")
        assertEquals("Holding near 90.0", slot(readout(listOf(100.0, 95.0, 90.0, 90.6)), 90.0), "within 0.68 kg")
        assertEquals("0.9 kg from 90.0", slot(readout(listOf(100.0, 95.0, 90.0, 90.9)), 90.0), "beyond it: a number only")
        val near = WeightGoal(89.5, day(1))
        assertEquals("Holding near 89.5", slot(readout(listOf(90.0, 90.0), goal = near), 89.5), "a near goal holds from day one")
        assertEquals("1.5 kg from 89.5", slot(readout(listOf(90.0, 91.0), goal = near), 89.5))

        // In pounds: 0.05 kg covered is 0.11 lb, past 0.1; 3 kg is 6.6 lb; the goal reads 198.4.
        assertEquals("0.1 lb closer to 198.4", slot(readout(listOf(100.0, 99.95), lb), 90.0, lb))
        assertEquals("6.6 lb closer to 198.4", slot(readout(listOf(100.0, 97.0), lb), 90.0, lb))
        assertEquals("1.1 kilograms to your goal, 87.0", WeightGoalCopy.spokenSlot(GoalReadout.ToGo(1.04), 87.0, kg, enGB))
        assertEquals("Goal, 87.0 kilograms", WeightGoalCopy.spokenSlot(GoalReadout.GoalOnly, 87.0, kg, enGB))
    }

    // MARK: 6. Fresh points

    @Test
    fun testOnlyASaveThatLightsAPointOnItsOwnDayAcknowledgesIt() {
        val goal = WeightGoal(80.0, day(1))
        fun moments(values: List<Double>): List<WeightMoment> {
            val trend = points(values)
            return WeightGoals.moments(goal, trend, everyDay(trend), 180.0)
        }
        val before = moments(listOf(100.0, 96.0))
        val after = moments(listOf(100.0, 96.0, 94.9))
        assertEquals("pct5", WeightGoals.fresh(before, after, day(3))?.id)
        assertNull(WeightGoals.fresh(after, after, day(3)), "a second weigh-in the same day")
        assertEquals("pct10", WeightGoals.fresh(before, moments(listOf(100.0, 96.0, 89.0)), day(3))?.id, "two at once: the higher rank")
        val withGoal = WeightGoal(89.0, day(1))
        val reachedTrend = points(listOf(100.0, 96.0, 89.0))
        val reached = WeightGoals.moments(withGoal, reachedTrend, everyDay(reachedTrend), 180.0)
        assertEquals(listOf("pct5", "pct10", "goal"), reached.map { it.id })
        assertEquals("goal", WeightGoals.fresh(emptyList(), reached, day(3))?.id, "the goal outranks 10%")
        assertNull(WeightGoals.fresh(before, moments(listOf(100.0, 94.9, 95.0)), day(3)), "a point dated before the saved day: silent")
        assertEquals(
            WeightGoals.fresh(before, after, day(3)), WeightGoals.fresh(before, after, day(3)),
            "Undo, then the same number again",
        )
    }

    // MARK: 7. The y domain

    @Test
    fun testTheGoalJoinsTheAxisOnlyIfTheDataKeepsHalfThePlot() {
        val weighIns = listOf(weighIn(92.0, 20), weighIn(91.0, 21), weighIn(90.0, 22))
        val trend = WeightTrend.trend(weighIns, londonClock())
        fun window(goal: Double?): WeightWindow =
            WeightWindow.make(weighIns, trend, emptyList(), WeightRange.WEEK, day(22), londonClock(), goal)
        val none = window(null)
        assertClose(89.6, none.lower)
        assertClose(92.4, none.upper)
        assertFalse(none.goalInDomain)
        val near = window(88.0)
        assertTrue(near.goalInDomain, "5.2 kg with it against 2.8 without: in")
        assertClose(87.4, near.lower)
        assertClose(92.6, near.upper)
        val far = window(87.0)
        assertFalse(far.goalInDomain, "6.5 kg against 2.8: pinned to the edge, the line keeps its height")
        assertClose(89.6, far.lower)
        assertTrue(window(94.0).goalInDomain)
        assertFalse(window(95.0).goalInDomain)
        assertTrue(window(91.0).goalInDomain, "inside the data")
    }

    // MARK: 8. The axis

    @Test
    fun testTicksAreFourOrFewerAndGiveWayToTheGoal() {
        assertEquals(listOf(90.0, 91.0, 92.0), WeightAxis.ticks(89.6, 92.4))
        assertEquals(0, WeightAxis.decimals(listOf(90.0, 91.0, 92.0)))
        assertEquals(listOf(88.0, 88.5, 89.0), WeightAxis.ticks(88.0, 89.2))
        assertEquals(1, WeightAxis.decimals(listOf(88.0, 88.5, 89.0)), "one decimal only for half steps")
        assertEquals(listOf(88.0, 90.0, 92.0), WeightAxis.ticks(86.25, 92.75))
        assertEquals(listOf(60.0, 80.0, 100.0), WeightAxis.ticks(60.0, 100.0))
        for ((lower, upper) in listOf(85.0 to 98.0, 190.0 to 216.0, 55.5 to 56.1, 40.0 to 300.0)) {
            assertTrue(WeightAxis.ticks(lower, upper).size <= 4, "$lower to $upper")
        }
        // 196 over 6.5 kg is about 30 a kilogram: 88 sits 9 from a goal at 87.7 and gives way; 12 is clear.
        assertEquals(listOf(90.0, 92.0), WeightAxis.clear(listOf(88.0, 90.0, 92.0), 87.7, 86.25, 92.75, 196.0))
        assertEquals(listOf(88.0, 90.0, 92.0), WeightAxis.clear(listOf(88.0, 90.0, 92.0), 87.6, 86.25, 92.75, 196.0))
        // A goal pinned 8 inside the top: the top tick under it gives way.
        val inset = 8.0 / 196.0 * (92.05 - 90.0)
        assertEquals(listOf(90.0, 91.0), WeightAxis.clear(WeightAxis.ticks(90.0, 92.05), 92.05 - inset, 90.0, 92.05, 196.0))
    }

    // MARK: 9. The change line

    @Test
    fun testTheChangeLineFollowsTheRange() {
        val clock = londonClock()
        val weighIns = listOf(weighIn(90.0, 1)) + (2..8).map { weighIn(89.0, it) }
        val trend = WeightTrend.trend(weighIns, clock)
        fun line(range: WeightRange, today: Int = 8): WeightChangeLine.Change? {
            val window = WeightWindow.make(weighIns, trend, emptyList(), range, day(today), clock)
            return WeightChangeLine.make(range, trend, window)
        }
        assertEquals(WeightChangeLine.Span.Days(7), line(WeightRange.WEEK)?.span)
        assertClose(0.9.pow(7) - 1, line(WeightRange.WEEK)?.kg)
        assertEquals(WeightChangeLine.Span.Since(day(1)), line(WeightRange.MONTH)?.span, "a trend shorter than the range: since its first day")
        assertClose(trend.last().kg - 90, line(WeightRange.MONTH)?.kg)
        assertEquals(WeightChangeLine.Span.Since(day(1)), line(WeightRange.ALL)?.span, "always since on All")
        assertNull(line(WeightRange.WEEK, today = 20), "fewer than two trend days in view: hidden")

        val today = day(22)
        fun text(kg: Double, span: WeightChangeLine.Span): String =
            WeightGoalCopy.text(WeightGoalCopy.changeLine(kg, span, this.kg, today, enGB))
        assertEquals("−1.2 kg over 30 days", text(-1.21, WeightChangeLine.Span.Days(30)))
        assertEquals("+0.5 kg since 4 Mar", text(0.5, WeightChangeLine.Span.Since(day(4, month = 3))))
        assertEquals("−9.7 kg since 4 Mar 2025", text(-9.72, WeightChangeLine.Span.Since(day(4, month = 3, year = 2025))))
        assertEquals("−0.4 kg over the year", text(-0.4, WeightChangeLine.Span.Year))
        assertEquals("No change over 30 days", text(0.04, WeightChangeLine.Span.Days(30)))
        assertEquals("No change since 4 Mar", text(-0.04, WeightChangeLine.Span.Since(day(4, month = 3))))
        assertEquals(
            "−2.2 lb over 7 days",
            WeightGoalCopy.text(WeightGoalCopy.changeLine(-1.0, WeightChangeLine.Span.Days(7), lb, today, enGB)),
        )
        assertEquals("Down 1.2 kilograms over 30 days", WeightGoalCopy.spokenChange(-1.21, WeightChangeLine.Span.Days(30), kg, today, enGB))
        assertEquals(
            "Up 0.5 kilograms since 4 March",
            WeightGoalCopy.spokenChange(0.5, WeightChangeLine.Span.Since(day(4, month = 3)), kg, today, enGB),
        )
        assertEquals("No change over 30 days", WeightGoalCopy.spokenChange(0.01, WeightChangeLine.Span.Days(30), kg, today, enGB))
    }

    // MARK: 10. Copy

    /** Android wording: the menu items in sentence case (SPEC-ANDROID 6.4), every other line as on the iPhone. */
    @Test
    fun testTheGoalCopyIsPlainAndNeverJudges() {
        val banned = Regex("""\b(lose|lost|loss|ideal|great|should|missed|behind)\b|off track""", RegexOption.IGNORE_CASE)
        for (text in WeightGoalCopy.all) {
            assertFalse(text.isEmpty())
            assertCopyRules(text)
            assertNull(banned.find(text), text)
        }
        assertTrue(WeightGoalCopy.all.any { it.contains("closer") }, "whole words: closer holds lose and is fine")
        for (text in WeightCopy.all) {
            assertFalse(text.lowercase().contains("goal"), "the core copy still never says goal: $text")
        }
        assertEquals("Set goal…", WeightGoalCopy.SET_GOAL)
        assertEquals("Change goal…", WeightGoalCopy.CHANGE_GOAL)
        assertEquals("Set 183 cm", WeightGoalCopy.setHeight(183.0, HeightUnit.CENTIMETRES))
        assertEquals("Set 6 ft 0 in", WeightGoalCopy.setHeight(182.88, HeightUnit.FEET_INCHES))
        val ten = WeightMoment(WeightMoment.Kind.Percent(10), day(3, month = 8), 92.9)
        val goal = WeightMoment(WeightMoment.Kind.Goal, day(22), 87.0)
        assertEquals("Trend is now 10% below where you started.", WeightGoalCopy.text(WeightGoalCopy.moment(ten, 87.0, kg, enGB)))
        assertEquals("Trend reached 87.0.", WeightGoalCopy.text(WeightGoalCopy.moment(goal, 87.0, kg, enGB)))
        assertEquals("Trend reached your goal, 87.0 kilograms.", WeightGoalCopy.spokenMoment(goal, 87.0, kg, enGB))
        assertEquals("−10%", WeightGoalCopy.chartLabel(ten))
        assertNull(WeightGoalCopy.chartLabel(goal), "the goal point is never labelled")
        assertEquals("3 August, trend 92.9 kilograms", WeightGoalCopy.pointValue(ten, kg, enGB))
        assertEquals(
            "Marked: 5 percent below where you started, 3 August.",
            WeightGoalCopy.marked(listOf(WeightMoment(WeightMoment.Kind.Percent(5), day(3, month = 8), 92.9))),
        )
        assertEquals("Goal set, 87.0 kilograms.", WeightGoalCopy.goalSet(87.0, kg, enGB))
    }

    // MARK: 11. Storage

    /** The codec side; the file on disk is :app's WeightStoreTests. */
    @Test
    fun testTheGoalAndHeightAreStoredReadLossilyAndErased() {
        val state = WeightState(weighIns = listOf(weighIn(97.8, 1)), showsTab = true, unit = lb)
        state.goal = WeightGoal(87.0, day(1), startPicked = true)
        state.heightCm = 180.0
        val read = WeightCodec.decode(WeightCodec.encode(state))
        assertEquals(WeightGoal(87.0, day(1), startPicked = true), read.goal)
        assertEquals(180.0, read.heightCm)

        val lossy = WeightCodec.decode("""{"weighIns":[],"showsTab":true,"goal":{"startDay":{"ordinal":20000}},"heightCm":"tall"}""")
        assertNull(lossy.goal, "a goal that cannot be read is none")
        assertNull(lossy.heightCm)
        assertEquals(true, lossy.showsTab, "and the rest of the file still reads")
        assertNull(WeightCodec.decode("""{"weighIns":[],"unit":"kg"}""").goal)
        assertEquals(
            WeightGoal(87.0, DayKey(20000), startPicked = false),
            WeightCodec.decode("""{"goal":{"kg":87,"startDay":{"ordinal":20000}}}""").goal,
        )

        state.eraseAll()
        assertNull(state.goal)
        assertNull(state.heightCm)
        assertEquals(true, state.showsTab)
        assertEquals(lb, state.unit)
    }

    // MARK: 13. The Goal sheet's start

    @Test
    fun testTheSheetKeepsTheStartUnlessTheValueChanges() {
        val trend = points(listOf(97.8, 97.0, 96.0, 95.0))
        assertEquals(day(1), WeightGoals.sheetStartDay(null, null, null, trend))
        assertEquals(day(1), WeightGoals.sheetStartDay(null, 87.0, null, trend))
        assertEquals(day(4), WeightGoals.sheetStartDay(null, 96.5, null, trend), "Set goal follows what is typed")
        assertEquals(day(2), WeightGoals.sheetStartDay(null, 87.0, day(2), trend), "until the Start row is touched")
        val stored = WeightGoal(87.0, day(3))
        assertEquals(day(3), WeightGoals.sheetStartDay(stored, 87.0, null, trend), "Change goal with the same value keeps the start")
        assertEquals(day(1), WeightGoals.sheetStartDay(stored, 86.0, null, trend), "a new value recomputes it")
        val picked = WeightGoal(87.0, day(3), startPicked = true)
        assertEquals(day(3), WeightGoals.sheetStartDay(picked, 86.0, null, trend), "unless it was picked by hand")
        assertNull(WeightGoals.sheetStartDay(stored, 87.0, null, emptyList()))
    }
}
