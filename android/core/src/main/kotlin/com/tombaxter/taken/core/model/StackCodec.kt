package com.tombaxter.taken.core.model

import com.tombaxter.taken.core.theme.ThemeID
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/**
 * taken.json in the iPhone's exact shape (Shared/Model.swift's Codable, TakenStore.encode and decode). Decoding is as
 * lenient as the iPhone's: a bad optional setting becomes its default and never costs the file; a required item or dose
 * field that is missing or of the wrong type makes the whole file unreadable ([JsonShapeException]).
 */
object StackCodec {

    fun encode(state: StackState): String = encodeState(state).toString()

    fun decode(text: String): StackState = decodeState(TakenJson.parse(text))

    fun encodeState(state: StackState): JsonObject = TakenJson.obj(
        "schemaVersion" to TakenJson.int(state.schemaVersion),
        "items" to JsonArray(state.items.map(::encodeItem)),
        "doses" to JsonArray(state.doses.map(::encodeDose)),
        "settings" to encodeSettings(state.settings),
    )

    fun decodeState(element: JsonElement): StackState {
        val c = element.asObject()
        return StackState(
            schemaVersion = c.opt("schemaVersion")?.asInt() ?: 1,
            items = c.opt("items")?.asArray()?.map(::decodeItem) ?: emptyList(),
            doses = c.opt("doses")?.asArray()?.map(::decodeDose) ?: emptyList(),
            settings = c.opt("settings")?.let(::decodeSettings) ?: StackSettings(),
        )
    }

    // MARK: Frequency

    fun encodeFrequency(frequency: Frequency): JsonObject = when (frequency) {
        is Frequency.Daily -> TakenJson.obj("kind" to TakenJson.string("daily"), "times" to TakenJson.int(frequency.times))
        Frequency.AlternateDays -> TakenJson.obj("kind" to TakenJson.string("alt"))
        is Frequency.Weekdays -> TakenJson.obj(
            "kind" to TakenJson.string("weekdays"),
            "days" to JsonArray(frequency.days.sorted().map(TakenJson::int)),
        )
    }

    fun decodeFrequency(element: JsonElement): Frequency {
        val c = element.asObject()
        return when (c.opt("kind")?.asString() ?: "daily") {
            "alt" -> Frequency.AlternateDays
            "weekdays" -> {
                val days = c.opt("days")?.asArray()?.map { it.asInt() } ?: emptyList()
                Frequency.Weekdays(days.filter { it in 1..7 }.toSet())
            }
            else -> {
                val times = c.opt("times")?.asInt() ?: 1
                Frequency.Daily(times.coerceIn(1, 3))
            }
        }
    }

    // MARK: Item and dose

    fun encodeItem(item: Item): JsonObject = TakenJson.obj(
        "id" to TakenJson.uuid(item.id),
        "name" to TakenJson.string(item.name),
        "code" to TakenJson.string(item.code),
        "frequency" to encodeFrequency(item.frequency),
        "createdAt" to TakenJson.instant(item.createdAt),
        "archived" to TakenJson.bool(item.archived),
        "archivedAt" to item.archivedAt?.let(TakenJson::instant),
        "sortIndex" to TakenJson.int(item.sortIndex),
        "pastFrequencies" to item.pastFrequencies?.let { list ->
            JsonArray(list.map {
                TakenJson.obj("until" to TakenJson.instant(it.until), "frequency" to encodeFrequency(it.frequency))
            })
        },
        "pauses" to item.pauses?.let { list ->
            JsonArray(list.map { TakenJson.obj("from" to TakenJson.instant(it.from), "until" to TakenJson.instant(it.until)) })
        },
    )

    fun decodeItem(element: JsonElement): Item {
        val c = element.asObject()
        return Item(
            id = c.req("id").asUuid(),
            name = c.req("name").asString(),
            code = c.req("code").asString(),
            frequency = decodeFrequency(c.req("frequency")),
            createdAt = c.req("createdAt").asInstant(),
            archived = c.req("archived").asBool(),
            archivedAt = c.opt("archivedAt")?.asInstant(),
            sortIndex = c.req("sortIndex").asInt(),
            pastFrequencies = c.opt("pastFrequencies")?.asArray()?.map {
                val era = it.asObject()
                FrequencyEra(until = era.req("until").asInstant(), frequency = decodeFrequency(era.req("frequency")))
            },
            pauses = c.opt("pauses")?.asArray()?.map {
                val pause = it.asObject()
                Pause(from = pause.req("from").asInstant(), until = pause.req("until").asInstant())
            },
        )
    }

    fun encodeDose(dose: Dose): JsonObject = TakenJson.obj(
        "id" to TakenJson.uuid(dose.id),
        "itemId" to TakenJson.uuid(dose.itemId),
        "takenAt" to TakenJson.instant(dose.takenAt),
        "utcOffset" to dose.utcOffset?.let(TakenJson::int),
    )

    fun decodeDose(element: JsonElement): Dose {
        val c = element.asObject()
        return Dose(
            id = c.req("id").asUuid(),
            itemId = c.req("itemId").asUuid(),
            takenAt = c.req("takenAt").asInstant(),
            utcOffset = c.opt("utcOffset")?.asInt(),
        )
    }

    // MARK: Settings

    fun encodeSettings(settings: StackSettings): JsonObject = TakenJson.obj(
        "wakeMinutes" to TakenJson.int(settings.wakeMinutes),
        // Written too, so an earlier build reading this file rolls the day over at the same hour.
        "dayStartHour" to TakenJson.int(settings.dayStartHour),
        "reminderEnabled" to TakenJson.bool(settings.reminderEnabled),
        "reminderMinutes" to settings.chosenReminderMinutes?.let(TakenJson::int),
        "hapticsEnabled" to TakenJson.bool(settings.hapticsEnabled),
        "theme" to TakenJson.string(settings.theme.raw),
        // Written only once set, so a file that never showed a one-time row looks as it did.
        "nudgeOfferDone" to if (settings.nudgeOfferDone) TakenJson.bool(true) else null,
        "widgetInviteDay" to settings.widgetInviteDay?.let(TakenJson::int),
        "widgetInviteDone" to if (settings.widgetInviteDone) TakenJson.bool(true) else null,
        "repairClosedDay" to settings.repairClosedDay?.let(TakenJson::int),
        // Written only once turned off.
        "trialReminderEnabled" to if (!settings.trialReminderEnabled) TakenJson.bool(false) else null,
    )

    fun decodeSettings(element: JsonElement): StackSettings {
        val c = element.asObject()
        val wake = TakenJson.lenient { c.opt("wakeMinutes")?.asInt() }
        val wakeMinutes = when {
            wake != null -> StackSettings.clampMinutes(wake)
            else -> {
                // A file from before the wake-up time: the same rollover, as a wake-up time.
                val hour = TakenJson.lenient { c.opt("dayStartHour")?.asInt() }
                if (hour != null) StackSettings.wakeMinutes(forDayStartHour = hour) else StackSettings.DEFAULT_WAKE_MINUTES
            }
        }
        return StackSettings(
            wakeMinutes = wakeMinutes,
            reminderEnabled = c.opt("reminderEnabled")?.asBool() ?: false,
            chosenReminderMinutes = TakenJson.lenient { c.opt("reminderMinutes")?.asInt() },
            hapticsEnabled = c.opt("hapticsEnabled")?.asBool() ?: true,
            // A look this version does not know (or a malformed one) reads as Signal and never costs the file.
            theme = ThemeID.stored(TakenJson.lenient { c.opt("theme")?.asString() }),
            nudgeOfferDone = TakenJson.lenient { c.opt("nudgeOfferDone")?.asBool() } ?: false,
            widgetInviteDay = TakenJson.lenient { c.opt("widgetInviteDay")?.asInt() },
            widgetInviteDone = TakenJson.lenient { c.opt("widgetInviteDone")?.asBool() } ?: false,
            repairClosedDay = TakenJson.lenient { c.opt("repairClosedDay")?.asInt() },
            trialReminderEnabled = TakenJson.lenient { c.opt("trialReminderEnabled")?.asBool() } ?: true,
        )
    }
}
