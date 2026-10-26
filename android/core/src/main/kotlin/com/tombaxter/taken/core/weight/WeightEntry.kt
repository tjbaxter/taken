package com.tombaxter.taken.core.weight

import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.day.DayKey
import java.util.Locale

// The Weight tab's page, entry first (REDESIGN.md, "Weight tab page: entry first, 2026-10-22"): what the big number shows,
// what the small line under it says, when the range hint shows, and where a scroll comes to rest, as pure rules. Ported
// from Shared/WeightEntry.swift with WeightEntryTests carried over.

/** What the big number shows. It always shows a weigh-in, never the trend. */
sealed class WeightFigure {
    /** Never weighed in: no digits, the caret and the unit. */
    data object Empty : WeightFigure()

    /** The last weigh-in in grey: on an earlier day, or as the hint while nothing is typed yet. It can never be saved. */
    data class Ghost(val kg: Double) : WeightFigure()

    /** Today's latest weigh-in, in the look's ink. */
    data class Today(val kg: Double) : WeightFigure()

    /** What is being typed. */
    data class Typing(val text: String) : WeightFigure()

    /** "empty", "ghost", "today", "typing". */
    val kind: String
        get() = when (this) {
            Empty -> "empty"
            is Ghost -> "ghost"
            is Today -> "today"
            is Typing -> "typing"
        }
}

/** What the small line under the number says. */
sealed class WeightLine {
    /** "Last weigh-in yesterday, 07:42", or "No weigh-ins yet". */
    data object Last : WeightLine()

    /** "Between 20 and 350 kg": typing, a finished-looking number outside the bounds. */
    data object Range : WeightLine()

    /** "Trend 1.1 kg to 87.0": after a save on this visit, with a goal. */
    data class Closing(val readout: GoalReadout) : WeightLine()

    /** The lit dot and "Trend is now 10% below where you started.": a save on this visit lit a point. */
    data class Moment(val moment: WeightMoment) : WeightLine()

    /** "last", "range", "closing", "moment". */
    val kind: String
        get() = when (this) {
            Last -> "last"
            Range -> "range"
            is Closing -> "closing"
            is Moment -> "moment"
        }
}

object WeightEntry {
    /**
     * The big number: typing shows the draft, or the last weigh-in in grey (today's included) until a key is pressed;
     * otherwise today's latest weigh-in, the last one in grey, or nothing.
     */
    fun figure(last: WeighIn?, today: DayKey, clock: DayClock, draft: String, focused: Boolean): WeightFigure {
        if (focused) {
            if (draft.isNotEmpty()) return WeightFigure.Typing(draft)
            return last?.let { WeightFigure.Ghost(it.kg) } ?: WeightFigure.Empty
        }
        if (last == null) return WeightFigure.Empty
        return if (clock.day(last) == today) WeightFigure.Today(last.kg) else WeightFigure.Ghost(last.kg)
    }

    /**
     * Whether the draft looks finished (the iPhone's own rule): a decimal separator followed by a digit, or 3 or more
     * whole digits. So "8" on the way to "88" never shows a warning.
     */
    fun looksFinished(draft: String, locale: Locale): Boolean {
        val separators = WeightFormat.decimalSeparators(locale)
        var whole = 0
        var fraction = 0
        var separated = false
        for (codePoint in draft.codePoints().toArray()) {
            if (codePoint in separators) {
                separated = true
            } else if (WeightFormat.asciiDigit(codePoint) != null || Character.isDigit(codePoint)) {
                if (separated) fraction += 1 else whole += 1
            }
        }
        return whole >= 3 || (separated && fraction >= 1)
    }

    /** "Between 20 and 350 kg" shows while typing once the number looks finished and parses outside the unit's bounds. */
    fun showsRangeHint(draft: String, unit: WeightUnit, locale: Locale): Boolean {
        if (!looksFinished(draft, locale)) return false
        val value = WeightFormat.parse(draft, locale) ?: return false
        return value !in unit.bounds
    }

    /**
     * The small line, first rule that applies: the range hint while typing; else, while typing, the last weigh-in; else
     * the point a save on this visit lit; else, after a save on this visit with a goal, how close the trend is (never for
     * "Goal 87.0"); else the last weigh-in.
     */
    fun line(
        focused: Boolean,
        draft: String,
        unit: WeightUnit,
        locale: Locale,
        hasGoal: Boolean,
        justSaved: Boolean,
        justReached: WeightMoment?,
        readout: GoalReadout?,
    ): WeightLine {
        if (focused) return if (showsRangeHint(draft, unit, locale)) WeightLine.Range else WeightLine.Last
        if (justReached != null) return WeightLine.Moment(justReached)
        if (justSaved && hasGoal && readout != null && readout != GoalReadout.GoalOnly) return WeightLine.Closing(readout)
        return WeightLine.Last
    }

    /**
     * The string that sizes the digits box: the longer of the grey value and the draft, so nothing re-centres while
     * typing.
     */
    fun sizing(ghost: String, draft: String): String = if (draft.length > ghost.length) draft else ghost
}

/**
 * Where a scroll comes to rest: between the top and the fold (the bottom of screen one), the nearer of the two, so a
 * flick goes all the way to the trend; anywhere else, where the scroll was going.
 */
object WeightFold {
    fun snap(y: Double, fold: Double): Double {
        if (fold <= 0 || y <= 0 || y >= fold) return y
        return if (y < fold / 2) 0.0 else fold
    }
}
