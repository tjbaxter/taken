package com.tombaxter.taken.core.todo

import com.tombaxter.taken.core.day.DayClock
import java.time.Duration
import java.time.Instant

// Code checks every task against the words that were actually said (SPEC 3.10), ported line for line from
// Taken/Todo/TodoGrounding.swift: rules G1 to G7 give each word of the note one owner before titles are cleaned and
// dates checked. Pure and deterministic, so CI tests it with canned answers (TodoGroundingTests).

object TodoGrounding {
    /** A rebuilt title keeps at most this many words. */
    const val MAX_TITLE_WORDS = 8

    /** A note this short with no separator in it is one thought, however many tasks the model made of it (G4). */
    const val SHORT_NOTE_WORDS = 8

    /** A clock time this close to the prompt's "Now" with no time said for it is the model copying "Now" (G7). */
    val PROMPT_NOW_SLACK: Duration = Duration.ofSeconds(120)

    data class Indexed(val source: Int, val task: RawTodo)

    /** The model's tasks with each word of the transcript owned by one task (G1 to G7; see the Swift for the rules). */
    fun reconcile(
        raw: List<RawTodo>,
        transcript: String,
        windows: List<IntRange?>? = null,
        carried: List<String?>? = null,
        context: TodoContext? = null,
    ): List<RawTodo> = reconcileIndexed(raw, transcript, windows, carried, context).map { it.task }

    /** [reconcile], with the index in `raw` each task comes from (a merged task's first member in the answer). */
    fun reconcileIndexed(
        raw: List<RawTodo>,
        transcript: String,
        windows: List<IntRange?>? = null,
        carried: List<String?>? = null,
        context: TodoContext? = null,
    ): List<Indexed> {
        val note = SpokenNote(transcript)
        val all = note.words.indices
        val wholeNote = SaidWhen(day = note.saysDay(all), time = note.saysTime(all), ownTime = note.saysTime(all))
        fun unplaced(task: RawTodo): RawTodo {
            if (context == null || !isPromptNow(task, context) || wholeNote.time) return task
            return dueAsSaid(task, wholeNote)
        }
        if (note.words.isEmpty() || raw.isEmpty()) return raw.mapIndexed { i, task -> Indexed(i, unplaced(task)) }

        // G1: place.
        val spans = arrayOfNulls<WordSpan>(raw.size)
        val dropped = HashSet<Int>()
        var previousEnd = -1
        for ((index, task) in raw.withIndex()) {
            val window = windows?.getOrNull(index)
            val spoken = note.aligned(SpokenNote.tokens(task.spoken ?: ""))
            var span = if (spoken.isEmpty()) null else note.place(spoken, previousEnd, window)
            val share = if (task.spoken != null && spoken.isEmpty()) 0.5 else 0.6
            if (span == null) span = note.place(task.title, previousEnd, window, share)
            if (span == null && task.spoken != null) dropped.add(index)
            if (span != null) {
                val trimmed = note.withoutEdgeSeparators(span)
                spans[index] = trimmed
                previousEnd = trimmed.end
            }
        }
        val placed = raw.indices.filter { spans[it] != null }
        if (placed.isEmpty()) return raw.indices.filter { it !in dropped }.map { Indexed(it, unplaced(raw[it])) }

        val owners = TaskOwners(raw.size)

        // G2: one owner per word.
        val titleWords = raw.map { task -> SpokenNote.tokens(task.title).filter { SpokenNote.isContent(it) }.toSet() }
        for ((n, a) in placed.withIndex()) {
            for (b in placed.drop(n + 1)) {
                val spanA = spans[a] ?: continue
                val spanB = spans[b] ?: continue
                if (spanA.overlaps(spanB)) {
                    owners.join(a, b)
                    continue
                }
                val shared = titleWords[a].intersect(titleWords[b]).filter { note.counts[it] == 1 }.toSet()
                if (shared.isEmpty()) continue
                val (left, right) = if (spanA.start < spanB.start) spanA to spanB else spanB to spanA
                val between = placed.any { other ->
                    if (other == a || other == b) return@any false
                    val span = spans[other] ?: return@any false
                    span.start > left.end && span.end < right.start
                }
                if (between) continue
                if (note.breakBetween(left.end, right.start) != SpeechBreak.NONE &&
                    !note.leadsWithCarriedWord(raw[a].title, spanA, shared) &&
                    !note.leadsWithCarriedWord(raw[b].title, spanB, shared)
                ) {
                    continue
                }
                owners.join(a, b)
            }
        }
        owners.joinOverlapping(placed, spans)

        // G3: a fragment joins the task it touches.
        var changed = true
        while (changed) {
            changed = false
            val groups = owners.groups(placed, spans)
            if (groups.size <= 1) break
            for ((k, group) in groups.withIndex()) {
                val lone = group.span.start == group.span.end
                if (!lone && !note.isAttachment(group.span)) continue
                val previous = if (k > 0) groups[k - 1] else null
                val next = if (lone && k + 1 < groups.size) groups[k + 1] else null
                val toPrevious = previous?.let { other ->
                    if (duesAgree(other.members + group.members, raw)) note.link(other.span, group.span) else null
                }
                val toNext = next?.let { other ->
                    if (duesAgree(group.members + other.members, raw)) note.link(group.span, other.span) else null
                }
                val target: GroundedTask? = when {
                    toPrevious != null && toNext != null -> if (toPrevious < toNext) previous else next
                    toPrevious != null -> previous
                    toNext != null -> next
                    else -> null
                }
                if (target == null) continue
                owners.join(group.members[0], target.members[0])
                owners.joinOverlapping(placed, spans)
                changed = true
                break
            }
        }

        // G4: a short note with no separator is one thought, unless the model heard two times in it.
        if (placed.size == raw.size - dropped.size && note.words.size <= SHORT_NOTE_WORDS && note.isOneThought &&
            duesAgree(placed, raw)
        ) {
            for (index in placed.drop(1)) owners.join(placed[0], index)
        }

        // G5, G6 and G7: one task per group, where its first member was in the model's answer.
        val groups = owners.groups(placed, spans)
        val result = ArrayList<Indexed>()
        val emitted = HashSet<Int>()
        for (index in raw.indices) {
            if (index in dropped) continue
            if (spans[index] == null) {
                result.add(Indexed(index, unplaced(raw[index])))
                continue
            }
            val group = groups.firstOrNull { index in it.members } ?: continue
            if (!emitted.add(group.root)) continue
            val nextStart = groups.map { it.span.start }.filter { it > group.span.end }.minOrNull()
            val previousEnd2 = groups.map { it.span.end }.filter { it < group.span.start }.maxOrNull() ?: -1
            var grounded = task(group, raw, spans, note, nextStart, previousEnd2)
            if ((grounded.dueISO8601 ?: "").trim().isNotEmpty()) {
                val phrases = group.members.mapNotNull { member -> carried?.getOrNull(member) }
                val earlier = groups.map { it.span }.filter { it.end < group.span.start }
                val whenSaid = note.saidWhen(group.span, nextStart, earlier, phrases)
                if (context != null && isPromptNow(grounded, context) && !whenSaid.ownTime) whenSaid.time = false
                grounded = dueAsSaid(grounded, whenSaid)
            }
            result.add(Indexed(index, grounded))
        }
        return result
    }

    /**
     * One group's task. A lone task keeps the model's title unless it adds a word never said, drops a name its words
     * cover, drops a word from the middle of what it kept, or leaves out the action said before it; a merged one is
     * always rebuilt from the transcript, and keeps the due date of its earliest words.
     */
    private fun task(group: GroundedTask, raw: List<RawTodo>, spans: Array<WordSpan?>, note: SpokenNote, nextStart: Int?, previousEnd: Int): RawTodo {
        val byPlace = group.members.sortedWith { a, b ->
            val sa = spans[a]?.start ?: 0
            val sb = spans[b]?.start ?: 0
            if (sa != sb) sa.compareTo(sb) else a.compareTo(b)
        }
        val first = raw[group.members.minOrNull() ?: byPlace[0]]
        val merged = group.members.size > 1
        var due = first.dueISO8601
        var hasTime = first.hasTime
        if (merged) {
            val source = byPlace.firstOrNull { (raw[it].dueISO8601 ?: "").trim().isNotEmpty() }
            due = source?.let { raw[it].dueISO8601 }
            hasTime = source?.let { raw[it].hasTime } ?: false
        }
        var title = if (merged) raw[byPlace[0]].title else first.title
        val actionStart = if (merged) null else note.actionStart(group.span, title, previousEnd)
        val source = group.span.copy()
        if (actionStart != null) source.start = minOf(source.start, actionStart)
        val rebuild = merged || actionStart != null || SpokenNote.tokens(title).isEmpty() || note.addsUnsaidWord(title) ||
            note.dropsName(group.span, title) || note.dropsInnerWord(group.span, title)
        val rebuilt = if (rebuild) {
            note.title(source, nextStart, hasDue = due != null, members = byPlace.mapNotNull { spans[it] })
        } else {
            null
        }
        if (rebuilt != null) {
            title = rebuilt
        } else if (!merged) {
            title = note.respelled(title)
        }
        return RawTodo(spoken = note.text(group.span), title = title, dueISO8601 = due, hasTime = hasTime)
    }

    /** G7: the due as far as it was said. A clock time needs a time said; a day alone keeps the day; nothing, no due. */
    fun dueAsSaid(task: RawTodo, whenSaid: SaidWhen): RawTodo {
        if ((task.dueISO8601 ?: "").trim().isEmpty()) return task
        if (!whenSaid.day && !whenSaid.time) return task.copy(dueISO8601 = null, hasTime = false)
        if (task.hasTime && !whenSaid.time) return task.copy(hasTime = false)
        return task
    }

    /** The task's clock time is within [PROMPT_NOW_SLACK] of the moment the note was sorted against. */
    fun isPromptNow(task: RawTodo, context: TodoContext): Boolean {
        val text = task.dueISO8601 ?: return false
        if (!task.hasTime) return false
        val due = TodoValidation.parseDue(text, hasTime = true, context = context) as? TodoDue.Time ?: return false
        return Duration.between(context.now, due.at).abs() <= PROMPT_NOW_SLACK
    }

    /** The tasks carry one due date at most: none, or the same one (to the minute). */
    fun duesAgree(members: List<Int>, raw: List<RawTodo>): Boolean {
        val dues = members.mapNotNull { index ->
            val due = Words.trimAll(raw[index].dueISO8601 ?: "")
            if (due.isEmpty()) null else due.take(16)
        }.toSet()
        return dues.size <= 1
    }
}

/** Tasks that became one, and the words they cover. */
data class GroundedTask(val root: Int, val members: List<Int>, val span: WordSpan)

/** Which tasks are one (union-find over the model's answer). */
class TaskOwners(count: Int) {
    private val parent = IntArray(count) { it }

    fun root(index: Int): Int {
        var current = index
        while (parent[current] != current) {
            parent[current] = parent[parent[current]]
            current = parent[current]
        }
        return current
    }

    fun join(a: Int, b: Int) {
        val ra = root(a)
        val rb = root(b)
        if (ra != rb) parent[maxOf(ra, rb)] = minOf(ra, rb)
    }

    /** The placed tasks' groups in the order their words were said. */
    fun groups(placed: List<Int>, spans: Array<WordSpan?>): List<GroundedTask> {
        val byRoot = LinkedHashMap<Int, GroundedTask>()
        for (index in placed) {
            val span = spans[index] ?: continue
            val key = root(index)
            val group = byRoot[key]
            byRoot[key] = if (group != null) {
                GroundedTask(group.root, group.members + index, group.span.union(span))
            } else {
                GroundedTask(key, listOf(index), span)
            }
        }
        return byRoot.values.sortedWith { a, b ->
            if (a.span.start != b.span.start) a.span.start.compareTo(b.span.start) else a.root.compareTo(b.root)
        }
    }

    /** Joins groups whose words overlap until none do. */
    fun joinOverlapping(placed: List<Int>, spans: Array<WordSpan?>) {
        var changed = true
        while (changed) {
            changed = false
            val all = groups(placed, spans)
            outer@ for ((n, a) in all.withIndex()) {
                for (b in all.drop(n + 1)) {
                    if (a.span.overlaps(b.span)) {
                        join(a.root, b.root)
                        changed = true
                        break@outer
                    }
                }
            }
        }
    }
}

/**
 * Keep as one: what a split note reads as once it is put back together (Taken/Todo/TodoGrounding.swift `TodoMerge`).
 */
object TodoMerge {
    /** A note this short reads best in the words said. */
    const val MAX_SPOKEN_WORDS = 12

    /**
     * For a note of 12 words or fewer, the words said, rebuilt as G5 rebuilds a title; longer, the tasks' titles in the
     * order said, joined with commas. Cleaned like every title.
     */
    fun title(transcript: String, titles: List<String>, hasDue: Boolean): String? {
        val note = SpokenNote(transcript)
        if (note.words.isNotEmpty() && note.words.size <= MAX_SPOKEN_WORDS) {
            val spoken = note.title(WordSpan(0, note.words.size - 1), null, hasDue, MAX_SPOKEN_WORDS)?.let(TodoText::clean)
            if (spoken != null) return spoken
        }
        return TodoText.clean(titles.joinToString(", "))
    }

    /** The soonest of the due dates, ordered as the list orders them (a day alone is due by its end), or null. */
    fun earliestDue(dues: List<TodoDue?>, clock: DayClock): TodoDue? =
        dues.filterNotNull().minByOrNull { TodoOrdering.sortDate(it, clock) ?: Instant.MAX }
}
