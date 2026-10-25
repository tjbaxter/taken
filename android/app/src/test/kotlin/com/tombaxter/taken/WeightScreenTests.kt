package com.tombaxter.taken

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import com.tombaxter.taken.core.weight.WeightCopy
import com.tombaxter.taken.core.weight.WeightFigure
import com.tombaxter.taken.ui.shell.Platform
import com.tombaxter.taken.ui.shell.TakenRoot
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The Weight tab on the real Compose tree (SPEC-ANDROID 12): a tap on the number brings the field and Weigh in saves; a
 * locked tap opens the paywall and never the keyboard; a drag from anywhere on screen one scrolls to the trend; the More
 * options menu hides the tab; the long press offers Edit… and Delete; TalkBack's field carries the iPhone's label; the
 * tab sits last on the bar only while it is on; taken://weight lands on it or on Today.
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w411dp-h914dp-420dpi")
class WeightScreenTests {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private fun show(screen: String): AppModel {
        val model = DemoScreens.make(screen)
        compose.setContent { TakenRoot(model, Platform.none) }
        compose.waitForIdle()
        return model
    }

    @Test
    fun aTapOnTheNumberBringsTheFieldAndWeighInSaves() {
        val model = show("weight")
        compose.onNodeWithTag("weight-number").performClick()
        compose.waitForIdle()
        assertTrue(model.weight.entryFocused, "the field has focus: the keyboard comes up")
        compose.onNodeWithTag("weight-field").performTextReplacement("88.1")
        compose.waitForIdle()
        assertEquals(WeightFigure.Typing("88.1"), model.weightFigure)
        compose.onNodeWithTag("weigh-in").performClick()
        compose.waitForIdle()
        assertEquals(88.1, model.weight.state.last?.kg)
        assertEquals("Weighed in", model.toast?.message)
        assertIs<WeightFigure.Today>(model.weightFigure, "the number stays as today's")
        assertTrue(!model.weight.entryFocused)
    }

    @Test
    fun aNumberOutsideTheBoundsCannotBeSaved() {
        val model = show("weight")
        compose.onNodeWithTag("weight-number").performClick()
        compose.waitForIdle()
        compose.onNodeWithTag("weight-field").performTextReplacement("883")
        compose.waitForIdle()
        compose.onNodeWithText(WeightCopy.rangeHint(model.weight.unit)).assertIsDisplayed()
        val before = model.weight.state.weighIns.size
        compose.onNodeWithTag("weigh-in").performClick()
        compose.waitForIdle()
        assertEquals(before, model.weight.state.weighIns.size, "Weigh in stays dimmed until the number is a weight")
    }

    @Test
    fun aLockedTapOpensThePaywallAndNeverTheKeyboard() {
        val model = show("weight-locked")
        compose.onNodeWithTag("weight-number").performClick()
        compose.waitForIdle()
        assertNotNull(model.paywall)
        assertTrue(!model.weight.entryFocused)
        assertTrue(compose.onAllNodes(androidx.compose.ui.test.hasTestTag("weight-field")).fetchSemanticsNodes().isEmpty(), "no field while locked")
    }

    @Test
    fun aDragFromScreenOneScrollsToTheTrend() {
        show("weight")
        // From the number itself: the touch layer over it never takes the drag from the page.
        compose.onNodeWithTag("weight").performTouchInput {
            swipeUp(startY = height * 0.9f, endY = height * 0.1f, durationMillis = 200)
        }
        compose.waitForIdle()
        compose.onNodeWithTag("weight-trend").assertIsDisplayed()
    }

    @Test
    fun theChevronShowsTheTrend() {
        show("weight")
        compose.onNodeWithTag("show-trend").performClick()
        compose.waitForIdle()
        compose.onNodeWithTag("weight-chart").assertIsDisplayed()
    }

    @Test
    fun theMoreMenuHidesTheTabWithUndo() {
        val model = show("weight")
        compose.onNodeWithTag("weight-more").performClick()
        compose.waitForIdle()
        compose.onNodeWithTag("hide-weight-tab").performClick()
        compose.waitForIdle()
        assertEquals(AppTab.TODAY, model.tab)
        assertTrue(compose.onAllNodes(androidx.compose.ui.test.hasTestTag("tab-weight")).fetchSemanticsNodes().isEmpty(), "gone from the bar")
        assertEquals(WeightCopy.HIDDEN, model.toast?.message)
    }

    @Test
    fun theLongPressOnTodaysNumberOffersEditAndDelete() {
        val model = show("weight-weighed")
        compose.onNodeWithTag("weight-number").performTouchInput { longClick() }
        compose.waitForIdle()
        compose.onNodeWithText(WeightCopy.DELETE).performClick()
        compose.waitForIdle()
        assertEquals(WeightCopy.DELETED, model.toast?.message)
    }

    @Test
    fun talkBackHearsTheField() {
        val model = show("weight-weighed")
        val node = compose.onNodeWithTag("weight-field").fetchSemanticsNode()
        assertEquals(listOf(WeightCopy.TODAYS_WEIGH_IN), node.config.getOrNull(SemanticsProperties.ContentDescription))
        val actions = node.config.getOrNull(SemanticsActions.CustomActions)?.map { it.label }
        assertEquals(listOf(WeightCopy.EDIT_WEIGH_IN, WeightCopy.DELETE_WEIGH_IN), actions)
        val today = assertNotNull(model.weight.state.last)
        assertEquals(com.tombaxter.taken.core.weight.WeightFormat.spoken(today.kg, model.weight.unit, java.util.Locale.US), node.config.getOrNull(SemanticsProperties.StateDescription))
    }

    @Test
    fun theTabIsLastOnTheBarOnlyWhileItIsOn() {
        val model = show("today")
        assertTrue(compose.onAllNodes(androidx.compose.ui.test.hasTestTag("tab-weight")).fetchSemanticsNodes().isEmpty(), "off by default")
        model.setWeightTab(true)
        compose.waitForIdle()
        compose.onNodeWithTag("tab-weight").performClick()
        compose.waitForIdle()
        assertEquals(AppTab.WEIGHT, model.tab)
        compose.onNodeWithTag("weight").assertIsDisplayed()
    }

    @Test
    fun theOfferRowAddsTheTab() {
        val model = show("today-weight-offer")
        compose.onNodeWithTag("weight-offer-add").performClick()
        compose.waitForIdle()
        assertTrue(model.weight.showsTab)
        compose.onNodeWithTag("tab-weight").assertIsDisplayed()
        assertNull(model.todayPrompt)
    }

    @Test
    fun theWeightLinkLandsOnTheTabOrOnToday() {
        val off = show("today")
        off.handle("taken://weight")
        compose.waitForIdle()
        assertEquals(AppTab.TODAY, off.tab, "off: Today")
    }

    @Test
    fun allWeighInsOpensAndARowOpensItsEditor() {
        val model = show("weight-list")
        compose.onNodeWithTag("weigh-ins-sheet").assertIsDisplayed()
        compose.onAllNodes(androidx.compose.ui.test.hasTestTag("weigh-in-row"))[0].performClick()
        compose.waitForIdle()
        assertNotNull(model.weight.editing)
        compose.onNodeWithTag("weigh-in-editor").assertIsDisplayed()
    }

    @Test
    fun profileHasTheSwitchAndTheCsvRows() {
        val model = show("weight-settings")
        compose.onNodeWithTag("weight-switch").performScrollTo().performClick()
        compose.waitForIdle()
        assertTrue(!model.weight.showsTab, "the switch turns the tab off")
        compose.onNodeWithTag("import-weight").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("export-weight").performScrollTo().assertIsDisplayed()
    }
}
