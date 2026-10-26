package com.tombaxter.taken.core.model

import com.tombaxter.taken.core.theme.ThemeID
import java.time.Instant
import java.util.UUID

/** How often an item is due. Ported from Shared/Model.swift. */
sealed class Frequency {
    /** Every day, `times` doses (1...3). */
    data class Daily(val times: Int) : Frequency()

    /** Due if never taken, or if the last dose was two or more days ago. */
    data object AlternateDays : Frequency()

    /** Due on the given weekdays (Calendar numbering: 1 = Sunday ... 7 = Saturday). Weekly is a one-day set. */
    data class Weekdays(val days: Set<Int>) : Frequency()

    /** Doses due on a due day. */
    val dosesPerDay: Int
        get() = if (this is Daily) times.coerceIn(1, 3) else 1

    companion object {
        val onceDaily: Frequency = Daily(1)
    }
}

/**
 * A frequency an item had before it was changed. Days before the day of `until` keep `frequency`, so a settings change
 * never rewrites the past.
 */
data class FrequencyEra(val until: Instant, val frequency: Frequency)

/** A stretch an item spent archived: from the day of `from` up to, not including, the day of `until`. */
data class Pause(val from: Instant, val until: Instant)

/** One thing in the stack. */
data class Item(
    val id: UUID = UUID.randomUUID(),
    val name: String,
    val code: String,
    /** The frequency from the last change on. Earlier days use `pastFrequencies`. */
    val frequency: Frequency,
    val createdAt: Instant,
    val archived: Boolean = false,
    val archivedAt: Instant? = null,
    val sortIndex: Int,
    /** Frequencies before each change, oldest first. Null in files written before it existed. */
    val pastFrequencies: List<FrequencyEra>? = null,
    /** Archived stretches that have ended, oldest first. Null in files written before it existed. */
    val pauses: List<Pause>? = null,
)

/** One logged dose. The only source of truth for "taken". */
data class Dose(
    val id: UUID = UUID.randomUUID(),
    val itemId: UUID,
    val takenAt: Instant,
    /**
     * Seconds east of UTC where the dose was logged, so it keeps the day it was taken on after the phone changes time
     * zone. Null in files written before it existed: those read in the current zone.
     */
    val utcOffset: Int? = null,
)

/**
 * The settings in taken.json. `wakeMinutes` and a chosen nudge time are clamped to 0...1439 when made, as the iPhone's
 * initialiser does.
 */
data class StackSettings(
    /** Profile > Wake-up time, minutes after midnight. Default 07:00. The day rolls over from it. */
    var wakeMinutes: Int = DEFAULT_WAKE_MINUTES,
    var reminderEnabled: Boolean = false,
    /** The nudge time the person chose. Null until they choose one: the nudge then comes 13 hours after waking up. */
    var chosenReminderMinutes: Int? = null,
    var hapticsEnabled: Boolean = true,
    /** The look (Profile > Look). */
    var theme: ThemeID = ThemeID.SIGNAL,
    /** Today's one-time nudge offer was answered (Turn on or Not now). Kept by Erase all data. */
    var nudgeOfferDone: Boolean = false,
    /** The day (DayKey ordinal) the widget invite first showed, under the first All taken: it shows on that day only. */
    var widgetInviteDay: Int? = null,
    /** The widget invite was tapped or closed, or a Taken widget was already placed. */
    var widgetInviteDone: Boolean = false,
    /** The day (DayKey ordinal) whose repair line was closed: hidden for that day only. Not kept by Erase all data. */
    var repairClosedDay: Int? = null,
    /** Profile > Reminder > Trial reminder. On unless turned off; files from before it read as on. */
    var trialReminderEnabled: Boolean = true,
) {
    init {
        wakeMinutes = clampMinutes(wakeMinutes)
        chosenReminderMinutes = chosenReminderMinutes?.let(::clampMinutes)
    }

    /** The hour the day rolls over (0...12): the wake-up time minus 4 hours, never before midnight or after noon. */
    val dayStartHour: Int get() = dayStartHour(forWake = wakeMinutes)

    /** Minutes after midnight for the nudge: the one chosen, or 13 hours after waking up. */
    var reminderMinutes: Int
        get() = chosenReminderMinutes ?: ((wakeMinutes + NUDGE_AFTER_WAKE) % (24 * 60))
        set(value) {
            chosenReminderMinutes = clampMinutes(value)
        }

    /** Where the day sheet starts a backfill on a past day: an hour after waking up. */
    val backfillMinutes: Int get() = (wakeMinutes + BACKFILL_AFTER_WAKE) % (24 * 60)

    /**
     * The Nudge toggle in Profile, or Turn on on the offer: either is an explicit answer, so the one-time offer on Today
     * never comes back after it, even once the nudge is turned off again.
     */
    fun setReminder(enabled: Boolean) {
        reminderEnabled = enabled
        nudgeOfferDone = true
    }

    companion object {
        const val DEFAULT_WAKE_MINUTES = 7 * 60
        /** The day rolls over this long before the wake-up time, so a late night stays on the day being lived. */
        const val ROLLOVER_LEAD = 4 * 60
        /** The latest the day may roll over: a wake-up time in the afternoon still starts its day by noon. */
        const val LATEST_ROLLOVER_HOUR = 12
        /** The nudge, unless the person chose a time: this long after waking up. */
        const val NUDGE_AFTER_WAKE = 13 * 60
        /** A missed day's backfill time: this long after waking up. */
        const val BACKFILL_AFTER_WAKE = 60

        fun dayStartHour(forWake: Int): Int {
            val rollover = clampMinutes(forWake) - ROLLOVER_LEAD
            if (rollover <= 0) return 0
            return minOf(rollover / 60, LATEST_ROLLOVER_HOUR)
        }

        fun wakeMinutes(forDayStartHour: Int): Int = (forDayStartHour.coerceIn(0, 23) * 60 + ROLLOVER_LEAD) % (24 * 60)

        fun clampMinutes(minutes: Int): Int = minutes.coerceIn(0, 24 * 60 - 1)

        /**
         * Settings as 1.0 described them, with a day-start hour: the wake-up time is that hour plus 4, so the day rolls
         * over exactly where it did.
         */
        fun fromDayStartHour(
            dayStartHour: Int,
            reminderEnabled: Boolean = false,
            reminderMinutes: Int = 21 * 60,
            hapticsEnabled: Boolean = true,
            theme: ThemeID = ThemeID.SIGNAL,
        ): StackSettings = StackSettings(
            wakeMinutes = wakeMinutes(forDayStartHour = dayStartHour),
            reminderEnabled = reminderEnabled,
            chosenReminderMinutes = reminderMinutes,
            hapticsEnabled = hapticsEnabled,
            theme = theme,
        )
    }
}

/**
 * Everything Taken knows. Stored as one JSON file, taken.json. Its fields are `var`s holding immutable values, so a
 * mutation (Mutations.kt) works on a [clone] and the copy the screen shows never changes underneath it.
 */
data class StackState(
    var items: List<Item> = emptyList(),
    var doses: List<Dose> = emptyList(),
    var settings: StackSettings = StackSettings(),
    var schemaVersion: Int = 1,
) {
    /** A copy that shares nothing mutable with this one. */
    fun clone(): StackState = copy(settings = settings.copy())
}

/** What the Add sheet hands over. */
data class ItemDraft(
    val name: String,
    val code: String? = null,
    val frequency: Frequency = Frequency.onceDaily,
)
