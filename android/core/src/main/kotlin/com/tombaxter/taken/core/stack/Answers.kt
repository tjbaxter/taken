package com.tombaxter.taken.core.stack

import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.theme.ThemeID
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import java.util.UUID

/**
 * The sentences that answer "Did I take it?" and say why Take all logged nothing (Shared/Intents.swift `SiriAnswers`).
 * No Siri surface ships on Android 1.0; the sentences stay ported and tested because the nudge and the widgets share
 * their rules (SPEC-ANDROID 8.2, DayLogicTests).
 */
object SiriAnswers {
    /** "Yes. Vitamin D3 at 7:42 AM, Fish Oil at 7:42 AM." or "Not yet: Fish Oil is pending." */
    fun status(state: StackState, now: Instant, zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): String {
        val clock = DayClock(state.settings.dayStartHour, zone)
        val engine = StackEngine(state, clock)
        val today = engine.todaySummary(now)
        if (today.isEmpty) return "Your stack is empty. Open Taken to add what you take."
        val weeks = ArrayList<String>()
        val weekly = HashSet<UUID>()
        for (row in today.items) {
            if (row.isDue || row.doses.isNotEmpty()) continue
            val week = engine.weekRow(row.item, today.day) ?: continue
            weekly.add(row.item.id)
            weeks.add(weekSentence(week, today.day, clock, locale))
        }

        // A dose logged on another day (an early weekly dose on its due day) names that day.
        val taken = today.items.filter { it.doses.isNotEmpty() }.map { row ->
            val sameDay = row.doses.all { clock.day(it) == today.day }
            val times = Fmt.spokenDoses(row.doses, today.day, clock, locale)
            if (sameDay) "${row.item.name} $times" else "${row.item.name} taken $times"
        }
        val pending = today.items.filter { it.isPending }.map { row ->
            if (row.dosesPerDay > 1 && row.doses.isNotEmpty()) {
                "${row.item.name} (${row.doses.size} of ${row.dosesPerDay})"
            } else {
                row.item.name
            }
        }
        val notDue = today.items.filter { !it.isDue && it.doses.isEmpty() && it.item.id !in weekly }.map { it.item.name }

        val sentences = ArrayList<String>()
        if (pending.isEmpty()) {
            sentences.add(if (taken.isEmpty()) "Nothing is due today." else "Yes. ${taken.joinToString(", ")}.")
        } else {
            sentences.add("Not yet: ${Fmt.list(pending)} ${if (pending.size == 1) "is" else "are"} pending.")
            if (taken.isNotEmpty()) sentences.add("${taken.joinToString(", ")}.")
        }
        if (notDue.isNotEmpty()) sentences.add("${Fmt.list(notDue)} ${if (notDue.size == 1) "is" else "are"} not due today.")
        sentences.addAll(weeks)
        return sentences.joinToString(" ")
    }

    /**
     * A weekly item's week: "Semaglutide was taken Friday at 8:12 AM, for Thursday.", "Semaglutide was taken Thursday at
     * 8:12 AM.", "Semaglutide is not logged for Thursday." Never when, whether or how much to take.
     */
    fun weekSentence(week: ItemDay, today: DayKey, clock: DayClock, locale: Locale = Locale.getDefault()): String {
        val name = week.item.name
        val dose = week.lastDose ?: return "$name is not logged for ${Fmt.weekday(week.day)}."
        val whenText = Fmt.spokenDose(dose, today, clock, locale)
        if (clock.day(dose) == week.day) return "$name was taken $whenText."
        return "$name was taken $whenText, for ${Fmt.weekday(week.day)}."
    }

    /** Why TAKE ALL logged nothing. */
    fun nothingPending(state: StackState, now: Instant, zone: ZoneId = ZoneId.systemDefault()): String {
        val clock = DayClock(state.settings.dayStartHour, zone)
        val today = StackEngine(state, clock).todaySummary(now)
        if (today.isEmpty) return "Your stack is empty. Open Taken to add what you take."
        if (today.allTaken) return "Nothing pending. All taken today."
        // Still pending, but logged within the last hour: TAKE ALL never logs a next dose on top of it.
        val recent = today.pendingItems.map { it.item.name }
        if (recent.isNotEmpty()) {
            return "Nothing logged. ${Fmt.list(recent)} ${if (recent.size == 1) "was" else "were"} logged in the last hour. " +
                "To log another dose now, tap it in Taken."
        }
        return "Nothing pending right now."
    }
}

data class WidgetRow(
    val id: UUID,
    val code: String,
    val name: String,
    val taken: Int,
    val due: Int,
    val lastTime: Instant?,
    /** A tap may log it now: still pending, and not logged in the last hour (StackEngine.repeatGuard). */
    val ready: Boolean,
) {
    val done: Boolean get() = taken >= due
}

/**
 * What a home screen widget shows, as pure numbers (Shared/WidgetViews.swift `WidgetSnapshot`). The Glance widget that
 * draws it is NEXT 4; the snapshot's rules are pinned now by DayLogicTests and ThemeTests.
 */
class WidgetSnapshot(state: StackState, now: Instant, zone: ZoneId = ZoneId.systemDefault(), locked: Boolean = false) {
    val clock: DayClock = DayClock(state.settings.dayStartHour, zone)
    val takenDue: Int
    val dueDoses: Int
    val pendingItems: Int
    /** Items TAKE ALL logs right now. Fewer than `pendingItems` while one was logged in the last hour. */
    val readyItems: Int
    val rows: List<WidgetRow>
    val lastDose: Instant?
    val hasStack: Boolean
    /** When a pending item held back by the repeat guard can be tapped again, for the refresh. */
    val nextReady: Instant?
    /** Logging needs Taken Pro: the stack shows read-only, and a tap opens the paywall. */
    val locked: Boolean
    val theme: ThemeID = state.settings.theme

    init {
        val engine = StackEngine(state, clock)
        val summary = engine.todaySummary(now)
        takenDue = summary.takenDueDoses
        dueDoses = summary.dueDoses
        pendingItems = summary.pendingItems.size
        readyItems = engine.quickLogRows(summary, now).size
        nextReady = summary.pendingItems.mapNotNull { engine.quickLogResumes(it, now) }.minOrNull()
        val all = summary.due.map { row ->
            WidgetRow(
                id = row.item.id, code = row.item.code, name = row.item.name, taken = row.takenCount, due = row.dosesPerDay,
                lastTime = row.lastDose?.takenAt, ready = engine.canQuickLog(row, now),
            )
        }
        // What is still to take comes first, so the rows a widget has room for are the ones worth tapping.
        rows = all.filter { !it.done } + all.filter { it.done }
        lastDose = summary.lastDose?.takenAt
        hasStack = !summary.isEmpty
        this.locked = locked && !summary.isEmpty
    }

    val allTaken: Boolean get() = dueDoses > 0 && takenDue >= dueDoses
}
