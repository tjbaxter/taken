package com.tombaxter.taken

import android.content.Intent
import android.net.Uri
import android.os.Looper
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.Item
import com.tombaxter.taken.core.model.StackState
import kotlinx.coroutines.runBlocking
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The real MainActivity over its real files (SPEC-ANDROID 7.2 and 10.3): a configuration change (rotation, fold, resize)
 * recreates the activity, and neither ends edit mode nor replays the link Taken was opened with. Robolectric's recreate
 * runs Android's own path, `isChangingConfigurations` included.
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w360dp-h640dp-xxhdpi")
class ActivityTests {
    @get:Rule
    val compose = createEmptyComposeRule()

    private val app: TakenApp get() = ApplicationProvider.getApplicationContext()

    /** Vitamin D3, daily, on file before Taken opens. */
    private fun seed() = runBlocking {
        val vd3 = Item(
            name = "Vitamin D3", code = "VD3", frequency = Frequency.Daily(1),
            createdAt = Instant.now().minusSeconds(3L * 86_400), sortIndex = 0,
        )
        app.container.stores.stack.updateData { StackState(items = listOf(vd3)) }
    }

    /** The model once the files are read: DataStore reads on its own thread and hands back to the main looper. */
    private fun ActivityScenario<MainActivity>.awaitModel(): AppModel {
        val end = System.currentTimeMillis() + 10_000
        while (true) {
            shadowOf(Looper.getMainLooper()).idle()
            var model: AppModel? = null
            onActivity { model = it.model }
            model?.let { return it }
            check(System.currentTimeMillis() < end) { "the files were never read" }
            Thread.sleep(10)
        }
    }

    @Test
    fun aRotationKeepsEditModeSoARowStillOpensItsItem() {
        seed()
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            val model = scenario.awaitModel()
            compose.waitForIdle()
            assertTrue(model.hasStack)
            model.setEditingStack(true)

            scenario.recreate()
            compose.waitForIdle()
            assertTrue(model.editingStack, "a configuration change is not a trip to the background")
            val doses = model.state.doses
            compose.onNodeWithTag("row-Vitamin D3").performClick()
            compose.waitForIdle()
            assertEquals(doses, model.state.doses, "nothing logs while editing")
            assertEquals(Sheet.EditItem(model.activeItems.single().id), model.sheet, "the tap opens the item")

            model.sheet = null
            scenario.moveToState(Lifecycle.State.CREATED)
            assertFalse(model.editingStack, "a real trip to the background still ends it")
        }
    }

    @Test
    fun aLinkIsHandledOnceAndNotAgainAfterARotation() {
        seed()
        val link = Intent(Intent.ACTION_VIEW, Uri.parse("taken://today"), app, MainActivity::class.java)
        ActivityScenario.launch<MainActivity>(link).use { scenario ->
            val model = scenario.awaitModel()
            compose.waitForIdle()
            model.tab = AppTab.HISTORY
            model.openProfile()
            compose.waitForIdle()

            scenario.recreate()
            compose.waitForIdle()
            assertEquals(Route.Profile, model.backStack.last(), "Profile stays open")
            assertEquals(AppTab.HISTORY, model.tab, "the link does not bring Today forward again")
        }
    }

    /** SPEC-ANDROID 15.3's link checks: `taken://todo` and `taken://todo/record` bring To-do to the front over Profile. */
    @Test
    fun toDoLinksBringToDoToTheFrontOverProfile() {
        seed()
        val link = Intent(Intent.ACTION_VIEW, Uri.parse("taken://todo"), app, MainActivity::class.java)
        ActivityScenario.launch<MainActivity>(link).use { scenario ->
            val model = scenario.awaitModel()
            compose.waitForIdle()
            assertEquals(AppTab.TODO, model.tab, "taken://todo opens the To-do tab")
            compose.onNodeWithTag("mic").assertExists()

            model.tab = AppTab.HISTORY
            model.openProfile()
            compose.waitForIdle()
            scenario.onActivity { model.handle("taken://todo/record") }
            compose.waitForIdle()
            assertEquals(AppTab.TODO, model.tab, "taken://todo/record too")
            assertEquals(listOf<Route>(Route.Main), model.backStack.toList(), "over Profile")
            compose.onNodeWithTag("mic").assertExists()
        }
    }

    @Test
    fun aRelaunchFromRecentsCarriesNoLink() {
        val link = Intent(Intent.ACTION_VIEW, Uri.parse("taken://today"))
        assertEquals("taken://today", launchLink(link))
        assertNull(launchLink(Intent(link).addFlags(Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY)), "Recents hands back the first intent")
        assertNull(launchLink(Intent(Intent.ACTION_MAIN)))
        assertNull(launchLink(null))
    }
}
