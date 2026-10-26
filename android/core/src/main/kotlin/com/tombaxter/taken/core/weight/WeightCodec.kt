package com.tombaxter.taken.core.weight

import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.model.JsonShapeException
import com.tombaxter.taken.core.model.TakenJson
import com.tombaxter.taken.core.model.asArray
import com.tombaxter.taken.core.model.asBool
import com.tombaxter.taken.core.model.asDouble
import com.tombaxter.taken.core.model.asInstant
import com.tombaxter.taken.core.model.asInt
import com.tombaxter.taken.core.model.asObject
import com.tombaxter.taken.core.model.asString
import com.tombaxter.taken.core.model.asUuid
import com.tombaxter.taken.core.model.opt
import com.tombaxter.taken.core.model.req
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import java.util.UUID

/**
 * weights.json in the iPhone's exact shape (Shared/WeightData.swift and WeightGoal.swift's Codable, WeightStore.encode and
 * decode; SPEC-ANDROID 5.2): keys sorted, dates as seconds since 1970, optional values left out, a goal's start day as
 * `{"ordinal": n}`. Decoding is as lenient as the iPhone's: every field has a default, an unknown unit or range reads as
 * none, one unreadable weigh-in never costs the rest, and a goal or height that cannot be read is none. Only a file that
 * is not a JSON object is unreadable ([JsonShapeException]), which the store then sets aside.
 */
object WeightCodec {
    const val FILE_NAME = "weights.json"

    fun encode(state: WeightState): String = encodeState(state).toString()

    fun decode(text: String): WeightState = decodeState(TakenJson.parse(text))

    fun encodeState(state: WeightState): JsonObject = TakenJson.obj(
        "schemaVersion" to TakenJson.int(state.schemaVersion),
        "weighIns" to JsonArray(state.weighIns.map(::encodeWeighIn)),
        "showsTab" to state.showsTab?.let(TakenJson::bool),
        "unit" to state.unit?.let { TakenJson.string(it.raw) },
        "range" to state.range?.let { TakenJson.string(it.raw) },
        "offerAnswered" to TakenJson.bool(state.offerAnswered),
        "firstWeighInAt" to state.firstWeighInAt?.let(TakenJson::instant),
        "goal" to state.goal?.let(::encodeGoal),
        "heightCm" to state.heightCm?.let(TakenJson::double),
    )

    fun decodeState(element: JsonElement): WeightState {
        val c = element.asObject()
        val weighIns = TakenJson.lenient { c.opt("weighIns")?.asArray() }
            ?.mapNotNull { TakenJson.lenient { decodeWeighIn(it) } }
            ?.filter { it.kg.isFinite() && it.kg > 0 }
            ?: emptyList()
        return WeightState(
            schemaVersion = TakenJson.lenient { c.opt("schemaVersion")?.asInt() } ?: 1,
            weighIns = weighIns,
            showsTab = TakenJson.lenient { c.opt("showsTab")?.asBool() },
            unit = TakenJson.lenient { c.opt("unit")?.asString() }?.let(WeightUnit::fromRaw),
            range = TakenJson.lenient { c.opt("range")?.asString() }?.let(WeightRange::fromRaw),
            offerAnswered = TakenJson.lenient { c.opt("offerAnswered")?.asBool() } ?: false,
            firstWeighInAt = TakenJson.lenient { c.opt("firstWeighInAt")?.asInstant() },
            // A goal or height that cannot be read is none, so older and newer files still read.
            goal = TakenJson.lenient { c.opt("goal")?.let(::decodeGoal) },
            heightCm = TakenJson.lenient { c.opt("heightCm")?.asDouble() }?.takeIf { it.isFinite() && it > 0 },
        )
    }

    fun encodeWeighIn(weighIn: WeighIn): JsonObject = TakenJson.obj(
        "id" to TakenJson.uuid(weighIn.id),
        "kg" to TakenJson.double(weighIn.kg),
        "weighedAt" to TakenJson.instant(weighIn.weighedAt),
        "utcOffset" to weighIn.utcOffset?.let(TakenJson::int),
    )

    /** A weigh-in needs its weight and its moment; anything else missing has a default. */
    fun decodeWeighIn(element: JsonElement): WeighIn {
        val c = element.asObject()
        return WeighIn(
            kg = c.req("kg").asDouble(),
            weighedAt = c.req("weighedAt").asInstant(),
            id = TakenJson.lenient { c.opt("id")?.asUuid() } ?: UUID.randomUUID(),
            utcOffset = TakenJson.lenient { c.opt("utcOffset")?.asInt() },
        )
    }

    fun encodeGoal(goal: WeightGoal): JsonObject = TakenJson.obj(
        "kg" to TakenJson.double(goal.kg),
        "startDay" to TakenJson.obj("ordinal" to TakenJson.int(goal.startDay.ordinal)),
        "startPicked" to TakenJson.bool(goal.startPicked),
    )

    /** The weight and the start day are required, and the weight must be a weight. */
    fun decodeGoal(element: JsonElement): WeightGoal {
        val c = element.asObject()
        val kg = c.req("kg").asDouble()
        val startDay = DayKey(c.req("startDay").asObject().req("ordinal").asInt())
        val startPicked = TakenJson.lenient { c.opt("startPicked")?.asBool() } ?: false
        if (!kg.isFinite() || kg <= 0) throw JsonShapeException("not a weight")
        return WeightGoal(kg = kg, startDay = startDay, startPicked = startPicked)
    }
}
