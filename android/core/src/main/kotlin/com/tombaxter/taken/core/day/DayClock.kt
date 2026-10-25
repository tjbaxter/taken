package com.tombaxter.taken.core.day

import com.tombaxter.taken.core.model.Dose
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime

/**
 * Maps absolute moments to the day the user was living, using the day-start hour. A 01:00 dose with a 04:00 rollover
 * belongs to the previous day. Ported from Shared/DayMath.swift `DayClock`; the Gregorian calendar in a zone is
 * `java.time` here.
 */
class DayClock(dayStartHour: Int, val zone: ZoneId = ZoneId.systemDefault()) {
    val dayStartHour: Int = dayStartHour.coerceIn(0, 23)

    /** The logical day a moment belongs to (wall clock based, so DST safe). */
    fun day(instant: Instant): DayKey {
        val c = instant.atZone(zone)
        val key = DayKey(c.year, c.monthValue, c.dayOfMonth)
        return if (c.hour < dayStartHour) key.adding(-1) else key
    }

    /** The moment a logical day starts: its calendar date at the day-start hour. */
    fun start(day: DayKey): Instant {
        val (y, m, d) = day.ymd
        return ZonedDateTime.of(y, m, d, dayStartHour, 0, 0, 0, zone).toInstant()
    }

    fun end(day: DayKey): Instant = start(day.adding(1))

    /** A wall-clock time on a logical day. Hours before the rollover fall on the next calendar date. */
    fun date(on: DayKey, hour: Int, minute: Int): Instant {
        val calendarDay = if (hour < dayStartHour) on.adding(1) else on
        val (y, m, d) = calendarDay.ymd
        return ZonedDateTime.of(y, m, d, hour.coerceIn(0, 23), minute.coerceIn(0, 59), 0, 0, zone).toInstant()
    }

    fun nextRollover(after: Instant): Instant = start(day(after).adding(1))

    data class HourMinute(val hour: Int, val minute: Int)

    fun hourMinute(instant: Instant): HourMinute {
        val c = instant.atZone(zone)
        return HourMinute(c.hour, c.minute)
    }

    /** Minutes since local midnight. */
    fun minutesOfDay(instant: Instant): Int {
        val hm = hourMinute(instant)
        return hm.hour * 60 + hm.minute
    }

    /** Seconds east of UTC in this clock's time zone at a moment. */
    fun utcOffset(at: Instant): Int = zone.rules.getOffset(at).totalSeconds

    /** The same day start at a fixed UTC offset: how a dose logged in another zone finds its day. */
    fun fixed(utcOffset: Int): DayClock = DayClock(dayStartHour, ZoneOffset.ofTotalSeconds(utcOffset))

    /**
     * The day a dose belongs to: the day that was being lived where it was logged. A dose with no recorded offset, or
     * one logged in this clock's offset, reads in this clock's zone.
     */
    fun day(dose: Dose): DayKey {
        val offset = dose.utcOffset
        if (offset == null || offset == utcOffset(dose.takenAt)) return day(dose.takenAt)
        return fixed(offset).day(dose.takenAt)
    }

    companion object {
        /** Seconds east of UTC for a zone at a moment (`TimeZone.secondsFromGMT(for:)`). */
        fun offset(zone: ZoneId, at: Instant): Int = zone.rules.getOffset(at).totalSeconds
    }
}
