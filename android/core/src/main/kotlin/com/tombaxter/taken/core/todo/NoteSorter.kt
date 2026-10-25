package com.tombaxter.taken.core.todo

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimeMark
import kotlin.time.TimeSource

// Sorting a voice note into to-dos, part by part (SPEC 3.10), ported from Taken/Todo/NoteSorter.swift. The Swift actor
// becomes a class whose state lives on one confined dispatcher (`limitedParallelism(1)`), which, like an actor, runs one
// piece of it at a time and lets another in while one waits (https://kotlinlang.org/docs/shared-mutable-state-and-concurrency.html#thread-confinement-fine-grained).
// The budgets are the iPhone's. A part that fails or runs past its time is saved as said; the other parts keep theirs.

/** What sorts one part: a model added later, or canned answers in tests. Android 1.0 has only [FallbackSorter]. */
interface ChunkSorting {
    /** Null when the model can sort now; otherwise why not, and every part is saved as said. */
    val unavailable: TodoSorting?

    /** Loads the model while the person is still talking. */
    suspend fun prepare()

    /** The model's answer for one part, in a session of its own. */
    suspend fun answer(chunk: TodoChunk, prompt: String): List<RawTodo>
}

sealed class ChunkSortError : Exception() {
    /** The part and its answer did not fit in the session's context window. */
    class ContextExceeded : ChunkSortError()

    /** The model cannot run on this phone now. */
    class Unavailable(val reason: TodoSorting) : ChunkSortError()
}

/** No model on this phone (all of Android 1.0, SPEC-ANDROID 11): the note is saved as said, one line per sentence. */
class FallbackSorter(val reason: TodoSorting = TodoSorting.NO_MODEL) : ChunkSorting {
    override val unavailable: TodoSorting get() = reason
    override suspend fun prepare() = Unit
    override suspend fun answer(chunk: TodoChunk, prompt: String): List<RawTodo> = throw ChunkSortError.Unavailable(reason)
}

/** What became of one part. */
sealed class ChunkOutcome {
    /** The model's tasks, before any check. */
    data class Model(val tasks: List<RawTodo>) : ChunkOutcome()

    /** No answer within its time. */
    data object TimedOut : ChunkOutcome()

    /** The model failed. */
    data class Failed(val reason: String) : ChunkOutcome()

    /** No model on this phone. */
    data class Unavailable(val reason: TodoSorting) : ChunkOutcome()
}

/** One part as it was sorted. A part the model had no room for comes back as its two halves. */
data class SortedChunk(
    val chunk: TodoChunk,
    val outcome: ChunkOutcome,
    /** When it was sent, in seconds from the note's start, and how long its answer took. */
    val sentAt: Double,
    val seconds: Double,
    /** What the model was asked. */
    val prompt: String,
)

/**
 * Runs `work` and returns its value, or `fallback` once `limit` has passed (or `cutoff` fires first), without waiting for
 * `work` to notice it was cancelled: a model that hangs never holds the To-do tab. The work and the timer run in `scope`,
 * never in the caller's job, so the limit holds from a cancelled caller too (the iPhone's `firstResult`).
 */
suspend fun <T> firstResult(
    scope: CoroutineScope,
    limit: Duration,
    fallback: T,
    cutoff: Cutoff? = null,
    work: suspend () -> T,
): T {
    val result = CompletableDeferred<T>()
    val job = scope.launch {
        try {
            result.complete(work())
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Work that fails gives the fallback, never an uncaught exception in the sorter's scope.
            result.complete(fallback)
        }
    }
    cutoff?.arm {
        job.cancel()
        result.complete(fallback)
    }
    val timer = scope.launch {
        delay(limit)
        job.cancel()
        result.complete(fallback)
    }
    return try {
        withContext(NonCancellable) { result.await() }
    } finally {
        timer.cancel()
    }
}

/** Ends a [firstResult] before its limit: its fallback comes back the moment [fire] is called, or at once if fired first. */
class Cutoff {
    private val lock = Any()
    private var action: (() -> Unit)? = null
    private var fired = false

    fun arm(action: () -> Unit) {
        val already = synchronized(lock) {
            if (!fired) this.action = action
            fired
        }
        if (already) action()
    }

    fun fire() {
        val pending = synchronized(lock) {
            fired = true
            val current = action
            action = null
            current
        }
        pending?.invoke()
    }
}

/** One note's parts, sorted in order, one at a time. Made when listening starts with the one context taken at the tap. */
@OptIn(ExperimentalCoroutinesApi::class)
class NoteSorter(
    private val sorter: ChunkSorting,
    private val context: TodoContext,
    private val budget: Budget = Budget.STANDARD,
    private val onProgress: ((part: Int, of: Int) -> Unit)? = null,
    /** Where the parts are asked and timed: never the caller's job, as the iPhone's tasks never inherit cancellation. */
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
) {
    /** How long the parts get. */
    data class Budget(
        /** While listening, per part: only a part that hangs reaches it. */
        val whileListening: Duration = 30.seconds,
        /** After the stop, per part: 4 s plus 0.15 s a word, at most 15 s. */
        val base: Duration = 4.seconds,
        val perWord: Duration = 150.milliseconds,
        val perPartCap: Duration = 15.seconds,
        /** After the stop, in all: 6 s a part still to sort, at least 20 s, at most 60 s. */
        val totalPerPart: Duration = 6.seconds,
        val totalFloor: Duration = 20.seconds,
        val totalCap: Duration = 60.seconds,
    ) {
        fun afterStop(words: Int): Duration = minOf(perPartCap, base + perWord * words)

        fun total(remaining: Int): Duration = minOf(totalCap, maxOf(totalFloor, totalPerPart * remaining))

        /** Every time multiplied by `factor` (tests run the same rules in less time). */
        fun scaled(factor: Double): Budget = Budget(
            whileListening * factor, base * factor, perWord * factor, perPartCap * factor, totalPerPart * factor,
            totalFloor * factor, totalCap * factor,
        )

        companion object {
            val STANDARD = Budget()
        }
    }

    /** One piece of the sorter's state at a time, as an actor's. */
    private val confined = Dispatchers.Default.limitedParallelism(1)
    private val started: TimeMark = TimeSource.Monotonic.markNow()

    private var note = SpokenNote("")
    private var heard = ""
    private var parts: List<TodoChunk> = emptyList()
    private var queue: List<TodoChunk> = emptyList()
    private var results: List<SortedChunk> = emptyList()
    private var running = false
    private var deadline: TimeMark? = null
    private var closed = false
    private var total: Int? = null
    private var asking: Pair<TodoChunk, Cutoff>? = null
    private val waiting = ArrayList<CompletableDeferred<Unit>>()

    /** The finished transcript so far, while listening: every part it closes is sorted, in order. */
    suspend fun listen(finished: String) = withContext(confined) {
        if (deadline != null || finished == heard || !finished.startsWith(heard)) return@withContext
        heard = finished
        note = SpokenNote(finished)
        val closedNow = TodoChunker.chunks(note, final = false)
        if (closedNow.size <= parts.size) return@withContext
        val fresh = closedNow.drop(parts.size)
        parts = parts + fresh
        queue = queue + fresh
        startIfIdle()
    }

    /**
     * The whole note, at the stop: the rest is cut into its last parts and every part not sorted yet gets its time after
     * the stop. Returns every part in the order said, each with its answer, or timed out. Runs to its end even from a
     * cancelled caller, as the iPhone's does: the note must be saved.
     */
    suspend fun finish(note text: String): List<SortedChunk> = withContext(NonCancellable + confined) {
        val whole = SpokenNote(text)
        var begun = parts.size - queue.size
        var all = TodoChunker.chunks(whole, final = true, sent = begun)
        if (!text.startsWith(heard) || all.size < begun || all.take(begun) != parts.take(begun)) {
            results = emptyList()
            all = TodoChunker.chunks(whole, final = true)
            begun = 0
        }
        note = whole
        heard = text
        queue = all.drop(begun)
        parts = all
        total = all.size
        val remaining = queue.size + if (running) 1 else 0
        val stop = TimeSource.Monotonic.markNow()
        val budgetAll = budget.total(remaining)
        val end = stop + budgetAll
        deadline = end
        if (running) {
            val current = all.firstOrNull { part -> results.none { it.chunk.index == part.index } }
            if (current != null) onProgress?.invoke(current.index + 1, all.size)
        }
        // The part being asked was given 30 s while listening; from the stop it gets a part's time after the stop, or the
        // rest of the note's when nothing waits behind it.
        asking?.let { (part, cutoff) ->
            val limit = if (queue.isEmpty()) budgetAll else minOf(budget.afterStop(part.wordCount), budgetAll)
            scope.launch {
                delay(limit)
                cutoff.fire()
            }
        }
        startIfIdle()
        firstResult(scope, -end.elapsedNow(), Unit) { sorted() }
        closed = true
        asking?.second?.fire()
        val answered = results.toMutableList()
        for (part in all) {
            if (answered.none { it.chunk.index == part.index }) {
                answered.add(SortedChunk(part, ChunkOutcome.TimedOut, elapsed(), 0.0, TodoPrompt.prompt(part, all.size, context)))
            }
        }
        answered.sortedBy { it.chunk.wordRange.lowerBound }
    }

    /** Waits until every part handed over so far is sorted, from a cancelled caller too (as the iPhone's does). */
    suspend fun settle() = withContext(NonCancellable) { sorted() }

    /** Returns once every part handed over so far is sorted, or at once when none is waiting. */
    private suspend fun sorted() {
        val waiter = withContext(confined) {
            if (closed || (!running && queue.isEmpty())) return@withContext null
            CompletableDeferred<Unit>().also { waiting.add(it) }
        } ?: return
        withContext(NonCancellable) { waiter.await() }
    }

    // MARK: Sorting

    private fun startIfIdle() {
        if (running || closed || queue.isEmpty()) return
        running = true
        scope.launch(confined) { drain() }
    }

    private suspend fun drain() {
        while (!closed && queue.isNotEmpty()) {
            val part = queue.first()
            queue = queue.drop(1)
            total?.let { onProgress?.invoke(part.index + 1, it) }
            val sorted = sort(part, halved = false)
            if (closed) break
            // A transcript that changed under the parts (`finish`) drops what was sorted from the old ones.
            if (part !in parts) continue
            results = results + sorted
        }
        running = false
        val done = waiting.toList()
        waiting.clear()
        for (waiter in done) waiter.complete(Unit)
    }

    private sealed class Answer {
        data class Tasks(val tasks: List<RawTodo>) : Answer()
        data object ContextExceeded : Answer()
        data class Unavailable(val reason: TodoSorting) : Answer()
        data class Failed(val reason: String) : Answer()
        data object TimedOut : Answer()
    }

    private suspend fun sort(part: TodoChunk, halved: Boolean): List<SortedChunk> {
        val prompt = TodoPrompt.prompt(part, total ?: (parts.size + 1), context)
        val sentAt = elapsed()
        sorter.unavailable?.let { reason ->
            return listOf(SortedChunk(part, ChunkOutcome.Unavailable(reason), sentAt, 0.0, prompt))
        }
        val cutoff = Cutoff()
        asking = part to cutoff
        val answer = try {
            firstResult(scope, limit(part), Answer.TimedOut, cutoff) {
                try {
                    Answer.Tasks(sorter.answer(part, prompt))
                } catch (e: ChunkSortError.ContextExceeded) {
                    Answer.ContextExceeded
                } catch (e: ChunkSortError.Unavailable) {
                    Answer.Unavailable(e.reason)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Answer.Failed(e.toString())
                }
            }
        } finally {
            asking = null
        }
        val seconds = elapsed() - sentAt
        return when (answer) {
            is Answer.Tasks -> listOf(SortedChunk(part, ChunkOutcome.Model(answer.tasks), sentAt, seconds, prompt))
            Answer.ContextExceeded -> {
                // No room in one session: once, each half in a new one.
                val halves = if (!halved && !closed) TodoChunker.split(part, note) else null
                if (halves != null) {
                    halves.flatMap { sort(it, halved = true) }
                } else {
                    listOf(SortedChunk(part, ChunkOutcome.Failed("exceededContextWindowSize"), sentAt, seconds, prompt))
                }
            }
            is Answer.Unavailable -> listOf(SortedChunk(part, ChunkOutcome.Unavailable(answer.reason), sentAt, seconds, prompt))
            is Answer.Failed -> listOf(SortedChunk(part, ChunkOutcome.Failed(answer.reason), sentAt, seconds, prompt))
            Answer.TimedOut -> listOf(SortedChunk(part, ChunkOutcome.TimedOut, sentAt, seconds, prompt))
        }
    }

    /**
     * While listening, 30 s; after the stop, the part's own time, never past the note's deadline. The note's last part
     * gets the rest of the note's time.
     */
    private fun limit(part: TodoChunk): Duration {
        val end = deadline ?: return budget.whileListening
        val left = maxOf(Duration.ZERO, -end.elapsedNow())
        if (queue.isEmpty() && part.wordRange.upperBound >= note.words.size) return left
        return minOf(budget.afterStop(part.wordCount), left)
    }

    private fun elapsed(): Double = started.elapsedNow().inWholeMicroseconds / 1e6

    companion object {
        /** Parts are sorted while the person talks when a model exists. One switch, as on the iPhone. */
        const val SORTS_WHILE_LISTENING = true
    }
}

/** Used by tests: whether a part was sorted by a model. */
val SortedChunk.isSorted: Boolean get() = outcome is ChunkOutcome.Model
