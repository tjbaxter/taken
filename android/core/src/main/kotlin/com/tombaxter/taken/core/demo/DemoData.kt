package com.tombaxter.taken.core.demo

import com.tombaxter.taken.core.catalog.Catalog
import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.model.Dose
import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.Item
import com.tombaxter.taken.core.model.StackSettings
import com.tombaxter.taken.core.model.StackState
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime

/**
 * Which stack a demo capture seeds. The store screenshots come in two sets (REDESIGN.md "App Store pack for 1.1"):
 * `US`, the standard stack plus Semaglutide weekly on Thursday; `NEUTRAL`, a "Weekly shot" row and no prescription-only
 * medicine. Every other capture uses `STANDARD`. Ported from Shared/DemoData.swift; Android reads it only in debug code.
 */
enum class DemoStack(val raw: String) {
    STANDARD("standard"), US("us"), NEUTRAL("neutral");

    /** The store sets show a Thursday, the day their weekly row is due. */
    val isStoreSet: Boolean get() = this != STANDARD

    /** The weekly row's name in a store set. */
    val weeklyName: String?
        get() = when (this) {
            STANDARD -> null
            US -> "Semaglutide"
            NEUTRAL -> "Weekly shot"
        }

    /** What the Add sheet's type-ahead capture has typed: "tum", or "mag" for the neutral set. */
    val typedQuery: String get() = if (this == NEUTRAL) "mag" else "tum"

    companion object {
        /** `-demo-stack us|neutral` from a list of arguments; anything else is the standard stack. */
        fun fromArguments(arguments: List<String>): DemoStack {
            val index = arguments.indexOf("-demo-stack")
            if (index < 0 || index + 1 >= arguments.size) return STANDARD
            return entries.firstOrNull { it.raw == arguments[index + 1] } ?: STANDARD
        }
    }
}

/** A realistic stack with weeks of history, for demo captures and widget previews. Never the real store. */
object DemoData {
    /** Thursday in Calendar numbering (1 = Sunday ... 7 = Saturday): the store sets' day. */
    const val STORE_WEEKDAY = 5

    /**
     * Today at 21:41 local time: the end-of-day moment Taken exists for. A store set moves back to the most recent
     * Thursday, so its weekly row is due and taken that day.
     */
    fun referenceNow(real: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault(), stack: DemoStack = DemoStack.STANDARD): Instant {
        val c = real.atZone(zone)
        val evening = ZonedDateTime.of(c.year, c.monthValue, c.dayOfMonth, 21, 41, 0, 0, zone)
        if (!stack.isStoreSet) return evening.toInstant()
        // java.time numbers Monday 1 ... Sunday 7; Calendar numbers Sunday 1 ... Saturday 7.
        val weekday = c.dayOfWeek.value % 7 + 1
        val back = (weekday - STORE_WEEKDAY + 7) % 7
        return evening.minusDays(back.toLong()).toInstant()
    }

    /** The demo's settings: the nudge on, waking at 07:00 (the default), so the day rolls over at 03:00. */
    val settings: StackSettings get() = StackSettings(reminderEnabled = true)

    /**
     * `yesterdayPartial` leaves last night's Magnesium out, for the repair capture. A store set's weekly row is due on
     * today's weekday and logged that morning, every week.
     */
    fun state(
        now: Instant,
        allTaken: Boolean,
        yesterdayPartial: Boolean = false,
        zone: ZoneId = ZoneId.systemDefault(),
        stack: DemoStack = DemoStack.STANDARD,
    ): StackState {
        val clock = DayClock(settings.dayStartHour, zone)
        val today = clock.day(now)
        val created = clock.start(today.adding(-60))
        val random = SeededRandom(0x7A4E_2026L)

        val vd3 = Item(name = "Vitamin D3", code = "VD3", frequency = Frequency.Daily(1), createdAt = created, sortIndex = 0)
        val fin = Item(name = "Finasteride", code = "FIN", frequency = Frequency.Daily(1), createdAt = created, sortIndex = 1)
        val fsh = Item(name = "Fish Oil", code = "FSH", frequency = Frequency.Daily(2), createdAt = created, sortIndex = 2)
        val cre = Item(name = "Creatine", code = "CRE", frequency = Frequency.Daily(1), createdAt = created, sortIndex = 3)
        val mag = Item(name = "Magnesium", code = "MAG", frequency = Frequency.Daily(1), createdAt = created, sortIndex = 4)
        val znc = Item(name = "Zinc", code = "ZNC", frequency = Frequency.AlternateDays, createdAt = created, sortIndex = 5)
        // A weekly dose on its day (the Add sheet saves Weekly as a one-day Days set), right after the stack's first rows.
        val weekly = stack.weeklyName?.let { name ->
            Item(name = name, code = Catalog.code(name), frequency = Frequency.Weekdays(setOf(today.weekday)), createdAt = created,
                sortIndex = 1)
        }

        val doses = ArrayList<Dose>()
        fun log(item: Item, day: DayKey, hour: Int, minute: Int) {
            doses.add(Dose(itemId = item.id, takenAt = clock.date(day, hour, minute)))
        }

        val takesFinasteride = stack != DemoStack.NEUTRAL
        for (offset in 59 downTo 1) {
            val day = today.adding(-offset)
            val morning = 24 + (random.next() % 28).toInt()
            log(vd3, day, 7, morning)
            if (takesFinasteride) log(fin, day, 7, morning)
            log(fsh, day, 7, morning + 1)
            if (offset != 27) log(cre, day, 7, morning + 2)
            if (offset != 22) log(fsh, day, 18 + (random.next() % 2).toInt(), (random.next() % 55).toInt())
            if (offset != 15 && offset != 27 && !(yesterdayPartial && offset == 1)) {
                log(mag, day, 21, 2 + (random.next() % 40).toInt())
            }
            if (offset % 2 == 1) log(znc, day, 7, morning + 3)
            // Its own minute, drawn from nothing, so the other rows' history is the same in every stack.
            if (weekly != null && offset % 7 == 0) log(weekly, day, 7, morning + 4)
        }

        log(vd3, today, 7, 42)
        if (takesFinasteride) log(fin, today, 7, 42)
        log(fsh, today, 7, 43)
        log(cre, today, 7, 44)
        if (weekly != null) log(weekly, today, 7, 45)
        if (allTaken) {
            log(fsh, today, 19, 6)
            log(mag, today, 21, 12)
        }

        val items = (if (takesFinasteride) listOf(vd3, fin, fsh, cre, mag, znc) else listOf(vd3, fsh, cre, mag, znc)).toMutableList()
        if (weekly != null) items.add(if (takesFinasteride) 2 else 1, weekly)
        val ordered = items.mapIndexed { index, item -> item.copy(sortIndex = index) }
        return StackState(items = ordered, doses = doses, settings = settings)
    }

    /** The partly taken day shown in the day-sheet screenshot. */
    fun sheetDay(now: Instant, zone: ZoneId = ZoneId.systemDefault()): DayKey =
        DayClock(settings.dayStartHour, zone).day(now).adding(-15)

    /** The demo profile's name: its initials on every tab. */
    const val PROFILE_NAME = "Alex Morgan"
}

/** Small deterministic generator so demo history looks the same on every run: state × 6364136223846793005 + 1442695040888963407. */
class SeededRandom(seed: Long) {
    private var state: Long = seed

    fun next(): Long {
        state = state * 6_364_136_223_846_793_005L + 1_442_695_040_888_963_407L
        return state ushr 33
    }
}
