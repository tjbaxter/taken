package com.tombaxter.taken

import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.profile.Profile
import com.tombaxter.taken.data.MemoryPersistence
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The app-level cases of TakenTests/RedesignTests.swift (its pure cases are in :core's RedesignTests), adapted to Android
 * routing (SPEC-ANDROID 8.2): a voice to-do request brings To-do to the front over any sheet and over Profile, which is a
 * screen on Android (6.3); the demo screens open on their tab; a real launch opens on Today; the erase dialog says the
 * to-dos go too. The widget gallery's mode comes with the widgets (NEXT 4).
 */
@RunWith(RobolectricTestRunner::class)
class RedesignTests {
    @Test
    fun testAVoiceToDoRequestBringsTheToDoTabToTheFrontOverAnySheet() {
        val model = DemoScreens.make("today")
        assertEquals(AppTab.TODAY, model.tab)
        model.openProfile()
        model.sheet = Sheet.Add
        assertFalse(model.showsTodoTabUncovered)
        model.openTodoTab()
        assertEquals(AppTab.TODO, model.tab)
        assertNull(model.sheet, "the sheet closes so Listening and the stop button are on screen")
        assertEquals(listOf<Route>(Route.Main), model.backStack.toList(), "and Profile with it")
        assertTrue(model.showsTodoTabUncovered)

        assertEquals(AppTab.TODO, DemoScreens.make("todo").tab)
        assertEquals(AppTab.TODO, DemoScreens.make("todo-recording").tab)
        assertEquals(AppTab.HISTORY, DemoScreens.make("log").tab, "the calendar lives on History")
        assertEquals(AppTab.HISTORY, DemoScreens.make("day").tab)
        val launched = AppModel(MemoryPersistence(), StackState(), null, Profile(), null)
        assertEquals(AppTab.TODAY, launched.tab, "a real launch opens on Today")
    }

    @Test
    fun testEraseSaysWhatItTakes() {
        assertTrue(AppModel.ERASE_MESSAGE.contains("to-dos"), "the to-dos go too, so the dialog says so")
        assertTrue(AppModel.ERASE_MESSAGE.contains("profile"))
    }
}
