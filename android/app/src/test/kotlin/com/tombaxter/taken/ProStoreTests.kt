package com.tombaxter.taken

import android.app.Activity
import com.tombaxter.taken.billing.ProStore
import com.tombaxter.taken.core.pro.PlayEntitlement
import com.tombaxter.taken.core.pro.PlayPurchase
import com.tombaxter.taken.core.pro.PlayResponse
import com.tombaxter.taken.core.pro.ProAccess
import com.tombaxter.taken.core.pro.ProCopy
import com.tombaxter.taken.core.pro.ProGate
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.pro.ProPlan
import com.tombaxter.taken.core.pro.ProReason
import com.tombaxter.taken.core.pro.ProStatus
import com.tombaxter.taken.core.reminders.TrialReminder
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.data.MemoryPersistence
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Taken Pro over a fake Google Play (SPEC-ANDROID 9.3 and 9.7): the real ProStore, its pro.json and the gate, driven
 * through every state: no purchase, a trial, active monthly, active yearly, lifetime, pending, cancelled but active,
 * expired, refunded, Play unavailable; and the purchase flow's answers.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class ProStoreTests {
    private val zone = ZoneId.of("Europe/London")
    private var now = Instant.parse("2026-10-28T09:14:00Z")
    private val activity: Activity by lazy { Robolectric.buildActivity(androidx.activity.ComponentActivity::class.java).setup().get() }

    private class Setup(val store: ProStore, val play: FakeBilling, val file: MemoryPersistence) {
        var changes = 0
    }

    private fun TestScope.setup(play: FakeBilling = FakeBilling(), ledger: ProLedger? = ProLedger(firstSeenAt = now)): Setup {
        val file = MemoryPersistence(ledger = ledger)
        val store = ProStore(play, file::updateLedger, backgroundScope, clock = { now }, locale = { java.util.Locale.US })
        val setup = Setup(store, play, file)
        store.listen { setup.changes += 1 }
        store.adoptLedger(ledger)
        store.attach(activity)
        return setup
    }

    /** Taken opens: ON_START then ON_RESUME, and Play answers. */
    private fun TestScope.open(setup: Setup) {
        setup.store.foreground()
        setup.store.resumed()
        runCurrent()
    }

    private fun access(store: ProStore, logged: Boolean = true) =
        ProGate.access(store.status, store.settled, legacyLog = false, hasLogged = logged, now = now)

    @Test
    fun testNoPurchaseLocksAfterTheFirstDose() = runTest {
        val s = setup()
        open(s)
        assertTrue(s.store.settled)
        assertFalse(assertNotNull(s.store.status).isPro)
        assertEquals(ProAccess.LOCKED, access(s.store))
        assertEquals(ProAccess.FIRST_SESSION, access(s.store, logged = false), "the first dose needs no Pro")
        assertEquals(true, s.store.introEligible, "the yearly trial came back with the plans")
        assertEquals(setOf(ProPlan.YEARLY, ProPlan.MONTHLY, ProPlan.LIFETIME), s.store.offers.keys)
        assertEquals(OffersPhase.READY, s.store.offersPhase)
        assertEquals(1, s.play.inAppMessages, "Play's own payment messages, once on opening")
        assertEquals(2, s.file.ledger?.prices?.size, "the prices the trial reminder names, kept in pro.json")
        assertFalse(assertNotNull(s.file.ledger?.status).isPro, "every surface reads the same answer")
    }

    @Test
    fun testATrialStartedInThePaywall() = runTest {
        val s = setup()
        open(s)
        s.play.buys(now)
        val outcome = s.store.purchase(ProPlan.YEARLY)
        assertEquals(PurchaseOutcome.Unlocked(trialStarted = true), outcome)
        assertEquals(ProPlan.YEARLY.productId to "yearly-trial", s.play.launches.single(), "the trial offer's token for an eligible person")
        val end = now.plus(Duration.ofDays(7))
        assertEquals(end, s.file.ledger?.trialEnds?.get(PlayEntitlement.trialKey(now)), "the trial's end, known on this phone")
        val status = assertNotNull(s.store.status)
        assertEquals(ProReason.TRIAL, status.reason)
        assertEquals(end, status.expiresAt)
        assertEquals("Trial · ends 4 Nov", ProCopy.statusLine(status, now, zone))
        runCurrent()
        assertEquals(listOf("token-${ProPlan.YEARLY.productId}-${now.toEpochMilli()}"), s.play.acknowledged.distinct(), "acknowledged at once")
        assertTrue(s.changes >= 1, "widgets and reminders follow")
        val state = StackState(items = listOf(com.tombaxter.taken.core.model.Item(name = "Vitamin D3", code = "VD3", frequency = com.tombaxter.taken.core.model.Frequency.Daily(1), createdAt = now, sortIndex = 0)))
        val reminder = assertNotNull(TrialReminder.planFor(s.file.ledger, state, now, zone), "the reminder's plan, for the Reminders phase")
        assertTrue(reminder.body.contains("$19.99 a year"), reminder.body)
    }

    @Test
    fun testActiveMonthlyAndYearly() = runTest {
        val monthly = setup(FakeBilling(held = listOf(FakeBilling.purchase(ProPlan.MONTHLY.productId, now))))
        open(monthly)
        assertEquals(ProReason.MONTHLY, monthly.store.status?.reason)
        assertEquals(ProAccess.PRO, access(monthly.store))
        assertEquals(ProPlan.MONTHLY, monthly.store.heldSubscription)
        assertEquals("Pro monthly · renewing", ProCopy.statusLine(monthly.store.status, now, zone))

        val yearly = setup(FakeBilling(held = listOf(FakeBilling.purchase(ProPlan.YEARLY.productId, now))))
        open(yearly)
        assertEquals(ProReason.YEARLY, yearly.store.status?.reason, "a trial bought on another phone reads as yearly here")
        assertEquals(ProAccess.PRO, access(yearly.store))
    }

    @Test
    fun testLifetime() = runTest {
        val s = setup()
        open(s)
        s.play.buys(now)
        assertEquals(PurchaseOutcome.Unlocked(trialStarted = false), s.store.purchase(ProPlan.LIFETIME))
        assertEquals(ProPlan.LIFETIME.productId to "lifetime-buy", s.play.launches.single(), "the purchase option's offer token")
        assertEquals(ProReason.LIFETIME, s.store.status?.reason)
        assertNull(s.store.status?.expiresAt, "for good")
        runCurrent()
        assertEquals(1, s.play.acknowledged.distinct().size, "a non-consumable is acknowledged, never consumed")
    }

    @Test
    fun testAPendingPurchaseGrantsNothingUntilItGoesThrough() = runTest {
        val s = setup()
        open(s)
        s.play.buys(now, state = PlayPurchase.State.PENDING)
        assertEquals(PurchaseOutcome.Pending, s.store.purchase(ProPlan.YEARLY))
        assertTrue(s.store.waitingForApproval)
        assertFalse(s.store.status?.isPro == true)
        runCurrent()
        assertTrue(s.play.acknowledged.isEmpty(), "never acknowledged while PENDING")

        // Approved later, while Taken runs: Play's listener says so.
        val approved = FakeBilling.purchase(ProPlan.YEARLY.productId, now, acknowledged = false, token = s.play.held.single().token)
        s.play.held = listOf(approved)
        s.play.deliver(PlayResponse.OK, listOf(approved))
        runCurrent()
        assertEquals(ProReason.YEARLY, s.store.status?.reason, "no trial was recorded for a purchase that waited")
        assertFalse(s.store.waitingForApproval)
        assertEquals(listOf(approved.token), s.play.acknowledged.distinct())
    }

    @Test
    fun testCancelledButStillActive() = runTest {
        val s = setup(FakeBilling(held = listOf(FakeBilling.purchase(ProPlan.YEARLY.productId, now, autoRenewing = false))))
        open(s)
        val status = assertNotNull(s.store.status)
        assertTrue(status.isPro, "Play still returns a cancelled subscription until it expires")
        assertEquals(false, status.willRenew)
        assertEquals("Pro yearly · not renewing", ProCopy.statusLine(status, now, zone))
        assertEquals(ProAccess.PRO, access(s.store))
    }

    @Test
    fun testExpiredAndRefundedPurchasesLockAtTheNextAnswer() = runTest {
        // Yesterday Play said yearly; today it returns nothing: the plan expired, or was refunded and revoked.
        val before = ProStatus(isPro = true, reason = ProReason.YEARLY, checkedAt = now.minus(Duration.ofDays(1)), expiresAt = now.plus(Duration.ofDays(2)), willRenew = true, plan = ProPlan.YEARLY)
        val s = setup(FakeBilling(held = emptyList()), ProLedger(status = before, firstSeenAt = now))
        assertEquals(ProAccess.PRO, access(s.store), "the cached answer, before Play's")
        open(s)
        assertFalse(assertNotNull(s.store.status).isPro)
        assertEquals(ProAccess.LOCKED, access(s.store))
        assertFalse(assertNotNull(s.file.ledger?.status).isPro, "pro.json follows, so widgets and the tile lock too")
        assertEquals(1, s.changes)

        val lifetime = ProStatus(isPro = true, reason = ProReason.LIFETIME, checkedAt = now)
        val refunded = setup(FakeBilling(held = emptyList()), ProLedger(status = lifetime, firstSeenAt = now))
        open(refunded)
        assertEquals(ProAccess.LOCKED, access(refunded.store), "a refunded lifetime purchase is no longer returned")
    }

    @Test
    fun testPlayUnavailableKeepsWhatWasKnown() = runTest {
        val before = ProStatus(isPro = true, reason = ProReason.MONTHLY, checkedAt = now, expiresAt = now.plus(Duration.ofDays(3)), willRenew = true, plan = ProPlan.MONTHLY)
        val s = setup(FakeBilling(connectAnswer = PlayResponse.BILLING_UNAVAILABLE), ProLedger(status = before, firstSeenAt = now))
        open(s)
        assertTrue(s.store.settled, "no wait on a Play that cannot answer")
        assertEquals(before, s.store.status, "nothing is taken away without Play's answer")
        assertEquals(OffersPhase.FAILED, s.store.offersPhase)
        assertEquals(RestoreOutcome.Failed(ProCopy.CANNOT_PAY_HERE), s.store.restore())
        assertEquals(PurchaseOutcome.Failed(ProCopy.PLANS_LOADING), s.store.purchase(ProPlan.YEARLY))

        val fresh = setup(FakeBilling(connectAnswer = PlayResponse.SERVICE_UNAVAILABLE), ProLedger(firstSeenAt = now))
        open(fresh)
        assertNull(fresh.store.status, "a new install with no answer is not Pro")
        assertEquals(ProAccess.LOCKED, access(fresh.store))
        assertEquals(RestoreOutcome.Failed(ProCopy.NO_CONNECTION), fresh.store.restore())
    }

    @Test
    fun testTheAppWaitsAtMostFourSecondsForPlay() = runTest {
        val play = FakeBilling(held = listOf(FakeBilling.purchase(ProPlan.YEARLY.productId, now)))
        play.hangConnect = CompletableDeferred()
        val s = setup(play)
        s.store.foreground()
        runCurrent()
        assertFalse(s.store.settled)
        assertEquals(ProAccess.CHECKING, access(s.store), "no lock flashes before Play answers")
        advanceTimeBy(4_001)
        assertTrue(s.store.settled, "after 4 s the cached answer stands")
        assertEquals(ProAccess.LOCKED, access(s.store))
        play.hangConnect?.complete(PlayResponse.OK)
        runCurrent()
        assertEquals(ProAccess.PRO, access(s.store), "and Play's answer still counts when it comes")
    }

    @Test
    fun testAnAnswerThatRanOutWaitsForPlayOnReturn() = runTest {
        val s = setup(FakeBilling(held = listOf(FakeBilling.purchase(ProPlan.YEARLY.productId, now))))
        open(s)
        assertEquals(ProAccess.PRO, access(s.store))
        // A week away: the cached answer has run out, but the subscription renewed.
        now = now.plus(Duration.ofDays(7))
        assertTrue(PlayEntitlement.needsCheck(s.store.status, now))
        s.store.foreground()
        assertFalse(s.store.settled)
        assertEquals(ProAccess.CHECKING, access(s.store), "a payer is never shown a lock on a guess")
        s.store.resumed()
        runCurrent()
        assertEquals(ProAccess.PRO, access(s.store))
    }

    @Test
    fun testThePurchaseFlowsOtherAnswers() = runTest {
        val s = setup()
        open(s)
        s.play.onLaunch = { _, _ -> s.play.deliver(PlayResponse.USER_CANCELED) }
        assertEquals(PurchaseOutcome.Cancelled, s.store.purchase(ProPlan.MONTHLY), "a cancelled purchase says nothing")
        s.play.onLaunch = { _, _ -> s.play.deliver(PlayResponse.NETWORK_ERROR) }
        assertEquals(PurchaseOutcome.Failed("No connection to Google Play. Try again."), s.store.purchase(ProPlan.MONTHLY))
        s.play.launchAnswer = PlayResponse.BILLING_UNAVAILABLE
        assertEquals(PurchaseOutcome.Failed(ProCopy.CANNOT_PAY_HERE), s.store.purchase(ProPlan.MONTHLY))

        // Already owned (bought on another phone a moment ago): Play is asked again and Pro comes on.
        s.play.launchAnswer = PlayResponse.ITEM_ALREADY_OWNED
        s.play.held = listOf(FakeBilling.purchase(ProPlan.MONTHLY.productId, now))
        assertEquals(PurchaseOutcome.Unlocked(trialStarted = false), s.store.purchase(ProPlan.MONTHLY))
        assertEquals(ProReason.MONTHLY, s.store.status?.reason)
    }

    @Test
    fun testATrialAlreadyUsedSellsTheYearWithoutIt() = runTest {
        val s = setup(FakeBilling(products = FakeBilling.catalog(trial = false)))
        open(s)
        assertEquals(false, s.store.introEligible)
        assertNull(s.store.offers[ProPlan.YEARLY]?.intro)
        s.play.buys(now)
        assertEquals(PurchaseOutcome.Unlocked(trialStarted = false), s.store.purchase(ProPlan.YEARLY))
        assertEquals(ProPlan.YEARLY.productId to "yearly-base", s.play.launches.single())
        assertTrue(s.file.ledger?.trialEnds.isNullOrEmpty(), "no trial, no trial end")
        assertEquals(ProReason.YEARLY, s.store.status?.reason)
    }

    @Test
    fun testAcknowledgementRetriesWithBackoff() = runTest {
        val play = FakeBilling(held = listOf(FakeBilling.purchase(ProPlan.YEARLY.productId, now, acknowledged = false, token = "t")))
        play.acknowledgeAnswers.addAll(listOf(PlayResponse.SERVICE_UNAVAILABLE, PlayResponse.NETWORK_ERROR))
        val s = setup(play)
        open(s)
        assertEquals(listOf("t"), play.acknowledged, "asked once")
        advanceTimeBy(2_001)
        assertEquals(listOf("t", "t"), play.acknowledged, "again after 2 s")
        advanceTimeBy(4_001)
        assertEquals(listOf("t", "t", "t"), play.acknowledged, "and after 4 s more")
        assertTrue(play.held.single().acknowledged)
        advanceUntilIdle()
        assertEquals(3, play.acknowledged.size, "three tries at most")
    }

    @Test
    fun testCallsMadeTogetherShareOneQuestion() = runTest {
        val s = setup()
        s.store.foreground()
        s.store.resumed()
        val again = async { s.store.refresh() }
        runCurrent()
        again.await()
        assertEquals(1, s.play.purchaseQueries, "ON_START, ON_RESUME and a refresh at once ask Play once")
    }
}
