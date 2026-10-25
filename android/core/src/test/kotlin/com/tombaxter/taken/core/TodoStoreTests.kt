package com.tombaxter.taken.core

import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.model.TakenJson
import com.tombaxter.taken.core.pro.ProAccess
import com.tombaxter.taken.core.pro.ProReason
import com.tombaxter.taken.core.pro.ProStatus
import com.tombaxter.taken.core.reminders.Reminders
import com.tombaxter.taken.core.todo.TodoCapture
import com.tombaxter.taken.core.todo.TodoCodec
import com.tombaxter.taken.core.todo.TodoCopy
import com.tombaxter.taken.core.todo.TodoDraft
import com.tombaxter.taken.core.todo.TodoDue
import com.tombaxter.taken.core.todo.TodoEditRules
import com.tombaxter.taken.core.todo.TodoGate
import com.tombaxter.taken.core.todo.TodoMerge
import com.tombaxter.taken.core.todo.TodoNotificationScheduler
import com.tombaxter.taken.core.todo.TodoNotifications
import com.tombaxter.taken.core.todo.TodoOrdering
import com.tombaxter.taken.core.todo.TodoState
import com.tombaxter.taken.core.todo.TodoStopReason
import com.tombaxter.taken.core.todo.TodoTask
import com.tombaxter.taken.core.todo.TodoText
import com.tombaxter.taken.core.todo.TodoValidation
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/TodoStoreTests.swift: the file's shape, the order of the list, carry-over, completion, the Pro
 * rule, the labels, the capture timing, saved as said then sorted, Keep as one and the due-time plan. The coordinated
 * file cases (a second process, the set-aside copy) run on DataStore in :app's TodoFileTests.
 */
class TodoStoreTests {

    /** A due as the old tests wrote it: a moment with a time, or the London calendar date of a day-only one. */
    private fun make(date: Instant, hasTime: Boolean): TodoDue =
        if (hasTime) TodoDue.Time(date) else TodoDue.Day(DayKey.calendarDateOf(date, london))

    // MARK: Store

    @Test
    fun testRoundTrip() {
        assertEquals(TodoState(), TodoCodec.decode("{}"), "an empty file reads as no tasks")

        val now = at(2026, 10, 13, 9, 41)
        val state = TodoState()
        val added = state.add(
            listOf(
                TodoDraft("Call the dentist", TodoDue.Time(at(2026, 10, 13, 16))),
                TodoDraft("Renew the passport", TodoDue.Day(DayKey(2026, 10, 16))),
                TodoDraft("Buy milk"),
            ),
            at = now,
        )
        state.complete(added[2].id, at(2026, 10, 13, 10))
        assertEquals(now, state.firstNoteAt, "the first note is remembered")
        assertEquals(listOf(0, 1, 2), added.map { it.order }, "a note keeps the order it was said in")
        assertEquals(1, added.map { it.noteId }.toSet().size, "one note, one id")

        val text = TodoCodec.encode(state)
        assertEquals(state, TodoCodec.decode(text, london))
        assertEquals(state, TodoCodec.decode(TodoCodec.encode(TodoCodec.decode(text, london)), london), "a second reader sees the same tasks")
        assertTrue(text.contains("\"dueDay\":\"2026-10-16\""), "a day alone is stored as that date: $text")
        assertFalse(text.contains("hasTime"), text)
        assertTrue(text.contains(added[0].id.toString().uppercase()), "UUIDs as the iPhone writes them")
    }

    @Test
    fun testUpdateIsCoordinatedAndReturnsItsValue() {
        // On Android the coordination is DataStore's updateData (:app TodoFileTests); the change itself returns its value.
        val state = TodoState()
        val added = state.add(listOf(TodoDraft("Email Sam the deck")), at = at(2026, 10, 13, 9))
        assertEquals("Email Sam the deck", added.firstOrNull()?.title)
        assertEquals(1, TodoCodec.decode(TodoCodec.encode(state)).tasks.size)
    }

    @Test
    fun testDecodesOlderAndNewerFiles() {
        // Fields missing (an earlier version) or unknown (a later one) never cost a task; one unreadable task never
        // costs the others.
        val json = """
            {"tasks":[
              {"id":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","title":"Call the dentist","createdAt":1791000000},
              {"id":"7A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","title":"Buy milk","dueDate":1791100000,"hasTime":true,
               "createdAt":1791000000,"completedAt":1791050000,"noteId":"8A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F",
               "order":1,"colour":"red"},
              {"id":"9A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","title":"No due date","hasTime":true,"createdAt":1791000000},
              {"title":"","createdAt":1791000000},
              {"id":12,"title":"Broken id"}
            ],"futureKey":true}
        """.trimIndent()
        val state = TodoCodec.decode(json, london)
        assertEquals(listOf("Call the dentist", "Buy milk", "No due date"), state.tasks.map { it.title })
        val first = state.tasks[0]
        assertNull(first.due)
        assertFalse(first.hasTime)
        assertNull(first.completedAt)
        assertEquals(first.id, first.noteId, "a task saved without a note is its own note")
        assertEquals(0, first.order)
        assertTrue(state.tasks[1].hasTime, "a file from before 1.1 shipped: dueDate with hasTime is a time")
        assertEquals(TodoDue.Time(Instant.ofEpochSecond(1_791_100_000L)), state.tasks[1].due)
        assertEquals(1, state.tasks[1].order)
        assertNotNull(state.tasks[1].completedAt)
        assertFalse(state.tasks[2].hasTime, "no due date, no time")
        assertNull(state.firstNoteAt)
        assertEquals(1, state.schemaVersion)
        assertEquals(TodoState(), TodoCodec.decode("{}"))

        val current = """
            {"tasks":[
              {"id":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","title":"Call Sam","dueAt":1791100000,"createdAt":1791000000},
              {"id":"7A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","title":"Renew the passport","dueDay":"2026-10-16","createdAt":1791000000},
              {"id":"8A1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","title":"Bad day","dueDay":"2026-02-31","createdAt":1791000000}
            ]}
        """.trimIndent()
        val tasks = TodoCodec.decode(current, london).tasks
        assertEquals(TodoDue.Time(Instant.ofEpochSecond(1_791_100_000L)), tasks[0].due)
        assertEquals(TodoDue.Day(DayKey(2026, 10, 16)), tasks[1].due)
        assertNull(tasks[2].due, "a day that does not exist is no due date, and the task stays")
    }

    @Test
    fun testUnreadableFileIsKeptAsideNotOverwritten() {
        // The codec refuses a file that is not JSON; :app's TodoFileTests checks DataStore sets it aside, never silently
        // overwritten.
        kotlin.test.assertFailsWith<com.tombaxter.taken.core.model.JsonShapeException> { TodoCodec.decode("not json") }
        kotlin.test.assertFailsWith<com.tombaxter.taken.core.model.JsonShapeException> { TodoCodec.decode("[1,2]") }
    }

    @Test
    fun testTheIPhonesListValuesAreReadPastAndNotWritten() {
        // SPEC-ANDROID 5.2: the 1.1 internal builds' area, lastArea and areaOrder are left out on Android.
        val json = """{"areaOrder":["work","personal"],"lastArea":"work","schemaVersion":1,"tasks":[
            {"area":"work","createdAt":1791000000,"id":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","noteId":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","order":0,"title":"LinkedIn ICP"}]}"""
        val state = TodoCodec.decode(json)
        assertEquals(listOf("LinkedIn ICP"), state.tasks.map { it.title })
        val text = TodoCodec.encode(state)
        assertFalse(text.contains("area"), text)
        // The written tree is the iPhone's, key for key, minus those.
        val tree = TakenJson.parse(text).toString()
        assertEquals(
            TakenJson.parse("""{"schemaVersion":1,"tasks":[{"createdAt":1791000000,"id":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","noteId":"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F","order":0,"title":"LinkedIn ICP"}]}""").toString(),
            tree,
        )
    }

    // MARK: Order

    @Test
    fun testDueFirstSoonestFirstThenTheNewestNoteInTheOrderSaid() {
        val clock = londonClock()
        val morning = UUID.randomUUID()
        val evening = UUID.randomUUID()
        val early = at(2026, 10, 13, 8)
        val late = at(2026, 10, 13, 18)
        val tasks = listOf(
            TodoTask(title = "Morning first", createdAt = early, noteId = morning, order = 0),
            TodoTask(title = "Morning second", createdAt = early, noteId = morning, order = 1),
            TodoTask(title = "Tomorrow, any time", due = TodoDue.Day(DayKey(2026, 10, 14)), createdAt = early, noteId = morning, order = 2),
            TodoTask(title = "Tomorrow 09:00", due = TodoDue.Time(at(2026, 10, 14, 9)), createdAt = late, noteId = evening, order = 0),
            TodoTask(title = "Today 16:00", due = TodoDue.Time(at(2026, 10, 13, 16)), createdAt = late, noteId = evening, order = 1),
            TodoTask(title = "Evening, no time", createdAt = late, noteId = evening, order = 2),
            TodoTask(title = "Tomorrow 23:00", due = TodoDue.Time(at(2026, 10, 14, 23)), createdAt = late, noteId = evening, order = 3),
        )
        assertEquals(
            listOf("Today 16:00", "Tomorrow 09:00", "Tomorrow 23:00", "Tomorrow, any time", "Evening, no time", "Morning first", "Morning second"),
            TodoState(tasks = tasks).openTasks(clock).map { it.title },
        )
    }

    // MARK: Carry-over and completion

    @Test
    fun testOpenTasksCarryOverAndDoneTodayIsTheDayBeingLived() {
        val clock = londonClock()
        val state = TodoState()
        val yesterday = state.add(listOf(TodoDraft("Yesterday, still open"), TodoDraft("Yesterday, done")), at = at(2026, 10, 12, 9))
        state.complete(yesterday[1].id, at(2026, 10, 12, 20))
        val today = state.add(listOf(TodoDraft("Done this morning"), TodoDraft("Done after midnight")), at = at(2026, 10, 13, 9))
        state.complete(today[0].id, at(2026, 10, 13, 10))
        // 01:30 on the 14th is still the 13th with the day starting at 04:00, as it is for doses.
        state.complete(today[1].id, at(2026, 10, 14, 1, 30))

        val day = clock.day(at(2026, 10, 13, 21))
        assertEquals(listOf("Yesterday, still open"), state.openTasks(clock).map { it.title }, "yesterday's open tasks stay until they are done")
        assertEquals(listOf("Done after midnight", "Done this morning"), state.doneTasks(day, clock).map { it.title }, "Done today: newest first")
        assertEquals(listOf("Yesterday, done"), state.doneTasks(day.adding(-1), clock).map { it.title })
    }

    @Test
    fun testCompleteReopenEditDeleteAndRestore() {
        val state = TodoState()
        val id = state.add(listOf(TodoDraft("Call the dentist")), at = at(2026, 10, 13, 9))[0].id

        state.complete(id, at(2026, 10, 13, 10))
        state.complete(id, at(2026, 10, 13, 11))
        assertEquals(at(2026, 10, 13, 10), state.task(id)?.completedAt, "done twice keeps the first time")
        state.reopen(id)
        assertNull(state.task(id)?.completedAt, "a tap on the check opens it again")

        state.update(id, "  call the dentist about the filling. ", TodoDue.Time(at(2026, 10, 14, 9)))
        assertEquals("Call the dentist about the filling", state.task(id)?.title)
        assertEquals(TodoDue.Time(at(2026, 10, 14, 9)), state.task(id)?.due)
        assertEquals(true, state.task(id)?.hasTime)
        state.update(id, "   ", null)
        assertEquals("Call the dentist about the filling", state.task(id)?.title, "an empty title keeps the old one")
        assertNull(state.task(id)?.due)
        assertEquals(false, state.task(id)?.hasTime, "no due date, no time")

        val removed = assertNotNull(state.delete(id))
        assertNull(state.task(id))
        state.restore(removed)
        state.restore(removed)
        assertEquals(1, state.tasks.count { it.id == id }, "UNDO puts it back once")
    }

    @Test
    fun testOldDoneTasksArePrunedAndEraseNeverGivesTheFirstNoteBack() {
        val state = TodoState()
        val september = state.add(listOf(TodoDraft("Old and done"), TodoDraft("Old and open")), at = at(2026, 9, 1, 9))
        state.complete(september[0].id, at(2026, 9, 1, 10))
        state.add(listOf(TodoDraft("New")), at = at(2026, 10, 13, 9))
        assertEquals(listOf("Old and open", "New"), state.tasks.map { it.title }, "done more than 30 days ago is dropped; an open task never is")
        assertEquals(at(2026, 9, 1, 9), state.firstNoteAt, "the first note, not the latest")

        state.eraseAll()
        assertTrue(state.tasks.isEmpty())
        assertEquals(at(2026, 9, 1, 9), state.firstNoteAt, "erasing never opens the first note again")
    }

    @Test
    fun testAnEmptyNoteIsNotTheFirstNote() {
        val state = TodoState()
        assertTrue(state.add(emptyList(), at = at(2026, 10, 13, 9)).isEmpty())
        assertNull(state.firstNoteAt)
    }

    // MARK: Taken Pro

    @Test
    fun testTheFirstVoiceNoteNeedsNoProAfterThatTheMicDoes() {
        val now = at(2026, 10, 13, 9)
        assertEquals(ProAccess.FIRST_SESSION, TodoGate.access(null, null, settled = true, legacyLog = false, now = now), "the first note is on the house")
        assertEquals(ProAccess.LOCKED, TodoGate.access(now, null, settled = true, legacyLog = false, now = now))
        assertEquals(ProAccess.LOCKED, TodoGate.access(now, ProStatus.notPro(now), settled = true, legacyLog = false, now = now))
        val lifetime = ProStatus(isPro = true, reason = ProReason.LIFETIME, checkedAt = now)
        assertEquals(ProAccess.PRO, TodoGate.access(now, lifetime, settled = true, legacyLog = false, now = now))
        val ended = ProStatus(isPro = true, reason = ProReason.MONTHLY, checkedAt = now, expiresAt = at(2026, 10, 1, 9), willRenew = false)
        assertEquals(ProAccess.LOCKED, TodoGate.access(now, ended, settled = true, legacyLog = false, now = now))
        assertEquals(ProAccess.CHECKING, TodoGate.access(now, null, settled = false, legacyLog = false, now = now), "never locked before the store's first answer")
        assertEquals(ProAccess.PENDING, TodoGate.access(now, null, settled = true, legacyLog = true, now = now), "a log from 1.0 is never locked out on a guess")
    }

    // MARK: Reading

    @Test
    fun testDueLabels() {
        val clock = londonClock()
        val now = at(2026, 10, 13, 9, 41) // Tuesday
        fun label(due: Instant?, hasTime: Boolean, now: Instant = at(2026, 10, 13, 9, 41)): String? =
            TodoText.dueLabel(TodoTask(title = "x", due = due?.let { make(it, hasTime) }, createdAt = now, noteId = UUID.randomUUID()), now, clock)
        assertNull(label(null, false))
        assertEquals("16:00", label(at(2026, 10, 13, 16), true))
        assertEquals("Today", label(at(2026, 10, 13, 12), false))
        assertEquals("Tomorrow 09:00", label(at(2026, 10, 14, 9), true))
        assertEquals("Tomorrow", label(at(2026, 10, 14, 12), false))
        assertEquals("Fri", label(at(2026, 10, 16, 12), false))
        assertEquals("Fri 14:30", label(at(2026, 10, 16, 14, 30), true))
        assertEquals("25 Oct", label(at(2026, 10, 25, 12), false))
        assertEquals("Yesterday", label(at(2026, 10, 12, 12), false))
        // 01:30 on Wednesday is still Tuesday's day: Wednesday 09:00 is tomorrow, Wednesday 02:00 is today.
        val late = at(2026, 10, 14, 1, 30)
        assertEquals("Tomorrow 09:00", label(at(2026, 10, 14, 9), true, late))
        assertEquals("02:00", label(at(2026, 10, 14, 2), true, late))

        fun overdue(due: Instant, hasTime: Boolean): Boolean =
            TodoText.isOverdue(TodoTask(title = "x", due = make(due, hasTime), createdAt = now, noteId = UUID.randomUUID()), now, clock)
        assertTrue(overdue(at(2026, 10, 13, 9), true))
        assertFalse(overdue(at(2026, 10, 13, 10), true))
        assertFalse(overdue(at(2026, 10, 13, 12), false), "today, any time, is not late yet")
        assertTrue(overdue(at(2026, 10, 12, 12), false))

        // TalkBack's words, in the phone's own time style.
        val tomorrow = TodoTask(title = "x", due = TodoDue.Time(at(2026, 10, 14, 9)), createdAt = now, noteId = UUID.randomUUID())
        assertEquals("due tomorrow at 9:00 AM", TodoText.spokenDue(tomorrow, now, clock, enUS))
        val today = TodoTask(title = "x", due = TodoDue.Time(at(2026, 10, 13, 16)), createdAt = now, noteId = UUID.randomUUID())
        assertEquals("due at 4:00 PM", TodoText.spokenDue(today, now, clock, enUS))
        val day = TodoTask(title = "x", due = TodoDue.Day(DayKey(2026, 10, 16)), createdAt = now, noteId = UUID.randomUUID())
        assertEquals("due fri", TodoText.spokenDue(day, now, clock, enUS))
    }

    @Test
    fun testDueTimeRemindersOnlyForOpenTasksWithATimeStillToCome() {
        val now = at(2026, 10, 13, 9, 41)
        val tasks = listOf(
            TodoTask(title = "Call the dentist", due = TodoDue.Time(at(2026, 10, 13, 16)), createdAt = now, noteId = UUID.randomUUID()),
            TodoTask(title = "Already past", due = TodoDue.Time(at(2026, 10, 13, 9)), createdAt = now, noteId = UUID.randomUUID()),
            TodoTask(title = "Any time tomorrow", due = TodoDue.Day(DayKey(2026, 10, 14)), createdAt = now, noteId = UUID.randomUUID()),
            TodoTask(title = "Done", due = TodoDue.Time(at(2026, 10, 13, 18)), createdAt = now, completedAt = now, noteId = UUID.randomUUID()),
            TodoTask(title = "Tomorrow at nine", due = TodoDue.Time(at(2026, 10, 14, 9)), createdAt = now, noteId = UUID.randomUUID()),
        )
        val plans = TodoNotifications.plan(tasks, now, londonClock())
        assertEquals(listOf("Call the dentist", "Tomorrow at nine"), plans.map { it.title })
        assertEquals(at(2026, 10, 13, 16), plans.first().fireDate)
        assertEquals("Due 16:00", plans.first().body)
        assertTrue(plans.all { TodoNotifications.isTodo(it.identifier) })
        assertFalse(TodoNotifications.isTodo(Reminders.REQUEST_PREFIX + "20738"), "never the nudge's")
    }

    @Test
    fun testATapFinishesANoteAndOnlyThirtySecondsOfQuietOrFiveMinutesStopIt() {
        val start = Instant.ofEpochSecond(1_000_000)
        fun stop(now: Double, lastVoice: Double): TodoStopReason? =
            TodoCapture.shouldStop(start.plusMillis((now * 1000).toLong()), start, start.plusMillis((lastVoice * 1000).toLong()))
        assertNull(stop(12.0, 10.0), "2 s of quiet after words: still listening")
        assertNull(stop(20.0, 10.0), "10 s")
        assertNull(stop(39.9, 10.0), "29.9 s")
        assertNull(stop(29.9, 0.0), "29.9 s with nothing said")
        assertEquals(TodoStopReason.QUIET, stop(30.0, 0.0), "30 s with nothing said")
        assertEquals(TodoStopReason.QUIET, stop(70.0, 40.0), "30 s of quiet after words")
        assertNull(stop(299.0, 298.9), "talking at 4:59")
        assertEquals(TodoStopReason.CAP, stop(300.0, 299.9), "5 minutes at most, even mid-sentence")
        assertFalse(TodoCapture.capWarning(Duration.ofMillis(239_900)))
        assertTrue(TodoCapture.capWarning(Duration.ofSeconds(240)), "1 minute left from 4:00")
        assertEquals(Duration.ofSeconds(30), TodoCapture.SILENCE_TO_STOP)
        assertEquals(Duration.ofSeconds(300), TodoCapture.LONGEST_NOTE)
    }

    @Test
    fun testTheListeningCardSaysOneMinuteLeftOnceAndTheScreenStaysOn() {
        assertEquals("1 minute left", TodoCopy.ONE_MINUTE_LEFT)
        assertEquals("Listening", TodoCopy.LISTENING)
        assertEquals("Sorting into to-dos", TodoCopy.SORTING)
        assertEquals("Say what you need to do", TodoCopy.SAY_IT)
        assertEquals("part 2 of 5", TodoCopy.part(2, 5))
        assertFalse(TodoCopy.all.any { Regex("\\d:\\d\\d").containsMatchIn(it) }, "no running time and no countdown anywhere in the copy")
        for (text in listOf(TodoCopy.ONE_MINUTE_LEFT, TodoCopy.STOPPED_AT_CAP, TodoCopy.part(2, 5))) {
            assertTrue(text in TodoCopy.all, "$text is checked by the copy test")
        }
        assertEquals("Stopped at 5 minutes. Tap the mic to keep going.", TodoCopy.STOPPED_AT_CAP)

        assertTrue(TodoCapture.keepsScreenOn(TodoCapture.Phase.STARTING, isDemo = false))
        assertTrue(TodoCapture.keepsScreenOn(TodoCapture.Phase.LISTENING, isDemo = false))
        assertFalse(TodoCapture.keepsScreenOn(TodoCapture.Phase.SORTING, isDemo = false), "never once the note is heard")
        assertFalse(TodoCapture.keepsScreenOn(TodoCapture.Phase.IDLE, isDemo = false))
        assertFalse(TodoCapture.keepsScreenOn(TodoCapture.Phase.LISTENING, isDemo = true), "never in the demo")
        assertEquals("short", TodoCapture.tail("short"))
        val long = (1..100).joinToString(" ") { "word$it" }
        val tail = TodoCapture.tail(long)
        assertTrue(tail.startsWith("\u2026 word"), tail)
        assertTrue(tail.endsWith("word100"))
        assertTrue(tail.length <= TodoCapture.SHOWN_CHARACTERS + 2, "only the end of a long note")
    }

    @Test
    fun testTheNoiseFloorAndTheRingFollowTheIPhonesMaths() {
        // Taken/Todo/TodoModel.swift `handle(.level)`: the floor drops at once and rises by 0.4% of the gap.
        assertEquals(-70f, TodoCapture.nextNoiseFloor(-60f, -70f))
        assertEquals(-60f + 40f * 0.004f, TodoCapture.nextNoiseFloor(-60f, -20f))
        assertTrue(TodoCapture.isVoice(-45f, -60f), "15 dB above the room")
        assertFalse(TodoCapture.isVoice(-55f, -60f), "5 dB above the room")
        assertFalse(TodoCapture.isVoice(-51f, -70f), "never below -50 dBFS")
        assertEquals(0.0, TodoCapture.ringLevel(-80f))
        assertEquals(1.0, TodoCapture.ringLevel(0f))
        assertEquals(0.5, TodoCapture.ringLevel(-32.5f), 1e-6)
        // Android's scale is the recognizer's own: the ring reads against the room.
        assertEquals(0.0, TodoCapture.relativeRingLevel(-2f, -2f))
        assertEquals(0.5, TodoCapture.relativeRingLevel(4f, -2f), 1e-6)
        assertEquals(1.0, TodoCapture.relativeRingLevel(30f, -2f))
    }

    // MARK: Days stay days

    @Test
    fun testADayOnlyDueDateIsTheSameDateInEveryTimeZone() {
        // "Renew the passport on Friday", said in Sydney: Friday wherever the phone is later.
        val friday = DayKey(2026, 10, 16)
        val task = TodoTask(title = "Renew the passport", due = TodoDue.Day(friday), createdAt = at(2026, 10, 13, 9), noteId = UUID.randomUUID())
        val sydney = ZoneId.of("Australia/Sydney")
        val losAngeles = ZoneId.of("America/Los_Angeles")
        for (zone in listOf(sydney, losAngeles, london)) {
            val clock = DayClock(4, zone)
            val thursday = ZonedDateTime.of(2026, 10, 15, 10, 0, 0, 0, zone).toInstant()
            assertEquals("Tomorrow", TodoText.dueLabel(task, thursday, clock), zone.id)
            val fridayEvening = ZonedDateTime.of(2026, 10, 16, 20, 0, 0, 0, zone).toInstant()
            assertFalse(TodoText.isOverdue(task, fridayEvening, clock), "${zone.id}: due all Friday")
            val saturday = ZonedDateTime.of(2026, 10, 17, 10, 0, 0, 0, zone).toInstant()
            assertTrue(TodoText.isOverdue(task, saturday, clock), zone.id)
            val sorted = TodoOrdering.sortDate(task, clock)
            assertEquals(friday, sorted?.let { DayKey.calendarDateOf(it, zone) }, "sorted by the end of Friday there")
        }
        val la = DayClock(4, losAngeles)
        val edited = TodoEditRules.savedDue(true, false, TodoEditRules.pickerDate(TodoDue.Day(friday), la, Instant.now()), la)
        assertEquals(TodoDue.Day(friday), edited, "editing keeps the date")
        assertNull(TodoEditRules.savedDue(false, true, Instant.now(), londonClock()))
        assertEquals(at(2026, 10, 14, 9), TodoEditRules.suggestedDue(londonClock(), at(2026, 10, 13, 21, 41)), "a new due starts tomorrow at 09:00")
        assertEquals(at(2026, 10, 16, 9), TodoEditRules.pickerDate(TodoDue.Day(friday), londonClock(), at(2026, 10, 13, 9)))
    }

    // MARK: Saved whole, then sorted

    @Test
    fun testANoteSavedWholeIsReplacedByItsTasks() {
        val now = at(2026, 10, 13, 9)
        val state = TodoState()
        val whole = state.add(TodoValidation.wholeNote("call the dentist and buy milk"), at = now)[0]
        assertEquals(now, state.firstNoteAt, "the whole note is the first note")
        val sorted = state.replaceNote(whole.id, listOf(TodoDraft("Call the dentist", TodoDue.Time(at(2026, 10, 14, 9))), TodoDraft("Buy milk")), now)
        assertEquals(listOf("Call the dentist", "Buy milk"), sorted.map { it.title })
        assertNull(state.task(whole.id), "the whole note goes")
        assertEquals(listOf("Call the dentist", "Buy milk"), state.tasks.map { it.title })
        assertEquals(setOf(whole.noteId), state.tasks.map { it.noteId }.toSet(), "the same note")
        assertEquals(listOf(now, now), state.tasks.map { it.createdAt })
        assertEquals(listOf(0, 1), state.tasks.map { it.order })

        val same = TodoState()
        val note = same.add(listOf(TodoDraft("Sort out the garage")), at = now)[0]
        assertEquals(listOf(note), same.replaceNote(note.id, listOf(TodoDraft("Sort out the garage")), now), "a note kept whole stays as it is")
        assertEquals(listOf(note), same.tasks)

        val gone = TodoState()
        val erased = gone.add(listOf(TodoDraft("Call Sam")), at = now)[0]
        gone.eraseAll()
        assertTrue(gone.replaceNote(erased.id, listOf(TodoDraft("Call Sam")), now).isEmpty(), "erased meanwhile: nothing comes back")
        assertTrue(gone.tasks.isEmpty())

        val changed = TodoState()
        val done = changed.add(listOf(TodoDraft("Call Sam and Kim")), at = now)[0]
        changed.complete(done.id, now)
        assertEquals(listOf(done.id), changed.replaceNote(done.id, listOf(TodoDraft("Call Sam"), TodoDraft("Call Kim")), now).map { it.id }, "a note already done stays as it is")
    }

    @Test
    fun testANoteSavedAsSaidIsReplacedByItsTasksOnlyWhileItsLinesAreUntouched() {
        val now = at(2026, 10, 20, 9)
        val state = TodoState()
        val note = UUID.randomUUID()
        val lines = state.add(TodoValidation.lines("Call the dentist. Buy milk and bread."), note, now)
        assertEquals(listOf("Call the dentist", "Buy milk and bread"), lines.map { it.title }, "every sentence saved at once")
        val sorted = state.replaceNote(note, lines, listOf(TodoDraft("Call the dentist"), TodoDraft("Buy milk"), TodoDraft("Buy bread")), now)
        assertEquals(listOf("Call the dentist", "Buy milk", "Buy bread"), sorted.map { it.title })
        assertEquals(setOf(note), sorted.map { it.noteId }.toSet())
        assertEquals(listOf(0, 1, 2), sorted.map { it.order })
        assertEquals(3, state.tasks.size, "the lines are gone")

        val edited = TodoState()
        val second = UUID.randomUUID()
        val saved = edited.add(listOf(TodoDraft("Call the dentist"), TodoDraft("Buy milk")), second, now)
        edited.update(saved[1].id, "Buy oat milk", null)
        assertEquals(listOf("Call the dentist", "Buy oat milk"), edited.replaceNote(second, saved, listOf(TodoDraft("Call")), now).map { it.title }, "someone edited a line: the note stays")

        val done = TodoState()
        val third = UUID.randomUUID()
        val doneLines = done.add(listOf(TodoDraft("Call the dentist")), third, now)
        done.complete(doneLines[0].id, now)
        assertEquals(listOf(doneLines[0].id), done.replaceNote(third, doneLines, listOf(TodoDraft("Call")), now).map { it.id }, "a line done meanwhile: the note stays")

        val erased = TodoState()
        val fourth = UUID.randomUUID()
        val gone = erased.add(listOf(TodoDraft("Call Sam")), fourth, now)
        erased.eraseAll()
        assertTrue(erased.replaceNote(fourth, gone, listOf(TodoDraft("Call Sam")), now).isEmpty(), "erased meanwhile: nothing comes back")
        assertTrue(erased.tasks.isEmpty())

        val same = TodoState()
        val fifth = UUID.randomUUID()
        val kept = same.add(listOf(TodoDraft("Sort out the garage")), fifth, now)
        assertEquals(kept, same.replaceNote(fifth, kept, listOf(TodoDraft("Sort out the garage")), now), "the sorter kept it as said")
    }

    // MARK: Keep as one

    @Test
    fun testKeepAsOneMergesOnlyTheGivenOpenTasksAndKeepsTheNoteAndTheEarliestDue() {
        val clock = londonClock()
        val now = at(2026, 10, 19, 10)
        val state = TodoState()
        val other = state.add(listOf(TodoDraft("Ring Jo about the lease")), at = at(2026, 10, 19, 8))[0]
        val note = state.add(
            listOf(
                TodoDraft("Reach toothbrushes", TodoDue.Day(DayKey(2026, 10, 21))),
                TodoDraft("Order toothbrushes", TodoDue.Time(at(2026, 10, 20, 9))),
                TodoDraft("Buy floss"),
            ),
            at = now,
        )
        val due = TodoMerge.earliestDue(note.map { it.due }, clock)
        assertEquals(TodoDue.Time(at(2026, 10, 20, 9)), due, "Tuesday 09:00 comes before any time on Wednesday")
        val title = assertNotNull(TodoMerge.title("order Reach toothbrushes on Amazon", note.map { it.title }, hasDue = due != null))
        assertEquals("Order Reach toothbrushes on Amazon", title, "a short note reads as it was said")

        val merged = assertNotNull(state.mergeNote(note.map { it.id }, title, due))
        assertEquals(2, state.tasks.size, "three became one; the other note is untouched")
        assertEquals(other, state.task(other.id))
        assertEquals("Order Reach toothbrushes on Amazon", merged.title)
        assertEquals(TodoDue.Time(at(2026, 10, 20, 9)), merged.due)
        assertEquals(note[0].noteId, merged.noteId, "the same note")
        assertEquals(now, merged.createdAt, "said when the note was said")
        assertEquals(0, merged.order)
        assertEquals(note[0].id, merged.id, "the first task's row stays where it was")
        assertNull(state.task(note[1].id))
        assertNull(state.task(note[2].id))
        assertFalse(merged.isDone)
        assertNull(state.mergeNote(note.map { it.id }, title, due), "once only")
    }

    @Test
    fun testKeepAsOneLeavesTheListAloneWhenATaskWasDoneOrDeleted() {
        val now = at(2026, 10, 19, 10)
        val done = TodoState()
        val first = done.add(listOf(TodoDraft("Call the dentist"), TodoDraft("Email Priya the deck")), at = now)
        done.complete(first[1].id, now)
        val before = done.clone()
        assertNull(done.mergeNote(first.map { it.id }, "Call the dentist and email Priya", null))
        assertEquals(before, done, "one was done meanwhile: nothing changes")

        val deleted = TodoState()
        val second = deleted.add(listOf(TodoDraft("Call the dentist"), TodoDraft("Email Priya the deck")), at = now)
        deleted.delete(second[0].id)
        val left = deleted.clone()
        assertNull(deleted.mergeNote(second.map { it.id }, "Call the dentist and email Priya", null))
        assertEquals(left, deleted, "one was deleted meanwhile: nothing changes")

        val mixed = TodoState()
        val a = mixed.add(listOf(TodoDraft("Call the dentist")), at = now)[0]
        val b = mixed.add(listOf(TodoDraft("Buy milk")), at = now)[0]
        assertNull(mixed.mergeNote(listOf(a.id, b.id), "Call the dentist, Buy milk", null), "two notes are never merged")
        assertNull(mixed.mergeNote(listOf(a.id), "Call the dentist", null), "one task is already one")
        assertEquals(2, mixed.tasks.size)
    }

    @Test
    fun testKeepAsOneTitleIsTheWordsSaidForAShortNoteOtherwiseTheTitlesJoined() {
        val ab = listOf("A", "B")
        assertEquals("Order Reach toothbrushes on Amazon", TodoMerge.title("  um order Reach toothbrushes on Amazon. ", ab, false), "leading filler goes")
        assertEquals("Order Reach toothbrushes and floss", TodoMerge.title("Um so I need to order Reach toothbrushes and floss", ab, false))
        assertEquals("Order Reach toothbrushes on Amazon", TodoMerge.title("Order. Reach toothbrushes on Amazon.", ab, false), "a pause inside the note is not kept")
        assertEquals("Buy milk, eggs and bread", TodoMerge.title("buy milk, eggs and bread", ab, false), "a list keeps its commas")
        assertEquals("Call the dentist and buy milk", TodoMerge.title("Tomorrow at 9 call the dentist and buy milk", ab, true), "the due date carries the day and time")
        assertEquals("Tomorrow at 9 call the dentist and buy milk", TodoMerge.title("Tomorrow at 9 call the dentist and buy milk", ab, false), "with no due date, the day stays")
        val long = "so I need to call the dentist and also email Priya the deck and then buy milk eggs and bread"
        assertEquals(
            "Call the dentist, Email Priya the deck, Buy milk",
            TodoMerge.title(long, listOf("Call the dentist", "Email Priya the deck", "Buy milk"), false),
            "past 12 words: the titles, joined",
        )
        val titles = List(4) { "Pick up the parcel from the post office on the high street" }
        val joined = TodoMerge.title(long, titles, false) ?: ""
        assertTrue(joined.length <= TodoText.MAX_TITLE_LENGTH, "never a paragraph")
        assertNull(TodoMerge.earliestDue(listOf(null, null), londonClock()))
        assertEquals(
            TodoDue.Day(DayKey(2026, 10, 20)),
            TodoMerge.earliestDue(listOf(null, TodoDue.Day(DayKey(2026, 10, 22)), TodoDue.Day(DayKey(2026, 10, 20))), londonClock()),
        )
    }

    // MARK: Notifications

    @Test
    fun testDeliveredNotificationsForFinishedOrDeletedTasksAreWithdrawn() {
        val now = at(2026, 10, 13, 9)
        val open = TodoTask(title = "Open", due = TodoDue.Time(at(2026, 10, 13, 8)), createdAt = now, noteId = UUID.randomUUID())
        val done = TodoTask(title = "Done", due = TodoDue.Time(at(2026, 10, 13, 8)), createdAt = now, completedAt = now, noteId = UUID.randomUUID())
        val deleted = UUID.randomUUID()
        val delivered = listOf(
            TodoNotifications.identifier(open.id), TodoNotifications.identifier(done.id), TodoNotifications.identifier(deleted),
            Reminders.REQUEST_PREFIX + "20738",
        )
        assertEquals(
            listOf(TodoNotifications.identifier(done.id), TodoNotifications.identifier(deleted)),
            TodoNotifications.staleDelivered(delivered, listOf(open, done)),
            "an open task's stays; the nudge's is never touched",
        )
        assertEquals(open.id, TodoNotifications.taskId(TodoNotifications.identifier(open.id)))
        assertNull(TodoNotifications.taskId("taken.nudge.2026-10-19"))
    }

    /** What a test scheduler ran, and how many at once. */
    private class RebuildLog {
        val runs = java.util.Collections.synchronizedList(ArrayList<Int>())
        @Volatile var mostAtOnce = 0
        private var running = 0

        @Synchronized fun begin(count: Int) {
            running += 1
            mostAtOnce = maxOf(mostAtOnce, running)
            runs.add(count)
        }

        @Synchronized fun end() {
            running -= 1
        }
    }

    @Test
    fun testRebuildsRunOneAtATimeAndTheNewestWins() = runBlocking {
        // Two checks a moment apart must never interleave and leave a done task's notification scheduled. A rebuild never
        // overlaps another, and a request made while one runs replaces any waiting one.
        val log = RebuildLog()
        val scheduler = TodoNotificationScheduler { tasks ->
            log.begin(tasks.size)
            delay(600)
            log.end()
        }
        val call = TodoTask(title = "Call Sam", due = TodoDue.Time(at(2026, 10, 13, 16)), createdAt = at(2026, 10, 13, 9), noteId = UUID.randomUUID())
        val milk = TodoTask(title = "Buy milk", createdAt = at(2026, 10, 13, 9), noteId = UUID.randomUUID())
        val first = async(kotlinx.coroutines.Dispatchers.Default) { scheduler.reschedule(listOf(call)) }
        while (log.runs.isEmpty()) delay(5)
        scheduler.reschedule(listOf(call, milk))
        scheduler.reschedule(emptyList())
        first.await()
        assertEquals(listOf(1, 0), log.runs.toList(), "the waiting request was replaced by the newest one")
        assertEquals(1, log.mostAtOnce, "never two rebuilds at once")
    }
}
