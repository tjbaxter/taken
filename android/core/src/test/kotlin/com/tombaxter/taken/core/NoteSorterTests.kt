package com.tombaxter.taken.core

import com.tombaxter.taken.core.todo.ChunkOutcome
import com.tombaxter.taken.core.todo.ChunkSortError
import com.tombaxter.taken.core.todo.ChunkSorting
import com.tombaxter.taken.core.todo.FallbackSorter
import com.tombaxter.taken.core.todo.NoteSorter
import com.tombaxter.taken.core.todo.RawTodo
import com.tombaxter.taken.core.todo.SortedChunk
import com.tombaxter.taken.core.todo.SpokenNote
import com.tombaxter.taken.core.todo.TodoChunk
import com.tombaxter.taken.core.todo.TodoChunker
import com.tombaxter.taken.core.todo.TodoSorting
import com.tombaxter.taken.core.todo.TodoValidation
import com.tombaxter.taken.core.todo.isSorted
import com.tombaxter.taken.core.todo.upperBound
import com.tombaxter.taken.core.todo.lowerBound
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.delay
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import java.lang.management.ManagementFactory
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/NoteSorterTests.swift: sorting a long note part by part, in order, one part at a time; a part
 * past its time or failing is saved as said while the others keep their tasks; a part too big for the window is halved
 * once; the time after the stop holds; a task said in two parts is saved once. A fake sorter with canned answers and
 * delays stands in for a model, every time scaled down. The sorter is a class on one confined dispatcher here, where
 * the iPhone's is an actor.
 */
class NoteSorterTests {
    /** What the fake sorter was asked, in order, and how many at once. */
    private class Calls {
        val parts = ArrayList<Int>()
        val prompts = ArrayList<String>()
        var mostAtOnce = 0
        private var running = 0

        @Synchronized fun begin(part: TodoChunk, prompt: String) {
            parts.add(part.index)
            prompts.add(prompt)
            running += 1
            mostAtOnce = maxOf(mostAtOnce, running)
        }

        @Synchronized fun end() {
            running -= 1
        }

        @Synchronized fun snapshot(): List<Int> = parts.toList()
    }

    private class Fake(
        override val unavailable: TodoSorting? = null,
        val calls: Calls = Calls(),
        val delayFor: (TodoChunk) -> Duration = { 10.milliseconds },
        val failure: (TodoChunk) -> Exception? = { null },
        val answers: (TodoChunk) -> List<RawTodo> = CALLS,
    ) : ChunkSorting {
        override suspend fun prepare() = Unit

        override suspend fun answer(chunk: TodoChunk, prompt: String): List<RawTodo> {
            calls.begin(chunk, prompt)
            try {
                delay(delayFor(chunk))
            } finally {
                calls.end()
            }
            failure(chunk)?.let { throw it }
            return answers(chunk)
        }
    }

    companion object {
        /** A good model: one task for each "call <name>" in the part. */
        val CALLS: (TodoChunk) -> List<RawTodo> = { chunk ->
            val words = SpokenNote(chunk.text).words
            words.indices.mapNotNull { index ->
                if (words[index].key != "call" || index + 1 >= words.size) return@mapNotNull null
                val name = words[index + 1].surface
                RawTodo("call $name", "Call $name")
            }
        }
    }

    /** Twelve sentences of twenty words, one call each: six parts of 40 words. */
    private val note = (0 until 12).joinToString(" ") {
        "Please call person$it about the thing number $it today, and then there are a few more words to fill it."
    }
    private val context = TodoEval.context

    /** The real rules at a twentieth of the time: 1.5 s a part while listening, 0.5 s a 40-word part after the stop. */
    private val budget = NoteSorter.Budget.STANDARD.scaled(0.05)

    @Test
    fun testThePartsAreSortedInOrderOneAtATimeEachWithItsOwnPrompt() = runBlocking {
        val calls = Calls()
        val sorter = NoteSorter(Fake(calls = calls), context, budget)
        val parts = TodoChunker.chunks(note, final = true)
        assertEquals(6, parts.size)
        sorter.listen(note)
        val sorted = sorter.finish(note)
        assertEquals((0 until 6).toList(), calls.snapshot(), "in the order said, each once")
        assertEquals(1, calls.mostAtOnce, "never two at once")
        assertTrue(sorted.all { it.isSorted })
        assertTrue(calls.prompts[0].contains("Voice note, part 1: \"Please call person0"), calls.prompts[0])
        assertTrue(calls.prompts[1].contains("Voice note, part 2: \""), calls.prompts[1])
        assertFalse(calls.prompts[1].contains("Call person0"), "the tasks of earlier parts are never sent")

        val saved = TodoValidation.assemble(note, sorted, context)
        assertEquals((0 until 12).map { "Call person$it" }, saved.drafts.map { it.title })
        assertEquals(TodoSorting.MODEL, saved.sorting)
        assertFalse(saved.keepable, "Keep as one is for a note of one part")
    }

    @Test
    fun testAPartPastItsTimeIsSavedAsSaidAndTheOthersKeepTheirTasks() = runBlocking {
        val fake = Fake(delayFor = { if (it.index == 1) 10.seconds else 10.milliseconds })
        val sorter = NoteSorter(fake, context, budget)
        val started = System.nanoTime()
        val sorted = sorter.finish(note)
        assertTrue((System.nanoTime() - started) / 1e9 < 3.5, "a hung part never holds the note")
        assertEquals(listOf(false, true, false, false, false, false), sorted.map { it.outcome == ChunkOutcome.TimedOut })
        val saved = TodoValidation.assemble(note, sorted, context)
        assertEquals(TodoSorting.PARTLY_SORTED, saved.sorting)
        val titles = saved.drafts.map { it.title }
        assertEquals(listOf("Call person0", "Call person1"), titles.take(2))
        assertTrue(titles[2].startsWith("Please call person2 about the thing number 2 today"), titles[2])
        val kept = saved.drafts.flatMap { SpokenNote.tokens(it.title) }.toSet()
        val said = SpokenNote(sorted[1].chunk.text).tokens.toSet() - setOf("please", "and", "then")
        assertTrue(kept.containsAll(said), "every word of the late part: ${said - kept}")
    }

    @Test
    fun testAPartTooBigForTheWindowIsHalvedOnce() = runBlocking {
        val fake = Fake(failure = { if (it.index == 0 && it.cut != TodoChunk.Cut.SPLIT) ChunkSortError.ContextExceeded() else null })
        val sorted = NoteSorter(fake, context, budget).finish(note)
        assertEquals(2, sorted.count { it.chunk.cut == TodoChunk.Cut.SPLIT }, "two halves, each in a new session")
        assertTrue(sorted.all { it.isSorted })
        assertEquals(12, TodoValidation.assemble(note, sorted, context).drafts.size)

        val always = Fake(failure = { if (it.index == 0) ChunkSortError.ContextExceeded() else null })
        val halved = NoteSorter(always, context, budget).finish(note)
        assertEquals(2, halved.count { it.chunk.cut == TodoChunk.Cut.SPLIT }, "halved once, never again")
        assertFalse(halved.filter { it.chunk.index == 0 }.any { it.isSorted })
    }

    @Test
    fun testAnErrorSendsOnlyThatPartToLines() = runBlocking {
        class Refusal : Exception()
        val fake = Fake(failure = { if (it.index == 2) Refusal() else null })
        val sorted = NoteSorter(fake, context, budget).finish(note)
        assertFalse(sorted[2].isSorted)
        assertEquals(5, sorted.count { it.isSorted })
    }

    @Test
    fun testTheTimeAfterTheStopHoldsForTheWholeNote() = runBlocking {
        val fake = Fake(delayFor = { 400.milliseconds })
        val total = budget.total(6)
        val started = System.nanoTime()
        val sorted = NoteSorter(fake, context, budget).finish(note)
        val took = (System.nanoTime() - started) / 1e9
        val limit = total.inWholeMilliseconds / 1000.0
        assertTrue(took < limit + 0.6, "$took s for a budget of $limit s")
        assertTrue(sorted.any { it.outcome == ChunkOutcome.TimedOut }, "the parts past the budget are saved as said")
        assertTrue(sorted[0].isSorted)
        assertEquals(20.seconds, NoteSorter.Budget.STANDARD.total(1), "at least 20 s")
        assertEquals(30.seconds, NoteSorter.Budget.STANDARD.total(5), "6 s a part")
        assertEquals(60.seconds, NoteSorter.Budget.STANDARD.total(15), "at most 60 s")
        assertEquals(10.seconds, NoteSorter.Budget.STANDARD.afterStop(40), "4 s and 0.15 s a word")
        assertEquals(15.seconds, NoteSorter.Budget.STANDARD.afterStop(80), "at most 15 s")
    }

    @Test
    fun testATaskSaidInTwoPartsIsSavedOnce() = runBlocking {
        val repeated = "$note Please call person0 about the thing number 0 today, and then there are a few more words."
        val sorted = NoteSorter(Fake(), context, budget).finish(repeated)
        val saved = TodoValidation.assemble(repeated, sorted, context)
        assertEquals((0 until 12).map { "Call person$it" }, saved.drafts.map { it.title })

        val copied = Fake(answers = { listOf(RawTodo("call person0", "Call person0")) })
        val everywhere = NoteSorter(copied, context, budget).finish(note)
        assertEquals(listOf("Call person0"), TodoValidation.assemble(note, everywhere, context).drafts.map { it.title })
    }

    @Test
    fun testNoModelSavesTheNoteAsSaid() = runBlocking {
        val fake = Fake(unavailable = TodoSorting.NO_MODEL)
        val words = "Call the dentist. Buy milk."
        val sorted = NoteSorter(fake, context, budget).finish(words)
        val saved = TodoValidation.assemble(words, sorted, context)
        assertEquals(listOf("Call the dentist", "Buy milk"), saved.drafts.map { it.title })
        assertEquals(TodoSorting.NO_MODEL, saved.sorting)
        assertTrue(fake.calls.snapshot().isEmpty(), "the model is never asked")
        assertEquals(TodoSorting.COULD_NOT_SORT, FallbackSorter(TodoSorting.COULD_NOT_SORT).unavailable)
        assertEquals(TodoSorting.NO_MODEL, FallbackSorter().unavailable, "Android 1.0's sorter: no model")
    }

    @Test
    fun testOneShortPartSplitByTheModelMayBeKeptAsOne() = runBlocking {
        val fake = Fake(answers = { listOf(RawTodo("call the dentist", "Call the dentist"), RawTodo("buy milk", "Buy milk")) })
        val words = "call the dentist and buy milk"
        val sorted = NoteSorter(fake, context, budget).finish(words)
        val prompt = sorted.firstOrNull()?.prompt ?: ""
        assertTrue(prompt.endsWith("Voice note: \"call the dentist and buy milk\""), "one part: no part number")
        val saved = TodoValidation.assemble(words, sorted, context)
        assertEquals(listOf("Call the dentist", "Buy milk"), saved.drafts.map { it.title })
        assertTrue(saved.keepable)
    }

    /** CPU seconds the coroutine workers and this thread have used: a wait that spins shows here, the JIT never does. */
    private fun cpuSeconds(): Double {
        val bean = ManagementFactory.getThreadMXBean()
        val current = Thread.currentThread().id
        var nanos = 0L
        for (thread in Thread.getAllStackTraces().keys) {
            if (thread.id != current && !thread.name.startsWith("DefaultDispatcher")) continue
            val time = bean.getThreadCpuTime(thread.id)
            if (time > 0) nanos += time
        }
        return nanos / 1e9
    }

    /**
     * The 30 s quiet stop and the 5-minute stop finish the note from the listening watch's own job, which finishing
     * cancels. The stop must still wait for the model, and use almost no CPU while it does.
     */
    @Test
    fun testTheStopFromACancelledTaskWaitsForTheModelWithoutSpinning() = runBlocking {
        // Warm the classes up first, so loading them is not counted.
        NoteSorter(Fake(delayFor = { 1.milliseconds }), context, budget).finish("call the dentist and buy milk")
        val fake = Fake(delayFor = { 400.milliseconds })
        val sorter = NoteSorter(fake, context, budget)
        val before = cpuSeconds()
        var sorted: List<SortedChunk> = emptyList()
        val stop = launch(Dispatchers.Default) {
            coroutineContext.job.cancel()
            withContext(NonCancellable) { sorted = sorter.finish("call the dentist and buy milk") }
        }
        stop.join()
        val used = cpuSeconds() - before
        assertTrue(sorted.isNotEmpty() && sorted.all { it.isSorted }, "${sorted.map { it.outcome }}")
        assertTrue(used < 0.15, "$used s of CPU while waiting 0.4 s for the model")

        val listened = NoteSorter(Fake(), context, budget)
        listened.listen(note)
        val settle = launch(Dispatchers.Default) {
            coroutineContext.job.cancel()
            listened.settle()
        }
        settle.join()
        val parts = listened.finish(note)
        assertTrue(parts.count { it.isSorted } >= 5, "settle waited for the parts said so far")
    }

    @Test
    fun testAPartStillBeingSortedAtTheStopGetsThePostStopTime() = runBlocking {
        val opening = (0 until 2).joinToString(" ") {
            "Please call person$it about the thing number $it today, and then there are a few more words to fill it."
        }
        val words = "$opening Please call the dentist."
        val calls = Calls()
        val fake = Fake(calls = calls, delayFor = { if (it.index == 0) 10.seconds else 10.milliseconds })
        val sorter = NoteSorter(fake, context, budget)
        sorter.listen(words)
        val deadline = System.nanoTime() + 2_000_000_000L
        while (calls.snapshot().isEmpty() && System.nanoTime() < deadline) delay(5)
        val started = System.nanoTime()
        val sorted = sorter.finish(words)
        val took = (System.nanoTime() - started) / 1e9
        assertEquals(2, sorted.size)
        assertEquals(ChunkOutcome.TimedOut, sorted.firstOrNull()?.outcome, "the hung part is saved as said")
        assertTrue(sorted.size == 2 && sorted[1].isSorted, "the part said last is sorted: ${sorted.map { it.outcome }}")
        assertTrue(took < 0.95, "$took s")
    }

    @Test
    fun testTheLastPartHasTheRestOfTheNotesTime() = runBlocking {
        val words = "I should send messages to my LinkedIn ICPs"
        val answer = listOf(RawTodo("send messages to my linkedin icps", "Send messages to my LinkedIn ICPs"))
        val fake = Fake(delayFor = { 400.milliseconds }, answers = { answer })
        val sorted = NoteSorter(fake, context, budget).finish(words)
        assertEquals(1, sorted.size)
        assertTrue(sorted.all { it.isSorted }, "${sorted.map { it.outcome }}")
        val saved = TodoValidation.assemble(words, sorted, context)
        assertEquals(listOf("Send messages to my LinkedIn ICPs"), saved.drafts.map { it.title })
    }

    @Test
    fun testATranscriptThatChangedUnderItsPartsIsSortedAgain() = runBlocking {
        val sorter = NoteSorter(Fake(), context, budget)
        sorter.listen(note)
        sorter.settle()
        val changed = "Call Sam about the deck. $note"
        val sorted = sorter.finish(changed)
        val covered = sorted.map { it.chunk.wordRange }
        assertEquals(0, covered.first().lowerBound)
        assertEquals(SpokenNote(changed).words.size, covered.last().upperBound, "the new words, every one")
        val saved = TodoValidation.assemble(changed, sorted, context)
        assertEquals("Call Sam", saved.drafts.firstOrNull()?.title)
    }
}
