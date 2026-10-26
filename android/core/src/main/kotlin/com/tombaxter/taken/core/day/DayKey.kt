package com.tombaxter.taken.core.day

import java.time.Instant
import java.time.ZoneId

/**
 * A calendar day as a plain number: days since 1970-01-01 (proleptic Gregorian). Pure integer arithmetic, so adding days
 * never trips over DST or time zones. Ported from Shared/DayMath.swift `DayKey`.
 */
data class DayKey(val ordinal: Int) : Comparable<DayKey> {

    /** Howard Hinnant's days_from_civil. */
    constructor(year: Int, month: Int, day: Int) : this(civilToOrdinal(year, month, day))

    data class Ymd(val year: Int, val month: Int, val day: Int)

    /** (year, month, day) of this key. */
    val ymd: Ymd
        get() {
            val z = ordinal + 719468
            val era = (if (z >= 0) z else z - 146096) / 146097
            val doe = z - era * 146097
            val yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
            val y = yoe + era * 400
            val doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
            val mp = (5 * doy + 2) / 153
            val d = doy - (153 * mp + 2) / 5 + 1
            val m = if (mp < 10) mp + 3 else mp - 9
            return Ymd(if (m <= 2) y + 1 else y, m, d)
        }

    val dayOfMonth: Int get() = ymd.day

    /** 0 = Monday ... 6 = Sunday. 1970-01-01 was a Thursday. */
    val mondayIndex: Int get() = ((ordinal + 3) % 7 + 7) % 7

    /** Calendar weekday numbering: 1 = Sunday ... 7 = Saturday. */
    val weekday: Int get() = if (mondayIndex == 6) 1 else mondayIndex + 2

    fun adding(days: Int): DayKey = DayKey(ordinal + days)

    /** Whole days from this to [other] (positive when other is later). */
    fun distanceTo(other: DayKey): Int = other.ordinal - ordinal

    override fun compareTo(other: DayKey): Int = ordinal.compareTo(other.ordinal)

    /** "2026-10-13" */
    val iso: String
        get() {
            val (year, month, day) = ymd
            return String.format(java.util.Locale.ROOT, "%04d-%02d-%02d", year, month, day)
        }

    companion object {
        fun civilToOrdinal(year: Int, month: Int, day: Int): Int {
            val y = if (month <= 2) year - 1 else year
            val era = (if (y >= 0) y else y - 399) / 400
            val yoe = y - era * 400
            val mp = (month + 9) % 12
            val doy = (153 * mp + 2) / 5 + day - 1
            val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
            return era * 146097 + doe - 719468
        }

        /** "2026-10-13", a date that exists. Null for anything else. */
        fun fromIso(text: String): DayKey? {
            val parts = text.trim().split("-")
            if (parts.size != 3 || parts[0].length != 4) return null
            val year = parts[0].toIntOrNull() ?: return null
            val month = parts[1].toIntOrNull() ?: return null
            val day = parts[2].toIntOrNull() ?: return null
            if (month !in 1..12 || day !in 1..31) return null
            val key = DayKey(year, month, day)
            // 31 February would land in March: not a date.
            if (key.ymd.month != month || key.ymd.day != day) return null
            return key
        }

        /** The calendar date a moment falls on in a time zone (midnight to midnight, no day start). */
        fun calendarDateOf(instant: Instant, zone: ZoneId): DayKey {
            val date = instant.atZone(zone)
            return DayKey(date.year, date.monthValue, date.dayOfMonth)
        }
    }
}
