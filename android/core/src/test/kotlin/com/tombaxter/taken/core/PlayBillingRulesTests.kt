package com.tombaxter.taken.core

import com.tombaxter.taken.core.pro.Entitlement
import com.tombaxter.taken.core.pro.IntroTerms
import com.tombaxter.taken.core.pro.PlanPeriod
import com.tombaxter.taken.core.pro.PlanPeriod.PeriodUnit
import com.tombaxter.taken.core.pro.PlanPrice
import com.tombaxter.taken.core.pro.PlayCatalog
import com.tombaxter.taken.core.pro.PlayEntitlement
import com.tombaxter.taken.core.pro.PlayOneTimeOffer
import com.tombaxter.taken.core.pro.PlayPhase
import com.tombaxter.taken.core.pro.PlayProduct
import com.tombaxter.taken.core.pro.PlayPurchase
import com.tombaxter.taken.core.pro.PlayResponse
import com.tombaxter.taken.core.pro.PlaySubscriptionOffer
import com.tombaxter.taken.core.pro.ProAccess
import com.tombaxter.taken.core.pro.ProCopy
import com.tombaxter.taken.core.pro.ProGate
import com.tombaxter.taken.core.pro.ProPlan
import com.tombaxter.taken.core.pro.ProReason
import com.tombaxter.taken.core.pro.ProStatus
import com.tombaxter.taken.core.reminders.TrialReminder
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.stack.logDose
import java.math.BigDecimal
import java.time.Duration
import java.time.Instant
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Android only (SPEC-ANDROID 9): what Google Play tells the phone, turned into Taken Pro. Every state a person can be in:
 * no purchase, a trial, monthly, yearly, lifetime, a pending purchase, cancelled but still active, expired, refunded, and
 * Play unavailable; plus the catalog the paywall reads and the purchases Taken must acknowledge.
 */
class PlayBillingRulesTests {
    private val now = at(2026, 10, 28, 9, 14)
    private val yearly = ProPlan.YEARLY.productId
    private val monthly = ProPlan.MONTHLY.productId
    private val lifetime = ProPlan.LIFETIME.productId

    private fun purchase(
        product: String,
        state: PlayPurchase.State = PlayPurchase.State.PURCHASED,
        autoRenewing: Boolean = true,
        acknowledged: Boolean = true,
        time: Instant = now,
        token: String = "token-$product",
        changingTo: List<String> = emptyList(),
    ) = PlayPurchase(listOf(product), state, time, token, acknowledged, autoRenewing, changingTo)

    private fun phase(price: String, micros: Long, period: String, cycles: Int = 0, recurrence: PlayPhase.Recurrence = PlayPhase.Recurrence.INFINITE) =
        PlayPhase(price, micros, "USD", period, cycles, recurrence)

    private val yearlyBase = PlaySubscriptionOffer("yearly", null, "yearly-base", listOf(phase("$19.99", 19_990_000, "P1Y")))
    private val yearlyTrial = PlaySubscriptionOffer(
        "yearly", "trial-7d", "yearly-trial",
        listOf(phase("Free", 0, "P1W", 1, PlayPhase.Recurrence.FINITE), phase("$19.99", 19_990_000, "P1Y")),
    )
    private val monthlyBase = PlaySubscriptionOffer("monthly", null, "monthly-base", listOf(phase("$3.99", 3_990_000, "P1M")))
    private val lifetimeOption = PlayOneTimeOffer("$49.99", 49_990_000, "USD", "lifetime-buy", purchaseOptionId = "lifetime")

    private val catalog = listOf(
        PlayProduct(yearly, subscriptionOffers = listOf(yearlyBase, yearlyTrial)),
        PlayProduct(monthly, subscriptionOffers = listOf(monthlyBase)),
        PlayProduct(lifetime, oneTimeOffers = listOf(lifetimeOption)),
    )

    // MARK: The catalog

    @Test
    fun testBillingPeriodsReadAsPlanPeriods() {
        assertEquals(PlanPeriod(1, PeriodUnit.YEAR), PlayCatalog.period("P1Y"))
        assertEquals(PlanPeriod(1, PeriodUnit.MONTH), PlayCatalog.period("P1M"))
        assertEquals(PlanPeriod(3, PeriodUnit.MONTH), PlayCatalog.period("P3M"))
        assertEquals(PlanPeriod(1, PeriodUnit.WEEK), PlayCatalog.period("P1W"))
        assertEquals(PlanPeriod(7, PeriodUnit.DAY), PlayCatalog.period("P7D"))
        assertNull(PlayCatalog.period("P1Y6M"), "a shape Play does not use for Taken's plans")
        assertNull(PlayCatalog.period(""))
    }

    @Test
    fun testThePaywallReadsThePlansAsPlaySendsThem() {
        val plans = PlayCatalog.plans(catalog, Locale.US)
        val year = assertNotNull(plans[ProPlan.YEARLY])
        assertEquals("$19.99", year.offer.displayPrice)
        assertEquals(BigDecimal("19.990000"), year.offer.price)
        assertEquals(PlanPeriod(1, PeriodUnit.YEAR), year.offer.period)
        assertEquals(IntroTerms(IntroTerms.Mode.ON_US, PlanPeriod(1, PeriodUnit.WEEK), 1, "Free"), year.offer.intro)
        assertEquals("yearly-trial", year.offerToken, "the trial offer for someone Play offers it to")
        assertNotNull(year.trial)
        assertEquals("Start 7 days on us", ProCopy.cta(year.offer, eligible = true))
        assertEquals("about $1.67 / month", ProCopy.monthlyEquivalent(year.offer))

        val month = assertNotNull(plans[ProPlan.MONTHLY])
        assertEquals("monthly-base", month.offerToken)
        assertNull(month.offer.intro)
        assertEquals("$3.99 per month. ${ProCopy.RENEWAL_TERMS}", ProCopy.terms(month.offer, eligible = true))

        val once = assertNotNull(plans[ProPlan.LIFETIME])
        assertEquals("lifetime-buy", once.offerToken, "a one-time product needs its offer token too")
        assertNull(once.offer.period)
        assertEquals("$49.99" to "once", ProCopy.price(once.offer))

        assertEquals(true, PlayCatalog.introEligible(plans))
        assertEquals(
            mapOf(yearly to PlanPrice("$19.99", PlanPeriod(1, PeriodUnit.YEAR)), monthly to PlanPrice("$3.99", PlanPeriod(1, PeriodUnit.MONTH))),
            PlayCatalog.prices(plans),
            "the prices the trial reminder names",
        )
    }

    @Test
    fun testATrialAlreadyUsedComesBackWithoutItsOffer() {
        // Play returns only the offers this person is eligible for (integrate page).
        val used = listOf(PlayProduct(yearly, subscriptionOffers = listOf(yearlyBase)))
        val plans = PlayCatalog.plans(used)
        val year = assertNotNull(plans[ProPlan.YEARLY])
        assertEquals("yearly-base", year.offerToken)
        assertNull(year.offer.intro)
        assertNull(year.trial)
        assertEquals(false, PlayCatalog.introEligible(plans))
        assertEquals("Continue", ProCopy.cta(year.offer, eligible = false))
        assertNull(PlayCatalog.introEligible(PlayCatalog.plans(catalog.drop(1))), "no yearly plan loaded: not known")
    }

    @Test
    fun testOnlyTakensProductsAndKnownShapesBecomePlans() {
        assertTrue(PlayCatalog.plans(listOf(PlayProduct("com.example.other", subscriptionOffers = listOf(yearlyBase)))).isEmpty())
        assertNull(PlayCatalog.plan(PlayProduct(yearly)), "a subscription with no offers")
        assertNull(PlayCatalog.plan(PlayProduct(lifetime)), "a one-time product with no purchase option")
        val discounted = PlaySubscriptionOffer(
            "monthly", "intro", "monthly-intro",
            listOf(phase("$0.99", 990_000, "P1M", 3, PlayPhase.Recurrence.FINITE), phase("$3.99", 3_990_000, "P1M")),
        )
        val month = assertNotNull(PlayCatalog.plan(PlayProduct(monthly, subscriptionOffers = listOf(monthlyBase, discounted))))
        assertEquals(IntroTerms(IntroTerms.Mode.PAY_AS_YOU_GO, PlanPeriod(1, PeriodUnit.MONTH), 3, "$0.99"), month.offer.intro)
        assertNull(month.trial, "only an offer that costs nothing is a trial")
    }

    // MARK: Every state

    @Test
    fun testNoPurchaseIsNotPro() {
        val status = PlayEntitlement.status(emptyList(), emptyMap(), now)
        assertFalse(status.isPro)
        assertEquals("Not active", ProCopy.statusLine(status, now, london))
        assertEquals(ProAccess.LOCKED, ProGate.access(status, settled = true, legacyLog = false, hasLogged = true, now = now))
        assertEquals(ProAccess.FIRST_SESSION, ProGate.access(status, settled = true, legacyLog = false, hasLogged = false, now = now), "the first dose needs no Pro")
    }

    @Test
    fun testATrialBoughtOnThisPhone() {
        val start = now
        val end = PlayEntitlement.trialEnd(start, IntroTerms(IntroTerms.Mode.ON_US, PlanPeriod(1, PeriodUnit.WEEK), 1, "Free"))
        assertEquals(at(2026, 11, 4, 9, 14), end)
        val ends = mapOf(PlayEntitlement.trialKey(start) to end)
        val later = start.plus(Duration.ofHours(1))
        val status = PlayEntitlement.status(listOf(purchase(yearly, time = start)), ends, later)
        assertEquals(ProReason.TRIAL, status.reason)
        assertEquals(end, status.expiresAt, "the trial's real end, which the reminder needs")
        assertEquals(true, status.willRenew)
        assertEquals(ProPlan.YEARLY, status.plan)
        assertEquals("Trial · ends 4 Nov", ProCopy.statusLine(status, later, london))
        val state = StackState(items = listOf(makeItem("Vitamin D3", "VD3", created = start)))
        assertNotNull(TrialReminder.plan(status, null, state, later, london), "the reminder is planned on this phone")

        val converted = PlayEntitlement.status(listOf(purchase(yearly, time = start)), ends, end.plusSeconds(60))
        assertEquals(ProReason.YEARLY, converted.reason, "past the trial's end, a subscription Play still returns has converted")
        assertEquals("Pro yearly · renewing", ProCopy.statusLine(converted, end.plusSeconds(60), london))
    }

    @Test
    fun testATrialRestoredOnAnotherPhoneReadsAsYearly() {
        val status = PlayEntitlement.status(listOf(purchase(yearly)), emptyMap(), now)
        assertEquals(ProReason.YEARLY, status.reason, "a trial is known only on the phone that bought it")
        assertEquals(now.plus(PlayEntitlement.RENEWING_HORIZON), status.expiresAt)
        assertNull(TrialReminder.plan(status, null, StackState(), now, london), "no reminder there")
    }

    @Test
    fun testActiveMonthlyAndYearly() {
        val month = PlayEntitlement.status(listOf(purchase(monthly)), emptyMap(), now)
        assertEquals(ProReason.MONTHLY, month.reason)
        assertEquals(ProPlan.MONTHLY, month.plan)
        assertEquals(now.plus(PlayEntitlement.RENEWING_HORIZON), month.expiresAt, "a check horizon, not a period end")
        assertEquals(now.plus(PlayEntitlement.RENEWING_HORIZON).plus(ProStatus.renewalMargin), month.activeUntil, "6 days without asking Play")
        assertEquals("Pro monthly · renewing", ProCopy.statusLine(month, now, london))
        val year = PlayEntitlement.status(listOf(purchase(yearly)), emptyMap(), now)
        assertEquals(ProReason.YEARLY, year.reason)
        assertEquals("Pro yearly · renewing", ProCopy.statusLine(year, now, london))
        assertEquals(ProPlan.YEARLY, PlayEntitlement.heldSubscription(listOf(purchase(yearly))))
    }

    @Test
    fun testLifetime() {
        val status = PlayEntitlement.status(listOf(purchase(lifetime, autoRenewing = false)), emptyMap(), now)
        assertEquals(ProReason.LIFETIME, status.reason)
        assertNull(status.expiresAt, "for good")
        assertEquals("Pro lifetime", ProCopy.statusLine(status, now, london))
        val both = PlayEntitlement.status(listOf(purchase(lifetime, autoRenewing = false), purchase(monthly)), emptyMap(), now)
        assertEquals(ProReason.LIFETIME, both.reason)
        assertTrue(both.renewingSubscription, "Profile offers to cancel the subscription still charging")
        assertNull(PlayEntitlement.heldSubscription(listOf(purchase(lifetime, autoRenewing = false))))
    }

    @Test
    fun testAPendingPurchaseGrantsNothingYet() {
        val pending = listOf(purchase(yearly, state = PlayPurchase.State.PENDING, acknowledged = false))
        assertFalse(PlayEntitlement.status(pending, emptyMap(), now).isPro, "only PURCHASED grants Pro")
        assertTrue(PlayEntitlement.hasPending(pending))
        assertTrue(PlayEntitlement.toAcknowledge(pending).isEmpty(), "never acknowledged while PENDING")
        val lifetimePending = listOf(purchase(lifetime, state = PlayPurchase.State.PENDING, acknowledged = false))
        assertFalse(PlayEntitlement.status(lifetimePending, emptyMap(), now).isPro)
        assertFalse(PlayEntitlement.hasPending(listOf(purchase("com.example.other", state = PlayPurchase.State.PENDING))))
    }

    @Test
    fun testCancelledButStillActive() {
        // Play: a cancelled subscription "is still returned" until it expires.
        val status = PlayEntitlement.status(listOf(purchase(yearly, autoRenewing = false)), emptyMap(), now)
        assertTrue(status.isPro)
        assertEquals(false, status.willRenew)
        assertEquals(now.plus(PlayEntitlement.ENDING_HORIZON), status.activeUntil, "it may end any day, so the answer holds 24 hours")
        assertEquals("Pro yearly · not renewing", ProCopy.statusLine(status, now, london))

        val start = now
        val ends = mapOf(PlayEntitlement.trialKey(start) to at(2026, 11, 4, 9, 14))
        val cancelledTrial = PlayEntitlement.status(listOf(purchase(yearly, autoRenewing = false, time = start)), ends, now.plusSeconds(3600))
        assertEquals(ProReason.TRIAL, cancelledTrial.reason)
        assertEquals(at(2026, 11, 4, 9, 14), cancelledTrial.activeUntil, "a cancelled trial runs to its end, uncharged")
        assertNull(TrialReminder.plan(cancelledTrial, null, StackState(), now.plusSeconds(3600), london), "and its reminder is withdrawn")
    }

    @Test
    fun testExpiredRefundedAndRevokedPurchasesAreGone() {
        // An expired subscription and a refunded, revoked purchase are no longer returned by queryPurchasesAsync.
        val before = PlayEntitlement.status(listOf(purchase(lifetime, autoRenewing = false)), emptyMap(), now)
        val after = PlayEntitlement.status(emptyList(), emptyMap(), now.plusSeconds(60))
        assertEquals(false, Entitlement.next(before, after, answered = true)?.isPro, "Play answered: the refund counts at once")
        val month = PlayEntitlement.status(listOf(purchase(monthly)), emptyMap(), now)
        assertFalse(assertNotNull(Entitlement.next(month, after, answered = true)).isActive(now.plusSeconds(60)))
    }

    @Test
    fun testPlayUnavailableKeepsWhatWasKnown() {
        val known = PlayEntitlement.status(listOf(purchase(yearly)), emptyMap(), now)
        val nothing = PlayEntitlement.status(emptyList(), emptyMap(), now.plusSeconds(60))
        assertEquals(known, Entitlement.next(known, nothing, answered = false), "offline or no Play Store: nothing is taken away")
        assertNull(Entitlement.next(null, nothing, answered = false))
        assertTrue(PlayResponse.SERVICE_UNAVAILABLE.retriable)
        assertTrue(PlayResponse.NETWORK_ERROR.retriable)
        assertFalse(PlayResponse.BILLING_UNAVAILABLE.retriable, "needs the person to act: never retried by itself")
        assertFalse(PlayResponse.USER_CANCELED.retriable)
    }

    @Test
    fun testAnAnswerThatRanOutWaitsForPlayBeforeLocking() {
        val year = PlayEntitlement.status(listOf(purchase(yearly)), emptyMap(), now)
        val later = assertNotNull(year.activeUntil).plusSeconds(1)
        assertTrue(PlayEntitlement.needsCheck(year, later))
        assertEquals(ProAccess.CHECKING, ProGate.access(year, settled = false, legacyLog = false, hasLogged = true, now = later), "no lock flashes before Play answers")
        assertFalse(PlayEntitlement.needsCheck(year, now))
        assertFalse(PlayEntitlement.needsCheck(PlayEntitlement.status(listOf(purchase(lifetime)), emptyMap(), now), later))
        assertFalse(PlayEntitlement.needsCheck(ProStatus.notPro(now), later))
    }

    @Test
    fun testEveryPurchasedOneIsAcknowledgedOnce() {
        val purchases = listOf(
            purchase(yearly, acknowledged = false, token = "a"),
            purchase(lifetime, acknowledged = true, token = "b"),
            purchase(monthly, acknowledged = false, token = "a"),
            purchase("com.example.other", acknowledged = false, token = "c"),
        )
        assertEquals(listOf("a"), PlayEntitlement.toAcknowledge(purchases), "within three days, or Play refunds it")
    }

    @Test
    fun testAChangeOfPlanWaitingForTheRenewal() {
        val status = PlayEntitlement.status(listOf(purchase(yearly, changingTo = listOf(monthly))), emptyMap(), now)
        assertEquals(ProPlan.YEARLY, status.plan)
        assertEquals(ProPlan.MONTHLY, status.renewsTo, "the price the reminder names follows the plan that renews")
    }

    @Test
    fun testTheSameEntitlementIgnoresTheMovingHorizon() {
        val first = PlayEntitlement.status(listOf(purchase(yearly)), emptyMap(), now)
        val later = PlayEntitlement.status(listOf(purchase(yearly)), emptyMap(), now.plusSeconds(3600))
        assertTrue(PlayEntitlement.sameEntitlement(first, later), "a new check is not a change")
        assertFalse(first.sameEntitlement(later), "the ported rule would call it one")
        val cancelled = PlayEntitlement.status(listOf(purchase(yearly, autoRenewing = false)), emptyMap(), now)
        assertFalse(PlayEntitlement.sameEntitlement(first, cancelled), "a cancellation is")
        assertTrue(PlayEntitlement.sameEntitlement(null, null))
        assertFalse(PlayEntitlement.sameEntitlement(first, null))
    }

    @Test
    fun testTrialEndsOnTheCalendar() {
        val week = IntroTerms(IntroTerms.Mode.ON_US, PlanPeriod(1, PeriodUnit.WEEK), 1, "Free")
        assertEquals(now.plus(Duration.ofDays(7)), PlayEntitlement.trialEnd(now, week))
        val days = IntroTerms(IntroTerms.Mode.ON_US, PlanPeriod(3, PeriodUnit.DAY), 1, "Free")
        assertEquals(now.plus(Duration.ofDays(3)), PlayEntitlement.trialEnd(now, days))
        val month = IntroTerms(IntroTerms.Mode.ON_US, PlanPeriod(1, PeriodUnit.MONTH), 1, "Free")
        assertEquals(Instant.parse("2027-02-28T10:00:00Z"), PlayEntitlement.trialEnd(Instant.parse("2027-01-31T10:00:00Z"), month))
        assertEquals("1793178840000", PlayEntitlement.trialKey(Instant.ofEpochMilli(1_793_178_840_000)))
    }

    @Test
    fun testManageOpensPlaysSubscriptionCenter() {
        assertEquals(
            "https://play.google.com/store/account/subscriptions?sku=com.tombaxter.taken.pro.yearly&package=com.tombaxter.taken",
            PlayEntitlement.manageUrl(yearly, "com.tombaxter.taken"),
        )
        assertEquals("https://play.google.com/store/account/subscriptions", PlayEntitlement.manageUrl(null, "com.tombaxter.taken"))
    }

    @Test
    fun testTheGateReadsTheAnswerEverySurfaceReads() {
        val vd3 = makeItem("Vitamin D3", "VD3", created = now)
        val state = StackState(items = listOf(vd3))
        state.logDose(vd3.id, now, london)
        val status = PlayEntitlement.status(listOf(purchase(monthly)), emptyMap(), now)
        val ledger = com.tombaxter.taken.core.pro.ProLedger(status = status, firstSeenAt = now)
        assertEquals(ProAccess.PRO, ProGate.access(ledger, state, now.plus(Duration.ofDays(5))), "widgets and the tile, days later")
        assertEquals(ProAccess.LOCKED, ProGate.access(ledger, state, now.plus(Duration.ofDays(7))), "until Taken asks Play again")
    }
}
