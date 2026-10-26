package com.tombaxter.taken.core.pro

import java.math.BigDecimal
import java.time.Duration
import java.time.Instant
import java.time.ZoneOffset
import java.util.Locale

// What Google Play Billing tells the phone, as plain values, and the rules that turn it into Taken Pro (SPEC-ANDROID 9).
// The app's billing layer copies Play's `Purchase` and `ProductDetails` into these types, so every rule here is unit
// tested without Play, and a fake billing client can drive the app through every state.
//
// What the phone can know (Google's references, October 2026):
// - A `Purchase` gives its product ids, state (PURCHASED or PENDING), purchase time ("For subscriptions, this is the
//   subscription signup time. It won't change after renewal"), token, `isAcknowledged`, `isAutoRenewing` and, for a change
//   of plan waiting for the renewal, a `PendingPurchaseUpdate` with the new product ids. It has no base plan, offer, expiry
//   or trial phase (https://developer.android.com/reference/com/android/billingclient/api/Purchase); those live only in
//   the Play Developer API's `purchases.subscriptionsv2` (https://developer.android.com/google/play/billing/lifecycle/subscriptions).
// - `queryPurchasesAsync` returns active subscriptions and owned one-time products: a cancelled subscription "is still
//   returned" until it expires, one in grace period is returned, one on hold or paused is not (same lifecycle page); a
//   refunded and revoked purchase is no longer owned.
// - `queryProductDetailsAsync` returns "a maximum of 50 user eligible offers per subscription", so an offer that comes
//   back is one this person can have (https://developer.android.com/google/play/billing/integrate).

/** Google Play's answer to a call, as `BillingClient.BillingResponseCode` names it. */
enum class PlayResponse {
    OK, USER_CANCELED, SERVICE_UNAVAILABLE, BILLING_UNAVAILABLE, ITEM_UNAVAILABLE, DEVELOPER_ERROR, ERROR,
    ITEM_ALREADY_OWNED, ITEM_NOT_OWNED, NETWORK_ERROR, SERVICE_DISCONNECTED, FEATURE_NOT_SUPPORTED, SERVICE_TIMEOUT;

    /**
     * Worth asking again by itself: Google's errors page marks SERVICE_UNAVAILABLE, SERVICE_DISCONNECTED, ERROR,
     * NETWORK_ERROR and SERVICE_TIMEOUT retriable, and BILLING_UNAVAILABLE as needing the person to act first
     * (https://developer.android.com/google/play/billing/errors).
     */
    val retriable: Boolean
        get() = this == SERVICE_UNAVAILABLE || this == SERVICE_DISCONNECTED || this == ERROR || this == NETWORK_ERROR ||
            this == SERVICE_TIMEOUT
}

/** An answer with its value: the value is meaningful only when `response` is OK. */
data class PlayAnswer<T>(val response: PlayResponse, val value: T)

/** One `Purchase` as Taken reads it. */
data class PlayPurchase(
    val productIds: List<String>,
    val state: State,
    /** For subscriptions, the signup time, which never changes after a renewal. */
    val purchaseTime: Instant,
    val token: String,
    val acknowledged: Boolean,
    val autoRenewing: Boolean,
    /** A change of plan waiting for the renewal: the product ids it changes to (`PendingPurchaseUpdate.getProducts`). */
    val pendingUpdateProductIds: List<String> = emptyList(),
) {
    enum class State { PURCHASED, PENDING, UNSPECIFIED }

    /** One of Taken's three products. */
    val plan: ProPlan? get() = productIds.firstNotNullOfOrNull { ProPlan.fromProductId(it) }
}

/** One pricing phase of a subscription offer (`ProductDetails.PricingPhase`). */
data class PlayPhase(
    val formattedPrice: String,
    val priceMicros: Long,
    val currencyCode: String,
    /** ISO 8601: "P1Y", "P1M", "P1W", "P7D". */
    val billingPeriod: String,
    val cycleCount: Int,
    val recurrence: Recurrence,
) {
    enum class Recurrence { INFINITE, FINITE, NON_RECURRING }
}

/** One subscription offer (`ProductDetails.SubscriptionOfferDetails`): the base plan itself has no offer id. */
data class PlaySubscriptionOffer(
    val basePlanId: String,
    val offerId: String?,
    val offerToken: String,
    val phases: List<PlayPhase>,
    val tags: List<String> = emptyList(),
)

/** One purchase option or offer of a one-time product (`ProductDetails.OneTimePurchaseOfferDetails`). */
data class PlayOneTimeOffer(
    val formattedPrice: String,
    val priceMicros: Long,
    val currencyCode: String,
    val offerToken: String,
    val purchaseOptionId: String? = null,
    val offerId: String? = null,
)

/** One product as `queryProductDetailsAsync` returned it. */
data class PlayProduct(
    val productId: String,
    val subscriptionOffers: List<PlaySubscriptionOffer> = emptyList(),
    val oneTimeOffers: List<PlayOneTimeOffer> = emptyList(),
)

/** A plan Taken can sell: the paywall's words and what to hand Play's purchase flow. */
data class PlayPlan(
    val offer: PlanOffer,
    val productId: String,
    /** The offer token for the purchase flow: the trial offer for someone Play offers it to, else the base plan's. */
    val offerToken: String,
    /** The trial this token starts, if it is one, so its end can be kept on this phone (SPEC-ANDROID 9.4). */
    val trial: IntroTerms?,
)

/** From Play's product details to the paywall's plans. */
object PlayCatalog {
    /** The base plans and purchase option Taken creates in Play Console (SPEC-ANDROID 9.2). */
    fun basePlanId(plan: ProPlan): String = plan.raw

    /** An ISO 8601 billing period ("P1Y", "P1M", "P2W", "P7D") as a plan period. Null for any other shape. */
    fun period(iso: String): PlanPeriod? {
        val match = Regex("^P(\\d+)([YMWD])$").matchEntire(iso.trim().uppercase(Locale.ROOT)) ?: return null
        val value = match.groupValues[1].toIntOrNull() ?: return null
        val unit = when (match.groupValues[2]) {
            "Y" -> PlanPeriod.PeriodUnit.YEAR
            "M" -> PlanPeriod.PeriodUnit.MONTH
            "W" -> PlanPeriod.PeriodUnit.WEEK
            else -> PlanPeriod.PeriodUnit.DAY
        }
        return PlanPeriod.of(value, unit)
    }

    /** The introductory terms an offer's first phase gives, when the offer has more than its recurring phase. */
    fun intro(offer: PlaySubscriptionOffer): IntroTerms? {
        if (offer.offerId == null || offer.phases.size < 2) return null
        val first = offer.phases.first()
        val period = period(first.billingPeriod) ?: return null
        val count = maxOf(first.cycleCount, 1)
        return when {
            first.priceMicros == 0L -> IntroTerms(IntroTerms.Mode.ON_US, period, count, first.formattedPrice)
            first.recurrence == PlayPhase.Recurrence.NON_RECURRING ->
                IntroTerms(IntroTerms.Mode.PAY_UP_FRONT, period, 1, first.formattedPrice)
            else -> IntroTerms(IntroTerms.Mode.PAY_AS_YOU_GO, period, count, first.formattedPrice)
        }
    }

    private fun price(micros: Long): BigDecimal = BigDecimal.valueOf(micros).movePointLeft(6)

    /**
     * A product as a plan, or null when Play returned nothing Taken can sell. A subscription takes its price and period
     * from its base plan's recurring phase (the offer with no offer id), and buys with the offer that costs nothing at
     * first while Play returns one (Play returns only offers this person is eligible for), else with the base plan. The
     * lifetime takes its `lifetime` purchase option, else the first one.
     */
    fun plan(product: PlayProduct, locale: Locale = Locale.getDefault()): PlayPlan? {
        val plan = ProPlan.fromProductId(product.productId) ?: return null
        if (!plan.isSubscription) {
            val option = product.oneTimeOffers.firstOrNull { it.purchaseOptionId == basePlanId(plan) && it.offerId == null }
                ?: product.oneTimeOffers.firstOrNull { it.offerId == null }
                ?: product.oneTimeOffers.firstOrNull()
                ?: return null
            val offer = PlanOffer(
                plan = plan, displayPrice = option.formattedPrice, price = price(option.priceMicros),
                currencyCode = option.currencyCode, locale = locale, period = null, intro = null,
            )
            return PlayPlan(offer, product.productId, option.offerToken, trial = null)
        }
        val offers = product.subscriptionOffers
        if (offers.isEmpty()) return null
        val basePlanId = offers.firstOrNull { it.basePlanId == basePlanId(plan) }?.basePlanId ?: offers.first().basePlanId
        val onBase = offers.filter { it.basePlanId == basePlanId }
        val base = onBase.firstOrNull { it.offerId == null }
        val recurring = (base ?: onBase.first()).phases.lastOrNull() ?: return null
        val period = period(recurring.billingPeriod) ?: return null
        val trialOffer = onBase.firstOrNull { it.offerId != null && intro(it)?.mode == IntroTerms.Mode.ON_US }
        val introOffer = trialOffer ?: onBase.firstOrNull { it.offerId != null && intro(it) != null }
        val intro = introOffer?.let { intro(it) }
        val buyWith = introOffer ?: base ?: onBase.first()
        val offer = PlanOffer(
            plan = plan, displayPrice = recurring.formattedPrice, price = price(recurring.priceMicros),
            currencyCode = recurring.currencyCode, locale = locale, period = period, intro = intro,
        )
        return PlayPlan(offer, product.productId, buyWith.offerToken, trial = intro?.takeIf { it.mode == IntroTerms.Mode.ON_US })
    }

    fun plans(products: List<PlayProduct>, locale: Locale = Locale.getDefault()): Map<ProPlan, PlayPlan> {
        val found = LinkedHashMap<ProPlan, PlayPlan>()
        for (product in products) {
            val plan = plan(product, locale) ?: continue
            found.putIfAbsent(plan.offer.plan, plan)
        }
        return found
    }

    /**
     * Whether Play offers this person the yearly trial: the trial offer came back with the yearly plan. Null while the
     * yearly plan has not loaded (the locked bar then never promises the trial).
     */
    fun introEligible(plans: Map<ProPlan, PlayPlan>): Boolean? {
        val yearly = plans[ProPlan.YEARLY] ?: return null
        return yearly.trial != null
    }

    /** Each subscription's recurring price, by product id, for `ProLedger.prices`. */
    fun prices(plans: Map<ProPlan, PlayPlan>): Map<String, PlanPrice> =
        plans.values.mapNotNull { plan -> PlanPrice.of(plan.offer)?.let { plan.productId to it } }.toMap()
}

/** From Play's purchases on the phone to the ported entitlement rule (SPEC-ANDROID 9.4). */
object PlayEntitlement {
    /**
     * How long a renewing subscription's answer holds without asking Play again: a check horizon, not a period end,
     * since the phone never sees one. `ProStatus` adds its 3-day renewal margin to it, so the widgets, the tile and the
     * nudge keep a renewing payer unlocked for 6 days after Taken last heard from Play. [Own choice, from the iPhone's
     * 3-day margin.]
     */
    val RENEWING_HORIZON: Duration = Duration.ofHours(72)

    /** A subscription set not to renew holds 24 hours past the last answer: it may end any day. [Own choice] */
    val ENDING_HORIZON: Duration = Duration.ofHours(24)

    /** `ProLedger.trialEnds`' key: the purchase time in milliseconds, which Play never changes after a renewal. */
    fun trialKey(purchaseTime: Instant): String = purchaseTime.toEpochMilli().toString()

    /**
     * When a trial bought at `start` ends: a day or week trial by count of days, a month or year one on the calendar in
     * UTC. Play does not tell the phone (the Purchase reference above). [Own choice for months and years]
     */
    fun trialEnd(start: Instant, trial: IntroTerms): Instant {
        val days = trial.period.days
        val count = maxOf(trial.periodCount, 1)
        if (days != null) return start.plus(Duration.ofDays(days.toLong() * count))
        val at = start.atZone(ZoneOffset.UTC)
        val total = (trial.period.value * count).toLong()
        return (if (trial.period.unit == PlanPeriod.PeriodUnit.YEAR) at.plusYears(total) else at.plusMonths(total)).toInstant()
    }

    /**
     * Play's purchases as the entitlement rule's facts. Only PURCHASED grants anything ("Only grant entitlement when the
     * purchase transitions from PENDING to PURCHASED", integrate page). A subscription is a trial while the end this phone
     * recorded for it is still ahead; its fact then runs to that end. Any other subscription runs to the check horizon.
     */
    fun facts(purchases: List<PlayPurchase>, trialEnds: Map<String, Instant>, now: Instant): List<PurchaseFact> {
        val facts = ArrayList<PurchaseFact>()
        for (purchase in purchases) {
            if (purchase.state != PlayPurchase.State.PURCHASED) continue
            for (productId in purchase.productIds) {
                val plan = ProPlan.fromProductId(productId) ?: continue
                if (!plan.isSubscription) {
                    facts.add(PurchaseFact(productId))
                    continue
                }
                val trialEnd = trialEnds[trialKey(purchase.purchaseTime)]?.takeIf { it > now }
                val horizon = if (purchase.autoRenewing) RENEWING_HORIZON else ENDING_HORIZON
                facts.add(
                    PurchaseFact(
                        productId = productId,
                        expiresAt = trialEnd ?: now.plus(horizon),
                        isIntroOffer = trialEnd != null,
                        willRenew = purchase.autoRenewing,
                        renewsTo = purchase.pendingUpdateProductIds.firstOrNull { ProPlan.fromProductId(it)?.isSubscription == true },
                    ),
                )
            }
        }
        return facts
    }

    fun status(purchases: List<PlayPurchase>, trialEnds: Map<String, Instant>, now: Instant): ProStatus =
        Entitlement.evaluate(facts(purchases, trialEnds, now), now)

    /** A purchase of Taken Pro is waiting for approval (a slow card, a family approval). */
    fun hasPending(purchases: List<PlayPurchase>): Boolean =
        purchases.any { it.state == PlayPurchase.State.PENDING && it.plan != null }

    /**
     * Purchases to acknowledge: every PURCHASED one of Taken's not yet acknowledged. Google: within three days "so that
     * the purchase isn't automatically refunded and entitlement revoked"; never while PENDING (integrate page).
     */
    fun toAcknowledge(purchases: List<PlayPurchase>): List<String> = purchases
        .filter { it.state == PlayPurchase.State.PURCHASED && !it.acknowledged && it.plan != null }
        .map { it.token }
        .distinct()

    /** The subscription this Google account holds, for Profile's Manage subscription. */
    fun heldSubscription(purchases: List<PlayPurchase>): ProPlan? = purchases
        .filter { it.state == PlayPurchase.State.PURCHASED }
        .mapNotNull { it.plan }
        .firstOrNull { it.isSubscription }

    /**
     * The same entitlement, ignoring when it was checked and the moving check horizon (a trial's end is real, so it
     * counts). On a change the app refreshes the widgets and the reminders.
     */
    fun sameEntitlement(a: ProStatus?, b: ProStatus?): Boolean {
        if (a == null || b == null) return a == null && b == null
        val endsCount = a.reason == ProReason.TRIAL || b.reason == ProReason.TRIAL
        return a.isPro == b.isPro && a.reason == b.reason && a.willRenew == b.willRenew &&
            a.billingIssue == b.billingIssue && a.renewingSubscription == b.renewingSubscription &&
            a.plan == b.plan && a.renewsTo == b.renewsTo && (!endsCount || a.expiresAt == b.expiresAt)
    }

    /**
     * A subscription whose cached answer has run out: only Play knows whether it still holds, so the app waits for Play
     * (at most a few seconds) before it shows a lock, as the iPhone does for a lapsed renewal.
     */
    fun needsCheck(status: ProStatus?, now: Instant): Boolean =
        status != null && status.isPro && status.expiresAt != null && !status.isActive(now)

    /**
     * Profile's Manage subscription: Play's subscription center, at the subscription when one is held. Google's
     * recommended form (https://developer.android.com/google/play/billing/subscriptions).
     */
    fun manageUrl(productId: String?, packageName: String): String =
        if (productId == null) {
            "https://play.google.com/store/account/subscriptions"
        } else {
            "https://play.google.com/store/account/subscriptions?sku=$productId&package=$packageName"
        }
}
