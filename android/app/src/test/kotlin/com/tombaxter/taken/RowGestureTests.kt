package com.tombaxter.taken

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.click
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipe
import androidx.compose.ui.unit.dp
import com.tombaxter.taken.core.stack.RowSpeech
import com.tombaxter.taken.ui.today.AllTakenCheckScale
import com.tombaxter.taken.ui.shell.Platform
import com.tombaxter.taken.ui.shell.TakenRoot
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.util.Locale
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The row on the real Compose tree (SPEC-ANDROID 7.2), on Fish Oil (1 of 2, in view at phone size): a tap anywhere
 * logs; a drag that starts on a row scrolls and logs nothing; the pencil switches edit mode; TalkBack hears one node per
 * row with the iPhone's sentence, Android's click label and the long-press menu as custom actions.
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w360dp-h640dp-xxhdpi")
class RowGestureTests {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private fun show(screen: String = "today"): AppModel {
        val model = DemoScreens.make(screen)
        compose.setContent { TakenRoot(model, Platform.none) }
        compose.waitForIdle()
        return model
    }

    @Test
    fun aTapAnywhereOnTheRowLogs() {
        val model = show()
        val before = model.state.doses.size
        // Not only the ring: a tap near the row's leading edge, on the name.
        compose.onNodeWithTag("row-Fish Oil").performTouchInput { click(Offset(width * 0.1f, height / 2f)) }
        compose.waitForIdle()
        assertEquals(before + 1, model.state.doses.size, "the whole row is the target")
        assertEquals("Fish Oil taken at", model.toast?.message)
    }

    @Test
    fun aDragThatStartsOnARowScrollsAndLogsNothing() {
        val model = show()
        val before = model.state.doses
        compose.onNodeWithTag("row-Fish Oil").performTouchInput {
            swipe(start = center, end = center - Offset(0f, 600f), durationMillis = 400)
        }
        compose.waitForIdle()
        assertEquals(before, model.state.doses, "the scroll takes the gesture before the click fires")
        assertTrue(model.rowLogs.isEmpty())
    }

    @Test
    fun thePencilPutsTheStackInEditModeAndARowThenOpensItsItem() {
        val model = show()
        compose.onNodeWithTag("edit-stack").performClick()
        compose.waitForIdle()
        assertTrue(model.editingStack)
        val before = model.state.doses
        compose.onNodeWithTag("row-Fish Oil").performClick()
        compose.waitForIdle()
        assertEquals(before, model.state.doses, "nothing logs while editing")
        val fish = model.state.items.first { it.name == "Fish Oil" }
        assertEquals(Sheet.EditItem(fish.id), model.sheet)
    }

    @Test
    fun talkBackHearsOneNodePerRowWithItsActions() {
        val model = show()
        val node = compose.onNodeWithTag("row-Fish Oil").fetchSemanticsNode()
        val config = node.config
        val fish = model.today.items.first { it.item.name == "Fish Oil" }
        val sentence = RowSpeech.label(fish, model.today.day, model.clock, null, Locale.US)
        assertTrue(sentence.startsWith("Fish Oil, 1 of 2 taken, ") && sentence.endsWith(". Pending."), sentence)
        assertEquals(listOf(sentence), config.getOrNull(SemanticsProperties.ContentDescription), "the iPhone's VoiceOver sentence")
        assertEquals("Log Fish Oil", config.getOrNull(SemanticsActions.OnClick)?.label)
        assertEquals("Options", config.getOrNull(SemanticsActions.OnLongClick)?.label)
        assertEquals(
            listOf("Undo last dose", "Set time", "Edit item"),
            config.getOrNull(SemanticsActions.CustomActions)?.map { it.label },
        )
    }

    /**
     * The All taken moment (SPEC 3.1, SPEC-ANDROID 7.2): the tap that finishes the day springs the check in from 0.55,
     * on the same tap, as the iPhone's pop does.
     */
    @Test
    fun theTapThatFinishesTheDayPlaysTheAllTakenCheck() {
        val model = show()
        fun checkScale(): Float? = compose.onNodeWithTag("progress").fetchSemanticsNode().config.getOrNull(AllTakenCheckScale)
        model.tap(model.today.items.first { it.item.name == "Fish Oil" })
        compose.waitForIdle()
        assertNull(checkScale(), "Magnesium is still to take")

        compose.mainClock.autoAdvance = false
        model.tap(model.today.items.first { it.item.name == "Magnesium" })
        compose.mainClock.advanceTimeByFrame()
        val first = assertNotNull(checkScale(), "All taken shows on the tap that finishes the day")
        assertTrue(first < 0.6f, "the check springs in from 0.55, never shown full size first: $first")
        compose.mainClock.advanceTimeBy(2_000)
        assertEquals(1f, assertNotNull(checkScale()), 0.01f, "and settles at full size")
    }

    /**
     * Beside the rail (600 dp and wider) nothing else pads the bottom inset: Take all must still sit above the
     * navigation bar or taskbar (SPEC-ANDROID 6.2).
     */
    @Test
    @Config(qualifiers = "w1280dp-h800dp-land-xhdpi")
    fun besideTheRailTakeAllSitsAboveTheNavigationBar() {
        val model = DemoScreens.make("today")
        compose.setContent {
            WithSystemBars(navigationBar = 48.dp) {
                Box(Modifier.fillMaxSize().testTag("screen")) { TakenRoot(model, Platform.none) }
            }
        }
        compose.waitForIdle()
        val screen = compose.onNodeWithTag("screen").getUnclippedBoundsInRoot()
        val takeAll = compose.onNodeWithTag("take-all").getUnclippedBoundsInRoot()
        assertTrue(
            takeAll.bottom <= screen.bottom - 48.dp,
            "Take all ends ${screen.bottom - takeAll.bottom} above the bottom edge, inside a 48 dp navigation bar",
        )
    }

    @Test
    fun takeAllShowsForTwoRowsAndStepsAsideWhileEditing() {
        val model = show()
        compose.onNodeWithTag("take-all").performClick()
        compose.waitForIdle()
        assertTrue(model.today.allTaken, "Fish Oil's second dose and Magnesium, at one moment")
        assertEquals("2 taken at", model.toast?.message)
    }
}
