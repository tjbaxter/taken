package com.tombaxter.taken.core.stack

import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.model.Dose
import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.Item
import com.tombaxter.taken.core.model.StackState
import java.time.Duration
import java.time.Instant
import java.util.UUID

enum class DayStatus { FUTURE, NOTHING_DUE, COMPLETE, PARTIAL, MISSED }

/** One item on one logical day. Ported from Shared/StackLogic.swift `ItemDay`. */
data class ItemDay(
    val item: Item,
    val day: DayKey,
    /** The item's frequency on this day. A later change in settings never rewrites it. */
    val frequency: Frequency,
    val isDue: Boolean,
    /** False when the item was not in the stack this day: added later, or archived then. */
    val isActive: Boolean,
    /** True when the item sat archived on this day, rather than not being added yet. */
    val isPaused: Boolean,
    val doses: List<Dose>,
    /**
     * A weekly item's due day whose week is still open (SPEC 3.3, R2): nothing counts for it yet and the day being lived
     * is 1 to 6 days after it. It neither counts as due nor as missed until the next due day closes it.
     */
    val isOpen: Boolean = false,
) {
    val id: UUID get() = item.id
    val dosesPerDay: Int get() = frequency.dosesPerDay
    val dueCount: Int get() = if (isDue && isActive && !isOpen) dosesPerDay else 0
    val takenCount: Int get() = doses.size
    val takenDueCount: Int get() = minOf(doses.size, dueCount)
    val pendingCount: Int get() = maxOf(0, dueCount - doses.size)
    val isPending: Boolean get() = pendingCount > 0

    /** Nothing more to take today. */
    val isDone: Boolean get() = if (isDue) doses.size >= dosesPerDay else doses.isNotEmpty()
    val lastDose: Dose? get() = doses.lastOrNull()
}

/** Everything about one logical day. */
data class DaySummary(val day: DayKey, val items: List<ItemDay>) {
    val due: List<ItemDay> get() = items.filter { it.isDue }
    val notDue: List<ItemDay> get() = items.filter { !it.isDue }
    val dueDoses: Int get() = items.sumOf { it.dueCount }
    val takenDueDoses: Int get() = items.sumOf { it.takenDueCount }
    val pendingDoses: Int get() = maxOf(0, dueDoses - takenDueDoses)
    val pendingItems: List<ItemDay> get() = items.filter { it.isPending }
    val allTaken: Boolean get() = dueDoses > 0 && takenDueDoses >= dueDoses
    val isEmpty: Boolean get() = items.isEmpty()
    val allDoses: List<Dose> get() = items.flatMap { it.doses }.sortedBy { it.takenAt }
    val lastDose: Dose? get() = allDoses.lastOrNull()

    /** Weekly items whose week is still open on this day: not logged yet, and neither due nor missed. */
    val openCount: Int get() = items.count { it.isOpen }

    val status: DayStatus
        get() = when {
            dueDoses == 0 -> DayStatus.NOTHING_DUE
            takenDueDoses >= dueDoses -> DayStatus.COMPLETE
            takenDueDoses > 0 -> DayStatus.PARTIAL
            else -> DayStatus.MISSED
        }
}

data class HistoryCell(val day: DayKey, val status: DayStatus, val isToday: Boolean)

data class Adherence(val taken: Int, val due: Int) {
    /** Whole percent, rounded down so 100% only ever means perfect. Null when nothing was due. */
    val percent: Int?
        get() = if (due <= 0) null else Math.floor(taken.toDouble() * 100 / due.toDouble()).toInt()
}

/** A frequency era resolved to days: days before `until` used `frequency`. */
internal data class DayEra(val until: DayKey, val frequency: Frequency)

/** Archived days, from `from` up to, not including, `until`. */
internal data class DayRange(val from: DayKey, val until: DayKey) {
    fun contains(day: DayKey): Boolean = day >= from && day < until
}

/**
 * Read-only view over a StackState for one day-start setting. Everything is computed from doses. Ported line for line
 * from Shared/StackLogic.swift `StackEngine`; the Swift stays the truth where the two disagree.
 */
class StackEngine(val state: StackState, val clock: DayClock) {
    val orderedItems: List<Item> = state.orderedItems

    private val doseDays: Map<UUID, Map<DayKey, List<Dose>>>
    /** The days doses count for (R1), sorted. */
    private val sortedDoseDays: Map<UUID, List<DayKey>>
    /** The days doses were logged, sorted. Every other day reads these. */
    private val sortedLoggedDays: Map<UUID, List<DayKey>>
    private val latestDoseAt: Map<UUID, Instant>
    private val activeFrom: Map<UUID, DayKey>
    private val archivedFrom: Map<UUID, DayKey>
    private val frequencyEras: Map<UUID, List<DayEra>>
    private val pausedDays: Map<UUID, List<DayRange>>

    init {
        val grouped = LinkedHashMap<UUID, MutableList<Dose>>()
        for (dose in state.doses) grouped.getOrPut(dose.itemId) { mutableListOf() }.add(dose)

        // Each dose's logged day, in time order: the day that was being lived where it was logged.
        val fixedClocks = HashMap<Int, DayClock>()
        val logged = LinkedHashMap<UUID, List<Pair<Dose, DayKey>>>()
        val loggedDays = HashMap<UUID, List<DayKey>>()
        val latest = HashMap<UUID, Instant>()
        for ((itemId, list) in grouped) {
            val sorted = list.sortedBy { it.takenAt }
            val entries = ArrayList<Pair<Dose, DayKey>>(sorted.size)
            for (dose in sorted) {
                val offset = dose.utcOffset
                val day = if (offset != null && offset != clock.utcOffset(dose.takenAt)) {
                    // Logged in another time zone: it keeps the day that was being lived there.
                    val fixed = fixedClocks.getOrPut(offset) { clock.fixed(offset) }
                    fixed.day(dose.takenAt)
                } else {
                    clock.day(dose.takenAt)
                }
                entries.add(dose to day)
            }
            logged[itemId] = entries
            loggedDays[itemId] = entries.map { it.second }.toSortedSet().toList()
            sorted.lastOrNull()?.let { latest[itemId] = it.takenAt }
        }
        latestDoseAt = latest
        sortedLoggedDays = loggedDays

        // Frequency eras, archived stretches and each item's start come before the doses: a weekly dose's credit (R1)
        // reads all three.
        val from = HashMap<UUID, DayKey>()
        val archived = HashMap<UUID, DayKey>()
        val eras = HashMap<UUID, List<DayEra>>()
        val paused = HashMap<UUID, List<DayRange>>()
        for (item in state.items) {
            var start = clock.day(item.createdAt)
            val first = logged[item.id]?.minOfOrNull { it.second }
            if (first != null && first < start) start = first
            from[item.id] = start
            if (item.archived) {
                archived[item.id] = item.archivedAt?.let { clock.day(it) } ?: start
            }
            val past = item.pastFrequencies
            if (!past.isNullOrEmpty()) {
                eras[item.id] = past.sortedBy { it.until }.map { DayEra(until = clock.day(it.until), frequency = it.frequency) }
            }
            val pauses = item.pauses
            if (!pauses.isNullOrEmpty()) {
                paused[item.id] = pauses.map { DayRange(from = clock.day(it.from), until = clock.day(it.until)) }
            }
        }
        activeFrom = from
        archivedFrom = archived
        frequencyEras = eras
        pausedDays = paused

        // The day each dose counts for. Only a weekly item's can differ from the day it was logged (R1); the dose keeps
        // its real time either way.
        val items = HashMap<UUID, Item>()
        for (item in state.items) items.putIfAbsent(item.id, item)
        val byDay = HashMap<UUID, Map<DayKey, List<Dose>>>()
        val days = HashMap<UUID, List<DayKey>>()
        for ((itemId, entries) in logged) {
            val map = HashMap<DayKey, MutableList<Dose>>()
            for ((dose, loggedDay) in entries) {
                var day = loggedDay
                val item = items[itemId]
                if (item != null) {
                    day = creditedDay(
                        logged = loggedDay, start = from[itemId], counted = map,
                        frequency = { frequencyOf(item, it, eras[itemId]) },
                        paused = { isPaused(it, archived[itemId], paused[itemId]) },
                    )
                }
                map.getOrPut(day) { mutableListOf() }.add(dose)
            }
            byDay[itemId] = map
            days[itemId] = map.keys.sorted()
        }
        doseDays = byDay
        sortedDoseDays = days
    }

    companion object {
        /**
         * TAKE ALL, a widget row, the tile and the nudge skip an item logged this recently, so a second tap seconds later
         * never logs a 2x or 3x item's next dose on top of the first. A tap on the row in the app is never held back.
         */
        val repeatGuard: Duration = Duration.ofHours(1)

        /**
         * R1, a weekly dose counts for its week. `logged` is the day the dose was logged, `counted` what already counts
         * for each day (the item's earlier doses, in time order). Any other schedule keeps the logged day.
         * a) It counts for the latest due day on or before it (P, 0 to 6 days back) when P is on or after the start, not
         *    archived, has the same Weekly schedule, and nothing counts for P yet.
         * b) Otherwise, when P already has its dose, a dose 1 to 3 days before the next due day (N) counts for N, if N
         *    has the same schedule, is not archived and has nothing yet.
         * c) Otherwise it stays on the day it was logged.
         */
        private fun creditedDay(
            logged: DayKey,
            start: DayKey?,
            counted: Map<DayKey, List<Dose>>,
            frequency: (DayKey) -> Frequency,
            paused: (DayKey) -> Boolean,
        ): DayKey {
            val schedule = frequency(logged)
            if (schedule !is Frequency.Weekdays || schedule.days.size != 1) return logged
            val weekday = schedule.days.first()
            val due = logged.adding(-((logged.weekday - weekday + 7) % 7))
            val dueHasDose = !(counted[due]?.isEmpty() ?: true)
            if (!dueHasDose && start != null && due >= start && !paused(due) && frequency(due) == schedule) return due
            val next = due.adding(7)
            if (dueHasDose && logged.distanceTo(next) in 1..3 && frequency(next) == schedule && !paused(next) &&
                (counted[next]?.isEmpty() ?: true)
            ) {
                return next
            }
            return logged
        }

        private fun frequencyOf(item: Item, day: DayKey, eras: List<DayEra>?): Frequency =
            eras?.firstOrNull { day < it.until }?.frequency ?: item.frequency

        private fun isPaused(day: DayKey, archivedFrom: DayKey?, pauses: List<DayRange>?): Boolean {
            if (archivedFrom != null && day >= archivedFrom) return true
            return pauses?.any { it.contains(day) } ?: false
        }
    }

    // MARK: Days

    fun today(now: Instant): DayKey = clock.day(now)

    /** True if the item was part of the stack on that day: added on or before it, and not archived then. */
    fun isActive(item: Item, day: DayKey): Boolean {
        val start = activeFrom[item.id] ?: return false
        if (day < start) return false
        val end = archivedFrom[item.id]
        if (end != null && day >= end) return false
        val ranges = pausedDays[item.id]
        if (ranges != null && ranges.any { it.contains(day) }) {
            // A dose logged for an archived day proves it was taken, as a backfill before the add does.
            return doses(item.id, day).isNotEmpty()
        }
        return true
    }

    /** True if the item sat archived on that day. */
    fun isPaused(item: Item, day: DayKey): Boolean = isPaused(day, archivedFrom[item.id], pausedDays[item.id])

    /** The frequency in force on a day, so changing it in settings never rewrites earlier days. */
    fun frequency(item: Item, day: DayKey): Frequency = frequencyOf(item, day, frequencyEras[item.id])

    /** Weekly: a one-day Days set on that day. Only these get a week (SPEC 3.3, R1 to R5). */
    fun isWeekly(item: Item, day: DayKey): Boolean {
        val f = frequency(item, day)
        return f is Frequency.Weekdays && f.days.size == 1
    }

    fun doses(itemId: UUID, day: DayKey): List<Dose> = doseDays[itemId]?.get(day) ?: emptyList()

    /**
     * The last day a dose was logged strictly before `day`, for Every other day. It reads the logged day, not the day a
     * weekly dose counts for (R1), so switching from Weekly to Every other day after a late dose keeps the real gap.
     */
    fun lastDoseDay(itemId: UUID, before: DayKey): DayKey? {
        val days = sortedLoggedDays[itemId]
        if (days.isNullOrEmpty()) return null
        var lo = 0
        var hi = days.size
        while (lo < hi) {
            val mid = (lo + hi) / 2
            if (days[mid] < before) lo = mid + 1 else hi = mid
        }
        return if (lo > 0) days[lo - 1] else null
    }

    fun isDue(item: Item, day: DayKey): Boolean = when (val f = frequency(item, day)) {
        is Frequency.Daily -> true
        is Frequency.Weekdays -> f.days.contains(day.weekday)
        Frequency.AlternateDays -> {
            val last = lastDoseDay(item.id, before = day)
            last == null || last.distanceTo(day) >= 2
        }
    }

    /**
     * One item on one day. `today`, the day being lived, turns on the open week (R2): a weekly due day with nothing for
     * it, 1 to 6 days before `today`, is open, so it is neither due nor missed. Null turns the rule off (the nudge plan
     * and the widgets, which only look at today and later).
     */
    fun itemDay(item: Item, day: DayKey, asOf: DayKey? = null): ItemDay {
        val due = isDue(item, day)
        val active = isActive(item, day)
        val doses = doses(item.id, day)
        var open = false
        if (asOf != null && due && active && doses.isEmpty() && isWeekly(item, day)) {
            open = day.distanceTo(asOf) in 1..6
        }
        return ItemDay(
            item = item, day = day, frequency = frequency(item, day), isDue = due, isActive = active,
            isPaused = isPaused(item, day), doses = doses, isOpen = open,
        )
    }

    /**
     * Today's Not today row for a weekly item on a day that is not its due day: the week today is in (SPEC 3.3). The
     * next due day when an early dose already counts for it (R1 b), otherwise the due day of this week, open or logged.
     * Null when the item is not weekly today, is due today, or this week's due day is not one of its days.
     */
    fun weekRow(item: Item, today: DayKey): ItemDay? {
        if (isDue(item, today)) return null
        val f = frequency(item, today)
        if (f !is Frequency.Weekdays || f.days.size != 1) return null
        val weekday = f.days.first()
        val due = today.adding(-((today.weekday - weekday + 7) % 7))
        val next = due.adding(7)
        if (doses(item.id, next).isNotEmpty()) return itemDay(item, next, asOf = today)
        if (frequency(item, due) != frequency(item, today) || !isDue(item, due) || !isActive(item, due)) return null
        return itemDay(item, due, asOf = today)
    }

    /**
     * R1 b from Today: this week's due day already has its dose, nothing counts for the next due day yet, and today is 1
     * to 3 days before it, so a dose logged now counts for the next due day. Today's Not today row is then today's quiet
     * ring. On the 3 days after the due day it is false: the lit ring stays, and a tap never logs a second dose.
     */
    fun takesEarlyDose(item: Item, today: DayKey): Boolean {
        val week = weekRow(item, today) ?: return false
        if (week.day >= today || week.doses.isEmpty()) return false
        return today.distanceTo(week.day.adding(7)) in 1..3
    }

    /** Whether anything at all counts for a day in this span: the honest repair asks it of the week before yesterday. */
    fun loggedAnything(from: DayKey, through: DayKey): Boolean {
        if (from > through) return false
        return sortedDoseDays.values.any { days -> days.any { it >= from && it <= through } }
    }

    // MARK: Quick logging

    /** When the item was last logged, on any day. */
    fun latestDose(itemId: UUID): Instant? = latestDoseAt[itemId]

    /**
     * True when TAKE ALL, a widget row, the tile or the nudge may log this row now: a dose is still pending, and the item
     * was not logged within the repeat guard.
     */
    fun canQuickLog(row: ItemDay, now: Instant): Boolean {
        if (!row.isPending) return false
        val last = latestDoseAt[row.item.id] ?: return true
        return Duration.between(last, now) >= repeatGuard
    }

    /** The rows TAKE ALL logs right now. */
    fun quickLogRows(summary: DaySummary, now: Instant): List<ItemDay> = summary.items.filter { canQuickLog(it, now) }

    /** When a pending row held back by the repeat guard can be quick logged again (null when it is not held back). */
    fun quickLogResumes(row: ItemDay, now: Instant): Instant? {
        if (!row.isPending) return null
        val last = latestDoseAt[row.item.id] ?: return null
        val resumes = last.plus(repeatGuard)
        return if (resumes > now) resumes else null
    }

    /**
     * A day as history sees it: only items that were in the stack that day. With `asOf`, a weekly item whose week is
     * still open counts neither way (R2); null turns that off.
     */
    fun summary(day: DayKey, asOf: DayKey? = null): DaySummary =
        DaySummary(day, orderedItems.filter { isActive(it, day) }.map { itemDay(it, day, asOf) })

    /** TODAY: every item that is not archived, in the user's order. */
    fun todaySummary(now: Instant): DaySummary {
        val day = clock.day(now)
        return DaySummary(day, orderedItems.filter { !it.archived }.map { itemDay(it, day, asOf = day) })
    }

    /** The day sheet: items in the stack that day plus current items, so a missed day can be backfilled. */
    fun sheetSummary(day: DayKey, asOf: DayKey? = null): DaySummary {
        val items = orderedItems.filter { isActive(it, day) || !it.archived }
        return DaySummary(day, items.map { itemDay(it, day, asOf) })
    }

    /** The next day after `after` on which the item is due, assuming nothing else gets logged. */
    fun nextDueDay(item: Item, after: DayKey): DayKey? = when (val f = item.frequency) {
        is Frequency.Daily -> after.adding(1)
        is Frequency.Weekdays -> {
            if (f.days.isEmpty()) {
                null
            } else {
                (1..7).map { after.adding(it) }.firstOrNull { f.days.contains(it.weekday) }
            }
        }
        Frequency.AlternateDays -> {
            val last = lastDoseDay(item.id, before = after.adding(1))
            if (last == null) {
                after.adding(1)
            } else {
                val candidate = last.adding(2)
                if (candidate > after) candidate else after.adding(1)
            }
        }
    }

    // MARK: Stats

    /**
     * Consecutive complete days ending today (today counts once complete; days with nothing due are skipped). A weekly
     * item's open week neither breaks nor grows it, and a week nothing was logged for breaks it on the next due day.
     */
    fun streak(today: DayKey): Int {
        val earliest = activeFrom.values.minOrNull() ?: return 0
        var count = if (summary(today, asOf = today).status == DayStatus.COMPLETE) 1 else 0
        var day = today.adding(-1)
        while (day >= earliest) {
            when (summary(day, asOf = today).status) {
                DayStatus.COMPLETE -> count += 1
                DayStatus.NOTHING_DUE, DayStatus.FUTURE -> Unit
                DayStatus.PARTIAL, DayStatus.MISSED -> return count
            }
            day = day.adding(-1)
        }
        return count
    }

    /**
     * Due doses taken over the last `days` days. Today only counts what is already taken, so the number never drops
     * just because the day is not over.
     */
    fun adherence(today: DayKey, days: Int = 30): Adherence {
        var taken = 0
        var due = 0
        for (offset in 0 until maxOf(days, 1)) {
            val summary = summary(today.adding(-offset), asOf = today)
            taken += summary.takenDueDoses
            due += if (offset == 0) summary.takenDueDoses else summary.dueDoses
        }
        return Adherence(taken = taken, due = due)
    }

    /** Rows of 7 days (Monday first), oldest week first, the last row holding today. */
    fun history(today: DayKey, weeks: Int = 5): List<List<HistoryCell>> {
        val count = maxOf(weeks, 1)
        val thisMonday = today.adding(-today.mondayIndex)
        val start = thisMonday.adding(-7 * (count - 1))
        return (0 until count).map { week ->
            (0 until 7).map { offset ->
                val day = start.adding(week * 7 + offset)
                if (day > today) {
                    HistoryCell(day, DayStatus.FUTURE, isToday = false)
                } else {
                    HistoryCell(day, summary(day, asOf = today).status, isToday = day == today)
                }
            }
        }
    }
}
