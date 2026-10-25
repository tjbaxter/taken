package com.tombaxter.taken.core

import com.tombaxter.taken.core.pro.Entitlement
import com.tombaxter.taken.core.pro.ProPlan
import com.tombaxter.taken.core.pro.ProReason
import com.tombaxter.taken.core.pro.ProStatus
import com.tombaxter.taken.core.pro.PurchaseFact
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/EntitlementTests.swift: the money rule, Pro when a live subscription or the lifetime purchase
 * says so. Adapted to Play's facts (SPEC-ANDROID 9.4 and 8.2): the founding-member, app transaction, sandbox and TestFlight
 * cases are left out (no Android 1.0 users, no App Store), and "What a check keeps" asks whether Play answered where the
 * iPhone asks whether the app transaction was verified. What Play's purchases become as facts is PlayBillingRulesTests'.
 */
class EntitlementTests {

    private val now = at(2026, 10, 13, 9)
    private val yearly = ProPlan.YEARLY.productId
    private val monthly = ProPlan.MONTHLY.productId
    private val lifetime = ProPlan.LIFETIME.productId

    @Test
    fun testNothingBoughtIsNotPro() {
        val status = Entitlement.evaluate(emptyList(), now)
        assertFalse(status.isPro)
        assertEquals(ProReason.NONE, status.reason)
        assertNull(status.expiresAt)
        assertFalse(status.isActive(now))
    }

    @Test
    fun testLiveYearlySubscription() {
        val renews = at(2027, 10, 12, 9)
        val status = Entitlement.evaluate(listOf(PurchaseFact(yearly, expiresAt = renews, willRenew = true)), now)
        assertTrue(status.isPro)
        assertEquals(ProReason.YEARLY, status.reason)
        assertEquals(renews, status.expiresAt)
        assertEquals(true, status.willRenew)
        assertFalse(status.billingIssue)
        assertTrue(status.isActive(now))
        assertTrue(status.isActive(renews.minusSeconds(1)))
        assertEquals(renews.plus(ProStatus.renewalMargin), status.activeUntil)
        assertEquals(ProPlan.YEARLY, status.plan)
    }

    @Test
    fun testARenewingPlanStaysOnPastItsPeriodEnd() {
        // The widgets, the tile and the nudge read the cache: a renewal Play has charged must never lock them because
        // Taken was not opened that day.
        val renews = at(2027, 10, 12, 9)
        val status = Entitlement.evaluate(listOf(PurchaseFact(yearly, expiresAt = renews, willRenew = true)), now)
        assertTrue(status.isActive(renews), "the renewal moment itself")
        assertTrue(status.isActive(renews.plusSeconds(3600)), "an hour after the period end")
        assertTrue(status.isActive(renews.plus(ProStatus.renewalMargin).minusSeconds(1)))
        assertFalse(status.isActive(renews.plus(ProStatus.renewalMargin)), "the margin is capped")
        assertTrue(status.awaitingRenewal(renews.plusSeconds(3600)))
        assertFalse(status.awaitingRenewal(now), "not before the period ends")
        assertTrue(status.lapsedRenewal(renews.plus(ProStatus.renewalMargin).plusSeconds(1)), "past the margin the app asks Play before locking")

        val unknown = ProStatus(isPro = true, reason = ProReason.MONTHLY, checkedAt = now, expiresAt = renews)
        assertTrue(unknown.isActive(renews.plusSeconds(3600)), "Play did not say: treated as renewing")
    }

    @Test
    fun testAPlanSetNotToRenewEndsOnTime() {
        val ends = at(2027, 10, 12, 9)
        val status = Entitlement.evaluate(listOf(PurchaseFact(yearly, expiresAt = ends, willRenew = false)), now)
        assertTrue(status.isActive(ends.minusSeconds(1)))
        assertFalse(status.isActive(ends), "a cancelled plan is locked at its end")
        assertEquals(ends, status.activeUntil)
        assertFalse(status.awaitingRenewal(ends))
        assertFalse(status.lapsedRenewal(ends.plus(ProStatus.renewalMargin).plusSeconds(1)))
    }

    @Test
    fun testTheTrialConvertingKeepsPro() {
        // The introductory week ends and Play charges for the year. Until Taken hears about it, the trial's cache stays on.
        val trialEnds = at(2026, 10, 20, 9)
        val trial = PurchaseFact(yearly, expiresAt = trialEnds, isIntroOffer = true, willRenew = true)
        val justAfter = trialEnds.plusSeconds(60)
        val status = Entitlement.evaluate(listOf(trial), justAfter)
        assertTrue(status.isPro)
        assertEquals(ProReason.TRIAL, status.reason)
        assertEquals(trialEnds, status.expiresAt, "the cache keeps the trial's end")
        assertTrue(status.awaitingRenewal(justAfter))
        val converted = PurchaseFact(yearly, expiresAt = at(2027, 10, 20, 9), willRenew = true)
        assertEquals(ProReason.YEARLY, Entitlement.evaluate(listOf(trial, converted), justAfter).reason, "the paid year wins once it arrives")
        assertFalse(Entitlement.evaluate(listOf(trial), trialEnds.plus(ProStatus.renewalMargin).plusSeconds(1)).isPro)
    }

    @Test
    fun testAFailedRenewalGetsNoMargin() {
        val ended = at(2026, 10, 12, 9)
        val retrying = PurchaseFact(monthly, expiresAt = ended, willRenew = true, inBillingRetry = true)
        assertFalse(Entitlement.evaluate(listOf(retrying), now).isPro, "billing retry without a grace period grants nothing")
        val live = PurchaseFact(monthly, expiresAt = at(2026, 11, 12, 9), willRenew = true, inBillingRetry = true)
        val status = Entitlement.evaluate(listOf(live), now)
        assertTrue(status.billingIssue)
        assertEquals(at(2026, 11, 12, 9), status.activeUntil, "a billing issue ends on time")
    }

    @Test
    fun testLiveMonthlySubscription() {
        val status = Entitlement.evaluate(listOf(PurchaseFact(monthly, expiresAt = at(2026, 11, 13, 9))), now)
        assertTrue(status.isPro)
        assertEquals(ProReason.MONTHLY, status.reason)
    }

    @Test
    fun testIntroductoryWeekIsTheTrial() {
        val ends = at(2026, 10, 20, 9)
        val status = Entitlement.evaluate(listOf(PurchaseFact(yearly, expiresAt = ends, isIntroOffer = true, willRenew = true)), now)
        assertTrue(status.isPro)
        assertEquals(ProReason.TRIAL, status.reason)
        assertEquals(ends, status.expiresAt)
    }

    @Test
    fun testExpiredSubscriptionIsNotPro() {
        val lapsed = PurchaseFact(yearly, expiresAt = at(2026, 10, 12, 9), willRenew = false)
        assertFalse(Entitlement.evaluate(listOf(lapsed), now).isPro)
        val endsNow = PurchaseFact(monthly, expiresAt = now, willRenew = false)
        assertFalse(Entitlement.evaluate(listOf(endsNow), now).isPro, "the end moment is already out")
        val renewedLongAgo = PurchaseFact(monthly, expiresAt = now.minus(ProStatus.renewalMargin), willRenew = true)
        assertFalse(Entitlement.evaluate(listOf(renewedLongAgo), now).isPro, "a renewal that never came is over once the margin is")
        val noDate = PurchaseFact(monthly)
        assertFalse(Entitlement.evaluate(listOf(noDate), now).isPro, "a subscription with no end grants nothing")
    }

    @Test
    fun testBillingGracePeriodKeepsPro() {
        val grace = at(2026, 10, 25, 9)
        val fact = PurchaseFact(monthly, expiresAt = at(2026, 10, 12, 9), graceUntil = grace, willRenew = true)
        val status = Entitlement.evaluate(listOf(fact), now)
        assertTrue(status.isPro)
        assertEquals(ProReason.MONTHLY, status.reason)
        assertTrue(status.billingIssue)
        assertEquals(grace, status.expiresAt, "the cache holds through the grace period")
        assertEquals(grace, status.activeUntil, "and not past it")
        assertFalse(status.isActive(grace))
        assertFalse(Entitlement.evaluate(listOf(fact), at(2026, 10, 25, 10)).isPro, "and no longer")
    }

    @Test
    fun testRevokedTransactionsNeverCount() {
        val refunded = PurchaseFact(yearly, revokedAt = at(2026, 10, 10, 9), expiresAt = at(2027, 10, 1, 9))
        assertFalse(Entitlement.evaluate(listOf(refunded), now).isPro)
        val refundedLifetime = PurchaseFact(lifetime, revokedAt = at(2026, 10, 10, 9))
        assertFalse(Entitlement.evaluate(listOf(refundedLifetime), now).isPro)
    }

    @Test
    fun testUnverifiedTransactionsNeverCount() {
        // On Play: a purchase still PENDING (a slow card, a family approval).
        val pending = listOf(PurchaseFact(lifetime, verified = false), PurchaseFact(yearly, verified = false, expiresAt = at(2027, 10, 1, 9)))
        assertFalse(Entitlement.evaluate(pending, now).isPro)
    }

    @Test
    fun testLifetimeIsForGood() {
        val status = Entitlement.evaluate(listOf(PurchaseFact(lifetime)), now)
        assertTrue(status.isPro)
        assertEquals(ProReason.LIFETIME, status.reason)
        assertNull(status.expiresAt)
        assertTrue(status.isActive(at(2040, 1, 1, 0)), "lifetime never expires in the cache")
    }

    @Test
    fun testLifetimeWinsOverASubscription() {
        val status = Entitlement.evaluate(listOf(PurchaseFact(monthly, expiresAt = at(2026, 11, 1, 9)), PurchaseFact(lifetime)), now)
        assertEquals(ProReason.LIFETIME, status.reason)
        assertNull(status.expiresAt)
    }

    @Test
    fun testProForGoodNotesASubscriptionThatStillRenews() {
        // Profile offers Manage subscription to a lifetime member who is still paying for a plan.
        val renewing = PurchaseFact(monthly, expiresAt = at(2026, 11, 1, 9), willRenew = true)
        val lifetimeToo = Entitlement.evaluate(listOf(renewing, PurchaseFact(lifetime)), now)
        assertEquals(ProReason.LIFETIME, lifetimeToo.reason)
        assertTrue(lifetimeToo.renewingSubscription)
        assertNull(lifetimeToo.activeUntil, "still Pro for good")
        val cancelled = renewing.copy(willRenew = false)
        assertFalse(Entitlement.evaluate(listOf(cancelled, PurchaseFact(lifetime)), now).renewingSubscription, "a cancelled plan needs nothing more")
        assertFalse(Entitlement.evaluate(listOf(PurchaseFact(lifetime)), now).renewingSubscription)
    }

    // MARK: What a check keeps

    private val yearlyBefore = ProStatus(
        isPro = true, reason = ProReason.YEARLY, checkedAt = at(2026, 10, 1, 9), expiresAt = at(2026, 10, 4, 9), willRenew = true,
    )

    @Test
    fun testAnAnsweredCheckIsConclusive() {
        // Play answered both questions: an ended plan or a refunded purchase stops counting.
        val fresh = ProStatus.notPro(now)
        assertEquals(fresh, Entitlement.next(yearlyBefore, fresh, answered = true))
        assertEquals(fresh, Entitlement.next(null, fresh, answered = true))
        val lifetimeBefore = ProStatus(isPro = true, reason = ProReason.LIFETIME, checkedAt = at(2026, 10, 1, 9))
        assertEquals(false, Entitlement.next(lifetimeBefore, fresh, answered = true)?.isPro, "a refunded lifetime purchase is not kept")
    }

    @Test
    fun testNoAnswerKeepsWhatWasKnown() {
        // Offline, signed out of Play, or Play unavailable: finding no purchase proves nothing.
        val fresh = ProStatus.notPro(now)
        assertEquals(yearlyBefore, Entitlement.next(yearlyBefore, fresh, answered = false))
        assertNull(Entitlement.next(null, fresh, answered = false))
        val bought = ProStatus(isPro = true, reason = ProReason.LIFETIME, checkedAt = now)
        assertEquals(bought, Entitlement.next(null, bought, answered = false), "a purchase found still counts")
    }

    @Test
    fun testUpgradedAndUnknownTransactionsAreIgnored() {
        val upgradedAway = PurchaseFact(monthly, expiresAt = at(2026, 11, 1, 9), isUpgraded = true)
        assertFalse(Entitlement.evaluate(listOf(upgradedAway), now).isPro)
        val stranger = PurchaseFact("com.example.other", expiresAt = at(2027, 1, 1, 9))
        assertFalse(Entitlement.evaluate(listOf(stranger), now).isPro)
    }

    @Test
    fun testTheLaterOfTwoLiveSubscriptionsWins() {
        val status = Entitlement.evaluate(
            listOf(PurchaseFact(monthly, expiresAt = at(2026, 11, 1, 9)), PurchaseFact(yearly, expiresAt = at(2027, 10, 1, 9), willRenew = false)),
            now,
        )
        assertEquals(ProReason.YEARLY, status.reason)
        assertEquals(at(2027, 10, 1, 9), status.expiresAt)
        assertEquals(false, status.willRenew)
    }

    @Test
    fun testSameEntitlementIgnoresTheCheckTime() {
        val first = ProStatus(isPro = true, reason = ProReason.LIFETIME, checkedAt = now)
        var later = first.copy(checkedAt = now.plusSeconds(3600))
        assertTrue(later.sameEntitlement(first))
        assertFalse(later.sameEntitlement(null))
        later = later.copy(reason = ProReason.FOUNDING)
        assertFalse(later.sameEntitlement(first))
    }

    @Test
    fun testProductIDsAreFixed() {
        assertEquals(
            listOf("com.tombaxter.taken.pro.yearly", "com.tombaxter.taken.pro.monthly", "com.tombaxter.taken.pro.lifetime"),
            ProPlan.entries.map { it.productId },
        )
        assertEquals(ProPlan.LIFETIME, ProPlan.fromProductId("com.tombaxter.taken.pro.lifetime"))
        assertNull(ProPlan.fromProductId("com.tombaxter.taken.pro"))
    }
}
