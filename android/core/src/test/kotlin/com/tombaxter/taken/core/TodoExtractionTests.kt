package com.tombaxter.taken.core

import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.pro.ProRoute
import com.tombaxter.taken.core.todo.ChunkSorting
import com.tombaxter.taken.core.todo.FallbackSorter
import com.tombaxter.taken.core.todo.NoteSorter
import com.tombaxter.taken.core.todo.RawTodo
import com.tombaxter.taken.core.todo.SpokenNote
import com.tombaxter.taken.core.todo.TodoCaptureRoute
import com.tombaxter.taken.core.todo.TodoChunk
import com.tombaxter.taken.core.todo.TodoContext
import com.tombaxter.taken.core.todo.TodoCopy
import com.tombaxter.taken.core.todo.TodoDraft
import com.tombaxter.taken.core.todo.TodoDue
import com.tombaxter.taken.core.todo.TodoNotifications
import com.tombaxter.taken.core.todo.TodoPrompt
import com.tombaxter.taken.core.todo.TodoSorting
import com.tombaxter.taken.core.todo.TodoTask
import com.tombaxter.taken.core.todo.TodoText
import com.tombaxter.taken.core.todo.TodoValidation
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import java.time.Duration
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/TodoExtractionTests.swift: the layer between a model and what is saved, fed canned answers in
 * the guided generation's shape. Left out, as SPEC-ANDROID 8.2 says: the Apple Intelligence lines (Android shows one line,
 * "Saved as you said it, one line per sentence"), the Info.plist strings and the Siri intent. The quick capture links
 * test runs on the Android route.
 */
class TodoExtractionTests {
    /** Tuesday 13 October 2026, 09:41 in London, the day starting at 04:00. */
    private val context = TodoContext(at(2026, 10, 13, 9, 41), london, 4)

    @Test
    fun testACannedAnswerBecomesTasks() {
        val json = """
            {"tasks":[
              {"title":"call the dentist","dueISO8601":"2026-10-13T16:00:00","hasTime":true},
              {"title":"Pick up the dry cleaning.","dueISO8601":"2026-10-13T16:00","hasTime":true},
              {"title":"- email Sam the deck","dueISO8601":"2026-10-14","hasTime":false},
              {"title":"Book flights for March","dueISO8601":null,"hasTime":false}
            ]}
        """.trimIndent()
        val raw = assertNotNull(TodoValidation.decode(json))
        val drafts = TodoValidation.validate(raw, "today by 4 call the dentist ...", context)
        assertEquals(listOf("Call the dentist", "Pick up the dry cleaning", "Email Sam the deck", "Book flights for March"), drafts.map { it.title })
        assertEquals(TodoDue.Time(at(2026, 10, 13, 16)), drafts[0].due)
        assertEquals(TodoDue.Time(at(2026, 10, 13, 16)), drafts[1].due)
        assertEquals(TodoDue.Day(DayKey(2026, 10, 14)), drafts[2].due, "a day alone is that date")
        assertNull(drafts[3].due)
    }

    @Test
    fun testCannedAnswersInOtherShapesDecode() {
        assertEquals(listOf(RawTodo(title = "Buy milk")), TodoValidation.decode("""[{"title":"Buy milk"}]"""))
        assertEquals("2026-10-14", TodoValidation.decode("""{"tasks":[{"title":"Call Sam","due":"2026-10-14"}]}""")?.firstOrNull()?.dueISO8601)
        assertEquals(emptyList<RawTodo>(), TodoValidation.decode("""{"tasks":[]}"""))
        assertNull(TodoValidation.decode("not json"))
    }

    @Test
    fun testDatesAreCheckedNeverTrusted() {
        /** The moment of a timed answer, or the London noon of a day alone (so both read as dates here). */
        fun due(text: String, hasTime: Boolean = true): Instant? = when (val parsed = TodoValidation.parseDue(text, hasTime, context)) {
            is TodoDue.Time -> parsed.at
            is TodoDue.Day -> at(parsed.day.ymd.year, parsed.day.ymd.month, parsed.day.ymd.day, 12)
            null -> null
        }
        assertEquals(at(2026, 10, 13, 15), due("2026-10-13T16:00:00+02:00"), "an offset is honoured")
        assertEquals(at(2026, 10, 13, 16), due("2026-10-13T15:00:00Z"), "UTC")
        assertEquals(at(2026, 10, 13, 16), due("2026-10-13T15:00:00.000Z"))
        assertEquals(at(2026, 10, 13, 16), due("2026-10-13 16:00"))
        assertEquals(at(2026, 10, 13, 16), due(" 2026-10-13T16:00:00 "))
        assertEquals(TodoDue.Day(DayKey(2026, 10, 14)), TodoValidation.parseDue("2026-10-14T00:00:00", false, context), "midnight with no time said is a day")
        assertEquals(TodoDue.Day(DayKey(2026, 10, 14)), TodoValidation.parseDue("2026-10-14", true, context), "no time written, no time kept")
        assertEquals(at(2026, 10, 14, 8), due("2026-10-13T08:00:00"), "a time already gone today means that time tomorrow")
        assertEquals(at(2026, 10, 13, 9, 35), due("2026-10-13T09:35:00"), "six minutes ago is the time meant")
        assertNull(due("2026-10-12T08:00:00"), "more than a day in the past")
        assertNotNull(due("2026-10-12", false), "yesterday, said late at night")
        assertNull(due("2026-10-11", false), "the day before yesterday")
        assertNull(due("2062-10-13T16:00:00"), "a wrong year")
        assertNull(due("2027-12-01", false), "more than a year ahead")
        assertNull(due("2026-11-31", false), "a day that does not exist")
        assertNull(due("2026-13-01", false))
        assertNull(due("2026-10-13T25:00:00"))
        assertNull(due("2026-10-13T16:75:00"))
        assertNull(due("2026-10-13T16:00:00+25:00"))
        assertNull(due("tomorrow"))
        assertNull(due(""))
    }

    @Test
    fun testTitlesAreCleanedDedupedAndCapped() {
        val raw = listOf(
            RawTodo(title = "  1. call   the dentist  "),
            RawTodo(title = "Call the dentist."),
            RawTodo(title = "“Buy milk”"),
            RawTodo(title = "   "),
            RawTodo(title = "Call Sam", dueISO8601 = "2026-10-13T16:00:00", hasTime = true),
            RawTodo(title = "Call Sam", dueISO8601 = "2026-10-14T16:00:00", hasTime = true),
            RawTodo(title = "word ".repeat(60)),
        )
        val drafts = TodoValidation.validate(raw, "x", context)
        assertEquals(listOf("Call the dentist", "Buy milk", "Call Sam", "Call Sam"), drafts.map { it.title }.take(4), "the same words due at two times are two tasks")
        assertEquals(5, drafts.size)
        assertTrue(drafts[4].title.length <= TodoText.MAX_TITLE_LENGTH)

        assertEquals(80, TodoValidation.MAX_TASKS)
        val many = (1..90).map { RawTodo(title = "Task $it") }
        assertEquals(TodoValidation.MAX_TASKS, TodoValidation.validate(many, "x", context).size)
    }

    @Test
    fun testAnEmptyAnswerKeepsTheNoteAsSaid() = runBlocking {
        val drafts = TodoValidation.validate(emptyList(), "  um so I need to sort out the garage  ", context)
        assertEquals(listOf("Sort out the garage"), drafts.map { it.title })
        assertNull(drafts.firstOrNull()?.due)
        assertTrue(TodoValidation.validate(emptyList(), "   ", context).isEmpty(), "no words, no task")
        assertEquals(listOf("Um, okay"), TodoValidation.validate(emptyList(), "um, okay", context).map { it.title }, "only filler: kept whole")

        val words = "call mum and buy milk"
        val parts = NoteSorter(FallbackSorter(), context).finish(words)
        val fallback = TodoValidation.assemble(words, parts, context)
        assertEquals(listOf("Call mum and buy milk"), fallback.drafts.map { it.title }, "no model: a one-sentence note is one task")
        assertEquals(TodoSorting.NO_MODEL, fallback.sorting)
        assertEquals("Saved as you said it, one line per sentence. Tap one to edit.", TodoCopy.sortingNote(fallback.sorting), "Android's one line (SPEC-ANDROID 6.4)")

        val long = "and then the next thing ".repeat(40)
        val whole = TodoValidation.wholeNote(long)
        assertEquals(1, whole.size)
        assertTrue(whole[0].title.length <= TodoValidation.MAX_NOTE_LENGTH)
    }

    @Test
    fun testLinesKeepEveryWordOfALongNoteInShortLines() {
        val text = StringBuilder()
        for (index in 1..900) text.append("word$index").append(if (index % 15 == 0) ". " else if (index % 40 == 0) ", " else " ")
        val lines = TodoValidation.lines(text.toString())
        val kept = lines.flatMap { SpokenNote.tokens(it.title) }.toSet()
        assertTrue((1..900).all { "word$it" in kept }, "every word of a 900-word note")
        assertTrue(lines.all { it.title.length <= TodoText.MAX_TITLE_LENGTH })
        assertTrue(lines.all { it.due == null }, "no due nobody checked")

        val run = (1..60).joinToString(" ") { "longword$it" }
        val carried = TodoValidation.lines(run)
        assertTrue(carried.size > 1, "a line over 120 characters carries on")
        assertTrue(carried.all { it.title.length <= TodoText.MAX_TITLE_LENGTH })
        val words = carried.flatMap { SpokenNote.tokens(it.title) }.toSet()
        assertTrue((1..60).all { "longword$it" in words }, "never cut off")

        assertEquals(listOf("Call mum", "Buy milk"), TodoValidation.lines("Call mum. Buy milk. Um. Okay.").map { it.title }, "filler on its own is skipped")
        assertEquals(
            listOf("Call the dentist", "Email Sam about the deck", "Buy milk, eggs and bread"),
            TodoValidation.lines("so I need to call the dentist and then email Sam about the deck and also buy milk, eggs and bread").map { it.title },
            "a long sentence in pieces at its separators, a short list kept whole",
        )
        assertEquals(listOf("Tomorrow. Call the bank"), TodoValidation.lines("Tomorrow. Call the bank.").map { it.title }, "a day header stays with what it is for")
        val wifi = "Note to self, the wifi password is on the fridge"
        assertEquals(TodoValidation.wholeNote(wifi), TodoValidation.lines(wifi), "a one-sentence note is one line")
    }

    @Test
    fun testTheNewCopyKeepsTheRules() {
        for (text in listOf(TodoCopy.ALL_UNSORTED, TodoCopy.PART_UNSORTED, TodoCopy.SAY_IT, TodoCopy.DONE_TODAY, TodoCopy.ONE_MINUTE_LEFT)) {
            assertTrue(text in TodoCopy.all, "$text is checked by the copy test")
        }
        assertEquals("Saved as you said it, one line per sentence. Tap one to edit.", TodoCopy.sortingNote(TodoSorting.COULD_NOT_SORT))
        assertEquals("Part of your note was saved as you said it.", TodoCopy.sortingNote(TodoSorting.PARTLY_SORTED))
        assertNull(TodoCopy.sortingNote(TodoSorting.MODEL))
        assertEquals(TodoCopy.ALL_UNSORTED, TodoCopy.sortingNote(TodoSorting.NO_MODEL))
        assertFalse(TodoCopy.all.any { "Apple" in it || "iPhone" in it }, "no Apple words on Android")
        for (text in TodoCopy.all + TodoPrompt.INSTRUCTIONS) assertCopyRules(text)
    }

    @Test
    fun testAClockTimeAlreadyGoneMovesToItsNextOccurrence() {
        // 01:30 on Wednesday with the day starting at 04:00: "today by 4" comes back as Tuesday 16:00; Wednesday was meant.
        val lateNight = TodoContext(at(2026, 10, 14, 1, 30), london, 4)
        assertEquals(TodoDue.Time(at(2026, 10, 14, 16)), TodoValidation.parseDue("2026-10-13T16:00:00", true, lateNight))
        // 21:30: "call Sam at 9" is a bare 9, so the morning, and today's 09:00 has gone: tomorrow at 09:00.
        val evening = TodoContext(at(2026, 10, 13, 21, 30), london, 4)
        assertEquals(TodoDue.Time(at(2026, 10, 14, 9)), TodoValidation.parseDue("2026-10-13T09:00:00", true, evening))
        // Across the clocks going back (25 October 2026 in London): the same wall-clock time the next day.
        val afterChange = TodoContext(at(2026, 10, 25, 8, 30), london, 4)
        assertEquals(TodoDue.Time(at(2026, 10, 25, 10)), TodoValidation.parseDue("2026-10-24T10:00:00", true, afterChange))
        val plan = TodoNotifications.plan(
            listOf(TodoTask(title = "Call Sam", due = TodoDue.Time(at(2026, 10, 14, 9)), createdAt = evening.now, noteId = UUID.randomUUID())),
            evening.now, londonClock(),
        )
        assertEquals(listOf(at(2026, 10, 14, 9)), plan.map { it.fireDate }, "so it gets its notification")
        assertTrue(TodoPrompt.INSTRUCTIONS.contains("already passed today means that time tomorrow"))
    }

    @Test
    fun testTheSortersAnswerIsWhatIsSaved() = runBlocking {
        val stub = object : ChunkSorting {
            override val unavailable: TodoSorting? = null
            override suspend fun prepare() = Unit
            override suspend fun answer(chunk: TodoChunk, prompt: String) =
                listOf(RawTodo("call the dentist", "Call the dentist"), RawTodo("buy milk", "Buy milk"))
        }
        val note = "call the dentist and buy milk"
        val parts = NoteSorter(stub, context).finish(note)
        val sorted = TodoValidation.assemble(note, parts, context)
        assertEquals(listOf("Call the dentist", "Buy milk"), sorted.drafts.map { it.title })
        assertEquals(TodoSorting.MODEL, sorted.sorting)

        // A model that never answers still lets the note be saved, as said.
        val hanging = object : ChunkSorting {
            override val unavailable: TodoSorting? = null
            override suspend fun prepare() = Unit
            override suspend fun answer(chunk: TodoChunk, prompt: String): List<RawTodo> {
                repeat(5) { runCatching { delay(1_000) } }
                return emptyList()
            }
        }
        val started = System.nanoTime()
        val late = NoteSorter(hanging, context, NoteSorter.Budget.STANDARD.scaled(0.02)).finish("call the dentist")
        assertTrue((System.nanoTime() - started) / 1e9 < 2, "the deadline holds")
        val saved = TodoValidation.assemble("call the dentist", late, context)
        assertEquals(listOf("Call the dentist"), saved.drafts.map { it.title })
        assertEquals(TodoSorting.COULD_NOT_SORT, saved.sorting)
    }

    @Test
    fun testAPartOfALongNoteSaysWhichPartItIsAndWhatWasCarried() {
        val chunk = TodoChunk(1, "call the bank and pick up the prescription", 80 until 88, "today by 4", TodoChunk.Cut.END)
        val prompt = TodoPrompt.prompt(chunk, 2, context)
        assertTrue(prompt.contains("Said just before, for the same list: \"today by 4\"."), prompt)
        assertTrue(prompt.endsWith("Voice note, part 2: \"call the bank and pick up the prescription\""), prompt)
        assertFalse(TodoPrompt.prompt(TodoChunk(0, "x", 0 until 1, null, TodoChunk.Cut.END), 1, context).contains("part"), "a note of one part has no part number")
        assertTrue(TodoPrompt.INSTRUCTIONS.contains("starting with the verb, keeping the verb and what it is done to"))
        assertTrue(TodoPrompt.INSTRUCTIONS.contains("Note: \"I should text the new leads on WhatsApp\""))
    }

    @Test
    fun testThePromptCarriesNowTheZoneAndTheDayStart() {
        val prompt = TodoPrompt.prompt(" call the dentist by 4 ", context)
        assertTrue(prompt.contains("Now: Tuesday 13 October 2026, 09:41, time zone Europe/London."), prompt)
        assertTrue(prompt.contains("Tomorrow is Wednesday 14 October 2026 (2026-10-14)."), prompt)
        assertTrue(prompt.contains("Friday 2026-10-16"), prompt)
        assertTrue(prompt.endsWith("Voice note: \"call the dentist by 4\""), prompt)
        assertFalse(prompt.contains("still"), "awake in the day it is: no day-start line")

        val late = TodoContext(at(2026, 10, 14, 1, 30), london, 4)
        val latePrompt = TodoPrompt.prompt("x", late)
        assertTrue(latePrompt.contains("Now: Wednesday 14 October 2026, 01:30"), latePrompt)
        assertTrue(latePrompt.contains("The speaker's day starts at 04:00, so their today is still Tuesday 13 October 2026."), latePrompt)
        assertTrue(latePrompt.contains("Tomorrow is Wednesday 14 October 2026"), latePrompt)
    }

    @Test
    fun testQuickCaptureLinksAndRequests() {
        assertEquals(TodoCaptureRoute.Route.RECORD, TodoCaptureRoute.route(TodoCaptureRoute.RECORD_URL))
        assertEquals(TodoCaptureRoute.Route.LIST, TodoCaptureRoute.route(TodoCaptureRoute.LIST_URL))
        assertNull(TodoCaptureRoute.route(ProRoute().url), "taken://pro is the paywall's")
        assertNull(TodoCaptureRoute.route("https://example.com/todo"))
        assertEquals(TodoCaptureRoute.Route.LIST, TodoCaptureRoute.route("taken://todo/"), "a trailing slash is the list")
        // A quick capture asked for at 100 s starts listening at 110 s, never at 400 s (90 s at most).
        val asked = Instant.ofEpochSecond(100)
        assertTrue(TodoCaptureRoute.isFresh(asked, Instant.ofEpochSecond(110)))
        assertTrue(TodoCaptureRoute.isFresh(asked, asked.plus(Duration.ofSeconds(90))))
        assertFalse(TodoCaptureRoute.isFresh(asked, Instant.ofEpochSecond(400)), "a stale request never opens the mic")
    }
}
