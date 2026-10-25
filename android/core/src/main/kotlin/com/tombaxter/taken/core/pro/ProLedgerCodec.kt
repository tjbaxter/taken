package com.tombaxter.taken.core.pro

import com.tombaxter.taken.core.model.JsonShapeException
import com.tombaxter.taken.core.model.TakenJson
import com.tombaxter.taken.core.model.asBool
import com.tombaxter.taken.core.model.asInstant
import com.tombaxter.taken.core.model.asInt
import com.tombaxter.taken.core.model.asObject
import com.tombaxter.taken.core.model.asString
import com.tombaxter.taken.core.model.asUuid
import com.tombaxter.taken.core.model.opt
import com.tombaxter.taken.core.model.req
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject

/**
 * pro.json in the iPhone's shape (Shared/Pro.swift `ProLedger` and `ProStatus` Codable), plus Android's `trialEnds`
 * (SPEC-ANDROID 5.2), which the iPhone ignores as an unknown key.
 */
object ProLedgerCodec {
    fun encode(ledger: ProLedger): String = encodeLedger(ledger).toString()

    fun decode(text: String): ProLedger = decodeLedger(TakenJson.parse(text))

    fun encodeLedger(ledger: ProLedger): JsonObject = TakenJson.obj(
        "status" to ledger.status?.let(::encodeStatus),
        "firstSeenAt" to TakenJson.instant(ledger.firstSeenAt),
        "legacyLog" to TakenJson.bool(ledger.legacyLog),
        "firstDoseAt" to ledger.firstDoseAt?.let(TakenJson::instant),
        "introShownAt" to ledger.introShownAt?.let(TakenJson::instant),
        "pending" to ledger.pending?.let(::encodePending),
        "prices" to TakenJson.obj(ledger.prices.mapValues { encodePrice(it.value) }),
        "trialAskAt" to ledger.trialAskAt?.let(TakenJson::instant),
        "trialReminder" to ledger.trialReminder?.let {
            TakenJson.obj("trialEnd" to TakenJson.instant(it.trialEnd), "fireAt" to TakenJson.instant(it.fireAt))
        },
        "trialEnds" to if (ledger.trialEnds.isEmpty()) null else TakenJson.obj(ledger.trialEnds.mapValues { TakenJson.instant(it.value) }),
    )

    fun decodeLedger(element: JsonElement): ProLedger {
        val c = element.asObject()
        return ProLedger(
            status = TakenJson.lenient { c.opt("status")?.let(::decodeStatus) },
            firstSeenAt = c.opt("firstSeenAt")?.asInstant() ?: TakenJson.distantPast,
            legacyLog = c.opt("legacyLog")?.asBool() ?: false,
            firstDoseAt = TakenJson.lenient { c.opt("firstDoseAt")?.asInstant() },
            introShownAt = c.opt("introShownAt")?.asInstant(),
            pending = TakenJson.lenient { c.opt("pending")?.let(::decodePending) },
            prices = TakenJson.lenient {
                c.opt("prices")?.asObject()?.mapValues { decodePrice(it.value) }
            } ?: emptyMap(),
            trialAskAt = TakenJson.lenient { c.opt("trialAskAt")?.asInstant() },
            trialReminder = TakenJson.lenient {
                c.opt("trialReminder")?.asObject()?.let {
                    TrialReminderMark(trialEnd = it.req("trialEnd").asInstant(), fireAt = it.req("fireAt").asInstant())
                }
            },
            trialEnds = TakenJson.lenient { c.opt("trialEnds")?.asObject()?.mapValues { it.value.asInstant() } } ?: emptyMap(),
        )
    }

    fun encodeStatus(status: ProStatus): JsonObject = TakenJson.obj(
        "isPro" to TakenJson.bool(status.isPro),
        "reason" to TakenJson.string(status.reason.raw),
        "checkedAt" to TakenJson.instant(status.checkedAt),
        "expiresAt" to status.expiresAt?.let(TakenJson::instant),
        "willRenew" to status.willRenew?.let(TakenJson::bool),
        "billingIssue" to TakenJson.bool(status.billingIssue),
        "renewingSubscription" to TakenJson.bool(status.renewingSubscription),
        "plan" to status.plan?.let { TakenJson.string(it.raw) },
        "renewsTo" to status.renewsTo?.let { TakenJson.string(it.raw) },
    )

    fun decodeStatus(element: JsonElement): ProStatus {
        val c = element.asObject()
        return ProStatus(
            isPro = c.opt("isPro")?.asBool() ?: false,
            // A reason from a later version reads as none and never costs the rest of the status.
            reason = TakenJson.lenient { c.opt("reason")?.asString()?.let { ProReason.fromRaw(it) } } ?: ProReason.NONE,
            checkedAt = c.opt("checkedAt")?.asInstant() ?: TakenJson.distantPast,
            expiresAt = c.opt("expiresAt")?.asInstant(),
            willRenew = c.opt("willRenew")?.asBool(),
            billingIssue = c.opt("billingIssue")?.asBool() ?: false,
            renewingSubscription = c.opt("renewingSubscription")?.asBool() ?: false,
            plan = TakenJson.lenient { c.opt("plan")?.asString()?.let { ProPlan.fromRaw(it) } },
            renewsTo = TakenJson.lenient { c.opt("renewsTo")?.asString()?.let { ProPlan.fromRaw(it) } },
        )
    }

    /** Swift's synthesized enum coding: `{"takeAll":{}}` or `{"log":{"_0":"<UUID>"}}`. */
    fun encodePending(pending: PendingLog): JsonObject {
        val action = when (val a = pending.action) {
            ProPendingAction.TakeAll -> TakenJson.obj("takeAll" to TakenJson.obj())
            is ProPendingAction.Log -> TakenJson.obj("log" to TakenJson.obj("_0" to TakenJson.uuid(a.itemId)))
        }
        return TakenJson.obj("action" to action, "at" to TakenJson.instant(pending.at))
    }

    fun decodePending(element: JsonElement): PendingLog {
        val c = element.asObject()
        val action = c.req("action").asObject()
        if (action.size != 1) throw JsonShapeException("an action has one case")
        val decoded = when {
            action.containsKey("takeAll") -> ProPendingAction.TakeAll
            action.containsKey("log") -> ProPendingAction.Log(action.req("log").asObject().req("_0").asUuid())
            else -> throw JsonShapeException("unknown action")
        }
        return PendingLog(action = decoded, at = c.req("at").asInstant())
    }

    fun encodePrice(price: PlanPrice): JsonObject = TakenJson.obj(
        "displayPrice" to TakenJson.string(price.displayPrice),
        "period" to TakenJson.obj("value" to TakenJson.int(price.period.value), "unit" to TakenJson.string(price.period.unit.raw)),
    )

    fun decodePrice(element: JsonElement): PlanPrice {
        val c = element.asObject()
        val period = c.req("period").asObject()
        val unit = PlanPeriod.PeriodUnit.fromRaw(period.req("unit").asString()) ?: throw JsonShapeException("unknown unit")
        return PlanPrice(
            displayPrice = c.req("displayPrice").asString(),
            period = PlanPeriod(value = maxOf(period.req("value").asInt(), 1), unit = unit),
        )
    }
}
