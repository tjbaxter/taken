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

    /**
     * SPEC-ANDROID 6.1: the splash screen stays only until Taken has read its files, then MainActivity runs in Theme.Taken,
     * whose window is Signal's canvas, not the splash screen's layers.
     */
    @Test
    fun theSplashScreenHandsOverToTakensThemeOnceTheFilesAreRead() {
        seed()
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.awaitModel()
            scenario.onActivity { activity ->
                assertFalse(activity.keepsSplash, "the files are read: the splash screen goes")
                val window = activity.theme.obtainStyledAttributes(intArrayOf(android.R.attr.windowBackground))
                val background = window.getDrawable(0)
                window.recycle()
                assertEquals(0xFF08090A.toInt(), (background as android.graphics.drawable.ColorDrawable).color, "Theme.Taken's window")
            }
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

    /**
     * SPEC-ANDROID 10.3: a `taken://` link that reaches the exported MainActivity from outside Taken (another app's explicit
     * intent, a page) only navigates. It never takes all, logs, or opens the microphone: only Taken's own unexported way in
     * (`MainActivity.INTERNAL_LINK`, the widgets, the tile, the notifications, the shortcuts) may.
     */
    @Test
    fun aLinkFromOutsideTakenNeverLogs() {
        seed()
        val outside = Intent(Intent.ACTION_VIEW, Uri.parse("taken://today?then=take-all"), app, MainActivity::class.java)
        assertFalse(fromTaken(outside), "MainActivity itself is exported for the launcher: anyone can start it")
        ActivityScenario.launch<MainActivity>(outside).use { scenario ->
            val model = scenario.awaitModel()
            compose.waitForIdle()
            assertEquals(AppTab.TODAY, model.tab, "it may open Today")
            assertTrue(model.state.doses.isEmpty(), "and logs nothing")

            scenario.onActivity { it.receiveLink(Intent(outside).setData(Uri.parse("taken://pro?then=take-all"))) }
            compose.waitForIdle()
            assertTrue(model.state.doses.isEmpty(), "a pro link from outside keeps no Take all")
            scenario.onActivity { it.receiveLink(Intent(outside).setData(Uri.parse("taken://todo/record"))) }
            compose.waitForIdle()
            assertEquals(AppTab.TODO, model.tab, "To-do comes to the front")
            assertNull(model.todo.pendingRecording, "but the microphone never starts from outside")

            // The same link through Taken's own way in, as a widget, the tile or the shortcut sends it.
            val internal = Intent(Intent.ACTION_VIEW, Uri.parse("taken://today?then=take-all"))
                .setComponent(android.content.ComponentName(app, MainActivity.INTERNAL_LINK))
            assertTrue(fromTaken(internal))
            scenario.onActivity { it.receiveLink(internal) }
            compose.waitForIdle()
            assertEquals(1, model.state.doses.size, "Taken's own Take all logs")
        }
    }

    /** Taken's own way in is an alias of MainActivity that no other app can start. */
    @Test
    fun theInternalWayInIsNotExported() {
        val alias = app.packageManager.getActivityInfo(android.content.ComponentName(app, MainActivity.INTERNAL_LINK), 0)
        assertFalse(alias.exported, "not exported: only Taken and the launcher's shortcuts (started as Taken) reach it")
        assertEquals(MainActivity::class.java.name, alias.targetActivity)
        val widget = com.tombaxter.taken.widget.takenIntent(app, "taken://today?then=take-all")
        assertEquals(MainActivity.INTERNAL_LINK, widget.component?.className, "the widgets and the tile use it")
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
