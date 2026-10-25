package com.tombaxter.taken.core.weight

import com.tombaxter.taken.core.day.DayKey
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max

// The Weight tab's optional goal and its moments (REDESIGN.md, "Goal and moments, 2026-10-22"): the goal, its start and
// direction, the BMI 18.5 floor, at most three lit points on the trend (5% and 10% below the start, and the goal
// reached), the one line that says how close the trend is, the y axis ticks, the change line for the selected range and
// every word they show, as pure rules. Ported line for line from Shared/WeightGoal.swift, with WeightGoalTests carried
// over. Copy rules: no em or en dash, no exclamation mark, and never lose, lost, loss, ideal, great, should, missed,
// behind or off track.

// MARK: - The goal

/**
 * An optional goal weight, set only from the Weight tab's More options menu: kilograms, and the day whose trend is the
 * start weight. `startPicked` once the person moved the start in the Goal sheet. No date, pace, rate or plan, ever.
 */
data class WeightGoal(val kg: Double, val startDay: DayKey, val startPicked: Boolean = false)

/**
 * Which way the goal lies from the start, inferred and never asked: more than 0.68 kg below is lower, more than 0.68 kg
 * above is higher, anything else is near (MacroFactor's maintenance tolerance).
 */
enum class GoalDirection { LOWER, HIGHER, NEAR }

/**
 * A lit point on the trend: the first weigh-in day on or after the start on which the trend sat 5% or 10% below the
 * start, or reached the goal. Worked out from the weigh-ins, the goal and the height; nothing is stored.
 */
data class WeightMoment(val kind: Kind, val day: DayKey, val trendKg: Double) {
    sealed class Kind {
        data class Percent(val percent: Int) : Kind()
        data object Goal : Kind()
    }

    /** "pct5", "pct10", "goal" */
    val id: String
        get() = when (kind) {
            is Kind.Percent -> "pct${kind.percent}"
            Kind.Goal -> "goal"
        }

    /** When two arrive together, the goal outranks 10% and 10% outranks 5% (the iPhone's own choice). */
    val rank: Int
        get() = when (kind) {
            is Kind.Percent -> kind.percent
            Kind.Goal -> 1_000
        }

    val isGoal: Boolean get() = kind == Kind.Goal
}

/** What the goal's slot says, in kilograms. */
sealed class GoalReadout {
    /** "Goal 87.0": the trend has not moved 0.1 towards it yet, or sits on the far side of the start. */
    data object GoalOnly : GoalReadout()

    /** "4.2 kg closer to 87.0": less than half the way covered. */
    data class Closer(val kg: Double) : GoalReadout()

    /** "1.1 kg to 87.0": half or more covered, not yet reached. */
    data class ToGo(val kg: Double) : GoalReadout()

    /** "Holding near 87.0": reached, or a near goal, within 0.68 kg. */
    data object Holding : GoalReadout()

    /** "0.9 kg from 87.0": reached, or a near goal, more than 0.68 kg away. */
    data class From(val kg: Double) : GoalReadout()
}

/**
 * The goal's rules (REDESIGN.md, "Goal and moments"): the start, the direction, the floor, the points, the readout and
 * which point a weigh-in just lit.
 */
object WeightGoals {
    /** Within this of the goal the trend is holding (MacroFactor: 1.5 lb either way, on the trend weight). */
    const val HOLD_BAND_KG = 0.68

    /** A goal counts as reached within this of it, so "0.0 kg to 87.0" never shows (the iPhone's own choice). */
    const val REACH_TOLERANCE_KG = 0.05

    /** The lowest goal is BMI 18.5 at the person's height (Honary et al. 2019). */
    const val FLOOR_BMI = 18.5

    /** The 5% and 10% points need a start at BMI 25 or more (ACC/AHA 2013, adults with overweight or obesity). */
    const val PERCENT_POINTS_MIN_BMI = 25.0

    /** The guideline's "sustained weight loss of 5 percent to 10 percent". */
    val PERCENTS = listOf(5, 10)

    private const val EPSILON = 1e-9

    /** 18.5 x (height in metres) squared. */
    fun floorKg(heightCm: Double): Double {
        val metres = heightCm / 100
        return FLOOR_BMI * metres * metres
    }

    fun bmi(kg: Double, heightCm: Double): Double {
        val metres = heightCm / 100
        return kg / (metres * metres)
    }

    /**
     * The first weigh-in day, unless the trend has already been at the goal since then (the goal lies between its lowest
     * and highest values), when it is the last weigh-in day, so a long imported history never turns a regain into a
     * finished goal (the iPhone's own rule). Null without weigh-ins.
     */
    fun defaultStartDay(goalKg: Double, trend: List<WeightPoint>): DayKey? {
        val first = trend.firstOrNull() ?: return null
        val last = trend.lastOrNull() ?: return null
        val low = trend.minOf { it.kg }
        val high = trend.maxOf { it.kg }
        return if (goalKg >= low && goalKg <= high) last.day else first.day
    }

    /**
     * The Goal sheet's start day: the day picked in its Start row; else, for Change goal, the stored start while the
     * value is unchanged (or the field is empty) or once the start was picked by hand (`startPicked`); else the default
     * for what is typed, and the first weigh-in day before anything is typed. Null without weigh-ins.
     */
    fun sheetStartDay(existing: WeightGoal?, typedKg: Double?, pickedDay: DayKey?, trend: List<WeightPoint>): DayKey? {
        val first = trend.firstOrNull() ?: return null
        if (pickedDay != null) return pickedDay
        if (existing != null && (existing.startPicked || typedKg == null || typedKg == existing.kg)) return existing.startDay
        return typedKg?.let { defaultStartDay(it, trend) } ?: first.day
    }

    /**
     * The goal's start on the trend: its day, clamped to the first and last weigh-in days after edits or deletes, and
     * the trend that day. Null without weigh-ins: the goal waits for the next one.
     */
    fun start(goal: WeightGoal, trend: List<WeightPoint>): WeightPoint? {
        val first = trend.firstOrNull() ?: return null
        val last = trend.lastOrNull() ?: return null
        val day = minOf(maxOf(goal.startDay, first.day), last.day)
        val index = first.day.distanceTo(day)
        if (index in trend.indices && trend[index].day == day) return trend[index]
        return trend.firstOrNull { it.day == day }
    }

    fun direction(startKg: Double, goalKg: Double): GoalDirection {
        if (startKg - goalKg > HOLD_BAND_KG + EPSILON) return GoalDirection.LOWER
        if (goalKg - startKg > HOLD_BAND_KG + EPSILON) return GoalDirection.HIGHER
        return GoalDirection.NEAR
    }

    /**
     * Whether the floor stops this goal: a lower or near goal below BMI 18.5 at this height. A goal above the start,
     * gaining towards a healthier weight, is never blocked (the iPhone's own judgement: the floor stops unsafe loss, not
     * recovery).
     */
    fun floorBlocks(goalKg: Double, startKg: Double, heightCm: Double): Boolean {
        if (heightCm <= 0) return false
        if (direction(startKg, goalKg) == GoalDirection.HIGHER) return false
        return goalKg < floorKg(heightCm) - EPSILON
    }

    /**
     * At most three points, oldest first. 5% and 10% only for a lower goal, only from a start at BMI 25 or more, and only
     * where the threshold lies between the start and the goal, more than 0.05 kg from the goal; the goal point in either
     * direction; a near goal gets none. Each lands on the first real weigh-in day on or after the start on which the
     * trend is at or past it (never a day the trend filled in), and stays even if the trend rises again.
     */
    fun moments(goal: WeightGoal, trend: List<WeightPoint>, weighInDays: Set<DayKey>, heightCm: Double?): List<WeightMoment> {
        val start = start(goal, trend) ?: return emptyList()
        val direction = direction(start.kg, goal.kg)
        if (direction == GoalDirection.NEAR) return emptyList()
        val days = trend.filter { it.day >= start.day && it.day in weighInDays }
        val out = mutableListOf<WeightMoment>()
        if (direction == GoalDirection.LOWER && heightCm != null && heightCm > 0 && bmi(start.kg, heightCm) >= PERCENT_POINTS_MIN_BMI) {
            for (percent in PERCENTS) {
                val threshold = start.kg * (1 - percent.toDouble() / 100)
                if (threshold <= goal.kg + REACH_TOLERANCE_KG) continue
                days.firstOrNull { it.kg <= threshold }?.let { hit ->
                    out.add(WeightMoment(WeightMoment.Kind.Percent(percent), hit.day, hit.kg))
                }
            }
        }
        val reached = if (direction == GoalDirection.LOWER) {
            days.firstOrNull { it.kg <= goal.kg + REACH_TOLERANCE_KG }
        } else {
            days.firstOrNull { it.kg >= goal.kg - REACH_TOLERANCE_KG }
        }
        if (reached != null) out.add(WeightMoment(WeightMoment.Kind.Goal, reached.day, reached.kg))
        return out.sortedWith(compareBy<WeightMoment>({ it.day }, { it.rank }))
    }

    /**
     * The slot's reading, on the trend: T is the trend on the last weigh-in day. Covered is how far T has moved from the
     * start towards the goal; under 0.1 in the chosen unit, or on the far side, it is just the goal. Less than half the
     * way is "closer", half or more is "to go", and a reached or near goal holds within 0.68 kg.
     */
    fun readout(goal: WeightGoal, trend: List<WeightPoint>, moments: List<WeightMoment>, unit: WeightUnit = WeightUnit.KG): GoalReadout {
        val start = start(goal, trend) ?: return GoalReadout.GoalOnly
        val last = trend.lastOrNull() ?: return GoalReadout.GoalOnly
        val direction = direction(start.kg, goal.kg)
        if (direction == GoalDirection.NEAR || moments.any { it.isGoal }) {
            val away = abs(last.kg - goal.kg)
            return if (away <= HOLD_BAND_KG + EPSILON) GoalReadout.Holding else GoalReadout.From(away)
        }
        val covered = if (direction == GoalDirection.LOWER) start.kg - last.kg else last.kg - start.kg
        if (unit.valueFromKilograms(covered) < 0.1 - EPSILON) return GoalReadout.GoalOnly
        val distance = abs(start.kg - goal.kg)
        if (covered * 2 < distance - EPSILON) return GoalReadout.Closer(covered)
        return GoalReadout.ToGo(max(0.0, if (direction == GoalDirection.LOWER) last.kg - goal.kg else goal.kg - last.kg))
    }

    /**
     * The point a weigh-in saved from the page just lit: new since before the save and dated that weigh-in's day; the
     * highest-ranked if two arrive together. Null otherwise (a backdated weigh-in, an edit, an import or a goal change
     * makes points appear silently).
     */
    fun fresh(before: List<WeightMoment>, after: List<WeightMoment>, savedDay: DayKey): WeightMoment? {
        val old = before.map { it.id }.toSet()
        return after.filter { it.id !in old && it.day == savedDay }.maxByOrNull { it.rank }
    }
}

// MARK: - Height

/**
 * Centimetres, or feet and inches where the locale's person height is in feet and inches. Stored in centimetres; asked
 * only in the Goal sheet, to keep goals in a healthy range.
 */
enum class HeightUnit {
    CENTIMETRES,
    FEET_INCHES;

    /** "183 cm", "6 ft 0 in" */
    fun text(centimetres: Double): String = when (this) {
        CENTIMETRES -> "${roundedAway(centimetres).toInt()} cm"
        FEET_INCHES -> feetInches(centimetres).let { "${it.first} ft ${it.second} in" }
    }

    /** "183 centimetres", "6 feet 0 inches", for TalkBack. */
    fun spoken(centimetres: Double): String = when (this) {
        CENTIMETRES -> "${roundedAway(centimetres).toInt()} centimetres"
        FEET_INCHES -> feetInches(centimetres).let { "${it.first} feet ${it.second} inches" }
    }

    companion object {
        val CENTIMETRE_RANGE = 100..230
        val FEET_RANGE = 3..7
        val INCH_RANGE = 0..11
        const val CENTIMETRES_PER_INCH = 2.54

        /** Where the picker starts with no height stored: 170 cm, or 5 ft 7 in. */
        const val DEFAULT_CENTIMETRES = 170.0
        val DEFAULT_FEET_INCHES = 5 to 7

        /**
         * CLDR's unit preferences for length, usage "person-height": `foot-and-inch` in CA, GB, IN and US, centimetres
         * (or metres and centimetres, shown as centimetres, as on the iPhone) everywhere else
         * (https://github.com/unicode-org/cldr/blob/main/common/supplemental/units.xml). The iPhone reads the same table
         * through `UnitLength(forLocale:usage: .personHeight)`.
         */
        private val FEET_REGIONS = setOf("CA", "GB", "IN", "US")

        fun preferred(locale: Locale): HeightUnit =
            if (locale.country.uppercase(Locale.ROOT) in FEET_REGIONS) FEET_INCHES else CENTIMETRES

        fun centimetres(feet: Int, inches: Int): Double = (feet * 12 + inches).toDouble() * CENTIMETRES_PER_INCH

        /** The nearest whole inch, as (feet, inches). */
        fun feetInches(centimetres: Double): Pair<Int, Int> {
            val total = roundedAway(centimetres / CENTIMETRES_PER_INCH).toInt()
            return total / 12 to total % 12
        }
    }
}

// MARK: - The y axis

/** The chart's y ticks as explicit values, so a tick next to the goal's own label can give way. */
object WeightAxis {
    val STEPS = listOf(0.5, 1.0, 2.0, 5.0, 10.0, 20.0)

    /** A tick closer than this to the goal's label loses its label and its grid line (points, dp on Android). */
    const val CLEARANCE = 12.0

    /** The smallest step of 0.5, 1, 2, 5, 10 or 20 that gives four or fewer ticks inside the domain, in the unit shown. */
    fun ticks(lower: Double, upper: Double): List<Double> {
        if (!(upper > lower) || !lower.isFinite() || !upper.isFinite()) return emptyList()
        // Past 20 (a domain wider than any one person's record) the steps carry on, so there are never more than four.
        for (step in STEPS + listOf(50.0, 100.0, 200.0)) {
            val values = ticks(lower, upper, step)
            if (values.size <= 4) return values
        }
        return emptyList()
    }

    /** One decimal only for half steps ("88.5"), else whole numbers. */
    fun decimals(ticks: List<Double>): Int = if (ticks.any { abs(it - roundedAway(it)) > 1e-9 }) 1 else 0

    /** The ticks more than `gap` from `mark` on a plot `plotHeight` tall showing `lower` to `upper`. */
    fun clear(ticks: List<Double>, mark: Double, lower: Double, upper: Double, plotHeight: Double, gap: Double = CLEARANCE): List<Double> {
        if (!(upper > lower) || plotHeight <= 0) return ticks
        val pointsPerUnit = plotHeight / (upper - lower)
        return ticks.filter { abs(it - mark) * pointsPerUnit >= gap - 1e-9 }
    }

    private fun ticks(lower: Double, upper: Double, step: Double): List<Double> {
        val first = ceil(lower / step - 1e-9).toLong()
        val last = floor(upper / step + 1e-9).toLong()
        if (first > last) return emptyList()
        return (first..last).map { it.toDouble() * step }
    }
}

// MARK: - The change line

/**
 * The trend's change for the selected range, one line under the range control: over 7, 30 or 90 days or the year,
 * ending on the last weigh-in day; since the first trend day in view when the trend is shorter than the range, and
 * always on All. Hidden with fewer than two trend days in view.
 */
object WeightChangeLine {
    sealed class Span {
        data class Days(val days: Int) : Span()
        data object Year : Span()
        data class Since(val day: DayKey) : Span()
    }

    data class Change(val kg: Double, val span: Span)

    fun make(range: WeightRange, trend: List<WeightPoint>, window: WeightWindow): Change? {
        if (window.trend.size < 2) return null
        val first = window.trend.first()
        val last = window.trend.last()
        val days = range.days
        val change = days?.let { WeightTrend.change(trend, it) }
        if (days == null || change == null) return Change(last.kg - first.kg, Span.Since(first.day))
        return Change(change, if (range == WeightRange.YEAR) Span.Year else Span.Days(days))
    }
}

// MARK: - Copy

/**
 * Every word the goal, its points and the change line show. "Goal" is Tom's word; never lose, lost, loss, ideal, great,
 * should, missed, behind or off track (whole words: "closer" holds "lose"), and no exclamation mark. Android wording
 * where SPEC-ANDROID 6.4 changes it: the menu items in sentence case and "Kept on this phone.".
 */
object WeightGoalCopy {
    const val SET_GOAL = "Set goal…"
    const val CHANGE_GOAL = "Change goal…"
    const val CLEAR_GOAL = "Clear goal"
    const val TITLE = "Goal"
    const val START = "Start"
    const val HEIGHT = "Height"
    const val SET_BUTTON = "Set"
    const val SAVE = "Save"
    const val FOOTNOTE =
        "Shows as a line on your chart, measured on your trend, not single weigh-ins. No dates, no pace, no reminders. Goals are for adults."
    const val HEIGHT_FOOTNOTE = "Height is used only to keep goals in a healthy range. Kept on this phone."
    const val TOO_LOW = "Too low for your height. Taken keeps goals in a healthy range."
    const val CLEARED = "Goal cleared"
    const val CLEARED_SPOKEN = "Goal cleared."
    const val TREND = "Trend"
    const val WEIGH_IN = "Weigh-in"
    const val GOAL_LINE = "Goal"

    /** A piece of a line: a number with its unit, in Geist Mono, or words, in Geist. */
    data class Part(val text: String, val isNumber: Boolean = false)

    private val MONTHS_SHORT = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
    private val MONTHS_LONG = listOf(
        "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November",
        "December",
    )

    /** One decimal, in the locale, no grouping. */
    fun oneDecimal(value: Double, locale: Locale = Locale.getDefault()): String = WeightFormat.decimal(value, 1, 1, locale)

    /** The goal as the slot and the axis name it: "87.0". */
    fun goal(kg: Double, unit: WeightUnit, locale: Locale = Locale.getDefault()): String =
        oneDecimal(unit.valueFromKilograms(kg), locale)

    /** Down to a tenth (closer), up to a tenth (to go), in the unit shown. */
    fun roundedDown(value: Double): Double = floor(value * 10 + 1e-6) / 10
    fun roundedUp(value: Double): Double = ceil(value * 10 - 1e-6) / 10

    private fun amount(value: Double, unit: WeightUnit, locale: Locale): String = "${oneDecimal(value, locale)} ${unit.symbol}"

    // MARK: The slot

    /** "Goal 87.0", "4.2 kg closer to 87.0", "1.1 kg to 87.0", "Holding near 87.0", "0.9 kg from 87.0". */
    fun slot(readout: GoalReadout, goalKg: Double, unit: WeightUnit, locale: Locale = Locale.getDefault()): List<Part> {
        val target = goal(goalKg, unit, locale)
        return when (readout) {
            GoalReadout.GoalOnly -> listOf(Part("Goal "), Part(target, isNumber = true))
            is GoalReadout.Closer -> listOf(
                Part(amount(roundedDown(unit.valueFromKilograms(readout.kg)), unit, locale), isNumber = true),
                Part(" closer to "), Part(target, isNumber = true),
            )
            is GoalReadout.ToGo -> listOf(
                Part(amount(roundedUp(unit.valueFromKilograms(readout.kg)), unit, locale), isNumber = true),
                Part(" to "), Part(target, isNumber = true),
            )
            GoalReadout.Holding -> listOf(Part("Holding near "), Part(target, isNumber = true))
            is GoalReadout.From -> listOf(
                Part(amount(unit.valueFromKilograms(readout.kg), unit, locale), isNumber = true),
                Part(" from "), Part(target, isNumber = true),
            )
        }
    }

    fun text(parts: List<Part>): String = parts.joinToString("") { it.text }

    /** For TalkBack: "1.1 kilograms to your goal, 87.0". */
    fun spokenSlot(readout: GoalReadout, goalKg: Double, unit: WeightUnit, locale: Locale = Locale.getDefault()): String {
        val target = goal(goalKg, unit, locale)
        return when (readout) {
            GoalReadout.GoalOnly -> "Goal, $target ${unit.spoken}"
            is GoalReadout.Closer ->
                "${oneDecimal(roundedDown(unit.valueFromKilograms(readout.kg)), locale)} ${unit.spoken} closer to your goal, $target"
            is GoalReadout.ToGo ->
                "${oneDecimal(roundedUp(unit.valueFromKilograms(readout.kg)), locale)} ${unit.spoken} to your goal, $target"
            GoalReadout.Holding -> "Holding near your goal, $target"
            is GoalReadout.From -> "${oneDecimal(unit.valueFromKilograms(readout.kg), locale)} ${unit.spoken} from your goal, $target"
        }
    }

    /**
     * Screen one's small line after a save on this visit: the slot with "Trend" in front, so it never reads as arithmetic
     * on the big number. "Trend 1.1 kg to 87.0", "Trend holding near 87.0". Null for "Goal 87.0".
     */
    fun visit(readout: GoalReadout, goalKg: Double, unit: WeightUnit, locale: Locale = Locale.getDefault()): List<Part>? = when (readout) {
        GoalReadout.GoalOnly -> null
        GoalReadout.Holding -> listOf(Part("Trend holding near "), Part(goal(goalKg, unit, locale), isNumber = true))
        else -> listOf(Part("Trend ")) + slot(readout, goalKg, unit, locale)
    }

    /** For TalkBack: "Trend 1.1 kilograms to your goal, 87.0", "Trend holding near your goal, 87.0". Null for goal only. */
    fun spokenVisit(readout: GoalReadout, goalKg: Double, unit: WeightUnit, locale: Locale = Locale.getDefault()): String? = when (readout) {
        GoalReadout.GoalOnly -> null
        GoalReadout.Holding -> "Trend holding near your goal, ${goal(goalKg, unit, locale)}"
        else -> "Trend ${spokenSlot(readout, goalKg, unit, locale)}"
    }

    // MARK: Moments

    /** The line for one visit after a crossing: "Trend is now 10% below where you started.", "Trend reached 87.0." */
    fun moment(moment: WeightMoment, goalKg: Double, unit: WeightUnit, locale: Locale = Locale.getDefault()): List<Part> =
        when (val kind = moment.kind) {
            is WeightMoment.Kind.Percent -> listOf(Part("Trend is now ${kind.percent}% below where you started."))
            WeightMoment.Kind.Goal -> listOf(Part("Trend reached "), Part(goal(goalKg, unit, locale), isNumber = true), Part("."))
        }

    /**
     * The announcement's second sentence: "Trend is now 10 percent below where you started.", "Trend reached your goal,
     * 87.0 kilograms."
     */
    fun spokenMoment(moment: WeightMoment, goalKg: Double, unit: WeightUnit, locale: Locale = Locale.getDefault()): String =
        when (val kind = moment.kind) {
            is WeightMoment.Kind.Percent -> "Trend is now ${kind.percent} percent below where you started."
            WeightMoment.Kind.Goal -> "Trend reached your goal, ${goal(goalKg, unit, locale)} ${unit.spoken}."
        }

    /** A point's TalkBack label: "5 percent below where you started", "Trend reached your goal". */
    fun pointLabel(moment: WeightMoment): String = when (val kind = moment.kind) {
        is WeightMoment.Kind.Percent -> "${kind.percent} percent below where you started"
        WeightMoment.Kind.Goal -> "Trend reached your goal"
    }

    /** A point's TalkBack value: "3 August, trend 92.9 kilograms". */
    fun pointValue(moment: WeightMoment, unit: WeightUnit, locale: Locale = Locale.getDefault()): String =
        "${spokenDay(moment.day)}, trend ${oneDecimal(unit.valueFromKilograms(moment.trendKg), locale)} ${unit.spoken}"

    /** The scrub popover's line on a point's day: "5% below where you started", "Reached 87.0". */
    fun pointFact(moment: WeightMoment, goalKg: Double, unit: WeightUnit, locale: Locale = Locale.getDefault()): String =
        when (val kind = moment.kind) {
            is WeightMoment.Kind.Percent -> "${kind.percent}% below where you started"
            WeightMoment.Kind.Goal -> "Reached ${goal(goalKg, unit, locale)}"
        }

    /** The one label on the chart, on the newest percent point in view: "−5%", "−10%" (U+2212). The goal point has none. */
    fun chartLabel(moment: WeightMoment): String? = when (val kind = moment.kind) {
        is WeightMoment.Kind.Percent -> "−${kind.percent}%"
        WeightMoment.Kind.Goal -> null
    }

    /** The chart summary's last clause: "Marked: 5 percent below where you started, 3 August." */
    fun marked(moments: List<WeightMoment>): String? {
        if (moments.isEmpty()) return null
        return "Marked: " + moments.joinToString("; ") { "${pointLabel(it)}, ${spokenDay(it.day)}" } + "."
    }

    // MARK: The goal

    /** "Goal set, 87.0 kilograms." */
    fun goalSet(kg: Double, unit: WeightUnit, locale: Locale = Locale.getDefault()): String =
        "Goal set, ${goal(kg, unit, locale)} ${unit.spoken}."

    /** The goal line for TalkBack: "87.0 kilograms". */
    fun goalValue(kg: Double, unit: WeightUnit, locale: Locale = Locale.getDefault()): String = "${goal(kg, unit, locale)} ${unit.spoken}"

    /** "Set 183 cm", "Set 6 ft 0 in" */
    fun setHeight(centimetres: Double, unit: HeightUnit): String = "$SET_BUTTON ${unit.text(centimetres)}"

    // MARK: The change line

    /** "over 7 days", "over 30 days", "over 90 days", "over the year", "since 4 Mar", "since 4 Mar 2025". */
    fun span(span: WeightChangeLine.Span, today: DayKey): String = when (span) {
        is WeightChangeLine.Span.Days -> "over ${span.days} days"
        WeightChangeLine.Span.Year -> "over the year"
        is WeightChangeLine.Span.Since -> "since ${shortDay(span.day, today)}"
    }

    /**
     * "−1.2 kg" and " over 30 days", or no number and "No change over 30 days" when it rounds to 0.0. One neutral colour
     * both ways: the U+2212 minus or a plus, no arrow, no word for which way.
     */
    fun changeLine(kg: Double, span: WeightChangeLine.Span, unit: WeightUnit, today: DayKey, locale: Locale = Locale.getDefault()): List<Part> {
        val shown = roundedAway(unit.valueFromKilograms(kg) * 10) / 10
        val words = this.span(span, today)
        if (shown == 0.0) return listOf(Part("No change $words"))
        val sign = if (shown < 0) "−" else "+"
        return listOf(Part("$sign${amount(abs(shown), unit, locale)}", isNumber = true), Part(" $words"))
    }

    /** "Down 1.2 kilograms over 30 days", "Up 0.5 kilograms since 4 March", "No change over 30 days". */
    fun spokenChange(kg: Double, span: WeightChangeLine.Span, unit: WeightUnit, today: DayKey, locale: Locale = Locale.getDefault()): String {
        val shown = roundedAway(unit.valueFromKilograms(kg) * 10) / 10
        val words = if (span is WeightChangeLine.Span.Since) "since ${spokenDay(span.day)}" else this.span(span, today)
        if (shown == 0.0) return "No change $words"
        return "${if (shown < 0) "Down" else "Up"} ${oneDecimal(abs(shown), locale)} ${unit.spoken} $words"
    }

    // MARK: Days

    /** "4 Mar", and "4 Mar 2025" from another year. */
    fun shortDay(day: DayKey, today: DayKey): String {
        val (year, month, dayOfMonth) = day.ymd
        val base = "$dayOfMonth ${MONTHS_SHORT[(month - 1).coerceIn(0, 11)]}"
        return if (year == today.ymd.year) base else "$base $year"
    }

    /** "3 August" */
    fun spokenDay(day: DayKey): String {
        val (_, month, dayOfMonth) = day.ymd
        return "$dayOfMonth ${MONTHS_LONG[(month - 1).coerceIn(0, 11)]}"
    }

    /** Every fixed line and a sample of each built one, for the copy rules test. */
    val all: List<String>
        get() {
            val moments = listOf(
                WeightMoment(WeightMoment.Kind.Percent(5), DayKey(2026, 8, 3), 92.9),
                WeightMoment(WeightMoment.Kind.Percent(10), DayKey(2026, 9, 4), 88.0),
                WeightMoment(WeightMoment.Kind.Goal, DayKey(2026, 10, 22), 87.0),
            )
            val today = DayKey(2026, 10, 22)
            val readouts = listOf(GoalReadout.GoalOnly, GoalReadout.Closer(4.2), GoalReadout.ToGo(1.1), GoalReadout.Holding, GoalReadout.From(0.9))
            val spans = listOf(
                WeightChangeLine.Span.Days(7), WeightChangeLine.Span.Days(30), WeightChangeLine.Span.Days(90),
                WeightChangeLine.Span.Year, WeightChangeLine.Span.Since(DayKey(2026, 3, 4)),
            )
            val kg = WeightUnit.KG
            val lines = mutableListOf(
                SET_GOAL, CHANGE_GOAL, CLEAR_GOAL, TITLE, START, HEIGHT, SET_BUTTON, SAVE, FOOTNOTE, HEIGHT_FOOTNOTE, TOO_LOW,
                CLEARED, CLEARED_SPOKEN, TREND, WEIGH_IN, GOAL_LINE, goalSet(87.0, kg), goalValue(87.0, kg),
                setHeight(183.0, HeightUnit.CENTIMETRES), setHeight(183.0, HeightUnit.FEET_INCHES),
            )
            lines += readouts.map { text(slot(it, 87.0, kg)) }
            lines += readouts.map { spokenSlot(it, 87.0, kg) }
            lines += readouts.mapNotNull { r -> visit(r, 87.0, kg)?.let { text(it) } }
            lines += readouts.mapNotNull { spokenVisit(it, 87.0, kg) }
            lines += moments.map { text(moment(it, 87.0, kg)) }
            lines += moments.map { spokenMoment(it, 87.0, kg) }
            lines += moments.map { pointLabel(it) } + moments.map { pointValue(it, kg) }
            lines += moments.map { pointFact(it, 87.0, kg) } + moments.mapNotNull { chartLabel(it) }
            lines += listOf(marked(moments) ?: "")
            lines += spans.flatMap { span ->
                listOf(
                    text(changeLine(-1.2, span, kg, today)), text(changeLine(0.01, span, kg, today)),
                    spokenChange(0.5, span, kg, today), spokenChange(-1.2, span, kg, today),
                )
            }
            return lines
        }
}
