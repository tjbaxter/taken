package com.tombaxter.taken

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeLeft
import androidx.compose.ui.test.swipeRight
import com.tombaxter.taken.core.todo.TodoCapture
import com.tombaxter.taken.core.todo.TodoCopy
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
 * The To-do tab on screen (SPEC-ANDROID 11 and 6.2), drawn by Robolectric from the demo's one list: the tab between Today
 * and History, a row as one TalkBack node with its actions, a tap on the words opening the edit sheet, a swipe to the
 * start deleting with Undo, the mic listening in the demo with "Tap to finish", the blocker's Type it instead adding
 * through the type sheet, and the edit sheet waiting for words before Save.
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = ScreenshotTests.PHONE)
class TodoScreenTests {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private fun show(model: AppModel) {
        compose.setContent { TakenRoot(model, Platform.none) }
        compose.waitForIdle()
    }

    @Test
    fun theTabSitsBetweenTodayAndHistory() {
        assertEquals(listOf(AppTab.TODAY, AppTab.TODO, AppTab.HISTORY), AppTab.entries.toList(), "the iPhone's order")
        val model = DemoScreens.make("today")
        show(model)
        compose.onNodeWithTag("tab-todo").performClick()
        compose.waitForIdle()
        assertEquals(AppTab.TODO, model.tab)
        compose.onNodeWithTag("todo").assertExists()
        compose.onNodeWithText(TodoCopy.DONE_TODAY).assertExists()
    }

    @Test
    fun aRowIsOneTalkBackNodeWithItsActions() {
        val model = DemoScreens.make("todo")
        show(model)
        val row = compose.onNodeWithTag("todo-row-Take the bins out")
        val node = row.fetchSemanticsNode()
        val label = node.config[SemanticsProperties.ContentDescription].single()
        assertTrue(label.startsWith("Take the bins out, due at "), label)
        assertEquals("mark done", node.config[SemanticsActions.OnClick].label)
        assertEquals(listOf("Edit", "Delete"), node.config[SemanticsActions.CustomActions].map { it.label })

        row.performSemanticsAction(SemanticsActions.OnClick)
        val bins = model.todo.state.tasks.first { it.title == "Take the bins out" }
        assertTrue(bins.id in model.todo.completing, "a double tap marks it done")

        val done = compose.onNodeWithTag("todo-row-Buy milk").fetchSemanticsNode()
        assertTrue(done.config[SemanticsProperties.ContentDescription].single().startsWith("Buy milk, done at "))
        assertEquals("mark not done", done.config[SemanticsActions.OnClick].label)
    }

    @Test
    fun aTapOnTheWordsOpensTheEditSheet() {
        val model = DemoScreens.make("todo")
        show(model)
        compose.onNodeWithTag("todo-row-Send Mum the photos").performClick()
        compose.waitForIdle()
        val sheet = assertIs<Sheet.TodoEdit>(model.sheet)
        assertEquals("Send Mum the photos", model.todo.state.task(sheet.taskId)?.title)
        compose.onNodeWithTag("todo-edit-sheet").assertExists()
    }

    @Test
    fun aSwipeToTheStartDeletesAndUndoPutsItBack() {
        val model = DemoScreens.make("todo")
        show(model)
        compose.onNodeWithTag("todo-row-Send Mum the photos").performTouchInput { swipeLeft() }
        compose.waitForIdle()
        assertEquals("Send Mum the photos", model.todo.deleted?.title, "swiped away")
        assertNull(model.todo.state.tasks.firstOrNull { it.title == "Send Mum the photos" })
        compose.onNodeWithText(TodoCopy.deleted("Send Mum the photos")).assertExists()
        compose.onNodeWithTag("todo-undo").performClick()
        compose.waitForIdle()
        assertNotNull(model.todo.state.tasks.firstOrNull { it.title == "Send Mum the photos" }, "Undo puts it back")
    }

    @Test
    fun aSwipeToTheEndFinishesATaskAndTheRowSpringsBack() {
        val model = DemoScreens.make("todo")
        show(model)
        val photos = model.todo.state.tasks.first { it.title == "Send Mum the photos" }
        compose.onNodeWithTag("todo-row-Send Mum the photos").performTouchInput { swipeRight() }
        compose.waitForIdle()
        assertTrue(photos.id in model.todo.completing || model.todo.state.task(photos.id)?.isDone == true, "finished")
        assertNull(model.todo.deleted, "never deleted")
        assertNotNull(model.todo.state.task(photos.id))
    }

    @Test
    fun theMicListensInTheDemoAndSaysTapToFinish() {
        val model = DemoScreens.make("todo")
        show(model)
        compose.onNodeWithTag("mic").performClick()
        compose.waitUntil(5_000) { model.todo.phase == TodoCapture.Phase.LISTENING }
        compose.onNodeWithText(TodoCopy.TAP_TO_FINISH).assertExists()
        compose.onNodeWithTag("listening-card").assertExists()
    }

    /** `taken://todo/record` over Profile and a sheet: To-do comes to the front and starts listening once uncovered. */
    @Test
    fun aRecordLinkListensOnceToDoIsUncovered() {
        val model = DemoScreens.make("today")
        show(model)
        model.openProfile()
        model.sheet = Sheet.Add
        compose.waitForIdle()
        model.handle("taken://todo/record")
        compose.waitUntil(5_000) { model.todo.phase == TodoCapture.Phase.LISTENING }
        assertEquals(AppTab.TODO, model.tab)
        assertNull(model.sheet)
        assertNull(model.todo.pendingRecording, "taken once")
        compose.onNodeWithTag("listening-card").assertExists()
    }

    @Test
    fun theBlockerOffersTypingAndTheTypeSheetSavesAsSaid() {
        val model = DemoScreens.make("todo-blocker")
        show(model)
        compose.onNodeWithText(TodoCopy.MICROPHONE_OFF).assertExists()
        compose.onNodeWithText(TodoCopy.TYPE_INSTEAD).performClick()
        compose.waitForIdle()
        assertEquals(Sheet.TodoType, model.sheet)
        compose.onNodeWithTag("sheet-confirm").assertIsNotEnabled()
        compose.onNodeWithTag("todo-type-field").performTextInput("Call the bank. Buy stamps.")
        compose.onNodeWithTag("sheet-confirm").assertIsEnabled().performClick()
        compose.waitForIdle()
        assertNull(model.sheet)
        // Saved at once as said, one line per sentence (TodoModelTests follows the rest of the save on its own thread).
        val lines = model.todo.state.tasks.map { it.title }
        assertTrue("Call the bank" in lines && "Buy stamps" in lines, "$lines")
    }

    @Test
    fun theEditSheetWaitsForWordsBeforeSave() {
        val model = DemoScreens.make("todo-edit")
        show(model)
        val sheet = assertIs<Sheet.TodoEdit>(model.sheet)
        compose.onNodeWithTag("todo-field").performTextClearance()
        compose.onNodeWithTag("sheet-confirm").assertIsNotEnabled()
        compose.onNodeWithTag("todo-field").performTextInput("Take the recycling out")
        compose.onNodeWithTag("sheet-confirm").assertIsEnabled().performClick()
        compose.waitForIdle()
        assertNull(model.sheet)
        val task = assertNotNull(model.todo.state.task(sheet.taskId))
        assertEquals("Take the recycling out", task.title)
        assertTrue(task.hasTime, "its time is kept")
    }
}
