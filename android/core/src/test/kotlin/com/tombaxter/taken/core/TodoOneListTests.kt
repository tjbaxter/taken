package com.tombaxter.taken.core

import com.tombaxter.taken.core.demo.TodoDemo
import com.tombaxter.taken.core.todo.TodoCodec
import com.tombaxter.taken.core.todo.TodoCopy
import com.tombaxter.taken.core.todo.TodoDraft
import com.tombaxter.taken.core.todo.TodoDue
import com.tombaxter.taken.core.todo.TodoNotifications
import com.tombaxter.taken.core.todo.TodoState
import com.tombaxter.taken.core.todo.TodoTask
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/TodoOneListTests.swift, the one-list cases (SPEC-ANDROID 8.2): every task is on one list, whatever
 * list an iPhone 1.1 internal build put it on; such a file loads on Android with every task (its list values are read
 * past, SPEC-ANDROID 5.2); the demo is the one list. The list-build round trip and the Lock Screen widget are left out.
 */
class TodoOneListTests {
    private val clock = londonClock()

    /** todos.json as an iPhone 1.1 internal build with Personal and Work wrote it. */
    private val listBuildFile = """
        {"areaOrder":["work","personal"],"firstNoteAt":1790000000,"lastArea":"work","schemaVersion":1,"tasks":[
        {"area":"work","createdAt":1791000000,"id":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","noteId":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","order":0,"title":"LinkedIn ICP"},
        {"area":"personal","createdAt":1791000100,"dueAt":1791100000,"id":"7A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","noteId":"7A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","order":0,"title":"Call the dentist"},
        {"area":"work","completedAt":1791050000,"createdAt":1790990000,"dueDay":"2026-10-21","id":"8A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","noteId":"8A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","order":0,"title":"Send Priya the deck"}
        ]}
    """.trimIndent()

    @Test
    fun testAFileTheListBuildsWroteDecodesAndRoundTripsUnchanged() {
        // Android reads every task of a list-build file onto its one list; the list values themselves are left out.
        val state = TodoCodec.decode(listBuildFile, london)
        assertEquals(listOf("LinkedIn ICP", "Call the dentist", "Send Priya the deck"), state.tasks.map { it.title })
        assertEquals(1, state.schemaVersion)
        assertEquals(state, TodoCodec.decode(TodoCodec.encode(state), london), "every task and value Android keeps round trips")
        val dentist = assertNotNull(state.tasks.firstOrNull { it.title == "Call the dentist" })
        state.complete(dentist.id, at(2026, 10, 21, 9))
        state.add(listOf(TodoDraft("Buy milk")), at = at(2026, 10, 21, 9, 5))
        assertEquals(4, TodoCodec.decode(TodoCodec.encode(state), london).tasks.size)
    }

    @Test
    fun testFormerWorkTasksShowOnTheOneListInItsOrder() {
        val state = TodoState()
        state.add(listOf(TodoDraft("Buy milk")), at = at(2026, 10, 21, 8))
        state.tasks = state.tasks + TodoTask(title = "LinkedIn ICP", createdAt = at(2026, 10, 20, 17, 18), noteId = UUID.randomUUID())
        state.tasks = state.tasks + TodoTask(title = "Send the deck", due = TodoDue.Time(at(2026, 10, 21, 16)), createdAt = at(2026, 10, 21, 7), noteId = UUID.randomUUID())
        state.tasks = state.tasks + TodoTask(title = "Reply to Dan", createdAt = at(2026, 10, 21, 7), completedAt = at(2026, 10, 21, 11), noteId = UUID.randomUUID())
        val ring = state.add(listOf(TodoDraft("Ring Mum")), at = at(2026, 10, 21, 8, 30))[0]
        state.complete(ring.id, at(2026, 10, 21, 12))
        val today = clock.day(at(2026, 10, 21, 14))

        assertEquals(listOf("Send the deck", "Buy milk", "LinkedIn ICP"), state.openTasks(clock).map { it.title })
        assertEquals(listOf("Ring Mum", "Reply to Dan"), state.doneTasks(today, clock).map { it.title })
        assertEquals("3 open, 2 done today", TodoCopy.summary(state.openTasks(clock).size, state.doneTasks(today, clock).size))
        assertEquals(listOf("Send the deck"), TodoNotifications.plan(state.tasks, at(2026, 10, 21, 14), clock).map { it.title }, "a task with a time still gets its notification")
    }

    @Test
    fun testANewTaskIsPersonalAndKeepAsOneKeepsTheFirstTask() {
        val state = TodoState()
        val added = state.add(listOf(TodoDraft("Email Sam"), TodoDraft("Call the bank")), at = at(2026, 10, 21, 10))
        val merged = assertNotNull(state.mergeNote(added.map { it.id }, "Email Sam and call the bank", null))
        assertEquals(added[0].id, merged.id)
        assertEquals(listOf("Email Sam and call the bank"), state.openTasks(clock).map { it.title })
    }

    @Test
    fun testEraseAllPutsTheStoredListValuesBack() {
        val state = TodoState()
        state.add(listOf(TodoDraft("Send the deck")), at = at(2026, 10, 21, 9))
        state.eraseAll()
        assertTrue(state.tasks.isEmpty())
        assertEquals(at(2026, 10, 21, 9), state.firstNoteAt, "erasing never opens the first note again")
    }

    @Test
    fun testTheLineUnderTheTitleAndDoneTodayAreAsBefore() {
        assertEquals("3 open, 2 done today", TodoCopy.summary(3, 2))
        assertEquals("3 open", TodoCopy.summary(3, 0))
        assertEquals("0 open, 2 done today", TodoCopy.summary(0, 2))
        assertEquals(null, TodoCopy.summary(0, 0), "nothing listed: the line that teaches it instead")
        assertEquals("Done today", TodoCopy.DONE_TODAY)
        assertEquals("Tap the mic and say what you need to do", TodoCopy.EMPTY)
        for (text in listOf(TodoCopy.DONE_TODAY, "3 open, 2 done today", "0 open, 2 done today", TodoCopy.KEEP_AS_ONE)) {
            assertTrue(text in TodoCopy.all, "$text is checked by the copy test")
        }
        assertFalse(TodoCopy.all.any { it.contains("Personal") || it.contains("Work") }, "no list in any line")
    }

    @Test
    fun testTheDemoSeedsOneListWithDoneToday() {
        val now = at(2026, 10, 19, 21, 41)
        val state = TodoDemo.state(now, recording = false, zone = london)
        assertEquals(
            listOf("Take the bins out", "Call the dentist", "Pick up the dry cleaning", "Email Sam the deck", "Renew the car insurance", "Book flights for March", "Send Mum the photos"),
            state.openTasks(clock).map { it.title },
        )
        assertEquals(listOf("Buy milk", "Pay the window cleaner"), state.doneTasks(clock.day(now), clock).map { it.title })
        val recording = TodoDemo.state(now, recording = true, zone = london)
        assertEquals(3, recording.openTasks(clock).size, "the note being said is not on the list yet")
        assertEquals(state.tasks.map { it.id }, TodoDemo.state(now, recording = false, zone = london).tasks.map { it.id }, "the same ids every capture")
    }
}
