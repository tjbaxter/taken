package com.tombaxter.taken.core.weight

import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.format.Fmt
import java.time.Instant
import java.util.Locale

/**
 * Every word the Weight tab shows (Shared/WeightData.swift `WeightCopy`). Weight, Trend and weigh-in; never lose, ideal
 * or goal. Android wording where SPEC-ANDROID 6.4 changes the iPhone's: "this phone" for "this iPhone", menu items in
 * sentence case (Material: "Titles, headings, labels, and menu items should use sentence-style capitalization",
 * https://m1.material.io/style/writing.html , and Material 3's content design style guide,
 * https://m3.material.io/foundations/content-design/style-guide/ux-writing-best-practices), and Android's own name for
 * the overflow button, "More options" (AndroidX AppCompat's `abc_action_menu_overflow_description`).
 */
object WeightCopy {
    const val TAB = "Weight"
    const val NO_WEIGH_INS = "No weigh-ins yet"

    /** The bar above the decimal keyboard: Tom's word. */
    const val WEIGH_IN = "Weigh in"
    const val SAVE = "Save"
    const val TREND = "Trend"
    const val TREND_CAPTION = "smooths daily swings"

    /** Screen two under its single dot, after the first weigh-in. */
    const val TREND_STARTS = "Your trend starts here."

    /** The chevron at the bottom of screen one, for TalkBack. */
    const val SHOW_TREND = "Show trend"

    /** The long-press menu on today's number, and its TalkBack actions. */
    const val EDIT = "Edit…"
    const val DELETE = "Delete"
    const val EDIT_WEIGH_IN = "Edit weigh-in"
    const val TICKS = "Ticks: weekly doses"
    const val EMPTY_RANGE = "No weigh-ins in this range"
    const val ALL_WEIGH_INS = "All weigh-ins"

    /** The overflow button's TalkBack label, Android's own (the iPhone's More button says "More"). */
    const val MORE = "More options"

    /** Sentence case on Android (the iPhone's "Hide Weight Tab" is title case, HIG Menus). */
    const val HIDE_TAB = "Hide Weight tab"

    /** The toast after Hide Weight tab, on Today, with Undo. */
    const val HIDDEN = "Weight tab hidden. Profile brings it back."

    /** The toast after a weigh-in is saved, with Undo. */
    const val WEIGHED_IN = "Weighed in"
    const val DELETED = "Weigh-in deleted"
    const val UPDATED = "Weigh-in updated"
    const val OFFER = "Log your weight here too: add a Weight tab"
    const val ADD_TAB = "Add tab"
    const val NOT_NOW = "Not now"

    /** The offer's Add tab, for TalkBack. */
    const val ADD_TAB_HINT = "Adds a Weight tab after History. Profile can hide it again."
    const val PROFILE_SECTION = "Weight"
    const val PROFILE_SWITCH = "Weight tab"
    const val PROFILE_FOOTNOTE = "Log your weight and see a smoothed trend. Kept on this phone."
    const val EXPORT_CSV = "Export weight CSV"
    const val IMPORT_CSV = "Import weight CSV"
    const val EDIT_TITLE = "Weigh-in"
    const val WEIGHT_FIELD = "Weight"
    const val WHEN = "When"
    const val DELETE_WEIGH_IN = "Delete weigh-in"
    const val COULD_NOT_SAVE = "Could not save. Try again."
    const val NOT_FOUND = "No weigh-ins found. Taken reads a date column and a weight column in kg or lb."
    const val COULD_NOT_OPEN = "Could not open that file."

    /** The field's TalkBack hints. */
    const val TYPE_HINT = "Double-tap to type today's weight."
    const val ANOTHER_HINT = "Double-tap to log another weigh-in."
    const val LOCKED_HINT = "Logging needs Taken Pro. Opens Taken Pro."

    /** The field's label once today has a weigh-in. */
    const val TODAYS_WEIGH_IN = "Today's weigh-in"

    /** TalkBack, after Add tab on Today's offer. */
    const val TAB_ADDED = "Weight tab added."

    /** The field's label: "Today's weight in kilograms", "Today's weight in pounds". */
    fun fieldLabel(unit: WeightUnit): String = "Today's weight in ${unit.spoken}"

    /** While typing, a finished-looking number outside the bounds: "Between 20 and 350 kg", "Between 44 and 770 lb". */
    fun rangeHint(unit: WeightUnit): String =
        "Between ${unit.bounds.start.toInt()} and ${unit.bounds.endInclusive.toInt()} ${unit.symbol}"

    /** "Between 20 and 350 kilograms" */
    fun spokenRangeHint(unit: WeightUnit): String =
        "Between ${unit.bounds.start.toInt()} and ${unit.bounds.endInclusive.toInt()} ${unit.spoken}"

    /**
     * Under the big number: "Last weigh-in yesterday, 07:42", "Last weigh-in Tuesday, 07:42", "Last weigh-in 14 Oct,
     * 07:42", "Last weigh-in 3 Mar 2025, 07:42". It never counts missed days.
     */
    fun lastLine(weighIn: WeighIn?, now: Instant, clock: DayClock): String {
        if (weighIn == null) return NO_WEIGH_INS
        return "Last weigh-in ${dayWord(clock.day(weighIn), clock.day(now), clock)}, ${Fmt.clock(weighIn.weighedAt, clock)}"
    }

    /**
     * The small line for TalkBack, with the number the grey digits show: "Last weigh-in 88.35 kilograms, yesterday at
     * 07:42"; on a day already weighed in, "Last weigh-in today at 07:06".
     */
    fun spokenLastLine(weighIn: WeighIn?, unit: WeightUnit, now: Instant, clock: DayClock, locale: Locale = Locale.getDefault()): String {
        if (weighIn == null) return NO_WEIGH_INS
        val day = clock.day(weighIn)
        val today = clock.day(now)
        val time = Fmt.clock(weighIn.weighedAt, clock)
        if (day == today) return "Last weigh-in today at $time"
        return "Last weigh-in ${WeightFormat.spoken(weighIn.kg, unit, locale)}, ${dayWord(day, today, clock)} at $time"
    }

    /** "today", "yesterday", "Tuesday" this past week, then "14 Oct", and "14 Oct 2025" from another year. */
    fun dayWord(day: DayKey, today: DayKey, clock: DayClock): String = when (day.distanceTo(today)) {
        0 -> "today"
        1 -> "yesterday"
        in 2 until 7 -> Fmt.weekday(day)
        else -> Fmt.shortDate(clock.noon(day), year = day.ymd.year != today.ymd.year, zone = clock.zone)
    }

    /** A row in All weigh-ins: "Today", "Yesterday", "Tue 20 Oct", and "Mon 3 Mar 2025" from another year. */
    fun listDay(day: DayKey, today: DayKey): String = when (day.distanceTo(today)) {
        0 -> "Today"
        1 -> "Yesterday"
        else -> {
            val weekdays = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
            val months = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
            val (year, month, dayOfMonth) = day.ymd
            val base = "${weekdays[day.mondayIndex]} $dayOfMonth ${months[(month - 1).coerceIn(0, 11)]}"
            if (year == today.ymd.year) base else "$base $year"
        }
    }

    /**
     * The result of an import: "Added 214 weigh-ins, read in kg." with what was already in Taken and what could not be
     * read after it.
     */
    fun imported(added: Int, already: Int, unreadable: Int, unit: WeightUnit): String {
        val parts = mutableListOf<String>()
        if (added > 0) {
            parts.add("Added $added ${if (added == 1) "weigh-in" else "weigh-ins"}, read in ${unit.symbol}.")
            if (already > 0) parts.add("$already ${if (already == 1) "was" else "were"} already in Taken.")
        } else {
            parts.add("Nothing new: ${if (already == 1) "that weigh-in is" else "those $already weigh-ins are"} already in Taken.")
        }
        if (unreadable > 0) parts.add("$unreadable ${if (unreadable == 1) "row" else "rows"} could not be read.")
        return parts.joinToString(" ")
    }

    /** The chart's first sentence for TalkBack: "Trend 88.1 kilograms." */
    fun spokenTrend(trendKg: Double?, unit: WeightUnit, locale: Locale = Locale.getDefault()): String {
        if (trendKg == null) return "$NO_WEIGH_INS."
        return "Trend ${WeightFormat.trend(trendKg, unit, locale)} ${unit.spoken}."
    }

    /**
     * The chart for TalkBack, with the selected range's change: "Trend 88.1 kilograms. Down 1.2 kilograms over 30 days."
     * The goal's clauses (`WeightGoalCopy`) go in between when there is a goal.
     */
    fun chartSummary(trendKg: Double?, change: String?, unit: WeightUnit, locale: Locale = Locale.getDefault()): String =
        listOfNotNull(spokenTrend(trendKg, unit, locale), change?.let { "$it." }).joinToString(" ")

    /** Every fixed line, for the copy rules test. */
    val all: List<String>
        get() = listOf(
            TAB, NO_WEIGH_INS, WEIGH_IN, SAVE, TREND, TREND_CAPTION, TREND_STARTS, SHOW_TREND, EDIT, DELETE, EDIT_WEIGH_IN,
            TICKS, EMPTY_RANGE, ALL_WEIGH_INS, MORE, HIDE_TAB, HIDDEN, WEIGHED_IN, DELETED, UPDATED, OFFER, ADD_TAB, NOT_NOW,
            ADD_TAB_HINT, PROFILE_SECTION, PROFILE_SWITCH, PROFILE_FOOTNOTE, EXPORT_CSV, IMPORT_CSV, EDIT_TITLE, WEIGHT_FIELD,
            WHEN, DELETE_WEIGH_IN, COULD_NOT_SAVE, NOT_FOUND, COULD_NOT_OPEN, TYPE_HINT, ANOTHER_HINT, LOCKED_HINT,
            TODAYS_WEIGH_IN, TAB_ADDED,
            imported(added = 214, already = 3, unreadable = 2, unit = WeightUnit.KG),
            imported(added = 0, already = 5, unreadable = 0, unit = WeightUnit.LB),
        ) + WeightUnit.entries.map { it.menuTitle } + WeightRange.entries.map { it.spoken } +
            WeightUnit.entries.flatMap { listOf(fieldLabel(it), rangeHint(it), spokenRangeHint(it)) }
}
