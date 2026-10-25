package com.tombaxter.taken.core.format

import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.model.Dose
import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.stack.DayStatus
import com.tombaxter.taken.core.stack.DaySummary
import com.tombaxter.taken.core.stack.ItemDay
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

/**
 * Text formatting. Words in sentence case, times on the 24-hour clock everywhere on screen whatever the locale; spoken
 * times (TalkBack) in the locale's short style with narrow and no-break spaces made plain. Ported from
 * Shared/Format.swift.
 */
object Fmt {
    private val weekdaysCaps = listOf("MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN")
    private val monthsCaps = listOf("JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC")
    private val weekdaysShort = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
    private val weekdaysLong = listOf("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
    private val monthsShort = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
    private val monthsLong = listOf(
        "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November",
        "December",
    )
    val weekdayLetters = listOf("M", "T", "W", "T", "F", "S", "S")

    private fun month(list: List<String>, month: Int): String = list[(month - 1).coerceIn(0, 11)]

    private fun two(value: Int): String = String.format(Locale.ROOT, "%02d", value)

    /** "07:42" */
    fun clock(instant: Instant, clock: DayClock): String {
        val hm = clock.hourMinute(instant)
        return "${two(hm.hour)}:${two(hm.minute)}"
    }

    /** "04:00" for an hour. */
    fun hour(hour: Int): String = "${two(hour)}:00"

    /** "21:00" for minutes after midnight. */
    fun minutes(minutes: Int): String = "${two(minutes / 60)}:${two(minutes % 60)}"

    /** Whole minutes from `date` to `now`, truncated toward zero as Swift's `Int(interval / 60)`. */
    private fun minutesBetween(date: Instant, now: Instant): Long = (Duration.between(date, now).toMillis() / 60_000.0).toLong()

    /** "9h ago", "12m ago", "now". */
    fun ago(date: Instant, now: Instant): String {
        val minutes = minutesBetween(date, now)
        if (minutes < 1) return "now"
        if (minutes < 60) return "${minutes}m ago"
        return "${minutes / 60}h ago"
    }

    /** "9h 12m ago", and "1d 2h ago" from a day on (a weekly dose logged on an earlier day). */
    fun agoDetailed(date: Instant, now: Instant): String {
        val minutes = minutesBetween(date, now)
        if (minutes < 1) return "just now"
        if (minutes < 60) return "${minutes}m ago"
        val hours = minutes / 60
        if (hours >= 24) {
            val rest = hours % 24
            return if (rest == 0L) "${hours / 24}d ago" else "${hours / 24}d ${rest}h ago"
        }
        val rest = minutes % 60
        return if (rest == 0L) "${hours}h ago" else "${hours}h ${rest}m ago"
    }

    /**
     * A dose's time as a row or a chip shows it: "08:12" when it was logged on the day being viewed, otherwise with the
     * day it was logged, "Fri 08:12" (a weekly dose that counts for its due day).
     */
    fun doseClock(dose: Dose, viewing: DayKey, clock: DayClock): String {
        val logged = clock.day(dose)
        val time = Fmt.clock(dose.takenAt, clock)
        return if (logged == viewing) time else "${weekdaysShort[logged.mondayIndex]} $time"
    }

    /** The same for TalkBack: "at 8:12 AM", or "Friday at 8:12 AM" when it was logged on another day. */
    fun spokenDose(dose: Dose, viewing: DayKey, clock: DayClock, locale: Locale = Locale.getDefault()): String {
        val logged = clock.day(dose)
        val time = spokenTime(dose.takenAt, clock.zone, locale)
        return if (logged == viewing) "at $time" else "${weekday(logged)} at $time"
    }

    /**
     * A row's doses for TalkBack: "at 7:42 AM and 9:00 AM" when all were logged on the day being viewed; otherwise each
     * with its day, "Tuesday at 8:12 AM".
     */
    fun spokenDoses(doses: List<Dose>, viewing: DayKey, clock: DayClock, locale: Locale = Locale.getDefault()): String {
        if (doses.all { clock.day(it) == viewing }) {
            return "at " + list(doses.map { spokenTime(it.takenAt, clock.zone, locale) })
        }
        return list(doses.map { spokenDose(it, viewing, clock, locale) })
    }

    /** "8:12 AM" or "08:12", in a zone and the locale's own short time, narrow and no-break spaces made plain. */
    fun spokenTime(instant: Instant, zone: ZoneId, locale: Locale): String {
        val formatter = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale).withZone(zone)
        return formatter.format(instant).replace('\u202F', ' ').replace('\u00A0', ' ')
    }

    /** "Thursday" */
    fun weekday(day: DayKey): String = weekdaysLong[day.mondayIndex]

    /** "MON 12 OCT", the short day the nudge's notifications name. */
    fun dayHeader(day: DayKey): String {
        val ymd = day.ymd
        return "${weekdaysCaps[day.mondayIndex]} ${ymd.day} ${month(monthsCaps, ymd.month)}"
    }

    /** "Tuesday 13 October", under the Today title and on the day sheet. */
    fun longDay(day: DayKey): String {
        val ymd = day.ymd
        return "${weekdaysLong[day.mondayIndex]} ${ymd.day} ${month(monthsLong, ymd.month)}"
    }

    /** "19 Oct", or "12 Oct 2027" with the year, for a moment in a time zone. */
    fun shortDate(instant: Instant, year: Boolean, zone: ZoneId = ZoneId.systemDefault()): String {
        val c = instant.atZone(zone)
        val dayMonth = "${c.dayOfMonth} ${month(monthsShort, c.monthValue)}"
        return if (year) "$dayMonth ${c.year}" else dayMonth
    }

    /** "Daily", "2x daily", "Every other day", "Weekly · Thu", "Weekdays", "Mon Wed Fri". */
    fun frequency(frequency: Frequency): String = when (frequency) {
        is Frequency.Daily -> if (frequency.times <= 1) "Daily" else "${minOf(frequency.times, 3)}x daily"
        Frequency.AlternateDays -> "Every other day"
        is Frequency.Weekdays -> {
            val set = frequency.days
            when {
                set.isEmpty() -> "No days set"
                set.size == 7 -> "Daily"
                // One day is Weekly: a weekly shot on its day.
                set.size == 1 -> "Weekly · ${weekdaysShort[(set.first() + 5) % 7]}"
                set == setOf(2, 3, 4, 5, 6) -> "Weekdays"
                set == setOf(1, 7) -> "Weekends"
                // Monday-first order.
                else -> listOf(2, 3, 4, 5, 6, 7, 1).filter { set.contains(it) }
                    .joinToString(" ") { weekdaysShort[(it + 5) % 7] }
            }
        }
    }

    /**
     * Under an item in Not today: "Every other day · Next: Thursday". A weekly item names its day once, "Weekly · Next:
     * Thursday".
     */
    fun notDue(frequency: Frequency, next: String): String {
        if (frequency is Frequency.Weekdays && frequency.days.size == 1) return "Weekly · $next"
        return "${Fmt.frequency(frequency)} · $next"
    }

    /** The item sheet's one fixed line under a Weekly schedule. Taken only records doses. */
    const val MISSED_DOSE_NOTE = "Missed a dose? Follow your medicine's leaflet, or ask your pharmacist or doctor."

    /**
     * Under a weekly item in Not today: "Weekly · Thu · Not logged" while the week is open, "Weekly · Next: Thursday"
     * once it is logged, "Weekly · Counts for Thursday" for an early dose. No countdown.
     */
    fun weekNote(row: ItemDay, today: DayKey): String {
        if (row.day > today) return "Weekly · Counts for ${weekday(row.day)}"
        if (row.isOpen) return "${frequency(row.frequency)} · Not logged"
        return notDue(row.frequency, next(row.day.adding(7), today))
    }

    /** "Next: tomorrow", "Next: Thursday", "Next: 14 Oct" */
    fun next(next: DayKey?, today: DayKey): String {
        if (next == null) return "Not scheduled"
        val gap = today.distanceTo(next)
        if (gap <= 1) return "Next: tomorrow"
        if (gap < 7) return "Next: ${weekdaysLong[next.mondayIndex]}"
        val ymd = next.ymd
        return "Next: ${ymd.day} ${month(monthsShort, ymd.month)}"
    }

    /** Today's progress line, in doses as the widgets count them: "4 of 6 taken", or "All taken". Null when nothing is due. */
    fun progress(summary: DaySummary): String? {
        if (summary.dueDoses <= 0) return null
        if (summary.allTaken) return "All taken"
        return "${summary.takenDueDoses} of ${summary.dueDoses} taken"
    }

    /**
     * The day sheet's status line. Today is still running, so what is not taken yet is pending, not missed. A weekly item
     * whose week is still open is "not logged", never missed.
     */
    fun daySheetStatus(summary: DaySummary, isToday: Boolean): String {
        val open = summary.openCount
        if (open > 0) {
            val parts = mutableListOf("${summary.takenDueDoses} of ${summary.dueDoses + open} taken")
            if (summary.pendingDoses > 0) parts.add("${summary.pendingDoses} ${if (isToday) "pending" else "missed"}")
            parts.add("$open not logged")
            return parts.joinToString(" · ")
        }
        return when (summary.status) {
            DayStatus.NOTHING_DUE ->
                if (summary.allDoses.isEmpty()) "Nothing due" else "${summary.allDoses.size} logged · nothing due"
            DayStatus.COMPLETE -> "All taken"
            DayStatus.PARTIAL ->
                "${summary.takenDueDoses} of ${summary.dueDoses} taken · ${summary.pendingDoses} ${if (isToday) "pending" else "missed"}"
            DayStatus.MISSED -> if (isToday) "${summary.dueDoses} pending" else "Nothing logged"
            DayStatus.FUTURE -> ""
        }
    }

    /** A day sheet row: "Daily · taken", "2x daily · 1 of 2", "Daily · missed", "Weekly · Thu · not logged". */
    fun dayItemStatus(row: ItemDay, isToday: Boolean): String {
        val schedule = frequency(row.frequency)
        if (!row.isActive && row.doses.isEmpty()) return "$schedule · ${if (row.isPaused) "archived" else "added later"}"
        if (row.isOpen) return "$schedule · not logged"
        if (!row.isDue) return "$schedule · not due"
        if (row.isDone) return "$schedule · taken"
        if (row.doses.isEmpty()) return "$schedule · ${if (isToday) "pending" else "missed"}"
        return "$schedule · ${row.takenCount} of ${row.dosesPerDay}"
    }

    /** Locale aware short time for TalkBack: "7:42 AM" or "07:42". */
    fun spoken(instant: Instant, zone: ZoneId = ZoneId.systemDefault(), locale: Locale = Locale.getDefault()): String =
        spokenTime(instant, zone, locale)

    /** "Vitamin D3, Fish Oil and Zinc" */
    fun list(parts: List<String>): String = when (parts.size) {
        0 -> ""
        1 -> parts[0]
        else -> parts.dropLast(1).joinToString(", ") + " and " + parts.last()
    }
}
