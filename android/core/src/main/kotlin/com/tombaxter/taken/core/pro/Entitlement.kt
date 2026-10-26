package com.tombaxter.taken.core.pro

import java.time.Instant

// The money rule (PRO.md), ported line for line from Shared/Pro.swift's `PurchaseFact` and `Entitlement`. Founding members
// and the app transaction have no Android meaning and are left out (SPEC-ANDROID 9.4). On Android the facts come from
// Google Play Billing's `queryPurchasesAsync` on the phone, through `PlayEntitlement.facts` (Play.kt).

/** One purchase as the entitlement rule sees it. */
data class PurchaseFact(
    val productId: String,
    /** Play says it is paid for (`PurchaseState.PURCHASED`). A pending purchase grants nothing. */
    val verified: Boolean = true,
    /** Set when the purchase was refunded or revoked. On Play a revoked purchase is simply no longer returned. */
    val revokedAt: Instant? = null,
    /** Subscriptions: until when this fact grants Pro (on Android a check horizon or a known trial end, SPEC-ANDROID 9.4). */
    val expiresAt: Instant? = null,
    /** Subscriptions: a billing grace period holds access open until this moment (never known on an Android phone). */
    val graceUntil: Instant? = null,
    /** The current period is the introductory offer: a trial known on this phone. */
    val isIntroOffer: Boolean = false,
    /** Subscriptions: whether it renews (Play's `isAutoRenewing`). Null when unknown. */
    val willRenew: Boolean? = null,
    /** Subscriptions: a renewal payment failed and is being retried (never known on an Android phone). */
    val inBillingRetry: Boolean = false,
    /** Replaced by another plan. */
    val isUpgraded: Boolean = false,
    /** Subscriptions: the product that renews next, when a change of plan waits for the renewal. */
    val renewsTo: String? = null,
) {
    /** Counts at all: paid for, never refunded or revoked, and not replaced. */
    val isValid: Boolean get() = verified && revokedAt == null && !isUpgraded

    val isSubscription: Boolean get() = ProPlan.fromProductId(productId)?.isSubscription == true

    /** Set to renew as far as the store knows: not cancelled, and no failed payment being retried or held in grace. */
    val renews: Boolean get() = willRenew != false && !inBillingRetry && graceUntil == null

    /**
     * Subscriptions: when access ends. A billing grace period holds it open to `graceUntil`. A plan set to renew holds it
     * `ProStatus.renewalMargin` past `expiresAt`. Null when it grants nothing at `now`.
     */
    fun accessEnds(after: Instant): Instant? {
        var end: Instant? = null
        val expires = expiresAt
        if (expires != null) {
            val until = if (renews) expires.plus(ProStatus.renewalMargin) else expires
            if (until > after) end = until
        }
        val grace = graceUntil
        if (grace != null && grace > after && grace > (end ?: Instant.MIN)) end = grace
        return end
    }
}

/** The entitlement rule (PRO.md): Pro when a live subscription or the lifetime purchase says so. */
object Entitlement {
    fun evaluate(purchases: List<PurchaseFact>, now: Instant): ProStatus {
        val valid = purchases.filter { it.isValid }
        // A subscription that still renews next to Pro for good: Profile offers to cancel it.
        val renewing = valid.any { it.isSubscription && it.willRenew == true && it.accessEnds(now) != null }
        // For good beats for now, so the cache never expires for someone who owns Pro outright.
        if (valid.any { it.productId == ProPlan.LIFETIME.productId }) {
            return ProStatus(isPro = true, reason = ProReason.LIFETIME, checkedAt = now, renewingSubscription = renewing)
        }
        var bestFact: PurchaseFact? = null
        var bestPlan: ProPlan? = null
        var bestUntil: Instant? = null
        for (fact in valid) {
            val plan = ProPlan.fromProductId(fact.productId) ?: continue
            if (!plan.isSubscription) continue
            val until = fact.accessEnds(now) ?: continue
            val current = bestUntil
            if (current != null && current >= until) continue
            bestFact = fact
            bestPlan = plan
            bestUntil = until
        }
        val fact = bestFact ?: return ProStatus.notPro(now)
        val plan = bestPlan ?: return ProStatus.notPro(now)
        val reason = when {
            fact.isIntroOffer -> ProReason.TRIAL
            plan == ProPlan.YEARLY -> ProReason.YEARLY
            else -> ProReason.MONTHLY
        }
        // In a billing grace period the cache holds to the grace end. Otherwise it keeps the period end, and ProStatus adds
        // the renewal margin to a plan set to renew.
        val pastEnd = fact.expiresAt?.let { it <= now } ?: true
        val inGrace = pastEnd && (fact.graceUntil?.let { it > now } ?: false)
        val renewsTo = fact.renewsTo?.let { ProPlan.fromProductId(it) }?.takeIf { it.isSubscription }
        return ProStatus(
            isPro = true, reason = reason, checkedAt = now,
            expiresAt = if (inGrace) fact.graceUntil else fact.expiresAt,
            willRenew = fact.willRenew, billingIssue = inGrace || fact.inBillingRetry,
            plan = plan, renewsTo = renewsTo,
        )
    }

    /**
     * What to keep after asking Play: `fresh` is what it said, `answered` whether Play answered both of Taken's questions
     * (subscriptions and one-time products) with OK. Where the iPhone needs a verified app transaction before a no counts,
     * Android needs Play's own answer: offline or with Play unavailable, finding nothing proves nothing, so what was known
     * stands. A purchase found always counts.
     */
    fun next(previous: ProStatus?, fresh: ProStatus, answered: Boolean): ProStatus? {
        if (answered) return fresh
        if (fresh.isPro) return fresh
        return previous
    }
}
