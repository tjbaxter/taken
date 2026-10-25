package com.tombaxter.taken

import com.tombaxter.taken.core.weight.GoalReadout
import com.tombaxter.taken.core.weight.WeightGoalCopy
import com.tombaxter.taken.core.weight.WeightGoals
import com.tombaxter.taken.core.weight.WeightRange
import com.tombaxter.taken.core.weight.WeightUnit
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.util.Locale
import kotlin.math.abs
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/WeightGoalTests.swift, the cases that run through the app model: a save that crosses lights its
 * point once and Undo takes it back, Clear goal with Undo, and the demo screens' one, two and three points. The pure rules
 * are :core's WeightGoalTests.
 */
@RunWith(RobolectricTestRunner::class)
class WeightGoalTests {

    /**
     * Through the app model: the demo stack 0.06 above the 10% line; saving 87.1 lights 10%, Undo takes it away, and
     * saving it again lights it again.
     */
    @Test
    fun testSavingAWeighInThatCrossesLightsItOnceAndUndoTakesItBack() {
        val model = DemoScreens.make("weight-goal")
        assertNull(model.weight.justReached)
        model.saveWeighIn(87.1)
        assertEquals("pct10", model.weight.justReached?.id)
        val toast = assertNotNull(model.toast)
        assertEquals("Weighed in", toast.message)
        assertTrue(toast.spoken!!.endsWith("Trend is now 10 percent below where you started."), toast.spoken)
        model.undo(toast)
        assertNull(model.weight.justReached, "Undo removes the point and its sentence")
        assertEquals(listOf("pct5"), model.weightPicture(WeightRange.ALL).moments.map { it.id })
        model.saveWeighIn(87.1)
        assertEquals("pct10", model.weight.justReached?.id, "a typo cannot use up a moment")
        model.saveWeighIn(87.0)
        assertNull(model.weight.justReached, "the next weigh-in brings the closing-in line back")
    }

    @Test
    fun testClearGoalActsAtOnceAndUndoBringsTheSameGoalBack() {
        val model = DemoScreens.make("weight-goal")
        val goal = assertNotNull(model.weight.goal)
        assertEquals(87.0, goal.kg)
        model.clearWeightGoal()
        assertNull(model.weight.goal)
        assertFalse(model.weight.isEmpty, "clearing a goal deletes no weigh-in")
        val toast = assertNotNull(model.toast)
        assertEquals("Goal cleared", toast.message)
        assertEquals(UndoStep.RestoreWeightGoal(goal), toast.undo)
        model.undo(toast)
        assertEquals(goal, model.weight.goal, "the same goal, start included")
        model.openWeightGoal()
        assertEquals(Sheet.WeightGoal, model.sheet)

        model.hideWeightTab()
        assertEquals(goal, model.weight.goal, "hiding the tab keeps the goal")
        model.eraseAll()
        assertNull(model.weight.goal)
        assertNull(model.weight.state.heightCm)
        assertTrue(AppModel.ERASE_MESSAGE.contains("your weight goal"), "the Erase dialog says so")
    }

    /** Save in the Goal sheet: the goal with its start and the height, and TalkBack hears it set. */
    @Test
    fun testSavingTheGoalKeepsItsStartAndHeight() {
        val model = DemoScreens.make("weight")
        val first = model.weightPicture(WeightRange.ALL).trend.first().day
        model.saveWeightGoal(85.0, first, startPicked = false, heightCm = 175.0, locale = Locale.UK)
        assertEquals(85.0, model.weight.goal?.kg)
        assertEquals(first, model.weight.goal?.startDay)
        assertEquals(175.0, model.weight.state.heightCm)
        assertNull(model.toast, "no toast for a goal set")
    }

    @Test
    fun testTheDemoScreensShowOneTwoAndThreePoints() {
        val goal = DemoScreens.make("weight-goal")
        val picture = goal.weightPicture(WeightRange.ALL)
        assertEquals(AppTab.WEIGHT, goal.tab)
        assertEquals(listOf("pct5"), picture.moments.map { it.id }, "exactly one point")
        assertEquals(97.8, picture.trend.first().kg, "the first weigh-in is exactly 97.8 kg")
        val last = picture.trend.last().kg
        assertTrue(last in 88.05..88.3, "$last")
        val left = assertIs<GoalReadout.ToGo>(picture.readout).kg
        assertTrue(WeightGoalCopy.roundedUp(left) in 1.1..1.3, "$left")
        assertEquals("1.1 kg to 87.0", WeightGoalCopy.text(WeightGoalCopy.slot(picture.readout!!, 87.0, WeightUnit.KG, Locale.UK)))
        assertEquals(180.0, goal.weight.state.heightCm)

        val moment = DemoScreens.make("weight-goal-moment")
        assertEquals(listOf("pct5", "pct10"), moment.weightPicture(WeightRange.ALL).moments.map { it.id })
        assertEquals("pct10", moment.weight.justReached?.id)

        val reached = DemoScreens.make("weight-goal-reached")
        val held = reached.weightPicture(WeightRange.ALL)
        assertEquals(listOf("pct5", "pct10", "goal"), held.moments.map { it.id })
        assertEquals(GoalReadout.Holding, held.readout)
        assertTrue(abs(held.trend.last().kg - 86.8) <= 0.1, "${held.trend.last().kg}")

        assertEquals(Sheet.WeightGoal, DemoScreens.make("weight-goal-sheet").sheet)
        val low = DemoScreens.make("weight-goal-low")
        assertEquals(Sheet.WeightGoal, low.sheet)
        assertEquals("55.0", low.weight.demoTypedGoal)
        assertTrue(WeightGoals.floorBlocks(55.0, 97.8, 180.0))

        assertNull(DemoScreens.make("weight").weight.goal, "every other weight screen has no goal")
    }
}
