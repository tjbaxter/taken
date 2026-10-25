package com.tombaxter.taken.core.weight

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.time.DateTimeException
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.chrono.IsoChronology
import java.time.format.DateTimeFormatterBuilder
import java.time.format.FormatStyle
import java.util.Locale

/**
 * Profile > Data > Import weight CSV: history from another app (MyNetDiary's Data Export, Weigh In, Libra) or Taken's own
 * taken-weight.csv. It reads a date column and a weight column in kilograms or pounds, by their headers: the unit from
 * the weight header ("Weight (kg)", "lbs") or from the cells ("88.35 kg"), else the person's own unit, which the result
 * names. An optional time column; a row with a date alone is noon, as Happy Scale records a day's weight. Commas,
 * semicolons or tabs; a decimal point or comma; ISO dates, day or month first (worked out from the whole column, then
 * the locale), and "21 Oct 2026" or "Oct 21, 2026". A row it cannot read, a weight outside the bounds or a moment still
 * to come is skipped and counted. Ported from Shared/WeightData.swift `WeightImport`.
 */
object WeightImport {
    data class Parsed(
        val weighIns: List<WeighIn>,
        /** The unit the weights were read in. */
        val unit: WeightUnit,
        /** Rows with something in them that could not be read. */
        val unreadable: Int,
    )

    enum class Failure {
        /** No date column and weight column side by side. */
        NO_COLUMNS,

        /** Columns found, but not one row could be read. */
        NOTHING_READABLE,
    }

    /** Swift's `Result<Parsed, Failure>`. */
    sealed class Result {
        data class Success(val parsed: Parsed) : Result()
        data class Failed(val failure: Failure) : Result()

        fun getOrNull(): Parsed? = (this as? Success)?.parsed
    }

    /** The minute a weigh-in falls in: two weigh-ins in the same minute are the same one (`WeightState.merge`). */
    fun minute(at: Instant): Long = Math.floorDiv(at.epochSecond, 60L)

    /** Text from a file: UTF-8 (with or without its byte order mark), UTF-16 with a byte order mark, else Latin-1. */
    fun text(data: ByteArray): String? {
        if (data.size >= 2) {
            val b0 = data[0].toInt() and 0xFF
            val b1 = data[1].toInt() and 0xFF
            if ((b0 == 0xFF && b1 == 0xFE) || (b0 == 0xFE && b1 == 0xFF)) return String(data, Charsets.UTF_16)
        }
        val strict = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        return try {
            strict.decode(ByteBuffer.wrap(data)).toString()
        } catch (e: CharacterCodingException) {
            String(data, Charsets.ISO_8859_1)
        }
    }

    fun parse(
        text: String,
        fallbackUnit: WeightUnit,
        locale: Locale = Locale.getDefault(),
        zone: ZoneId = ZoneId.systemDefault(),
        now: Instant = Instant.now(),
    ): Result {
        val cleaned = text.replace("﻿", "").replace("\r\n", "\n").replace("\r", "\n")
        val lines = cleaned.split("\n")
        // The header may sit under a title line or two.
        var found: Triple<Int, Char, Columns>? = null
        for ((index, line) in lines.take(12).withIndex()) {
            if (WeightFormat.trimWhitespace(line).isEmpty()) continue
            val delimiter = delimiter(line)
            val columns = Columns.fromHeader(split(line, delimiter))
            if (columns != null) {
                found = Triple(index, delimiter, columns)
                break
            }
        }
        val parser = DateParser(zone)
        val rows: List<List<String>>
        val columns: Columns
        val header = found
        if (header != null) {
            columns = header.third
            rows = lines.drop(header.first + 1).map { split(it, header.second) }
        } else {
            // No header: two columns, a date and a number, in the person's unit.
            val first = lines.firstOrNull { WeightFormat.trimWhitespace(it).isNotEmpty() }
                ?: return Result.Failed(Failure.NO_COLUMNS)
            val delimiter = delimiter(first)
            val cells = split(first, delimiter)
            if (cells.size < 2 || !parser.looksLikeDate(cells[0]) || number(cells[1]) == null) {
                return Result.Failed(Failure.NO_COLUMNS)
            }
            columns = Columns(date = 0, time = null, weight = 1, unit = null)
            rows = lines.map { split(it, delimiter) }
        }

        val filled = rows.filter { row -> row.any { WeightFormat.trimWhitespace(it).isNotEmpty() } }
        val order = parser.order(filled.mapNotNull { it.getOrNull(columns.date) }, locale)
        var unreadable = 0
        val byMinute = HashMap<Long, WeighIn>()
        var unitUsed = columns.unit ?: fallbackUnit
        for (row in filled) {
            val reading = if (columns.date < row.size && columns.weight < row.size) number(row[columns.weight]) else null
            if (reading == null) {
                unreadable += 1
                continue
            }
            val unit = reading.second ?: columns.unit ?: fallbackUnit
            val time = columns.time?.let { row.getOrNull(it) }
            val moment = if (reading.first in unit.bounds) parser.moment(row[columns.date], time, order) else null
            if (moment == null || moment.first > now.plusSeconds(60)) {
                unreadable += 1
                continue
            }
            unitUsed = unit
            val weighIn = WeighIn(kg = unit.kilograms(reading.first), weighedAt = moment.first, utcOffset = moment.second)
            val key = minute(moment.first)
            // Two rows in the same minute (a date alone, twice): the lower stays, as the trend reads a day.
            val kept = byMinute[key]
            if (kept != null && kept.kg <= weighIn.kg) continue
            byMinute[key] = weighIn
        }
        val weighIns = byMinute.values.sortedBy { it.weighedAt }
        if (weighIns.isEmpty()) return Result.Failed(Failure.NOTHING_READABLE)
        return Result.Success(Parsed(weighIns, unitUsed, unreadable))
    }

    // MARK: Columns

    data class Columns(val date: Int, val time: Int?, val weight: Int, val unit: WeightUnit?) {
        companion object {
            /** A header row with a date column and a weight column, or null. */
            fun fromHeader(header: List<String>): Columns? {
                val names = header.map { WeightFormat.trimWhitespace(it).lowercase(Locale.ROOT) }
                val date = names.indexOfFirst { isDate(it) }
                if (date < 0) return null
                val weight = names.indices.firstOrNull { it != date && isWeight(names[it]) } ?: return null
                val time = names.indices.firstOrNull { it != date && it != weight && isTime(names[it]) }
                return Columns(date = date, time = time, weight = weight, unit = WeightImport.unit(names[weight]))
            }

            /** "date", "Date/Time", "Timestamp", "Day"; "Datum", "Fecha", "Data" from a spreadsheet in another language. */
            fun isDate(name: String): Boolean =
                listOf("date", "datum", "fecha", "timestamp").any { name.contains(it) } ||
                    name in listOf("day", "data", "when", "jour", "giorno")

            fun isTime(name: String): Boolean =
                name == "time" || (name.contains("time") && !name.contains("stamp") && !name.contains("zone"))

            /**
             * "weight", "Weight (kg)", "Body Weight, lbs", "kg", "Gewicht (kg)"; never a goal, a trend, a change, fat, lean
             * mass, BMI or a percentage.
             */
            fun isWeight(name: String): Boolean {
                val excluded = listOf(
                    "goal", "target", "trend", "change", "fat", "lean", "bmi", "index", "muscle", "bone", "water", "%",
                    "diff", "delta", "average", "avg", "moving", "smooth", "loss", "gain", "note",
                )
                if (excluded.any { name.contains(it) }) return false
                val words = listOf("weight", "mass", "gewicht", "peso", "poids", "vikt", "vekt")
                return words.any { name.contains(it) } || WeightImport.unit(name) != null
            }
        }
    }

    /** The unit a header or a cell names: kg, kgs, kilograms; lb, lbs, pounds. Null for neither. */
    fun unit(text: String): WeightUnit? {
        val words = text.lowercase(Locale.ROOT).split(Regex("[^\\p{L}]+")).filter { it.isNotEmpty() }
        if (words.any { it == "kg" || it == "kgs" || it.startsWith("kilo") }) return WeightUnit.KG
        if (words.any { it == "lb" || it == "lbs" || it.startsWith("pound") }) return WeightUnit.LB
        return null
    }

    /** A weight cell: "88.35", "88,35", "194.6 lbs", "\"88.35\"". The number and the unit it names, if any. */
    fun number(cell: String): Pair<Double, WeightUnit?>? {
        val trimmed = WeightFormat.trimWhitespace(cell)
        val digits = trimmed.takeWhile { isNumber(it) || it == '.' || it == ',' }
        if (digits.isEmpty()) return null
        val value = WeightFormat.parse(digits, Locale.ROOT) ?: decimalComma(digits) ?: return null
        val rest = WeightFormat.trimWhitespace(trimmed.drop(digits.length))
        if (!(rest.isEmpty() || rest.all { it.isLetter() || it == '.' })) return null
        val unit = if (rest.isEmpty()) null else unit(rest)
        if (rest.isNotEmpty() && unit == null) return null
        return value to unit
    }

    /** Swift's `Character.isNumber`. */
    private fun isNumber(c: Char): Boolean {
        val type = Character.getType(c)
        return type == Character.DECIMAL_DIGIT_NUMBER.toInt() || type == Character.LETTER_NUMBER.toInt() ||
            type == Character.OTHER_NUMBER.toInt()
    }

    /** A value with more decimals than typing allows ("88.257" from another app's export): read as it is. */
    private fun decimalComma(text: String): Double? {
        val parts = text.replace(',', '.').split(".")
        if (parts.size > 2 || !parts.all { part -> part.all { isNumber(it) } }) return null
        val whole = parts.firstOrNull() ?: return null
        if (whole.isEmpty()) return null
        return parts.joinToString(".").toDoubleOrNull()
    }

    /** Commas, semicolons (Excel where the decimal point is a comma) or tabs, whichever the header uses most. */
    fun delimiter(line: String): Char {
        var commas = 0
        var semicolons = 0
        var tabs = 0
        var quoted = false
        for (c in line) {
            if (c == '"') quoted = !quoted
            if (!quoted) {
                when (c) {
                    ',' -> commas += 1
                    ';' -> semicolons += 1
                    '\t' -> tabs += 1
                }
            }
        }
        if (tabs > 0) return '\t'
        return if (semicolons > commas) ';' else ','
    }

    /** One line's cells, with double quotes around a cell that holds the delimiter (RFC 4180). */
    fun split(line: String, delimiter: Char): List<String> {
        val cells = mutableListOf<String>()
        val cell = StringBuilder()
        var quoted = false
        var index = 0
        while (index < line.length) {
            val c = line[index]
            val next = line.getOrNull(index + 1)
            if (c == '"') {
                if (quoted && next == '"') {
                    cell.append('"')
                    index += 1
                } else {
                    quoted = !quoted
                }
            } else if (c == delimiter && !quoted) {
                cells.add(cell.toString())
                cell.setLength(0)
            } else {
                cell.append(c)
            }
            index += 1
        }
        cells.add(cell.toString())
        return cells.map { WeightFormat.trimWhitespace(it) }
    }

    // MARK: Dates

    /** Which comes first in a date like 03/04/2026. */
    enum class DateOrder { DAY_FIRST, MONTH_FIRST }

    /** A moment from a date cell and an optional time cell, in the zone given unless the cell names its own. */
    class DateParser(private val zone: ZoneId) {
        private fun regex(pattern: String) = Regex(pattern, RegexOption.IGNORE_CASE)

        private val time = """(?:[ T,]+(\d{1,2}:\d{2}(?::\d{2})?(?:\.\d+)?\s*(?:[ap]\.?m\.?)?))?"""
        private val iso = regex("""^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})""" + time + """\s*(z|[+-]\d{2}:?\d{2})?$""")
        private val numeric = regex("""^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4}|\d{2})""" + time + "$")
        private val dayName = regex("""^(?:[a-z]+\.?,?\s+)?(\d{1,2})(?:st|nd|rd|th)?[\s-]+([a-z]{3,})\.?,?[\s-]+(\d{4})""" + time + "$")
        private val nameDay = regex("""^(?:[a-z]+\.?,?\s+)?([a-z]{3,})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})""" + time + "$")
        private val clock = regex("""^(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?\s*([ap])?\.?(?:m\.?)?$""")

        fun looksLikeDate(text: String): Boolean =
            moment(text, null, DateOrder.DAY_FIRST) != null || moment(text, null, DateOrder.MONTH_FIRST) != null

        /**
         * Day or month first for a numeric column: a first number over 12 means day first, a second over 12 month first;
         * with neither (every date 12 or under), the locale's own order (its short date pattern, as the iPhone reads
         * `DateFormatter.dateFormat(fromTemplate: "yMd")`).
         */
        fun order(cells: List<String>, locale: Locale): DateOrder {
            var dayFirst = false
            var monthFirst = false
            for (cell in cells) {
                val match = numeric.find(cell) ?: continue
                val a = match.groupValues[1].toIntOrNull() ?: continue
                val b = match.groupValues[2].toIntOrNull() ?: continue
                if (a > 12) dayFirst = true
                if (b > 12) monthFirst = true
            }
            if (dayFirst != monthFirst) return if (dayFirst) DateOrder.DAY_FIRST else DateOrder.MONTH_FIRST
            val pattern = try {
                DateTimeFormatterBuilder.getLocalizedDateTimePattern(FormatStyle.SHORT, null, IsoChronology.INSTANCE, locale)
            } catch (e: IllegalArgumentException) {
                "M/d/y"
            }
            val day = pattern.indexOf('d')
            val month = pattern.indexOf('M')
            if (day >= 0 && month >= 0 && day < month) return DateOrder.DAY_FIRST
            return DateOrder.MONTH_FIRST
        }

        /** The moment and the seconds east of UTC where it was, or null. */
        fun moment(text: String, timeText: String?, order: DateOrder): Pair<Instant, Int>? {
            val cell = WeightFormat.trimWhitespace(text)
            val year: Int
            val month: Int
            val day: Int
            var clockText: String? = null
            var cellZone: ZoneId? = null
            val isoMatch = iso.find(cell)
            val numericMatch = if (isoMatch == null) numeric.find(cell) else null
            val dayNameMatch = if (isoMatch == null && numericMatch == null) dayName.find(cell) else null
            val nameDayMatch = if (isoMatch == null && numericMatch == null && dayNameMatch == null) nameDay.find(cell) else null
            when {
                isoMatch != null -> {
                    year = group(isoMatch, 1)?.toIntOrNull() ?: return null
                    month = group(isoMatch, 2)?.toIntOrNull() ?: return null
                    day = group(isoMatch, 3)?.toIntOrNull() ?: return null
                    clockText = group(isoMatch, 4)
                    group(isoMatch, 5)?.let { cellZone = offsetZone(it) }
                }
                numericMatch != null -> {
                    val a = group(numericMatch, 1)?.toIntOrNull() ?: return null
                    val b = group(numericMatch, 2)?.toIntOrNull() ?: return null
                    val y = group(numericMatch, 3)?.toIntOrNull() ?: return null
                    if (order == DateOrder.DAY_FIRST) {
                        day = a
                        month = b
                    } else {
                        day = b
                        month = a
                    }
                    year = if (y < 100) 2000 + y else y
                    clockText = group(numericMatch, 4)
                }
                dayNameMatch != null -> {
                    day = group(dayNameMatch, 1)?.toIntOrNull() ?: return null
                    month = monthNumber(group(dayNameMatch, 2)) ?: return null
                    year = group(dayNameMatch, 3)?.toIntOrNull() ?: return null
                    clockText = group(dayNameMatch, 4)
                }
                nameDayMatch != null -> {
                    month = monthNumber(group(nameDayMatch, 1)) ?: return null
                    day = group(nameDayMatch, 2)?.toIntOrNull() ?: return null
                    year = group(nameDayMatch, 3)?.toIntOrNull() ?: return null
                    clockText = group(nameDayMatch, 4)
                }
                else -> return null
            }
            // A separate time column wins over a time inside the date cell; a date alone is noon.
            var hour = 12
            var minute = 0
            var second = 0
            val timeCell = timeText?.let { WeightFormat.trimWhitespace(it) }
            val written = if (!timeCell.isNullOrEmpty()) timeCell else clockText
            if (written != null) {
                val parsed = hourMinute(written) ?: return null
                hour = parsed.first
                minute = parsed.second
                second = parsed.third
            }
            if (month !in 1..12 || day !in 1..31 || year !in 1900..2999) return null
            val at = try {
                // 31 February is not a date: java.time refuses it, where the iPhone's calendar rolls it over and checks.
                ZonedDateTime.of(year, month, day, hour, minute, second, 0, cellZone ?: zone)
            } catch (e: DateTimeException) {
                return null
            }
            if (at.year != year || at.monthValue != month || at.dayOfMonth != day) return null
            val instant = at.toInstant()
            return instant to (cellZone ?: zone).rules.getOffset(instant).totalSeconds
        }

        /** "07:42", "7:42 AM", "19:05:30": hours, minutes and seconds on the 24-hour clock. */
        fun hourMinute(text: String): Triple<Int, Int, Int>? {
            val cell = WeightFormat.trimWhitespace(text)
            val match = clock.find(cell) ?: return null
            var hour = group(match, 1)?.toIntOrNull() ?: return null
            val minute = group(match, 2)?.toIntOrNull() ?: return null
            if (minute >= 60) return null
            val second = group(match, 3)?.toIntOrNull() ?: 0
            val half = group(match, 4)?.lowercase(Locale.ROOT)
            if (half != null) {
                if (hour !in 1..12) return null
                if (half == "p" && hour < 12) hour += 12
                if (half == "a" && hour == 12) hour = 0
            }
            if (hour >= 24 || second >= 60) return null
            return Triple(hour, minute, second)
        }

        private fun monthNumber(name: String?): Int? {
            val lower = name?.lowercase(Locale.ROOT) ?: return null
            if (lower.length < 3) return null
            val index = MONTHS.indexOf(lower.take(3))
            return if (index < 0) null else index + 1
        }

        private fun offsetZone(text: String): ZoneId? {
            val lower = text.lowercase(Locale.ROOT)
            if (lower == "z") return ZoneOffset.UTC
            val digits = lower.filter { it.isDigit() }
            if (digits.length != 4) return null
            val hours = digits.take(2).toIntOrNull() ?: return null
            val minutes = digits.takeLast(2).toIntOrNull() ?: return null
            val seconds = (hours * 60 + minutes) * 60
            return try {
                ZoneOffset.ofTotalSeconds(if (lower.startsWith("-")) -seconds else seconds)
            } catch (e: DateTimeException) {
                null
            }
        }

        /** A capture group's text; null when it did not take part in the match. */
        private fun group(match: MatchResult, index: Int): String? = match.groups[index]?.value

        private companion object {
            val MONTHS = listOf("jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec")
        }
    }
}
