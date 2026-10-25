package com.tombaxter.taken.core.surfaces

import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.pro.ProRoute
import com.tombaxter.taken.core.pro.ProPendingAction
import com.tombaxter.taken.core.pro.ProStatus
import com.tombaxter.taken.core.stack.WidgetRow
import com.tombaxter.taken.core.stack.WidgetSnapshot
import com.tombaxter.taken.core.todo.TodoCaptureRoute
import com.tombaxter.taken.core.todo.TodoState
import com.tombaxter.taken.core.todo.TodoText
import java.net.URI
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import java.util.UUID

// Taken's surfaces outside the app on Android (SPEC-ANDROID 10.1 and 10.2): the home screen widgets, the Take all tile
// and the static shortcuts. What each one shows and what a tap on it does are pure rules here, ported from the iPhone's
// widget faces (Shared/WidgetViews.swift, Shared/TodoWidgetViews.swift, TakenWidgets/*.swift) so they are unit tested on
// the JVM; the Glance composables and the TileService in :app only draw them.

/** The widget kinds (Shared/Sync.swift `TakenWidgetKind`, Shared/TodoIntents.swift `TodoCaptureRoute.widgetKind`). */
object TakenWidgetKind {
    /** The stack widget: logs. */
    const val STACK = "TakenStack"

    /** The to-do capture widget: opens Taken listening. It does not log doses. */
    const val TODO = "TakenVoiceTodo"

    /**
     * Today's widget invite is answered by a Taken stack widget on the home screen (the iPhone reads the stack widget's
     * Lock Screen families from WidgetKit; Android reads Taken's placed widgets, SPEC-ANDROID 10.1). The to-do widget does
     * not count: it does not log doses.
     */
    fun hasStackWidget(placed: Collection<String>): Boolean = STACK in placed
}

/** Taken's `taken://` links that only Android's surfaces send (SPEC-ANDROID 10.3). */
object SurfaceLinks {
    const val TODAY = "taken://today"

    /**
     * The "Take all" shortcut: Today, then Take all with its snackbar and Undo, or the paywall with the Take all kept
     * while logging needs Taken Pro (SPEC-ANDROID 10.2). [Own choice: the `then=take-all` words of `taken://pro`.]
     */
    const val TAKE_ALL = "taken://today?then=take-all"

    /** `taken://today?then=take-all`. */
    fun isTakeAll(url: String): Boolean {
        val uri = try {
            URI(url)
        } catch (e: Exception) {
            return false
        }
        if (uri.scheme != ProRoute.SCHEME || uri.host != "today") return false
        return (uri.rawQuery ?: "").split("&").any { it == "then=take-all" }
    }
}

/** What a tap on part of a widget does. */
sealed interface WidgetTap {
    /** Logs that item's next dose without opening Taken, only while it is still pending (`logNextDoseIfPending`). */
    data class LogNext(val itemId: UUID) : WidgetTap

    /** Logs every quick-loggable pending dose at one moment (`takeAllPending`). */
    data object TakeAll : WidgetTap

    /** Opens Taken on a `taken://` link. Android 12 and later start activities only from the widget itself. */
    data class Open(val url: String) : WidgetTap

    /** Nothing: a row already taken, or one logged in the last hour. Never un-takes. */
    data object None : WidgetTap
}

/** The bottom of the stack widget's counter block: TAKE ALL, or a status line instead of it. */
sealed interface WidgetBottom {
    /** TAKE ALL with the count of items it logs ("TAKE ALL 3"; no count for one). */
    data class TakeAll(val count: Int) : WidgetBottom {
        val countText: String? get() = if (count > 1) "$count" else null
    }

    /** "LOGGED 07:42", "LOCKED 21:12", "2 PENDING": a lamp, lit or not, and the words. */
    data class Status(val text: String, val lit: Boolean = true) : WidgetBottom
}

/** One row of the stack widget (the iPhone's `MediumRow`). */
data class WidgetRowFace(
    val id: UUID,
    val code: String,
    val name: String,
    val done: Boolean,
    /** "07:42" (the last dose), "1/2" (part taken), "TAP" (ready), "--:--" (not ready, or locked). */
    val value: String,
    /** The value is a time or a count, set in the signal's ink; otherwise the faint HUD words. */
    val valueLit: Boolean,
    val tap: WidgetTap,
    /** TalkBack's sentence for the row. */
    val spoken: String,
)

/**
 * Everything the stack widget shows, at every size (the iPhone's `SmallStackView` and `MediumStackView`), from the
 * snapshot's numbers (Shared/WidgetViews.swift `WidgetSnapshot`). Locked (no Pro after the first dose): read-only with the
 * PRO mark, a row's tap opens the paywall with that log kept, and the rest opens the paywall.
 */
class StackWidgetFace(snapshot: WidgetSnapshot, locale: Locale = Locale.getDefault()) {
    val hasStack: Boolean = snapshot.hasStack
    val locked: Boolean = snapshot.locked
    val allTaken: Boolean = snapshot.allTaken
    val taken: Int = snapshot.takenDue
    val due: Int = snapshot.dueDoses

    /** "2" and "/3": the counter, the taken part bright and the rest faint. */
    val counterTaken: String = "$taken"
    val counterDue: String = "/$due"

    /** The segmented bar: one segment per due dose, at most [MAX_SEGMENTS] (Glance containers hold ten children). */
    val segments: Int
    val litSegments: Int

    /** The counter block's last line; null on an empty stack, which shows [EMPTY_TITLE] and [EMPTY_HINT]. */
    val bottom: WidgetBottom?

    /** The rows, pending first. */
    val rows: List<WidgetRowFace>

    /** Where the rest of the widget goes: Today, or the paywall while locked (the iPhone's `widgetURL`). */
    val tap: WidgetTap

    /** TalkBack's sentence for the counter block (the iPhone's Lock Screen labels). */
    val spoken: String

    /** What the rows' area says when there are none to show. */
    val emptyRows: String = if (hasStack) WidgetCopy.NOTHING_DUE else WidgetCopy.ADD_STACK

    init {
        val clock = snapshot.clock
        if (due <= MAX_SEGMENTS) {
            segments = maxOf(due, 1)
            litSegments = if (due > 0) taken.coerceAtMost(due) else 0
        } else {
            // [Own choice] More than ten doses a day: ten segments, lit in proportion, never full before the day is.
            segments = MAX_SEGMENTS
            val share = (taken.toDouble() / due * MAX_SEGMENTS).toInt()
            litSegments = if (taken >= due) MAX_SEGMENTS else share.coerceAtMost(MAX_SEGMENTS - 1)
        }

        fun finished(): WidgetBottom.Status {
            // A finished day: LOCKED 21:12. Without Pro the widget's lock is Taken Pro's, so it reads DONE 21:12.
            val word = if (locked) WidgetCopy.DONE else WidgetCopy.LOCKED
            return WidgetBottom.Status(snapshot.lastDose?.let { "$word ${Fmt.clock(it, clock)}" } ?: word)
        }
        bottom = when {
            !hasStack -> null
            allTaken -> finished()
            // Read-only: the tap opens Taken Pro, never logs.
            locked -> WidgetBottom.Status(WidgetCopy.pending(snapshot.pendingItems), lit = false)
            snapshot.readyItems > 0 -> WidgetBottom.TakeAll(snapshot.readyItems)
            // Logged in the last hour, its next dose still to come: a second tap would log that dose too early, so the
            // button returns when the hour is up.
            snapshot.pendingItems > 0 ->
                WidgetBottom.Status(snapshot.lastDose?.let { "${WidgetCopy.LOGGED} ${Fmt.clock(it, clock)}" } ?: WidgetCopy.LOGGED)
            else -> finished()
        }

        rows = snapshot.rows.map { row -> rowFace(row, clock, snapshot.clock.zone, locale) }
        tap = if (locked) WidgetTap.Open(ProRoute().url) else WidgetTap.Open(SurfaceLinks.TODAY)
        spoken = when {
            !hasStack -> WidgetCopy.EMPTY_SPOKEN
            allTaken -> WidgetCopy.ALL_TAKEN_SPOKEN
            locked -> "$taken of $due taken. ${WidgetCopy.LOCKED_SPOKEN}"
            snapshot.readyItems > 0 -> "$taken of $due taken. Tap to take all."
            else -> "$taken of $due taken."
        }
    }

    private fun rowFace(row: WidgetRow, clock: DayClock, zone: ZoneId, locale: Locale): WidgetRowFace {
        val last = row.lastTime
        val value: String
        val lit: Boolean
        if (last != null) {
            value = if (row.due > 1 && !row.done) "${row.taken}/${row.due}" else Fmt.clock(last, clock)
            lit = true
        } else {
            value = if (row.ready && !locked) WidgetCopy.TAP else WidgetCopy.NO_TIME
            lit = false
        }
        val tap = when {
            // Locked: the row opens Taken Pro, and the dose it asked for is logged once Pro is on.
            locked && !row.done -> WidgetTap.Open(ProRoute(ProPendingAction.Log(row.id)).url)
            row.done || !row.ready -> WidgetTap.None
            else -> WidgetTap.LogNext(row.id)
        }
        val state = when {
            row.done && last != null -> "taken at ${Fmt.spokenTime(last, zone, locale)}"
            row.done -> "taken"
            row.taken > 0 -> "${row.taken} of ${row.due} taken"
            else -> "pending"
        }
        val hint = when {
            locked && !row.done -> " ${WidgetCopy.LOCKED_SPOKEN}"
            tap is WidgetTap.LogNext -> " Tap to log it."
            !row.done && !row.ready -> " Logged in the last hour."
            else -> ""
        }
        return WidgetRowFace(row.id, row.code, row.name, row.done, value, lit, tap, "${row.name}, $state.$hint")
    }

    /** "+2 MORE" under the rows a size has room for, or null. */
    fun more(shown: Int): String? = if (rows.size > shown) "+${rows.size - shown} MORE" else null

    companion object {
        const val MAX_SEGMENTS = 10
    }
}

/** One open to-do on the to-do widget. */
data class TodoWidgetRow(val id: UUID, val title: String, val due: String?, val overdue: Boolean, val spoken: String) {
    /** A tap opens To-do scrolled to it, with the wash (`taken://todo?task=`). */
    val url: String get() = TodoCaptureRoute.revealUrl(id)
}

/**
 * The to-do widget (Shared/TodoWidgetViews.swift `TodoEntry`): the open tasks in the To-do tab's order, with their count,
 * so the home screen and the app agree. The mic opens Taken listening; the list opens To-do.
 */
class TodoWidgetFace(state: TodoState, now: Instant, clock: DayClock, locale: Locale = Locale.getDefault()) {
    val rows: List<TodoWidgetRow>
    val openCount: Int

    init {
        val open = state.openTasks(clock)
        openCount = open.size
        rows = open.map { task ->
            val dueWords = TodoText.spokenDue(task, now, clock, locale)?.let { ", $it" } ?: ""
            TodoWidgetRow(
                id = task.id,
                title = task.title,
                due = TodoText.dueLabel(task, now, clock),
                overdue = TodoText.isOverdue(task, now, clock),
                spoken = "${task.title}$dueWords",
            )
        }
    }

    /** "To-do · 4", or "To-do" with nothing open. */
    val header: String get() = if (openCount == 0) WidgetCopy.TODO else "${WidgetCopy.TODO} · $openCount"

    /** "1 to-do", "4 to-dos": the narrowest size. */
    val countLine: String get() = if (openCount == 1) "1 to-do" else "$openCount to-dos"

    val micUrl: String get() = TodoCaptureRoute.RECORD_URL
    val listUrl: String get() = TodoCaptureRoute.LIST_URL
}

/** The Take all tile's state (`Tile.STATE_ACTIVE`, `STATE_INACTIVE`). */
enum class TileState { ACTIVE, INACTIVE }

enum class TileIcon { PILL, LOCK }

/**
 * The Quick Settings tile "Take all" (SPEC-ANDROID 10.2), the iPhone's Control Center control. Tiles show over the lock
 * screen, so it says a count, never an item's name. Active while a tap would log something; a tap logs every pending dose
 * with no unlock, like the iPhone's control. Locked: "Taken Pro" with a lock, and a tap opens the paywall with the Take all
 * kept.
 */
class TakeAllTileFace(snapshot: WidgetSnapshot) {
    val label: String
    val subtitle: String
    val icon: TileIcon
    val state: TileState
    val tap: WidgetTap

    init {
        val left = snapshot.pendingItems
        subtitle = when {
            !snapshot.hasStack -> WidgetCopy.TILE_NO_STACK
            snapshot.allTaken -> WidgetCopy.TILE_ALL_TAKEN
            left > 0 -> WidgetCopy.left(left)
            else -> WidgetCopy.TILE_NOTHING_DUE
        }
        when {
            snapshot.locked -> {
                label = WidgetCopy.TILE_LOCKED
                icon = TileIcon.LOCK
                state = TileState.INACTIVE
                tap = WidgetTap.Open(ProRoute(ProPendingAction.TakeAll).url)
            }
            !snapshot.hasStack -> {
                label = WidgetCopy.TILE_LABEL
                icon = TileIcon.PILL
                state = TileState.INACTIVE
                // Nothing to log yet: Taken opens on Today, where Add to stack is.
                tap = WidgetTap.Open(SurfaceLinks.TODAY)
            }
            snapshot.readyItems > 0 -> {
                label = WidgetCopy.TILE_LABEL
                icon = TileIcon.PILL
                state = TileState.ACTIVE
                tap = WidgetTap.TakeAll
            }
            else -> {
                // All taken, nothing due, or only doses logged in the last hour: a tap would log nothing.
                label = WidgetCopy.TILE_LABEL
                icon = TileIcon.PILL
                state = TileState.INACTIVE
                tap = WidgetTap.None
            }
        }
    }

    /** What TalkBack says for the tile: its label and its count. */
    val spoken: String get() = "$label, $subtitle"
}

/**
 * When the widgets and the tile must be drawn again without a write (the iPhone's widget timeline,
 * TakenWidgets/StackWidget.swift `getTimeline`): the next rollover; before it, the moment a pending item held back by the
 * repeat guard can be tapped again; the moment cached Pro runs out, so a widget turns read-only then; and the next to-do
 * due time, when its row turns overdue [Own choice: the iPhone refreshes the to-do widget hourly].
 */
object SurfaceRefresh {
    fun next(snapshot: WidgetSnapshot, status: ProStatus?, todos: TodoState?, now: Instant): Instant {
        val rollover = snapshot.clock.nextRollover(now)
        val moments = mutableListOf(rollover)
        snapshot.nextReady?.let { if (it > now && it < rollover) moments.add(it) }
        if (!snapshot.locked) {
            status?.activeUntil?.let { if (it > now && it < rollover) moments.add(it) }
        }
        todos?.tasks?.filter { !it.isDone }?.mapNotNull { it.dueTime }?.filter { it > now }?.minOrNull()?.let {
            if (it < rollover) moments.add(it)
        }
        return moments.min()
    }
}

/** Every word the widgets, the tile and the shortcuts show (Android wording of the iPhone's, SPEC-ANDROID 6.4). */
object WidgetCopy {
    const val TAKEN = "TAKEN"
    const val PRO = "PRO"
    const val TAKE_ALL = "TAKE ALL"
    const val LOGGED = "LOGGED"
    const val LOCKED = "LOCKED"
    const val DONE = "DONE"
    const val ALL_TAKEN = "ALL\nTAKEN"
    const val EMPTY_TITLE = "NO STACK YET"
    const val EMPTY_HINT = "OPEN TAKEN TO ADD"
    const val NOTHING_DUE = "NOTHING DUE TODAY"
    const val ADD_STACK = "ADD YOUR STACK IN TAKEN"
    const val TAP = "TAP"
    const val NO_TIME = "--:--"

    fun pending(count: Int): String = "$count PENDING"

    /** The widget gallery: "Taken", "Did I take it? Tap to log." */
    const val STACK_NAME = "Taken"
    const val STACK_DESCRIPTION = "Did I take it? Tap to log."
    const val TODO_NAME = "Voice to-do"
    const val TODO_DESCRIPTION = "Tap the mic and say what you need to do."

    const val TODO = "To-do"
    const val TODO_EMPTY = "Tap to see your list"
    const val NEW_VOICE_TODO = "New voice to-do"

    /** TalkBack. */
    const val LOCKED_SPOKEN = "Logging needs Taken Pro."
    const val LOCK_MARK_SPOKEN = "Logging needs Taken Pro"
    const val ALL_TAKEN_SPOKEN = "All taken"
    const val EMPTY_SPOKEN = "No stack yet. Open Taken to add what you take."

    /** The tile: at most 18 characters for its label (https://developer.android.com/develop/ui/views/quicksettings-tiles). */
    const val TILE_LABEL = "Take all"
    const val TILE_LOCKED = "Taken Pro"
    const val TILE_ALL_TAKEN = "All taken"
    const val TILE_NO_STACK = "No stack yet"
    const val TILE_NOTHING_DUE = "Nothing due"

    fun left(count: Int): String = "$count left"

    /** Profile's offer of the tile (Android 13 and later), its section and what it says under it. */
    const val TILE_SECTION = "Quick settings"
    const val ADD_TILE = "Add the Take all tile"
    const val ADD_TILE_FOOTNOTE = "Take all from quick settings, on the lock screen too. It shows how many are left, never a name."

    /** The static shortcuts: short labels of at most 10 characters where possible, long ones of at most 25. */
    const val SHORTCUT_TAKE_ALL = "Take all"
    const val SHORTCUT_VOICE_SHORT = "Voice to-do"
    const val SHORTCUT_VOICE_LONG = "New voice to-do"

    val all: List<String>
        get() = listOf(
            TAKEN, PRO, TAKE_ALL, LOGGED, LOCKED, DONE, ALL_TAKEN, EMPTY_TITLE, EMPTY_HINT, NOTHING_DUE, ADD_STACK, TAP, NO_TIME,
            pending(2), STACK_NAME, STACK_DESCRIPTION, TODO_NAME, TODO_DESCRIPTION, TODO, TODO_EMPTY, NEW_VOICE_TODO,
            LOCKED_SPOKEN, LOCK_MARK_SPOKEN, ALL_TAKEN_SPOKEN, EMPTY_SPOKEN, TILE_LABEL, TILE_LOCKED, TILE_ALL_TAKEN,
            TILE_NO_STACK, TILE_NOTHING_DUE, left(2), TILE_SECTION, ADD_TILE, ADD_TILE_FOOTNOTE, SHORTCUT_TAKE_ALL, SHORTCUT_VOICE_SHORT,
            SHORTCUT_VOICE_LONG,
        )
}
