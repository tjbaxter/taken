package com.tombaxter.taken.core.stack

import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.model.Dose
import com.tombaxter.taken.core.model.Item
import com.tombaxter.taken.core.model.StackState
import java.time.Instant
import java.util.Locale

/**
 * What Today does with a tap, as pure rules (SPEC-ANDROID 8.1 #5): Taken/AppModel.swift's `tap`, `notTodayRow`,
 * `offersSetTime`, `setTimeDose`, `takeAllCount` and the edit-mode rule from `feat/tap-row-to-log` (REDESIGN.md, "Tap the
 * row to log"), so the row's behaviour is unit tested without a screen.
 */
object TodayRules {

    /** What a tap anywhere on a Stack or Not today row does. */
    enum class Tap {
        /** Edit mode: the item sheet opens, and nothing is logged. */
        OPEN_ITEM,
        /** Pending, an open week, or a Not today row with nothing logged: log a dose now (Pro permitting). */
        LOG,
        /** Everything due is taken: never un-takes; the times detail opens or closes. */
        SHOW_TIMES,
    }

    fun tap(row: ItemDay, editing: Boolean): Tap = when {
        editing -> Tap.OPEN_ITEM
        row.isPending || row.isOpen || (!row.isDue && row.doses.isEmpty()) -> Tap.LOG
        else -> Tap.SHOW_TIMES
    }

    /** A row in Not today and the line under its name. */
    data class NotTodayRow(val row: ItemDay, val note: String)

    /** "Next: tomorrow", "Next: Thursday": when the item is next due after today. */
    fun nextLabel(engine: StackEngine, item: Item, today: DayKey): String =
        Fmt.next(engine.nextDueDay(item, after = today), today)

    /**
     * A row in Not today and the line under its name. A weekly item shows the week today is in (SPEC 3.3): its due day,
     * open ("Weekly · Thu · Not logged") or logged ("Weekly · Next: Thursday"), or the next due day an early dose already
     * counts for ("Weekly · Counts for Thursday"). In the 1 to 3 days before the next due day, with this week logged, it
     * is today's quiet ring instead ("Weekly · Next: Thursday"), so an early dose is one tap. Anything else is today's
     * row.
     */
    fun notTodayRow(engine: StackEngine, row: ItemDay, today: DayKey): NotTodayRow {
        if (!engine.takesEarlyDose(row.item, today)) {
            val week = engine.weekRow(row.item, today)
            if (week != null) return NotTodayRow(week, Fmt.weekNote(week, today))
        }
        val note = if (row.doses.isEmpty()) {
            Fmt.notDue(row.frequency, nextLabel(engine, row.item, today))
        } else {
            Fmt.frequency(row.frequency)
        }
        return NotTodayRow(row, note)
    }

    /** The dose Set time corrects: the item's latest dose logged today, whichever day it counts for. Null logs a new one. */
    fun setTimeDose(state: StackState, item: Item, today: DayKey, clock: DayClock): Dose? =
        state.doses.filter { it.itemId == item.id && clock.day(it) == today }.maxByOrNull { it.takenAt }

    /**
     * Set time belongs on a row whose last dose was logged today, or that has none and is today's. Otherwise (a weekly row
     * whose dose was logged another day, or whose week is open) the row offers its day's sheet instead.
     */
    fun offersSetTime(row: ItemDay, today: DayKey, clock: DayClock): Boolean {
        val last = row.lastDose ?: return row.day == today
        return clock.day(last) == today
    }

    /** Items Take all logs right now: pending, and not logged in the last hour (StackEngine.repeatGuard). */
    fun takeAllCount(engine: StackEngine, today: DaySummary, now: Instant): Int = engine.quickLogRows(today, now).size

    /** Take all shows for 2 or more quick-loggable rows, and steps aside while the stack is being edited. */
    fun showsTakeAll(count: Int, editing: Boolean): Boolean = count >= 2 && !editing

    /** "Daily", "2x daily · 1 of 2", or the Not today note: the line under a row's name. */
    fun subtitle(row: ItemDay, note: String?): String {
        if (note != null) return note
        val frequency = Fmt.frequency(row.frequency)
        if (row.isDue && row.dosesPerDay > 1) return "$frequency · ${row.takenCount} of ${row.dosesPerDay}"
        return frequency
    }

    /** The detail under a taken row: "Taken at 07:42 · 9h 12m ago", or "Dose 2 taken at ..." for each of several. */
    data class TimeLine(val lead: String, val time: String, val ago: String)

    fun timeLines(row: ItemDay, today: DayKey, clock: DayClock, now: Instant): List<TimeLine> =
        row.doses.mapIndexed { index, dose ->
            TimeLine(
                lead = if (row.doses.size > 1) "Dose ${index + 1} taken at" else "Taken at",
                time = Fmt.doseClock(dose, today, clock),
                ago = "· ${Fmt.agoDetailed(dose.takenAt, now)}",
            )
        }
}

/**
 * What TalkBack says for a Today row: the iPhone's VoiceOver label and hint (Taken/Views/ItemRow.swift on
 * `feat/tap-row-to-log`), word for word, plus Android's click labels (SPEC-ANDROID 7.2).
 */
object RowSpeech {
    /** What a double tap does: the same as a tap anywhere on the row. */
    fun hint(row: ItemDay, quiet: Boolean, locked: Boolean, editing: Boolean = false): String {
        if (editing) return "Double tap to edit."
        if (!(row.isPending || quiet)) return "Double tap for the times. Actions has Edit item."
        return if (locked) "Logging needs Taken Pro. Double tap to see plans." else "Double tap to mark taken."
    }

    /**
     * The row's one sentence. A weekly row in Not today speaks for its week: "Semaglutide, Thursday's dose not logged."
     * while open, "Semaglutide, taken Friday at 8:12 AM." once logged, with "Counts for Thursday." after an early dose.
     */
    fun label(row: ItemDay, today: DayKey, clock: DayClock, nextLabel: String?, locale: Locale = Locale.getDefault()): String {
        val name = row.item.name
        if (row.isOpen) return "$name, ${Fmt.weekday(row.day)}'s dose not logged."
        val last = row.lastDose
        if (row.day != today && last != null) {
            val taken = "$name, taken ${Fmt.spokenDose(last, today, clock, locale)}."
            return if (row.day > today) "$taken Counts for ${Fmt.weekday(row.day)}." else taken
        }
        if (row.doses.isEmpty()) {
            if (nextLabel != null) return "$name, not due today. $nextLabel."
            return "$name, pending."
        }
        val times = Fmt.spokenDoses(row.doses, today, clock, locale)
        if (row.isPending) return "$name, ${row.takenCount} of ${row.dosesPerDay} taken, $times. Pending."
        return "$name, taken $times."
    }

    /**
     * Android's click label, which TalkBack reads as "Double tap to ...": "Log Vitamin D3" while pending, "Show times" once
     * taken, "See Taken Pro plans" when locked, "Edit Vitamin D3" in edit mode.
     */
    fun clickLabel(row: ItemDay, quiet: Boolean, locked: Boolean, editing: Boolean): String = when {
        editing -> "Edit ${row.item.name}"
        !(row.isPending || quiet || row.isOpen) -> "Show times"
        locked -> "See Taken Pro plans"
        else -> "Log ${row.item.name}"
    }
}

/** Today's progress line and what TalkBack says for it (Taken/Views/ProgressSummary.swift). */
object ProgressCopy {
    /**
     * The time after "Last": "08:12", or "Tue 08:12" for an early weekly dose logged on another day that counts for today,
     * as its row shows it.
     */
    fun lastTime(summary: DaySummary, clock: DayClock): String? = summary.lastDose?.let { Fmt.doseClock(it, summary.day, clock) }

    fun spoken(summary: DaySummary): String = when {
        summary.dueDoses == 0 -> "Nothing due today."
        summary.allTaken -> "All taken. ${summary.takenDueDoses} of ${summary.dueDoses} doses."
        else -> "${summary.takenDueDoses} of ${summary.dueDoses} doses taken today. ${summary.pendingDoses} pending."
    }
}

/** The day sheet's rules (Taken/Views/DaySheet.swift). */
object DaySheetRules {
    /**
     * Today, or a day still to come: what is not taken yet reads as pending, never missed. A day after today opens only
     * from a weekly row whose early dose counts for its next due day ("Open Thursday").
     */
    fun isLive(day: DayKey, today: DayKey): Boolean = day >= today

    /** Where Log at starts: now's minutes today, an hour after waking up on an earlier day. */
    fun startMinutes(day: DayKey, today: DayKey, nowMinutes: Int, backfillMinutes: Int): Int =
        if (day == today) nowMinutes else backfillMinutes

    /** "Remove the 08:12 dose of Vitamin D3?" ("this item" when it is gone). */
    fun removalTitle(dose: Dose, name: String?, viewing: DayKey, clock: DayClock): String =
        "Remove the ${Fmt.doseClock(dose, viewing, clock)} dose of ${name ?: "this item"}?"
}
