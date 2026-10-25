package com.tombaxter.taken.core.todo

import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.pro.ProAccess
import com.tombaxter.taken.core.pro.ProGate
import com.tombaxter.taken.core.pro.ProStatus
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import java.util.UUID

// Voice to-dos (REDESIGN.md, SPEC 3.10, SPEC-ANDROID 11). The data and the pure rules: what is open, what was done
// today, in what order, and how a task reads. Ported line for line from Shared/TodoData.swift and
// Taken/Todo/TodoNoteSave.swift. Android leaves out the 1.1 internal builds' list values (`area`, `lastArea`,
// `areaOrder`, SPEC-ANDROID 5.2): Taken has one list, and no Android build ever wrote them.

/** When a to-do is due. */
sealed class TodoDue {
    /** A clock time was said ("by 4 pm"): the moment it is due. */
    data class Time(val at: Instant) : TodoDue()

    /** Only a day was said ("on Friday"): that calendar date, which stays the same date wherever the phone goes. */
    data class Day(val day: DayKey) : TodoDue()
}

/** One thing to do, from a voice note. */
data class TodoTask(
    val id: UUID = UUID.randomUUID(),
    /** Short and imperative: "Call the dentist". */
    val title: String,
    val due: TodoDue? = null,
    val createdAt: Instant,
    val completedAt: Instant? = null,
    /** The voice note it came from. Tasks from one note share it. */
    val noteId: UUID,
    /** Where it came in its note, so a ramble keeps the order it was said in. */
    val order: Int = 0,
) {
    val isDone: Boolean get() = completedAt != null

    /** A clock time was said. */
    val hasTime: Boolean get() = dueTime != null

    /** The moment it is due, when a clock time was said. */
    val dueTime: Instant? get() = (due as? TodoDue.Time)?.at
}

/** A task as a voice note produced it, before it is saved. */
data class TodoDraft(val title: String, val due: TodoDue? = null)

/**
 * Everything the To-do tab keeps: one JSON file next to the log (`todos.json`). Its fields are `var`s holding immutable
 * values, as StackState's are, so a change works on a [clone] and the copy the screen shows never changes underneath it.
 */
data class TodoState(
    var tasks: List<TodoTask> = emptyList(),
    /** The first voice note ever saved. That one needs no Taken Pro; after it the mic does. Erasing keeps it. */
    var firstNoteAt: Instant? = null,
    var schemaVersion: Int = 1,
) {
    fun clone(): TodoState = copy()

    // MARK: Reading

    fun task(id: UUID): TodoTask? = tasks.firstOrNull { it.id == id }

    /**
     * Every open task, whenever it was said: yesterday's stay until they are done. Due first, soonest first; then the
     * newest note first, each note in the order it was said. The To-do tab, the widget and the due-time notifications all
     * read this one list.
     */
    fun openTasks(clock: DayClock): List<TodoTask> = TodoOrdering.sorted(tasks.filter { !it.isDone }, clock)

    /** Tasks done on the day being lived (the day-start hour decides it, as it does for doses), newest first. */
    fun doneTasks(day: DayKey, clock: DayClock): List<TodoTask> =
        tasks.filter { task -> task.completedAt?.let { clock.day(it) == day } ?: false }
            .sortedByDescending { it.completedAt ?: DISTANT_PAST }

    // MARK: Changing

    /** Adds a note's tasks, in the order they were said, to the one list. Returns what was added. */
    fun add(drafts: List<TodoDraft>, noteId: UUID = UUID.randomUUID(), at: Instant): List<TodoTask> {
        val added = drafts.mapIndexed { index, draft ->
            TodoTask(title = draft.title, due = draft.due, createdAt = at, noteId = noteId, order = index)
        }
        tasks = tasks + added
        if (added.isNotEmpty() && firstNoteAt == null) firstNoteAt = at
        prune(at)
        return added
    }

    /**
     * A note saved whole (an older save, kept for notes saved before lines) replaced by the tasks sorted from it. Returns
     * the note's tasks as they now stand: the sorted ones; the whole note when the drafts are just that; nothing when the
     * note was deleted or erased meanwhile; and the note as it is when someone already changed it.
     */
    fun replaceNote(placeholder: UUID, drafts: List<TodoDraft>, at: Instant): List<TodoTask> {
        val index = tasks.indexOfFirst { it.id == placeholder }
        if (index < 0) return emptyList()
        val whole = tasks[index]
        if (whole.isDone || whole.due != null) return listOf(whole)
        if (drafts.size == 1 && drafts[0].title == whole.title && drafts[0].due == null) return listOf(whole)
        if (drafts.isEmpty()) return listOf(whole)
        val added = drafts.mapIndexed { offset, draft ->
            TodoTask(title = draft.title, due = draft.due, createdAt = whole.createdAt, noteId = whole.noteId, order = offset)
        }
        tasks = tasks.filterIndexed { i, _ -> i != index } + added
        prune(at)
        return added
    }

    /**
     * Replaces a note saved as said (`saved`, its lines as they were written) with the tasks sorted from it, on the one
     * list, said when the note was said. Only while every line is still there, open, with no due and its saved title: a
     * line someone edited or finished meanwhile leaves the note as it is. Returns the note's tasks as they now stand: the
     * sorted ones; the lines when the drafts are just those lines; what is there when it was changed; nothing when the
     * note was deleted or erased. (Taken/Todo/TodoNoteSave.swift)
     */
    fun replaceNote(noteId: UUID, saved: List<TodoTask>, drafts: List<TodoDraft>, at: Instant): List<TodoTask> {
        val current = tasks.filter { it.noteId == noteId }.sortedBy { it.order }
        if (current.isEmpty()) return emptyList()
        val untouched = current.size == saved.size && saved.all { line ->
            val task = task(line.id) ?: return@all false
            !task.isDone && task.due == null && task.title == line.title
        }
        if (!untouched || drafts.isEmpty()) return current
        if (drafts == saved.map { TodoDraft(it.title, it.due) }) return current
        val first = current[0]
        val ids = current.map { it.id }.toSet()
        val added = drafts.mapIndexed { offset, draft ->
            TodoTask(title = draft.title, due = draft.due, createdAt = first.createdAt, noteId = noteId, order = offset)
        }
        tasks = tasks.filter { it.id !in ids } + added
        prune(at)
        return added
    }

    /**
     * Keep as one (REDESIGN.md): a note split into several to-dos becomes one to-do again. Replaces exactly these tasks,
     * while every one is still here, still open and from the same note, with one task that keeps the note, the first
     * task's place and when the note was said. Returns it; null, with nothing changed, otherwise.
     */
    fun mergeNote(ids: List<UUID>, title: String, due: TodoDue?): TodoTask? {
        val unique = ids.distinct()
        if (unique.size < 2) return null
        val cleaned = TodoText.clean(title) ?: return null
        val group = unique.mapNotNull { task(it) }
        if (group.size != unique.size || group.any { it.isDone } || group.map { it.noteId }.toSet().size != 1) return null
        val first = group.minByOrNull { it.order } ?: return null
        val index = tasks.indexOfFirst { it.id == first.id }
        if (index < 0) return null
        val merged = first.copy(title = cleaned, due = due)
        val others = unique.toSet() - first.id
        tasks = tasks.mapIndexed { i, task -> if (i == index) merged else task }.filter { it.id !in others }
        return merged
    }

    /** Marks a task done. Done twice keeps the first time. */
    fun complete(id: UUID, at: Instant) {
        val index = tasks.indexOfFirst { it.id == id }
        if (index < 0 || tasks[index].completedAt != null) return
        tasks = tasks.mapIndexed { i, task -> if (i == index) task.copy(completedAt = at) else task }
        prune(at)
    }

    /** Back to open (a tap on a done task's check). */
    fun reopen(id: UUID) {
        tasks = tasks.map { if (it.id == id) it.copy(completedAt = null) else it }
    }

    /** Edits the words or when it is due. An empty title keeps the old one. */
    fun update(id: UUID, title: String, due: TodoDue?) {
        val cleaned = TodoText.clean(title)
        tasks = tasks.map { if (it.id == id) it.copy(title = cleaned ?: it.title, due = due) else it }
    }

    fun delete(id: UUID): TodoTask? {
        val removed = task(id) ?: return null
        tasks = tasks.filter { it.id != id }
        return removed
    }

    /** Puts a deleted task back where it was (UNDO). */
    fun restore(task: TodoTask) {
        if (tasks.any { it.id == task.id }) return
        tasks = tasks + task
    }

    /** Erase all data: the tasks go; the first note on the house stays used. */
    fun eraseAll() {
        tasks = emptyList()
    }

    /** Drops tasks done more than [DONE_RETENTION] ago. */
    fun prune(now: Instant) {
        val cutoff = now.minus(DONE_RETENTION)
        tasks = tasks.filter { task -> task.completedAt?.let { !it.isBefore(cutoff) } ?: true }
    }

    companion object {
        /** Done tasks are kept this long (for "Done today" and an undo), then dropped. */
        val DONE_RETENTION: Duration = Duration.ofDays(30)

        /** Swift's `Date.distantPast`: 1 January of year 1. */
        val DISTANT_PAST: Instant = Instant.ofEpochSecond(-62_135_596_800L)
    }
}

/**
 * Voice to-dos and Taken Pro (REDESIGN.md): the first voice note needs no Pro, so people feel it; after it the mic needs
 * Pro. The same gate as logging (`ProGate`), with "has logged" meaning "has saved a voice note".
 */
object TodoGate {
    fun access(firstNoteAt: Instant?, status: ProStatus?, settled: Boolean, legacyLog: Boolean, now: Instant): ProAccess =
        ProGate.access(status = status, settled = settled, legacyLog = legacyLog, hasLogged = firstNoteAt != null, now = now)
}

/** The order of the open list. */
object TodoOrdering {
    /**
     * Due first, soonest first (a task with a clock time before a day-only one on the same day, which counts as due by
     * the end of that day). Then tasks with no due date: the newest note first, each in the order it was said.
     */
    fun sorted(tasks: List<TodoTask>, clock: DayClock): List<TodoTask> = tasks.sortedWith { a, b ->
        val x = sortDate(a, clock)
        val y = sortDate(b, clock)
        when {
            x != null && y != null -> if (x != y) x.compareTo(y) else tieBreak(a, b)
            x != null -> -1
            y != null -> 1
            else -> tieBreak(a, b)
        }
    }

    /** The moment a task is due by: its time, or the end of its day where the phone is now. */
    fun sortDate(task: TodoTask, clock: DayClock): Instant? = sortDate(task.due, clock)

    fun sortDate(due: TodoDue?, clock: DayClock): Instant? = when (due) {
        is TodoDue.Time -> due.at
        is TodoDue.Day -> {
            val (year, month, day) = due.day.adding(1).ymd
            LocalDate.of(year, month, day).atStartOfDay(clock.zone).toInstant().minusSeconds(1)
        }
        null -> null
    }

    private fun tieBreak(a: TodoTask, b: TodoTask): Int {
        if (a.createdAt != b.createdAt) return b.createdAt.compareTo(a.createdAt)
        if (a.noteId != b.noteId) return uuidString(a.noteId).compareTo(uuidString(b.noteId))
        if (a.order != b.order) return a.order.compareTo(b.order)
        return uuidString(a.id).compareTo(uuidString(b.id))
    }

    /** Swift's `uuidString`: uppercase, so the order of ties is the iPhone's. */
    private fun uuidString(id: UUID): String = id.toString().uppercase()
}

/** How a task reads: due labels, spoken labels, cleaned titles. */
object TodoText {
    private val weekdays = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
    private val months = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
    const val MAX_TITLE_LENGTH = 120

    /** The day word and the clock time of a due label, apart, so the time can be set in mono: ("Tomorrow", "09:00"). */
    data class DueParts(val day: String?, val time: String?)

    /** "16:00" today, "Today", "Tomorrow 09:00", "Thu", "14 Oct 16:00", "Yesterday". Days are the days being lived. */
    fun dueLabel(task: TodoTask, now: Instant, clock: DayClock): String? {
        val parts = dueParts(task, now, clock) ?: return null
        return listOfNotNull(parts.day, parts.time).joinToString(" ")
    }

    fun dueParts(task: TodoTask, now: Instant, clock: DayClock): DueParts? {
        val due = task.due ?: return null
        val today = clock.day(now)
        val day: DayKey
        val time: String?
        when (due) {
            is TodoDue.Time -> {
                day = clock.day(due.at)
                time = clockTime(due.at, clock)
            }
            is TodoDue.Day -> {
                day = due.day
                time = null
            }
        }
        val dayWord: String? = when (val gap = today.distanceTo(day)) {
            0 -> if (time == null) "Today" else null
            1 -> "Tomorrow"
            -1 -> "Yesterday"
            in 2..6 -> weekdays[day.mondayIndex]
            else -> {
                val (_, month, dayOfMonth) = day.ymd
                "$dayOfMonth ${months[(month - 1).coerceIn(0, 11)]}"
            }
        }
        return DueParts(dayWord, time)
    }

    /** Past its time (or its day) and still open. */
    fun isOverdue(task: TodoTask, now: Instant, clock: DayClock): Boolean {
        if (task.isDone) return false
        return when (val due = task.due) {
            is TodoDue.Time -> due.at < now
            is TodoDue.Day -> due.day < clock.day(now)
            null -> false
        }
    }

    /** "due tomorrow at 9:00 AM", for TalkBack: the time in the phone's own short style. */
    fun spokenDue(task: TodoTask, now: Instant, clock: DayClock, locale: Locale = Locale.getDefault()): String? {
        val label = dueLabel(task, now, clock) ?: return null
        val due = task.dueTime
        if (due != null) {
            val spokenTime = Fmt.spokenTime(due, clock.zone, locale)
            val words = label.split(" ").dropLast(1).joinToString(" ")
            return if (words.isEmpty()) "due at $spokenTime" else "due ${words.lowercase()} at $spokenTime"
        }
        return "due ${label.lowercase()}"
    }

    /** "07:42" */
    fun clockTime(instant: Instant, clock: DayClock): String {
        val hm = clock.hourMinute(instant)
        return String.format(Locale.ROOT, "%02d:%02d", hm.hour, hm.minute)
    }

    /** The calendar date of a moment in the clock's zone (midnight to midnight), as a DayKey. */
    fun calendarDay(instant: Instant, clock: DayClock): DayKey = DayKey.calendarDateOf(instant, clock.zone)

    private val listNumber = Regex("^\\d{1,2}[.)]\\s+")

    /**
     * A title as the list shows it: trimmed, one space between words, no list marker or end punctuation, a capital first
     * letter, at most [MAX_TITLE_LENGTH] characters. Null when nothing is left.
     */
    fun clean(raw: String): String? {
        var text = Words.collapse(raw.replace("\n", " "))
        // List markers the model or a typed note may add: "- ", "* ", "1. ", "2) ".
        while (text.isNotEmpty() && text.first() in "-*•") {
            text = Words.trim(text.drop(1)) { false }
        }
        listNumber.find(text)?.let { text = text.removeRange(it.range) }
        text = Words.trim(text) { it in "\"'“”‘’" }
        text = Words.trim(text) { it in ".,;:" }
        if (text.isEmpty()) return null
        if (text.length > MAX_TITLE_LENGTH) {
            val cut = text.take(MAX_TITLE_LENGTH)
            val space = cut.lastIndexOf(' ')
            text = if (space >= 0 && space > MAX_TITLE_LENGTH / 2) cut.substring(0, space) else cut
            text = Words.trim(text) { it in ".,;:" }
        }
        if (text.isEmpty()) return null
        return text.first().uppercase() + text.drop(1)
    }

    /** Like [clean], with a longer limit: a whole voice note saved as one task. */
    fun cleanKeepingLength(raw: String, limit: Int): String? {
        var text = Words.collapse(raw)
        text = Words.trim(text) { it in ".,;:" }
        if (text.isEmpty()) return null
        if (text.length > limit) text = Words.trim(text.take(limit)) { false }
        if (text.isEmpty()) return null
        return text.first().uppercase() + text.drop(1)
    }
}

/**
 * Swift's whitespace and number rules for Kotlin strings: `split(whereSeparator: \.isWhitespace)` and
 * `trimmingCharacters(in: .whitespaces)`, and Character's `isNumber`.
 */
object Words {
    /** Swift's `Character.isWhitespace` (Unicode White_Space), which Kotlin's `isWhitespace` matches. */
    fun isWhitespace(c: Char): Boolean = c.isWhitespace()

    /** Swift's `CharacterSet.whitespaces`: spaces and tabs, never newlines. */
    fun isSpace(c: Char): Boolean = c == '\t' || Character.getType(c) == Character.SPACE_SEPARATOR.toInt()

    /** Swift's `Character.isNumber`: any Unicode number, "4", "½" or "²". */
    fun isNumber(c: Char): Boolean = when (Character.getType(c)) {
        Character.DECIMAL_DIGIT_NUMBER.toInt(), Character.LETTER_NUMBER.toInt(), Character.OTHER_NUMBER.toInt() -> true
        else -> false
    }

    /** Swift's `Int(text)` for plain digits: ASCII 0 to 9 only, never another script's digits. */
    fun asciiInt(text: String): Int? {
        if (text.isEmpty() || !text.all { it in '0'..'9' }) return null
        return text.toIntOrNull()
    }

    /** The words of a text, split on any whitespace, empties dropped. */
    fun split(text: String): List<String> {
        val out = ArrayList<String>()
        val current = StringBuilder()
        for (c in text) {
            if (isWhitespace(c)) {
                if (current.isNotEmpty()) out.add(current.toString())
                current.setLength(0)
            } else {
                current.append(c)
            }
        }
        if (current.isNotEmpty()) out.add(current.toString())
        return out
    }

    /** The words joined with one space. */
    fun collapse(text: String): String = split(text).joinToString(" ")

    /** Trims spaces (not newlines) and the characters `extra` names from both ends. */
    inline fun trim(text: String, extra: (Char) -> Boolean): String = text.trim { isSpace(it) || extra(it) }

    /** Trims all whitespace, newlines too (`.whitespacesAndNewlines`). */
    fun trimAll(text: String): String = text.trim { isWhitespace(it) }
}

/** Due-time reminders for tasks with a clock time, only when Taken may already notify. */
object TodoNotifications {
    const val PREFIX = "taken.todo."

    /** One plan holds at most this many (the iPhone keeps 64 pending requests per app; the nudge uses up to 14). */
    const val LIMIT = 30

    data class Plan(val identifier: String, val fireDate: Instant, val title: String, val body: String, val taskId: UUID)

    /** Pure planning, unit tested: open tasks with a clock time still to come, soonest first. */
    fun plan(tasks: List<TodoTask>, now: Instant, clock: DayClock = DayClock(4)): List<Plan> =
        tasks.mapNotNull { task ->
            val due = task.dueTime
            if (task.isDone || due == null || due <= now) null else task to due
        }
            .sortedBy { it.second }
            .take(LIMIT)
            .map { (task, due) ->
                Plan(identifier(task.id), due, task.title, "Due ${TodoText.clockTime(due, clock)}", task.id)
            }

    fun identifier(id: UUID): String = PREFIX + id.toString().uppercase()

    fun isTodo(identifier: String): Boolean = identifier.startsWith(PREFIX)

    /** The to-do a due-time notification is for, or null for any other identifier. */
    fun taskId(identifier: String): UUID? {
        if (!isTodo(identifier)) return null
        return com.tombaxter.taken.core.model.parseUuid(identifier.removePrefix(PREFIX))
    }

    /** Delivered due-time notifications to withdraw: every one whose to-do is done or deleted. */
    fun staleDelivered(identifiers: List<String>, tasks: List<TodoTask>): List<String> {
        val open = tasks.filter { !it.isDone }.map { identifier(it.id) }.toSet()
        return identifiers.filter { isTodo(it) && it !in open }
    }
}

/** The copy of the To-do tab, in one place (no dashes, never the word for no charge, no exclamation marks). */
object TodoCopy {
    const val EMPTY = "Tap the mic and say what you need to do"
    const val LISTENING = "Listening"
    const val SORTING = "Sorting into to-dos"
    const val TAP_TO_FINISH = "Tap to finish"

    /** The Listening card before a word is said. */
    const val SAY_IT = "Say what you need to do"

    /**
     * Android saves every note as said (SPEC-ANDROID 11 and 6.4: no on-device model in 1.0), and says so. The iPhone's
     * three Apple Intelligence lines are not used.
     */
    const val ALL_UNSORTED = "Saved as you said it, one line per sentence. Tap one to edit."

    /** A model sorted some parts of a long note; the rest is saved as said. */
    const val PART_UNSORTED = "Part of your note was saved as you said it."
    const val STOPPED_AT_CAP = "Stopped at 5 minutes. Tap the mic to keep going."

    /** The line under the list after a note, when it was not all sorted into separate to-dos. */
    fun sortingNote(sorting: TodoSorting): String? = when (sorting) {
        TodoSorting.MODEL -> null
        TodoSorting.PARTLY_SORTED -> PART_UNSORTED
        TodoSorting.NO_MODEL, TodoSorting.COULD_NOT_SORT -> ALL_UNSORTED
    }

    const val MICROPHONE_OFF = "Microphone access is off for Taken."

    /** SPEC-ANDROID 6.4's Android wording. */
    const val UNAVAILABLE =
        "Voice to-dos need on-device speech recognition, which this phone does not have for your language."

    /**
     * [Own choice, SPEC-ANDROID 11] Android 13 and later can download the phone's language for on-device speech when it
     * is supported but not installed: the download starts for next time, and typing works now.
     */
    const val DOWNLOADING =
        "This phone is downloading speech recognition for your language. Until it is ready, type your to-dos instead."
    const val MICROPHONE_BUSY = "The microphone is busy. Try again in a moment."
    const val NOTHING_HEARD = "Nothing heard. Tap the mic and try again."
    const val COULD_NOT_SAVE = "Could not save. Try again."
    const val OPEN_SETTINGS = "Open Settings"
    const val TYPE_INSTEAD = "Type it instead"

    /** Keep as one: the button beside the line, and what TalkBack says once it is done. */
    const val KEEP_AS_ONE = "Keep as one"
    const val KEPT_AS_ONE = "Kept as one to-do."

    /** SPEC-ANDROID 6.4: the rationale before Android's microphone prompt, when Android says one is due. */
    const val MIC_RATIONALE =
        "Taken listens only while the mic is on, to turn what you say into to-dos. The audio stays on this phone and is never saved."
    const val MIC_RATIONALE_TITLE = "Voice to-dos"
    const val CONTINUE = "Continue"
    const val NOT_NOW = "Not now"

    /** "3 to-dos from your note": the line beside Keep as one. */
    fun fromYourNote(count: Int): String = "$count to-dos from your note"

    /** The label over the tasks done on the day being lived. */
    const val DONE_TODAY = "Done today"

    /** "3 open, 2 done today", "3 open", "0 open, 2 done today". Null with nothing open and nothing done today. */
    fun summary(open: Int, doneToday: Int): String? {
        if (open <= 0 && doneToday <= 0) return null
        return if (doneToday > 0) "$open open, $doneToday done today" else "$open open"
    }

    /** From 4:00 of a 5-minute note, on the Listening card: said once, never counted down. */
    const val ONE_MINUTE_LEFT = "1 minute left"

    /** "part 2 of 5": a long note being sorted after the stop, beside "Sorting into to-dos". */
    fun part(part: Int, of: Int): String = "part $part of $of"

    /** "Deleted: Buy milk", the undo bar after a swipe. */
    fun deleted(title: String): String = "Deleted: $title"

    /** The edit and type sheets. */
    const val EDIT_TITLE = "Edit to-do"
    const val TYPE_TITLE = "Type your to-dos"
    const val TYPE_PLACEHOLDER = "Call the dentist tomorrow at 9, buy milk, email Sam the deck"
    const val FIELD = "To-do"
    const val DUE = "Due"
    const val TIME = "Time"
    const val WHEN = "When"
    const val DELETE = "Delete to-do"
    const val SAVE = "Save"
    const val ADD = "Add"
    const val CANCEL = "Cancel"
    const val UNDO = "Undo"

    val all: List<String> = listOf(
        EMPTY, LISTENING, SORTING, TAP_TO_FINISH, SAY_IT, ALL_UNSORTED, PART_UNSORTED, STOPPED_AT_CAP, MICROPHONE_OFF,
        UNAVAILABLE, DOWNLOADING, MICROPHONE_BUSY, NOTHING_HEARD, COULD_NOT_SAVE, OPEN_SETTINGS, TYPE_INSTEAD, KEEP_AS_ONE,
        KEPT_AS_ONE, MIC_RATIONALE, MIC_RATIONALE_TITLE, CONTINUE, NOT_NOW, fromYourNote(3), DONE_TODAY, ONE_MINUTE_LEFT,
        part(2, 5), deleted("Buy milk"), EDIT_TITLE, TYPE_TITLE, TYPE_PLACEHOLDER, FIELD, DUE, TIME, WHEN, DELETE, SAVE, ADD,
        CANCEL, UNDO,
    ) + listOfNotNull(summary(3, 2), summary(3, 0), summary(0, 2))
}

/** Why a note stopped listening, for the 5-minute line. */
enum class TodoStopReason {
    TAP,
    QUIET,
    CAP,

    /** A call or another app took the microphone, or the recognizer failed mid-note. */
    INTERRUPTED,

    /** Taken went to the background: a lock, a swipe home. */
    LEFT_APP,
}

/**
 * The capture timing rules of Taken/Todo/TodoModel.swift, pure: a tap finishes a note; 30 s of quiet or 5 minutes stop
 * it; from 4:00 the card says "1 minute left"; the screen stays on only while starting or listening.
 */
object TodoCapture {
    enum class Phase { IDLE, STARTING, LISTENING, SORTING }

    /** Quiet this long stops listening: no new words and nothing above the room's noise, words or not. */
    val SILENCE_TO_STOP: Duration = Duration.ofSeconds(30)

    /** One note is at most this long. */
    val LONGEST_NOTE: Duration = Duration.ofSeconds(300)

    /** From here the Listening card says "1 minute left", after one soft tap; nothing before it. */
    val CAP_WARNING_AT: Duration = Duration.ofSeconds(240)

    /** Keep as one stays on screen this long at most. */
    val KEEP_OFFER_DURATION: Duration = Duration.ofSeconds(10)

    /** The line after a note stopped at 5 minutes stays this long, and so does a sorting note. */
    val CAP_NOTICE_DURATION: Duration = Duration.ofSeconds(8)

    /** Other notices stay this long. */
    val NOTICE_DURATION: Duration = Duration.ofSeconds(5)

    /** A quick capture (the widget, a shortcut, a link) starts listening only if it was asked for this recently. */
    val CAPTURE_MAX_AGE: Duration = Duration.ofSeconds(90)

    /** A tap finishes a note. Listening also stops after 30 s of quiet, words or not, and at 5 minutes. */
    fun shouldStop(now: Instant, startedAt: Instant, lastVoiceAt: Instant): TodoStopReason? {
        if (Duration.between(startedAt, now) >= LONGEST_NOTE) return TodoStopReason.CAP
        if (Duration.between(lastVoiceAt, now) >= SILENCE_TO_STOP) return TodoStopReason.QUIET
        return null
    }

    /** From 4:00 the card says "1 minute left". */
    fun capWarning(elapsed: Duration): Boolean = elapsed >= CAP_WARNING_AT

    /** The screen stays on only while a note is starting or being heard, and never in the demo. */
    fun keepsScreenOn(phase: Phase, isDemo: Boolean): Boolean =
        !isDemo && (phase == Phase.STARTING || phase == Phase.LISTENING)

    /**
     * The room's noise floor, as the iPhone tracks it: it drops at once to a quieter reading and rises by 0.4% of the gap
     * per reading, so speech is anything clearly above the room.
     */
    fun nextNoiseFloor(floor: Float, decibels: Float): Float =
        if (decibels < floor) decibels else floor + (decibels - floor) * 0.004f

    /** A level reading counts as voice: clearly above the room (the iPhone's rule). */
    fun isVoice(decibels: Float, floor: Float): Boolean = decibels > maxOf(floor + 10f, -50f)

    /** The iPhone's ring level from a dBFS reading (about -80 quiet to 0 loud). */
    fun ringLevel(decibels: Float): Double = ((decibels + 55f) / 45f).toDouble().coerceIn(0.0, 1.0)

    /**
     * [Own choice, SPEC-ANDROID 11] Android's `onRmsChanged` gives an RMS dB value on a scale the docs leave to the
     * recognizer ("the new RMS dB value", https://developer.android.com/reference/android/speech/RecognitionListener),
     * not dBFS, so the ring reads the voice against the room instead: 12 dB above the noise floor fills it.
     */
    fun relativeRingLevel(decibels: Float, floor: Float): Double = ((decibels - floor) / 12f).toDouble().coerceIn(0.0, 1.0)

    /** The card shows only the end of a long note, so a 5-minute monologue never lays out a page of text. */
    const val SHOWN_CHARACTERS = 240

    /** The end of the words: at most [SHOWN_CHARACTERS], from a word start, after an ellipsis when cut. */
    fun tail(text: String, limit: Int = SHOWN_CHARACTERS): String {
        if (text.length <= limit) return text
        val end = text.takeLast(limit)
        val space = end.indexOfFirst { Words.isWhitespace(it) }
        if (space < 0) return "…$end"
        return "… " + end.substring(space + 1)
    }
}

/**
 * Where a voice to-do request sends the app: `taken://todo` opens the To-do tab, `taken://todo/record` opens it listening
 * (the widget's mic, the "New voice to-do" shortcut). Ported from Shared/TodoIntents.swift `TodoCaptureRoute`, the parse
 * pure and the pending recording a plain value the app holds.
 */
object TodoCaptureRoute {
    const val SCHEME = "taken"
    const val HOST = "todo"
    const val RECORD_URL = "taken://todo/record"
    const val LIST_URL = "taken://todo"

    enum class Route { RECORD, LIST }

    /** `taken://todo` and `taken://todo/record`. Null for any other link. */
    fun route(url: String): Route? {
        val uri = try {
            java.net.URI(url)
        } catch (e: Exception) {
            return null
        }
        if (uri.scheme != SCHEME || uri.host != HOST) return null
        val path = (uri.path ?: "").trim('/')
        return if (path == "record") Route.RECORD else Route.LIST
    }

    /** The recording asked for at `askedAt` is still wanted at `now`: at most 90 s old. */
    fun isFresh(askedAt: Instant, now: Instant, maxAge: Duration = TodoCapture.CAPTURE_MAX_AGE): Boolean =
        Duration.between(askedAt, now) <= maxAge
}

/**
 * The edit sheet's date rules (Taken/Todo/TodoSheets.swift `TodoEditSheet`'s statics): what the picker starts on, what
 * is saved, and a new due's suggestion.
 */
object TodoEditRules {
    /** What the picker starts on: the time said, the day said at 09:00 where the phone is now, or tomorrow at 09:00. */
    fun pickerDate(due: TodoDue?, clock: DayClock, now: Instant): Instant = when (due) {
        is TodoDue.Time -> due.at
        is TodoDue.Day -> {
            val (year, month, day) = due.day.ymd
            java.time.ZonedDateTime.of(year, month, day, 9, 0, 0, 0, clock.zone).toInstant()
        }
        null -> suggestedDue(clock, now)
    }

    /** What is saved: a time, or the calendar date picked, which stays that date wherever the phone goes. */
    fun savedDue(hasDue: Boolean, hasTime: Boolean, picked: Instant, clock: DayClock): TodoDue? {
        if (!hasDue) return null
        return if (hasTime) TodoDue.Time(picked) else TodoDue.Day(TodoText.calendarDay(picked, clock))
    }

    /** A new due date starts tomorrow at 09:00. */
    fun suggestedDue(clock: DayClock, now: Instant): Instant {
        val tomorrow = now.atZone(clock.zone).toLocalDate().plusDays(1)
        return tomorrow.atTime(9, 0).atZone(clock.zone).toInstant()
    }

    /** The picked date and time, as the dialogs give them, as one moment in the clock's zone. */
    fun moment(date: LocalDate, hour: Int, minute: Int, zone: ZoneId): Instant =
        date.atTime(hour.coerceIn(0, 23), minute.coerceIn(0, 59)).atZone(zone).toInstant()
}
