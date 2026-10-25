package com.tombaxter.taken.core.model

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.JsonUnquotedLiteral
import java.math.BigDecimal
import java.math.RoundingMode
import java.time.Instant
import java.util.TreeMap
import java.util.UUID

/**
 * The iPhone's JSON rules, by hand over kotlinx-serialization's JSON tree (SPEC-ANDROID 5.2), so a file crosses between
 * the two apps unchanged: keys written sorted; dates as seconds since 1970 as a JSON number, integral values without a
 * fraction; UUIDs uppercase and hyphenated; optional values left out when absent. Reading mirrors Swift's `Codable`:
 * a required key that is missing or null, or any value of the wrong type, throws [JsonShapeException]; the lenient
 * reads (`lenient { }`) turn that into null, as Swift's `try?` does.
 */
class JsonShapeException(message: String) : Exception(message)

object TakenJson {
    private val parser = Json { isLenient = false }

    /** The JSON tree of a file's text. A file that is not JSON at all throws [JsonShapeException]. */
    fun parse(text: String): JsonElement = try {
        parser.parseToJsonElement(text)
    } catch (e: Exception) {
        throw JsonShapeException("not JSON: ${e.message}")
    }

    /** An object whose keys are written sorted; null values are left out. */
    fun obj(vararg entries: Pair<String, JsonElement?>): JsonObject {
        val map = TreeMap<String, JsonElement>()
        for ((key, value) in entries) if (value != null) map[key] = value
        return JsonObject(map)
    }

    fun obj(map: Map<String, JsonElement>): JsonObject = JsonObject(TreeMap(map))

    fun string(value: String): JsonPrimitive = JsonPrimitive(value)
    fun int(value: Int): JsonPrimitive = JsonPrimitive(value)
    fun long(value: Long): JsonPrimitive = JsonPrimitive(value)
    fun bool(value: Boolean): JsonPrimitive = JsonPrimitive(value)
    fun double(value: Double): JsonPrimitive =
        if (value == Math.floor(value) && !value.isInfinite() && Math.abs(value) < 1e15) {
            JsonPrimitive(value.toLong())
        } else {
            JsonUnquotedLiteral(BigDecimal.valueOf(value).stripTrailingZeros().toPlainString())
        }

    /** "6F1C0A3E-..." as the iPhone writes it. */
    fun uuid(value: UUID): JsonPrimitive = JsonPrimitive(value.toString().uppercase())

    /**
     * Seconds since 1970 as a number: "1760510520" for a whole second, else "1760510520.123" to the microsecond, never
     * kotlinx's "1.76051052E9" style. Microseconds keep a time that came from the iPhone's double the same double.
     */
    fun instant(value: Instant): JsonPrimitive {
        var seconds = value.epochSecond
        var micros = Math.round(value.nano / 1000.0)
        if (micros >= 1_000_000L) {
            seconds += 1
            micros -= 1_000_000L
        }
        if (micros == 0L) return JsonPrimitive(seconds)
        val text = BigDecimal.valueOf(seconds).add(BigDecimal.valueOf(micros, 6)).stripTrailingZeros().toPlainString()
        return JsonUnquotedLiteral(text)
    }

    /** The moment Swift's `Date.distantPast` names: 1 January of year 1. */
    val distantPast: Instant = Instant.ofEpochSecond(-62_135_596_800L)

    /** Runs a read that may throw, as Swift's `try?`: a wrong value becomes null and never costs the rest. */
    inline fun <T> lenient(block: () -> T?): T? = try {
        block()
    } catch (e: JsonShapeException) {
        null
    } catch (e: ArithmeticException) {
        null
    } catch (e: NumberFormatException) {
        null
    } catch (e: IllegalArgumentException) {
        null
    }
}

// MARK: Reading

/** The value under a key, or null when it is missing or JSON null (`decodeIfPresent`). */
fun JsonObject.opt(key: String): JsonElement? = this[key]?.takeUnless { it is JsonNull }

/** The value under a key; missing or null throws (`decode`). */
fun JsonObject.req(key: String): JsonElement = opt(key) ?: throw JsonShapeException("missing $key")

fun JsonElement.asObject(): JsonObject = this as? JsonObject ?: throw JsonShapeException("not an object")

fun JsonElement.asArray(): JsonArray = this as? JsonArray ?: throw JsonShapeException("not an array")

private fun JsonElement.primitive(): JsonPrimitive {
    if (this is JsonNull) throw JsonShapeException("null")
    return this as? JsonPrimitive ?: throw JsonShapeException("not a value")
}

fun JsonElement.asString(): String {
    val p = primitive()
    if (!p.isString) throw JsonShapeException("not a string")
    return p.content
}

private fun JsonElement.asNumber(): BigDecimal {
    val p = primitive()
    if (p.isString) throw JsonShapeException("a string, not a number")
    return p.content.toBigDecimalOrNull() ?: throw JsonShapeException("not a number")
}

/** A whole number (3 and 3.0 read as 3; 3.5 throws, as Swift's decoder does). */
fun JsonElement.asInt(): Int {
    val number = asNumber()
    val whole = number.stripTrailingZeros()
    if (whole.scale() > 0) throw JsonShapeException("not a whole number")
    return try {
        whole.intValueExact()
    } catch (e: ArithmeticException) {
        throw JsonShapeException("out of range")
    }
}

fun JsonElement.asDouble(): Double = asNumber().toDouble()

fun JsonElement.asBool(): Boolean {
    val p = primitive()
    if (p.isString) throw JsonShapeException("a string, not a boolean")
    return when (p.content) {
        "true" -> true
        "false" -> false
        else -> throw JsonShapeException("not a boolean")
    }
}

/** Seconds since 1970, read to the microsecond. */
fun JsonElement.asInstant(): Instant {
    val value = asNumber()
    val floor = value.setScale(0, RoundingMode.FLOOR)
    var micros = value.subtract(floor).movePointRight(6).setScale(0, RoundingMode.HALF_UP).toLong()
    var seconds = try {
        floor.longValueExact()
    } catch (e: ArithmeticException) {
        throw JsonShapeException("date out of range")
    }
    if (micros >= 1_000_000L) {
        seconds += 1
        micros -= 1_000_000L
    }
    return try {
        Instant.ofEpochSecond(seconds, micros * 1000)
    } catch (e: Exception) {
        throw JsonShapeException("date out of range")
    }
}

private val uuidPattern = Regex("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")

/** A UUID string in either case, as Swift's `UUID(uuidString:)` reads it. */
fun parseUuid(text: String): UUID? = if (uuidPattern.matches(text)) UUID.fromString(text) else null

fun JsonElement.asUuid(): UUID = parseUuid(asString()) ?: throw JsonShapeException("not a UUID")
