package com.tombaxter.taken.core.weight

import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.model.Item
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.ProAccess
import com.tombaxter.taken.core.pro.ProGate
import com.tombaxter.taken.core.pro.ProStatus
import com.tombaxter.taken.core.stack.DaySummary
import com.tombaxter.taken.core.stack.StackEngine
import java.math.BigDecimal
import java.math.RoundingMode
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.time.Instant
import java.time.ZoneId
import java.util.Locale
import java.util.UUID
import kotlin.math.abs
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

// The Weight tab (SPEC 3.12; REDESIGN.md, "Weight tab, 2026-10-22"): weigh-ins, the smoothed trend, kilograms and pounds,
// the Pro rule, the one-time offer on Today and the CSV, as pure rules. Ported line for line from Shared/WeightData.swift
// (SPEC-ANDROID 8.1, item 13), with the iPhone's WeightTests carried over as JUnit. Off until the person turns it on.
// Copy rules: no em or en dash, never the word for no charge, no exclamation marks, and never lose, ideal or goal (the
// self-weighing research in REDESIGN.md).

// MARK: - Weigh-ins

/** One weigh-in: kilograms, as typed or converted from pounds, and when, like a `Dose`. */
data class WeighIn(
    val id: UUID = UUID.randomUUID(),
    val kg: Double,
    val weighedAt: Instant,
    /** Seconds east of UTC where it was logged, so it keeps its day after the phone changes time zone (`Dose.utcOffset`). */
    val utcOffset: Int? = null,
)

/**
 * The day a weigh-in belongs to, read as a dose's day is (`DayClock.day(dose)`): the day that was being lived where it
 * was logged, so "today" means what it means for doses.
 */
fun DayClock.day(weighIn: WeighIn): DayKey {
    val offset = weighIn.utcOffset
    if (offset == null || offset == utcOffset(weighIn.weighedAt)) return day(weighIn.weighedAt)
    return fixed(offset).day(weighIn.weighedAt)
}

/** Noon on a day, where the chart draws it (the day-start hour is never after noon, so it is always that date). */
fun DayClock.noon(day: DayKey): Instant = date(day, 12, 0)

/** Swift's `.rounded()`: to the nearest whole number, halves away from zero. */
internal fun roundedAway(value: Double): Double = if (value < 0) -floor(-value + 0.5) else floor(value + 0.5)

// MARK: - Units

/** Kilograms or pounds. Each weigh-in is stored in kilograms; this is only how it is shown and typed. */
enum class WeightUnit(val raw: String) {
    KG("kg"),
    LB("lb");

    fun valueFromKilograms(kg: Double): Double = if (this == KG) kg else kg / KILOGRAMS_PER_POUND

    fun kilograms(value: Double): Double = if (this == KG) value else value * KILOGRAMS_PER_POUND

    /** What a weigh-in may be, in this unit: 20 to 350 kg, 44 to 770 lb (the iPhone's own bounds). */
    val bounds: ClosedFloatingPointRange<Double> get() = if (this == KG) 20.0..350.0 else 44.0..770.0

    /** "kg", "lb" */
    val symbol: String get() = raw

    /** The More menu: "Kilograms", "Pounds". */
    val menuTitle: String get() = if (this == KG) "Kilograms" else "Pounds"

    /** TalkBack: "kilograms", "pounds". */
    val spoken: String get() = if (this == KG) "kilograms" else "pounds"

    /** Decimals a weigh-in shows: kilograms as typed with up to two, pounds with one. */
    val decimals: Int get() = if (this == KG) 2 else 1

    companion object {
        /** The international avoirdupois pound, exactly. */
        const val KILOGRAMS_PER_POUND = 0.45359237

        /**
         * The regions whose person weight is in pounds: CLDR's unit preferences for mass, usage "person", name `pound`
         * for US only; GB is `stone-and-pound`, which reads as kilograms here until a UK user asks for stones, as on the
         * iPhone (https://github.com/unicode-org/cldr/blob/main/common/supplemental/units.xml, `unitPreferences
         * category="mass" usage="person"`). The iPhone reads the same table through Foundation's
         * `UnitMass(forLocale:usage: .personWeight)`; Android has no person-weight API, so the region is read here.
         */
        private val POUND_REGIONS = setOf("US")

        /** The unit a new person sees: pounds where the locale's person weight is pounds, kilograms everywhere else. */
        fun preferred(locale: Locale): WeightUnit = if (locale.country.uppercase(Locale.ROOT) in POUND_REGIONS) LB else KG

        fun fromRaw(raw: String): WeightUnit? = entries.firstOrNull { it.raw == raw }
    }
}

/** Weights as numbers on screen and as typed, in the person's locale. */
object WeightFormat {
    /** A weigh-in: "88.35", "88.0" ("88,35" in de_DE), in kilograms with one or two decimals as typed; "194.8" in pounds. */
    fun value(kg: Double, unit: WeightUnit, locale: Locale = Locale.getDefault()): String {
        val value = unit.valueFromKilograms(kg)
        return when (unit) {
            WeightUnit.KG -> decimal(value, 1, 2, locale)
            WeightUnit.LB -> decimal(value, 1, 1, locale)
        }
    }

    /** The trend and its changes: one decimal in either unit, "88.1". */
    fun trend(kg: Double, unit: WeightUnit, locale: Locale = Locale.getDefault()): String =
        decimal(unit.valueFromKilograms(kg), 1, 1, locale)

    /** "88.35 kg" */
    fun withUnit(kg: Double, unit: WeightUnit, locale: Locale = Locale.getDefault()): String =
        "${value(kg, unit, locale)} ${unit.symbol}"

    /** "88.35 kilograms", for TalkBack. */
    fun spoken(kg: Double, unit: WeightUnit, locale: Locale = Locale.getDefault()): String =
        "${value(kg, unit, locale)} ${unit.spoken}"

    /**
     * A number with `minFraction` to `maxFraction` decimals in the locale, never grouped: Swift's
     * `.number.precision(.fractionLength(min...max)).grouping(.never).locale(locale)`. That is ICU, which rounds the
     * shortest decimal that reads back as the double ("88.35", not the binary 88.3499...) half to even, so 88.35 shows
     * as 88.4 at one decimal; the shortest decimal is Kotlin's `toString`, rounded the same way here.
     */
    fun decimal(value: Double, minFraction: Int, maxFraction: Int, locale: Locale = Locale.getDefault()): String {
        val format = DecimalFormat("0", DecimalFormatSymbols.getInstance(locale))
        format.isGroupingUsed = false
        format.minimumFractionDigits = minFraction
        format.maximumFractionDigits = maxFraction
        format.roundingMode = RoundingMode.HALF_EVEN
        if (!value.isFinite()) return format.format(value)
        return format.format(BigDecimal(value.toString()))
    }

    /**
     * What was typed, as a number: digits with at most one decimal separator (the locale's, a point or a comma; a weight
     * never needs a thousands separator) and at most two decimals. Any script's digits count, so the decimal keyboard
     * works in every locale. Null for anything else.
     */
    fun parse(text: String, locale: Locale = Locale.getDefault()): Double? {
        val separators = decimalSeparators(locale)
        val whole = StringBuilder()
        val fraction = StringBuilder()
        var seenSeparator = false
        for (codePoint in trimWhitespace(text).codePoints().toArray()) {
            val digit = asciiDigit(codePoint)
            if (digit != null) {
                if (seenSeparator) fraction.append(digit) else whole.append(digit)
            } else if (codePoint in separators && !seenSeparator) {
                seenSeparator = true
            } else {
                return null
            }
        }
        if (whole.isEmpty() || whole.length > 4 || fraction.length > 2) return null
        return (if (fraction.isEmpty()) whole.toString() else "$whole.$fraction").toDouble()
    }

    /**
     * The field as it is typed: digits and one separator, two decimals at most (one in the Goal sheet); anything else is
     * dropped as it comes.
     */
    fun sanitize(text: String, locale: Locale = Locale.getDefault(), maxDecimals: Int = 2): String {
        val separators = decimalSeparators(locale)
        val out = StringBuilder()
        var count = 0
        var decimals = -1
        for (codePoint in text.codePoints().toArray()) {
            if (asciiDigit(codePoint) != null) {
                if (decimals >= maxDecimals || (decimals < 0 && count >= 4)) continue
                out.appendCodePoint(codePoint)
                count += 1
                if (decimals >= 0) decimals += 1
            } else if (codePoint in separators && decimals < 0 && count > 0) {
                out.appendCodePoint(codePoint)
                count += 1
                decimals = 0
            }
        }
        return out.toString()
    }

    /** The weight a typed value saves, in kilograms: it parses in the locale and sits inside the unit's bounds. */
    fun kilograms(text: String, unit: WeightUnit, locale: Locale = Locale.getDefault()): Double? {
        val value = parse(text, locale) ?: return null
        if (value !in unit.bounds) return null
        return unit.kilograms(value)
    }

    /** A point, a comma, the Arabic decimal separator and the locale's own. */
    internal fun decimalSeparators(locale: Locale): Set<Int> =
        setOf('.'.code, ','.code, 0x066B, DecimalFormatSymbols.getInstance(locale).decimalSeparator.code)

    /** Swift's `isNumber` with a `wholeNumberValue` of 0 to 9: a digit in any script, as an ASCII digit. */
    internal fun asciiDigit(codePoint: Int): Char? {
        val type = Character.getType(codePoint)
        val numeric = type == Character.DECIMAL_DIGIT_NUMBER.toInt() || type == Character.LETTER_NUMBER.toInt() ||
            type == Character.OTHER_NUMBER.toInt()
        if (!numeric) return null
        val value = Character.getNumericValue(codePoint)
        if (value !in 0..9) return null
        return '0' + value
    }

    /** Swift's `trimmingCharacters(in: .whitespaces)`: spaces and tabs, not line breaks. */
    internal fun trimWhitespace(text: String): String =
        text.trim { it == '\t' || Character.getType(it) == Character.SPACE_SEPARATOR.toInt() }
}

// MARK: - The file

/** The chart's range: a week, 30 days, 90 days, a year or everything (MyNetDiary's set). It filters; it never scrolls. */
enum class WeightRange(val raw: String) {
    WEEK("week"),
    MONTH("30d"),
    QUARTER("90d"),
    YEAR("year"),
    ALL("all");

    /** "W", "30D", "90D", "Y", "All" */
    val label: String
        get() = when (this) {
            WEEK -> "W"
            MONTH -> "30D"
            QUARTER -> "90D"
            YEAR -> "Y"
            ALL -> "All"
        }

    /** For TalkBack. */
    val spoken: String
        get() = when (this) {
            WEEK -> "Week"
            MONTH -> "30 days"
            QUARTER -> "90 days"
            YEAR -> "Year"
            ALL -> "All"
        }

    /** Days in view, ending today; null for everything. */
    val days: Int?
        get() = when (this) {
            WEEK -> 7
            MONTH -> 30
            QUARTER -> 90
            YEAR -> 365
            ALL -> null
        }

    companion object {
        fun fromRaw(raw: String): WeightRange? = entries.firstOrNull { it.raw == raw }
    }
}

/** What an import added: new weigh-ins, and those whose minute was already here. */
data class WeightMerge(val added: Int, val already: Int)

/**
 * Everything the Weight tab keeps: weights.json, next to the log. Its own file, not taken.json, so a build without the tab
 * never reads or rewrites it. Its fields are `var`s holding immutable values, as `StackState`'s are, so a change works on
 * a [clone] and the copy the screen shows never changes underneath it.
 */
data class WeightState(
    var weighIns: List<WeighIn> = emptyList(),
    /**
     * The Weight tab: null until the person chooses, which is off; true or false once they have (Profile's switch, the
     * More menu, the offer on Today). An explicit choice is kept if the default ever changes.
     */
    var showsTab: Boolean? = null,
    /** Kilograms or pounds, from the More menu. Null follows the locale (`WeightUnit.preferred`). */
    var unit: WeightUnit? = null,
    /** The chart's last range. Null is All. */
    var range: WeightRange? = null,
    /** Today's one-time offer was answered, Add tab or Not now. Either answer is final. */
    var offerAnswered: Boolean = false,
    /** The first weigh-in ever saved. That one needs no Taken Pro; after it, logging does (`WeightGate`). Erase keeps it. */
    var firstWeighInAt: Instant? = null,
    /** The optional goal, from the More menu's Set goal (`WeightGoal`). Erase removes it. */
    var goal: WeightGoal? = null,
    /** Centimetres, asked only in the Goal sheet, used only for the BMI 18.5 floor and the BMI 25 check. Erase removes it. */
    var heightCm: Double? = null,
    var schemaVersion: Int = 1,
) {
    /** A copy that shares nothing mutable with this one. */
    fun clone(): WeightState = copy()

    // MARK: Reading

    /** Newest first: All weigh-ins. */
    val newestFirst: List<WeighIn> get() = weighIns.sortedByDescending { it.weighedAt }

    /** The latest weigh-in: the grey number on the page and "Last weigh-in". */
    val last: WeighIn? get() = weighIns.maxByOrNull { it.weighedAt }

    fun weighIn(id: UUID): WeighIn? = weighIns.firstOrNull { it.id == id }

    // MARK: Changing

    /** Logs a weigh-in at a moment, where it was taken. The first one ever is remembered for the Pro rule. */
    fun log(kg: Double, at: Instant, zone: ZoneId, id: UUID = UUID.randomUUID()): WeighIn {
        val weighIn = WeighIn(id = id, kg = kg, weighedAt = at, utcOffset = DayClock.offset(zone, at))
        weighIns = weighIns + weighIn
        if (firstWeighInAt == null) firstWeighInAt = at
        return weighIn
    }

    /** A new weight, day or time for one weigh-in (All weigh-ins). Returns it as it was, for Undo. */
    fun update(id: UUID, kg: Double, at: Instant, zone: ZoneId): WeighIn? {
        val index = weighIns.indexOfFirst { it.id == id }
        if (index < 0) return null
        val before = weighIns[index]
        var changed = before.copy(kg = kg)
        if (at != before.weighedAt) changed = changed.copy(weighedAt = at, utcOffset = DayClock.offset(zone, at))
        weighIns = weighIns.toMutableList().also { it[index] = changed }
        return before
    }

    fun delete(id: UUID): WeighIn? {
        val index = weighIns.indexOfFirst { it.id == id }
        if (index < 0) return null
        val removed = weighIns[index]
        weighIns = weighIns.toMutableList().also { it.removeAt(index) }
        return removed
    }

    /** Undo: puts a weigh-in back exactly as it was, deleted or edited. */
    fun restore(weighIn: WeighIn) {
        val index = weighIns.indexOfFirst { it.id == weighIn.id }
        weighIns = if (index >= 0) weighIns.toMutableList().also { it[index] = weighIn } else weighIns + weighIn
    }

    /**
     * Imported weigh-ins (`WeightImport`): one whose minute is already here is skipped, so importing the same file twice
     * adds nothing. Returns how many were added and how many were already here.
     */
    fun merge(incoming: List<WeighIn>, now: Instant): WeightMerge {
        val minutes = weighIns.map { WeightImport.minute(it.weighedAt) }.toMutableSet()
        var added = 0
        var already = 0
        val next = weighIns.toMutableList()
        for (weighIn in incoming.sortedBy { it.weighedAt }) {
            if (!minutes.add(WeightImport.minute(weighIn.weighedAt))) {
                already += 1
                continue
            }
            next.add(weighIn)
            added += 1
        }
        weighIns = next
        if (added > 0 && firstWeighInAt == null) firstWeighInAt = now
        return WeightMerge(added, already)
    }

    /**
     * Erase all data: the weigh-ins go, and so do the chart's range, the goal and the height. The tab setting, the unit,
     * the offer's answer and the first weigh-in's date stay, like the look and the date of the first voice note.
     */
    fun eraseAll() {
        weighIns = emptyList()
        range = null
        goal = null
        heightCm = null
    }

    /** The days that have a weigh-in, the only days a goal's points can land on. */
    fun weighInDays(clock: DayClock): Set<DayKey> = weighIns.map { clock.day(it) }.toSet()
}

// MARK: - The trend

/** A weight on a day: the day's lowest weigh-in, a day filled between two, or the trend. */
data class WeightPoint(val day: DayKey, val kg: Double)

/**
 * The trend under the daily swings, worked out the way The Hacker's Diet does it by hand
 * (https://www.fourmilab.ch/hackdiet/e4/pencilpaper.html, https://www.fourmilab.ch/hackdiet/e4/signalnoise.html).
 */
object WeightTrend {
    /**
     * Each day's trend moves a tenth of the way from yesterday's trend toward that day's weight (smoothing constant 0.9).
     * It lags about 9 to 10 days: Fourmilab calls 0.9 "roughly equivalent to a 20 day simple moving average".
     */
    const val SMOOTHING = 0.1

    /** The changes worked out for the trend, each once the trend is that long. */
    val CHANGE_SPANS = listOf(7, 30, 90)

    /**
     * (1) One value per day, the day's lowest weigh-in (Happy Scale: "the lowest weight you achieved that day",
     * https://happyscale.com/support), oldest first. Days are DayClock's, as for doses.
     */
    fun daily(weighIns: List<WeighIn>, clock: DayClock): List<WeightPoint> {
        val lowest = HashMap<DayKey, Double>()
        for (weighIn in weighIns) {
            if (!weighIn.kg.isFinite() || weighIn.kg <= 0) continue
            val day = clock.day(weighIn)
            lowest[day] = min(lowest[day] ?: weighIn.kg, weighIn.kg)
        }
        return lowest.map { WeightPoint(it.key, it.value) }.sortedBy { it.day }
    }

    /**
     * (2) Every day from the first weigh-in to the last: a day with weigh-ins is its lowest, a day between two is on the
     * straight line between them (MacroFactor: 151 on Monday and 150 on Wednesday give 150.5 on Tuesday,
     * https://help.macrofactorapp.com/dashboard/weight_trend/).
     */
    fun filled(daily: List<WeightPoint>): List<WeightPoint> {
        var previous = daily.firstOrNull() ?: return emptyList()
        val out = mutableListOf(previous)
        for (next in daily.drop(1)) {
            val gap = previous.day.distanceTo(next.day)
            if (gap > 1) {
                for (step in 1 until gap) {
                    val fraction = step.toDouble() / gap.toDouble()
                    out.add(WeightPoint(previous.day.adding(step), previous.kg + (next.kg - previous.kg) * fraction))
                }
            }
            out.add(next)
            previous = next
        }
        return out
    }

    /**
     * (3) The trend on every day from the first weigh-in to the last: it starts at the first weigh-in, then
     * T(n) = T(n-1) + 0.1 x (W(n) - T(n-1)). (4) Nothing past the last weigh-in: no line, no forecast.
     */
    fun trend(weighIns: List<WeighIn>, clock: DayClock): List<WeightPoint> = trend(daily(weighIns, clock))

    fun trend(daily: List<WeightPoint>): List<WeightPoint> {
        var trend: Double? = null
        return filled(daily).map { point ->
            val next = trend?.let { it + SMOOTHING * (point.kg - it) } ?: point.kg
            trend = next
            WeightPoint(point.day, next)
        }
    }

    /**
     * How far the trend moved over the last `days` days up to its last day, in kilograms (negative is down). Null until
     * the trend is that long, so a change is never read off a few days.
     */
    fun change(trend: List<WeightPoint>, days: Int): Double? {
        val first = trend.firstOrNull() ?: return null
        val last = trend.lastOrNull() ?: return null
        val target = last.day.adding(-days)
        val index = first.day.distanceTo(target)
        if (index < 0 || index >= trend.size || trend[index].day != target) return null
        return last.kg - trend[index].kg
    }

    /** Every change there is history for: 7, 30 and 90 days. */
    fun changes(trend: List<WeightPoint>): List<WeightChange> =
        CHANGE_SPANS.mapNotNull { days -> change(trend, days)?.let { WeightChange(days, it) } }
}

/** The trend's change over a span, one neutral arrow and a number, never red or green. */
data class WeightChange(val days: Int, val kg: Double) {
    enum class Direction { DOWN, UP, FLAT }

    /** As the number reads at one decimal in the unit: anything that rounds to 0.0 is flat. */
    fun direction(unit: WeightUnit): Direction {
        val shown = roundedAway(unit.valueFromKilograms(kg) * 10) / 10
        if (shown < 0) return Direction.DOWN
        if (shown > 0) return Direction.UP
        return Direction.FLAT
    }

    /** "7 days" */
    val label: String get() = "$days days"

    /** The arrow's name as the iPhone's SF Symbol names it ("arrow.down", "arrow.up", "arrow.right"). */
    fun symbol(unit: WeightUnit): String = when (direction(unit)) {
        Direction.DOWN -> "arrow.down"
        Direction.UP -> "arrow.up"
        Direction.FLAT -> "arrow.right"
    }

    /** "1.2 kg", without a sign: the arrow carries it. */
    fun amount(unit: WeightUnit, locale: Locale = Locale.getDefault()): String =
        "${WeightFormat.trend(abs(kg), unit, locale)} ${unit.symbol}"

    /** "Down 1.2 kilograms over 30 days", for TalkBack. */
    fun spoken(unit: WeightUnit, locale: Locale = Locale.getDefault()): String {
        val amount = WeightFormat.trend(abs(kg), unit, locale)
        return when (direction(unit)) {
            Direction.DOWN -> "Down $amount ${unit.spoken} over $days days"
            Direction.UP -> "Up $amount ${unit.spoken} over $days days"
            Direction.FLAT -> "No change over $days days"
        }
    }
}

// MARK: - The chart

/**
 * The days a weekly dose was logged: a small unlabelled tick on the chart's baseline, as the GLP-1 trackers mark doses on
 * their weight charts. Only items on a Weekly schedule (a one-day Days set, how Taken starts Semaglutide and Tirzepatide)
 * on the day the dose was logged, never a drug name.
 */
object WeightTicks {
    fun days(engine: StackEngine): List<DayKey> {
        // The first item with an id wins, as the iPhone's `uniquingKeysWith: { first, _ in first }`.
        val items = HashMap<UUID, Item>()
        for (item in engine.state.items) items.putIfAbsent(item.id, item)
        val days = HashSet<DayKey>()
        for (dose in engine.state.doses) {
            val item = items[dose.itemId] ?: continue
            val day = engine.clock.day(dose)
            if (engine.isWeekly(item, day)) days.add(day)
        }
        return days.sorted()
    }
}

/**
 * What the chart shows for a range: the days in view, the trend and the weigh-ins inside them, the dose ticks, and a y
 * axis fitted to them with padding that never starts at zero.
 */
data class WeightWindow(
    val firstDay: DayKey,
    val lastDay: DayKey,
    val trend: List<WeightPoint>,
    /** Every weigh-in in view, on its day (several on one day stack up). */
    val dots: List<WeightPoint>,
    val ticks: List<DayKey>,
    /** The y axis, in kilograms. */
    val lower: Double,
    val upper: Double,
    /**
     * The goal, in kilograms, and whether the y axis takes it in. It joins only if the padded span with it is at most
     * twice the span without it, so the data always keeps at least half the plot (the iPhone's own rule); otherwise its
     * label is pinned to the edge and nothing squashes the line.
     */
    val goalKg: Double?,
    val goalInDomain: Boolean,
) {
    val isEmpty: Boolean get() = dots.isEmpty() && trend.isEmpty()

    /** Whether a day is inside the window. */
    fun contains(day: DayKey): Boolean = day >= firstDay && day <= lastDay

    companion object {
        /** The least the y axis is padded by, either side, in kilograms (the iPhone's own choice). */
        const val MINIMUM_PADDING = 0.4

        /** The y axis around `low` and `high`: 15% of the span, at least [MINIMUM_PADDING], never below zero. */
        fun padded(low: Double, high: Double): Pair<Double, Double> {
            val padding = max(MINIMUM_PADDING, (high - low) * 0.15)
            return max(0.0, low - padding) to high + padding
        }

        fun make(
            weighIns: List<WeighIn>,
            trend: List<WeightPoint>,
            ticks: List<DayKey>,
            range: WeightRange,
            today: DayKey,
            clock: DayClock,
            goalKg: Double? = null,
        ): WeightWindow {
            val days = weighIns.map { clock.day(it) }
            val lastDay = maxOf(today, days.maxOrNull() ?: today)
            var firstDay = range.days?.let { lastDay.adding(-(it - 1)) } ?: (days.minOrNull() ?: lastDay)
            // At least a week across, so a single weigh-in is not a dot against the edge.
            if (firstDay.distanceTo(lastDay) < 6) firstDay = lastDay.adding(-6)
            fun inView(day: DayKey) = day >= firstDay && day <= lastDay
            val dots = weighIns.zip(days).filter { inView(it.second) }.map { WeightPoint(it.second, it.first.kg) }
                .sortedBy { it.day }
            val shownTrend = trend.filter { inView(it.day) }
            val values = dots.map { it.kg } + shownTrend.map { it.kg }
            val low = values.minOrNull() ?: 0.0
            val high = values.maxOrNull() ?: 0.0
            var bounds = padded(low, high)
            var goalInDomain = false
            if (goalKg != null && values.isNotEmpty()) {
                val with = padded(min(low, goalKg), max(high, goalKg))
                if (with.second - with.first <= 2 * (bounds.second - bounds.first) + 1e-9) {
                    bounds = with
                    goalInDomain = true
                }
            }
            return WeightWindow(
                firstDay = firstDay, lastDay = lastDay, trend = shownTrend, dots = dots, ticks = ticks.filter { inView(it) },
                lower = bounds.first, upper = bounds.second, goalKg = goalKg, goalInDomain = goalInDomain,
            )
        }
    }
}

// MARK: - Taken Pro

/**
 * Weigh-ins follow the rule doses and voice to-dos follow (PRO.md): the first weigh-in ever needs no Pro; after it,
 * logging, editing, backdating and importing need it. The chart, the trend, All weigh-ins and the CSV export never do.
 */
object WeightGate {
    fun access(firstWeighInAt: Instant?, status: ProStatus?, settled: Boolean, legacyLog: Boolean, now: Instant): ProAccess =
        ProGate.access(status = status, settled = settled, legacyLog = legacyLog, hasLogged = firstWeighInAt != null, now = now)
}

// MARK: - The offer on Today

/**
 * "Log your weight here too: add a Weight tab", once: only to a stack with an active Semaglutide, Tirzepatide or Oral
 * Semaglutide item whose dose has been logged, on a day everything due is taken, on a later day than the first dose and
 * than the widget invite's day (so never in the first session), while the tab was never chosen and the offer never
 * answered. `TodayPrompts.pick` puts it after every other row, and never while locked.
 */
object WeightOffer {
    /** Semaglutide, Tirzepatide, Oral Semaglutide (Catalog codes; their brand names typed in full map to these). */
    val MEDICINE_CODES: Set<String> = setOf("SEM", "TRZ", "OSM")

    fun shows(weight: WeightState, state: StackState, today: DaySummary, clock: DayClock): Boolean {
        if (weight.showsTab != null || weight.offerAnswered || !today.allTaken) return false
        val medicines = state.items.filter { !it.archived && it.code.uppercase(Locale.ROOT) in MEDICINE_CODES }.map { it.id }.toSet()
        if (medicines.isEmpty() || state.doses.none { it.itemId in medicines }) return false
        val first = state.doses.minByOrNull { it.takenAt } ?: return false
        if (clock.day(first) >= today.day) return false
        // The widget invite has had its day: shown on an earlier day, or answered without showing (a Taken widget already
        // there). Until then it comes first, and never on the same day as this.
        val inviteDay = state.settings.widgetInviteDay
        if (inviteDay != null) return inviteDay < today.day.ordinal
        return state.settings.widgetInviteDone
    }
}

// MARK: - CSV

/** Profile > Data > Export weight CSV: taken-weight.csv, one row per weigh-in, oldest first, in local wall-clock time. */
object WeightCSV {
    const val FILE_NAME = "taken-weight.csv"
    const val HEADER = "date,time,kg"

    fun make(weighIns: List<WeighIn>, zone: ZoneId = ZoneId.systemDefault()): String {
        val lines = mutableListOf(HEADER)
        for (weighIn in weighIns.sortedBy { it.weighedAt }) {
            val c = weighIn.weighedAt.atZone(zone)
            val date = String.format(Locale.ROOT, "%04d-%02d-%02d", c.year, c.monthValue, c.dayOfMonth)
            val time = String.format(Locale.ROOT, "%02d:%02d", c.hour, c.minute)
            lines.add("$date,$time,${kilograms(weighIn.kg)}")
        }
        return lines.joinToString("\n") + "\n"
    }

    /**
     * "88.35", "88.0", "88.269": up to three decimals, so a weigh-in typed in pounds comes back to the same tenth. The
     * iPhone's `String(format: "%.3f")` rounds the exact binary value half to even, as BigDecimal does here.
     */
    fun kilograms(kg: Double): String {
        var text = BigDecimal(kg).setScale(3, RoundingMode.HALF_EVEN).toPlainString()
        while (text.endsWith("0") && !text.endsWith(".0")) text = text.dropLast(1)
        return text
    }
}
