package com.tombaxter.taken.core

import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.Item
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale

// TakenTests/TestSupport.swift: a fixed zone so day math is deterministic on any CI machine.

val london: ZoneId = ZoneId.of("Europe/London")
val newYork: ZoneId = ZoneId.of("America/New_York")
val enUS: Locale = Locale.US

fun londonClock(dayStartHour: Int = 4, zone: ZoneId = london): DayClock = DayClock(dayStartHour, zone)

/** A wall-clock moment in London. */
fun at(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0, zone: ZoneId = london): Instant =
    ZonedDateTime.of(year, month, day, hour, minute, 0, 0, zone).toInstant()

fun makeItem(
    name: String,
    code: String,
    frequency: Frequency = Frequency.Daily(1),
    created: Instant,
    sortIndex: Int = 0,
): Item = Item(name = name, code = code, frequency = frequency, createdAt = created, sortIndex = sortIndex)

/** The copy rules every user-facing line keeps: no em or en dash, never the word for no charge, no exclamation mark. */
fun assertCopyRules(text: String) {
    kotlin.test.assertFalse(text.contains("—") || text.contains("–"), "no em or en dash: $text")
    kotlin.test.assertFalse(text.lowercase().contains("free"), "never the word for no charge: $text")
    kotlin.test.assertFalse(text.contains("!"), "no exclamation mark: $text")
}
