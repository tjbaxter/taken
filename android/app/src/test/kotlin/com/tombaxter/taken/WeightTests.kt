package com.tombaxter.taken

import com.tombaxter.taken.core.pro.ProAccess
import com.tombaxter.taken.core.retention.TodayPrompt
import com.tombaxter.taken.core.weight.WeightCopy
import com.tombaxter.taken.core.weight.WeightFigure
import com.tombaxter.taken.core.weight.WeightGoalCopy
import com.tombaxter.taken.core.weight.WeightLine
import com.tombaxter.taken.core.weight.GoalReadout
import com.tombaxter.taken.core.weight.WeightRange
import com.tombaxter.taken.core.weight.WeightState
import com.tombaxter.taken.core.weight.WeightUnit
import com.tombaxter.taken.core.weight.day
import com.tombaxter.taken.data.MemoryWeightPersistence
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/WeightTests.swift, the cases that run through the app model: the tab's visibility with the
 * selection it resets, the offer's answer, logging and Undo under the Pro rule, Edit… on today's number, the end of a
 * visit, the demo screens, and Erase. The pure rules are :core's WeightTests.
 */
@RunWith(RobolectricTestRunner::class)
class WeightTests {

    private fun file(model: AppModel): WeightState = (model.weight.persistence as MemoryWeightPersistence).state

    @Test
    fun testHidingTheTabBringsTodayForwardFirstAndUndoBringsItBack() {
        val model = DemoScreens.make("weight")
        assertEquals(AppTab.WEIGHT, model.tab)
        assertTrue(model.weight.showsTab)
        assertFalse(model.weight.isEmpty)
        assertEquals(listOf(AppTab.TODAY, AppTab.TODO, AppTab.HISTORY, AppTab.WEIGHT), model.visibleTabs, "last, while it is on")

        model.hideWeightTab()
        assertEquals(AppTab.TODAY, model.tab, "a hidden tab never stays selected")
        assertFalse(model.weight.showsTab)
        assertEquals(false, file(model).showsTab, "kept in weights.json")
        val toast = assertNotNull(model.toast)
        assertEquals("Weight tab hidden. Profile brings it back.", toast.message)
        assertEquals(UndoStep.ShowWeightTab, toast.undo)
        assertFalse(model.weight.isEmpty, "hiding deletes nothing")
        assertFalse(AppTab.WEIGHT in model.visibleTabs)

        model.undo(toast)
        assertTrue(model.weight.showsTab)
        assertEquals(AppTab.WEIGHT, model.tab)

        model.setWeightTab(false)
        assertEquals(AppTab.TODAY, model.tab, "Profile's switch off while the tab is in front")
        model.setWeightTab(true)
        assertEquals(AppTab.TODAY, model.tab, "on never switches tabs")
        assertEquals(true, file(model).showsTab)

        model.openWeightTab()
        assertEquals(AppTab.WEIGHT, model.tab, "taken://weight")
        model.setWeightTab(false)
        model.openWeightTab()
        assertEquals(AppTab.TODAY, model.tab, "taken://weight with the tab off lands on Today")
        model.setWeightTab(true)
        model.handle("taken://weight")
        assertEquals(AppTab.WEIGHT, model.tab, "the link itself")

        val others = DemoScreens.make("today")
        assertFalse(others.weight.showsTab, "every other screen shows the default app")
        assertEquals(listOf(AppTab.TODAY, AppTab.TODO, AppTab.HISTORY), others.visibleTabs)
        assertNull(WeightState().showsTab, "off by default: null until the person chooses")
    }

    @Test
    fun testTheOfferAddsTheTabWithoutSwitchingAndNeverComesBack() {
        val model = DemoScreens.make("today-weight-offer")
        assertEquals(TodayPrompt.WeightOffer, model.todayPrompt)
        assertTrue(model.today.allTaken)
        assertTrue(model.activeItems.any { it.code == "SEM" }, "a stack with a weekly shot")
        assertFalse(model.weight.showsTab)

        model.answerWeightOffer(addTab = true)
        assertNull(model.todayPrompt)
        assertTrue(model.weight.showsTab)
        assertTrue(model.weight.state.offerAnswered)
        assertEquals(AppTab.TODAY, model.tab, "Add tab does not switch to it")

        val declined = DemoScreens.make("today-weight-offer")
        declined.answerWeightOffer(addTab = false)
        assertFalse(declined.weight.showsTab)
        assertTrue(declined.weight.state.offerAnswered)
        assertNull(DemoScreens.make("today").todayPrompt)
    }

    /**
     * The first weigh-in needs no Pro: a tap on the number brings the keyboard at once. Weigh in saves it with "Weighed
     * in" and Undo; after it, a tap opens the paywall instead.
     */
    @Test
    fun testLoggingFollowsTheWeighInRuleAndUndoRemovesIt() {
        val model = DemoScreens.make("locked")
        assertEquals(ProAccess.FIRST_SESSION, model.weightAccess)
        var opened = false
        model.requireWeightPro { opened = true }
        assertTrue(opened, "the first weigh-in runs at once")

        model.saveWeighIn(88.35)
        val toast = assertNotNull(model.toast)
        assertEquals("Weighed in", toast.message)
        assertNull(toast.time, "the value lives in the big number, not the toast")
        assertNotNull(toast.undo)
        assertEquals(
            "Weighed in, ${com.tombaxter.taken.core.weight.WeightFormat.spoken(88.35, model.weight.unit, java.util.Locale.getDefault())}.",
            toast.spoken, "TalkBack hears the weight, in the unit the page shows",
        )
        val saved = model.weight.state.weighIns.first()
        assertEquals(saved.id, model.weight.justSaved)
        assertNotNull(model.weight.state.firstWeighInAt)
        assertEquals(ProAccess.LOCKED, model.weightAccess, "after the first weigh-in, logging needs Pro")

        model.undo(toast)
        assertTrue(model.weight.isEmpty, "Undo removes it")
        assertNull(model.weight.justSaved)
        assertNull(model.weight.justReached)
        assertEquals(ProAccess.LOCKED, model.weightAccess, "and the first weigh-in stays used")

        var again = false
        model.requireWeightPro { again = true }
        assertFalse(again)
        assertNotNull(model.paywall, "the paywall instead of the keyboard")
        assertNotEquals(ProAccess.FIRST_SESSION, model.access)
    }

    /** Edit… on today's number opens All weigh-ins at that weigh-in; when locked, the paywall opens and no sheet does. */
    @Test
    fun testEditOpensAllWeighInsAtTodaysWeighIn() {
        val model = DemoScreens.make("weight-weighed")
        val today = assertNotNull(model.weight.state.last)
        model.editWeighIn(today.id)
        assertEquals(Sheet.WeighIns, model.sheet)
        assertEquals(today.id, model.weight.editOnOpen)
        assertEquals(today.id, model.weight.editing, "the editor is already open, and back leads to the list")
        model.closeWeighIns()
        assertNull(model.sheet)
        assertNull(model.weight.editing)

        val locked = DemoScreens.make("weight-locked")
        assertEquals(ProAccess.LOCKED, locked.weightAccess)
        val id = assertNotNull(locked.weight.state.last?.id)
        locked.editWeighIn(id)
        assertNull(locked.sheet)
        assertNotNull(locked.paywall)
        assertNull(locked.weight.editOnOpen)

        // Inside All weigh-ins, the paywall comes over the sheet, which stays.
        val list = DemoScreens.make("weight-locked")
        list.sheet = Sheet.WeighIns
        list.openWeighInEditor(id)
        assertEquals(Sheet.WeighIns, list.sheet)
        assertNotNull(list.paywall)
        assertNull(list.weight.editing)
    }

    /** A visit's line and draft go when it ends: leaving the tab, or Taken going to the background. */
    @Test
    fun testEndVisitClearsTheVisit() {
        val model = DemoScreens.make("weight-goal-moment")
        assertNotNull(model.weight.justReached)
        assertNotNull(model.weight.justSaved)
        model.weight.momentPlayed = true
        model.weight.draft = "88.1"
        model.weight.endVisit()
        assertNull(model.weight.justReached)
        assertNull(model.weight.justSaved)
        assertFalse(model.weight.momentPlayed)
        assertEquals("", model.weight.draft)

        val left = DemoScreens.make("weight-goal-moment")
        left.tab = AppTab.HISTORY
        assertNull(left.weight.justReached, "leaving the tab ends the visit")
        val away = DemoScreens.make("weight-goal-moment")
        away.didEnterBackground()
        assertNull(away.weight.justSaved, "so does the background")
    }

    /** The demo screens open on Weight with the tab on, and hold what their captures need. */
    @Test
    fun testTheEntryDemoScreens() {
        val screens = listOf(
            "weight", "weight-entry", "weight-entry-range", "weight-empty", "weight-first", "weight-weighed", "weight-trend",
            "weight-locked", "weight-lb", "weight-goal-saved", "weight-goal-reached-moment",
        )
        for (screen in screens) {
            val model = DemoScreens.make(screen)
            assertEquals(AppTab.WEIGHT, model.tab, screen)
            assertTrue(model.weight.showsTab, screen)
        }
        val plain = DemoScreens.make("weight")
        val last = assertNotNull(plain.weight.state.last)
        assertEquals(plain.today.day.adding(-1), plain.clock.day(last), "the history ends yesterday")
        assertEquals(WeightFigure.Ghost(last.kg), plain.weightFigure)
        assertEquals(WeightLine.Last, plain.weightLine())

        assertEquals(1, DemoScreens.make("weight-first").weight.state.weighIns.size)

        val saved = DemoScreens.make("weight-goal-saved")
        assertNotNull(saved.weight.justSaved)
        val line = assertIs<WeightLine.Closing>(saved.weightLine())
        val left = assertIs<GoalReadout.ToGo>(line.readout).kg
        assertTrue(WeightGoalCopy.roundedUp(left) in 1.1..1.3, "$left")

        assertEquals(ProAccess.LOCKED, DemoScreens.make("weight-locked").weightAccess)
        assertEquals(WeightUnit.LB, DemoScreens.make("weight-lb").weight.unit)
        assertEquals("88.1", DemoScreens.make("weight-entry").weight.draft)
        assertEquals(WeightFigure.Empty, DemoScreens.make("weight-empty").weightFigure)
        assertIs<WeightFigure.Today>(DemoScreens.make("weight-weighed").weightFigure, "today's number")
        assertEquals("goal", DemoScreens.make("weight-goal-reached-moment").weight.justReached?.id)
    }

    /**
     * Erase all data takes the weigh-ins and keeps the tab setting, the unit, the offer's answer and the first weigh-in's
     * date; the dialog says so.
     */
    @Test
    fun testEraseTakesTheWeighInsAndKeepsTheChoices() {
        assertTrue(AppModel.ERASE_MESSAGE.contains("your weigh-ins"))
        assertTrue(AppModel.ERASE_MESSAGE.contains("to-dos"))
        val model = DemoScreens.make("weight")
        model.weight.setUnit(WeightUnit.LB)
        model.weight.answerOffer(addTab = true)
        model.setWeightRange(WeightRange.MONTH)
        val first = assertNotNull(model.weight.state.firstWeighInAt)
        model.eraseAll()
        val kept = file(model)
        assertTrue(kept.weighIns.isEmpty())
        assertEquals(true, kept.showsTab)
        assertEquals(WeightUnit.LB, kept.unit)
        assertTrue(kept.offerAnswered)
        assertEquals(first, kept.firstWeighInAt)
        assertNull(kept.range, "the chart's range goes back to All")
    }

    /** The import line under Profile's row, and a file that could not be read. */
    @Test
    fun testImportSaysWhatItDid() {
        val model = DemoScreens.make("weight-empty")
        assertEquals("Added 2 weigh-ins, read in kg.", model.importWeights("date,kg\n2026-10-19,88.6\n2026-10-20,88.35\n", java.util.Locale.UK))
        assertEquals("Added 2 weigh-ins, read in kg.", model.weight.importNote)
        assertEquals(2, file(model).weighIns.size)
        assertEquals(WeightCopy.COULD_NOT_OPEN, model.importWeights(null))
        assertEquals(WeightCopy.NOT_FOUND, model.importWeights("nothing here"))
    }
}
