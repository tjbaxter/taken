package com.tombaxter.taken.core.pro

import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.model.parseUuid
import java.net.URI
import java.net.URLDecoder
import java.time.Duration
import java.time.Instant
import java.util.UUID

// Taken Pro (PRO.md): the cached status, the ledger, the gate and the link, ported from Shared/Pro.swift. The rule that
// decides Pro is a pure function over plain values (Entitlement.kt), fed with what Google Play Billing says on the phone
// (Play.kt, SPEC-ANDROID 9.4). Founding members and the 1.0 legacy log have no Android meaning and are left out.

/** The three products, with the iPhone's ids (SPEC-ANDROID 9.2). */
enum class ProPlan(val raw: String, val productId: String) {
    YEARLY("yearly", "com.tombaxter.taken.pro.yearly"),
    MONTHLY("monthly", "com.tombaxter.taken.pro.monthly"),
    LIFETIME("lifetime", "com.tombaxter.taken.pro.lifetime");

    val isSubscription: Boolean get() = this != LIFETIME

    /** "Yearly" */
    val title: String get() = raw.replaceFirstChar { it.uppercase() }

    companion object {
        fun fromProductId(id: String): ProPlan? = entries.firstOrNull { it.productId == id }
        fun fromRaw(raw: String): ProPlan? = entries.firstOrNull { it.raw == raw }
    }
}

/** Why someone has Pro, or NONE. `founding` reads from an iPhone file and never applies on Android. */
enum class ProReason(val raw: String) {
    NONE("none"), TRIAL("trial"), YEARLY("yearly"), MONTHLY("monthly"), LIFETIME("lifetime"), FOUNDING("founding");

    companion object {
        fun fromRaw(raw: String): ProReason? = entries.firstOrNull { it.raw == raw }
    }
}

/** The answer, as cached for every surface: `{isPro, reason, checkedAt, expiresAt?}` (PRO.md). */
data class ProStatus(
    val isPro: Boolean,
    val reason: ProReason,
    val checkedAt: Instant,
    /** Subscriptions: the end of the current period (on Android a check horizon, SPEC-ANDROID 9.4). Null means for good. */
    val expiresAt: Instant? = null,
    /** Subscriptions: renews at `expiresAt`. Null when unknown. */
    val willRenew: Boolean? = null,
    val billingIssue: Boolean = false,
    /** Lifetime: a subscription on the same account still renews. */
    val renewingSubscription: Boolean = false,
    val plan: ProPlan? = null,
    val renewsTo: ProPlan? = null,
) {
    /** When cached Pro ends. Null for good. A plan set not to renew, or in a billing issue, ends on time. */
    val activeUntil: Instant?
        get() {
            val end = expiresAt ?: return null
            if (willRenew == false || billingIssue) return end
            return end.plus(renewalMargin)
        }

    /** Cached Pro holds until `activeUntil`, or for good. */
    fun isActive(at: Instant): Boolean {
        if (!isPro) return false
        val until = activeUntil ?: return true
        return at < until
    }

    /** The period has ended and the renewal has not shown yet: still Pro, inside the renewal margin. */
    fun awaitingRenewal(at: Instant): Boolean {
        val end = expiresAt ?: return false
        if (!isPro || end > at || willRenew == false || billingIssue) return false
        return isActive(at)
    }

    /** A plan set to renew whose margin ran out before anyone saw the renewal: the store is asked before anything locks. */
    fun lapsedRenewal(at: Instant): Boolean = isPro && expiresAt != null && willRenew != false && !billingIssue && !isActive(at)

    /** A subscription renews: this plan, or one alongside Pro for good. */
    val renewsASubscription: Boolean get() = renewingSubscription || (isPro && expiresAt != null && willRenew == true)

    /** The same entitlement, whenever it was checked. */
    fun sameEntitlement(other: ProStatus?): Boolean {
        if (other == null) return false
        return isPro == other.isPro && reason == other.reason && expiresAt == other.expiresAt &&
            willRenew == other.willRenew && billingIssue == other.billingIssue &&
            renewingSubscription == other.renewingSubscription && renewsTo == other.renewsTo
    }

    companion object {
        /** How long a plan set to renew stays on past the end of its period (3 days). */
        val renewalMargin: Duration = Duration.ofDays(3)

        fun notPro(checkedAt: Instant): ProStatus = ProStatus(isPro = false, reason = ProReason.NONE, checkedAt = checkedAt)
    }
}

/** A plan's billing period: 1 year, 1 month, 1 week. */
data class PlanPeriod(val value: Int, val unit: PeriodUnit) {
    enum class PeriodUnit(val raw: String) {
        DAY("day"), WEEK("week"), MONTH("month"), YEAR("year");

        companion object {
            fun fromRaw(raw: String): PeriodUnit? = entries.firstOrNull { it.raw == raw }
        }
    }

    /** Days in it, for day and week periods. */
    val days: Int?
        get() = when (unit) {
            PeriodUnit.DAY -> value
            PeriodUnit.WEEK -> value * 7
            PeriodUnit.MONTH, PeriodUnit.YEAR -> null
        }

    /** Months in it, for month and year periods. */
    val months: Int?
        get() = when (unit) {
            PeriodUnit.MONTH -> value
            PeriodUnit.YEAR -> value * 12
            PeriodUnit.DAY, PeriodUnit.WEEK -> null
        }

    val unitWord: String get() = unit.raw

    companion object {
        /** A period is never shorter than one unit, as the iPhone's initialiser clamps it. */
        fun of(value: Int, unit: PeriodUnit): PlanPeriod = PlanPeriod(maxOf(value, 1), unit)
    }
}

/**
 * A plan's recurring price as Play gives it: "$19.99" and 1 year. Cached in pro.json (`ProLedger.prices`) so the trial
 * reminder, which may be planned where Play is not asked (a widget, a receiver), names the real price.
 */
data class PlanPrice(val displayPrice: String, val period: PlanPeriod) {
    companion object
}

/** The trial reminder handed to the system: for which trial end, and when it fires. */
data class TrialReminderMark(val trialEnd: Instant, val fireAt: Instant)

/** A dose log a widget, the tile or a nudge could not make without Pro. */
sealed class ProPendingAction {
    data object TakeAll : ProPendingAction()
    data class Log(val itemId: UUID) : ProPendingAction()
}

data class PendingLog(val action: ProPendingAction, val at: Instant)

/** What the app last learned about Pro: pro.json. Erase all data never touches it. */
data class ProLedger(
    val status: ProStatus? = null,
    val firstSeenAt: Instant,
    /** Always false on Android: there are no Android 1.0 users (SPEC-ANDROID 5.2). Kept so iPhone files read. */
    val legacyLog: Boolean = false,
    /** The first dose ever logged, from any surface. From then on the first session is over for good. */
    val firstDoseAt: Instant? = null,
    val introShownAt: Instant? = null,
    val pending: PendingLog? = null,
    val prices: Map<String, PlanPrice> = emptyMap(),
    val trialAskAt: Instant? = null,
    val trialReminder: TrialReminderMark? = null,
    /** Android only: a trial's end by the purchase time it began at, known on the phone that bought it (SPEC-ANDROID 9.4). */
    val trialEnds: Map<String, Instant> = emptyMap(),
) {
    /**
     * The price the cached subscription renews at, if Play has given it: the plan it renews to when Play named one
     * (`ProStatus.renewsTo`), else its own plan.
     */
    val renewalPrice: PlanPrice?
        get() {
            val plan = status?.renewsTo ?: status?.plan ?: return null
            if (!plan.isSubscription) return null
            return prices[plan.productId]
        }
}

/** The ledger's small writes, as pure rules. */
object ProLedgers {
    /**
     * A dose was logged: the first one ever ends the first session for good. Written once; a ledger the app has not
     * created yet is left alone.
     */
    fun noteFirstDose(ledger: ProLedger?, at: Instant): ProLedger? {
        if (ledger == null || ledger.firstDoseAt != null) return ledger
        return ledger.copy(firstDoseAt = at)
    }

    /** Remember a refused log so the app can offer it when it opens. */
    fun recordPending(ledger: ProLedger?, action: ProPendingAction, at: Instant): ProLedger? =
        ledger?.copy(pending = PendingLog(action, at))

    /**
     * The refused log, if one was asked for recently (within `maxAge`, and not more than a minute ahead of `now`), and
     * the ledger without it: a pending log is offered once, whatever its age (the iPhone's `ProStore.takePendingLog`).
     */
    fun takePending(ledger: ProLedger?, maxAge: Duration, now: Instant): Pair<ProLedger?, PendingLog?> {
        val pending = ledger?.pending ?: return ledger to null
        val age = Duration.between(pending.at, now)
        val fresh = age > Duration.ofSeconds(-60) && age <= maxAge
        return ledger.copy(pending = null) to (if (fresh) pending else null)
    }

    /** The one automatic paywall after the first dose has been shown. Written once. */
    fun markIntroShown(ledger: ProLedger?, at: Instant): ProLedger? =
        if (ledger == null || ledger.introShownAt != null) ledger else ledger.copy(introShownAt = at)

    /** The one notification ask after a trial started has been on screen. Written once. */
    fun markTrialAskShown(ledger: ProLedger?, at: Instant): ProLedger? =
        if (ledger == null || ledger.trialAskAt != null) ledger else ledger.copy(trialAskAt = at)

    /** Play's latest answer, kept for every surface. */
    fun withStatus(ledger: ProLedger?, status: ProStatus): ProLedger? = ledger?.copy(status = status)

    /** Each subscription's price as Play last gave it, merged over the earlier ones, so the trial reminder names it. */
    fun cachePrices(ledger: ProLedger?, prices: Map<String, PlanPrice>): ProLedger? {
        if (ledger == null || prices.isEmpty()) return ledger
        val merged = ledger.prices + prices
        return if (merged == ledger.prices) ledger else ledger.copy(prices = merged)
    }

    /** A trial started through the paywall: its end, by the purchase time it began at (SPEC-ANDROID 9.4). */
    fun recordTrialEnd(ledger: ProLedger?, purchaseTime: Instant, end: Instant): ProLedger? {
        if (ledger == null) return null
        val key = PlayEntitlement.trialKey(purchaseTime)
        if (ledger.trialEnds[key] == end) return ledger
        return ledger.copy(trialEnds = ledger.trialEnds + (key to end))
    }

    /** What the trial reminder last handed to the system (`TrialReminder.nextMark`). */
    fun withTrialReminder(ledger: ProLedger?, mark: TrialReminderMark?): ProLedger? =
        if (ledger == null || ledger.trialReminder == mark) ledger else ledger.copy(trialReminder = mark)
}

/** Whether a dose may be logged right now. */
enum class ProAccess {
    /** Pro is active. */
    PRO,
    /** Nothing has been logged yet: the first dose needs no Pro. */
    FIRST_SESSION,
    /** An iPhone 1.0 log the store has not answered for: never on Android. */
    PENDING,
    /** The app is still waiting for the store's first answer of this launch. */
    CHECKING,
    /** Logging needs Pro. */
    LOCKED;

    val allowsLogging: Boolean get() = this == PRO || this == FIRST_SESSION || this == PENDING
}

/** How far ahead the nudge may be scheduled. */
sealed class NudgeWindow {
    data object Open : NudgeWindow()
    /** A subscription set not to renew: nudges stop when it ends. */
    data class Until(val end: Instant) : NudgeWindow()
    /** Locked: no nudges. */
    data object Closed : NudgeWindow()
}

object ProGate {
    /** The one rule for every surface. `settled` is false only in the app before the store's first answer. */
    fun access(status: ProStatus?, settled: Boolean, legacyLog: Boolean, hasLogged: Boolean, now: Instant): ProAccess {
        if (status != null && status.isActive(now)) return ProAccess.PRO
        if (!hasLogged) return ProAccess.FIRST_SESSION
        if (status == null && legacyLog) return ProAccess.PENDING
        if (!settled) return ProAccess.CHECKING
        return ProAccess.LOCKED
    }

    /** Whether anything was ever logged: a dose in the log now, or the first dose the ledger remembers. */
    fun hasLogged(state: StackState, ledger: ProLedger?): Boolean = state.doses.isNotEmpty() || ledger?.firstDoseAt != null

    /**
     * Widgets, the tile and the nudge read the ledger the app wrote. On Android a missing ledger reads as not legacy, the
     * opposite of the iPhone's default (SPEC-ANDROID 5.2): there is no 1.0 log to protect.
     */
    fun access(ledger: ProLedger?, state: StackState, now: Instant): ProAccess = access(
        status = ledger?.status, settled = true, legacyLog = ledger?.legacyLog ?: false,
        hasLogged = hasLogged(state, ledger), now = now,
    )

    fun nudgeWindow(access: ProAccess, status: ProStatus?): NudgeWindow {
        if (!access.allowsLogging) return NudgeWindow.Closed
        val end = status?.activeUntil
        if (access == ProAccess.PRO && status != null && status.willRenew == false && end != null) return NudgeWindow.Until(end)
        return NudgeWindow.Open
    }
}

/**
 * `taken://pro`, optionally with the log a locked widget tap asked for: `taken://pro?then=take-all`,
 * `taken://pro?then=log&item=<uuid>`.
 */
data class ProRoute(val then: ProPendingAction? = null) {
    val url: String
        get() = when (val action = then) {
            null -> "$SCHEME://$HOST"
            ProPendingAction.TakeAll -> "$SCHEME://$HOST?then=take-all"
            is ProPendingAction.Log -> "$SCHEME://$HOST?then=log&item=${action.itemId.toString().uppercase()}"
        }

    companion object {
        const val SCHEME = "taken"
        const val HOST = "pro"

        fun parse(url: String): ProRoute? {
            val uri = try {
                URI(url)
            } catch (e: Exception) {
                return null
            }
            if (uri.scheme != SCHEME || uri.host != HOST) return null
            val items = (uri.rawQuery ?: "").split("&").filter { it.isNotEmpty() }.map { part ->
                val pieces = part.split("=", limit = 2)
                URLDecoder.decode(pieces[0], "UTF-8") to URLDecoder.decode(pieces.getOrElse(1) { "" }, "UTF-8")
            }
            fun value(name: String): String? = items.firstOrNull { it.first == name }?.second
            val then = when (value("then")) {
                "take-all" -> ProPendingAction.TakeAll
                "log" -> value("item")?.let { parseUuid(it) }?.let { ProPendingAction.Log(it) }
                else -> null
            }
            return ProRoute(then)
        }
    }
}

/** An introductory offer's terms, as the store gives them. */
data class IntroTerms(val mode: Mode, val period: PlanPeriod, val periodCount: Int, val displayPrice: String) {
    enum class Mode { ON_US, PAY_AS_YOU_GO, PAY_UP_FRONT }
}
