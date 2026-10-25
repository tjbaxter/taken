package com.tombaxter.taken.core

import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.NudgeWindow
import com.tombaxter.taken.core.pro.PendingLog
import com.tombaxter.taken.core.pro.PlanPeriod
import com.tombaxter.taken.core.pro.PlanPrice
import com.tombaxter.taken.core.pro.ProAccess
import com.tombaxter.taken.core.pro.ProCopy
import com.tombaxter.taken.core.pro.ProGate
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.pro.ProLedgerCodec
import com.tombaxter.taken.core.pro.ProLedgers
import com.tombaxter.taken.core.pro.ProPendingAction
import com.tombaxter.taken.core.pro.ProPlan
import com.tombaxter.taken.core.pro.ProReason
import com.tombaxter.taken.core.pro.ProRoute
import com.tombaxter.taken.core.pro.ProStatus
import com.tombaxter.taken.core.pro.TrialReminderMark
import com.tombaxter.taken.core.reminders.Reminders
import com.tombaxter.taken.core.stack.logDose
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/ProGateTests.swift: the first dose needs no Pro, the log stays readable without it, and every
 * surface reads the same cached answer. Left out: `testALogFrom10IsNeverLockedOnAGuess` (no Android 1.0 users). Rewritten
 * against the Android fact: a missing ledger reads as not legacy (SPEC-ANDROID 5.2), and the ledger's file round trip is
 * its codec here (the DataStore file is :app's StoreTests).
 */
class ProGateTests {

    private val now = at(2026, 10, 13, 9)
    private val pro get() = ProStatus(isPro = true, reason = ProReason.YEARLY, checkedAt = now, expiresAt = at(2027, 10, 13, 9), willRenew = true)
    private val notPro get() = ProStatus.notPro(checkedAt = now)

    private fun access(status: ProStatus?, settled: Boolean = true, legacy: Boolean = false, logged: Boolean = true): ProAccess =
        ProGate.access(status, settled, legacyLog = legacy, hasLogged = logged, now = now)

    @Test
    fun testTheFirstDoseNeedsNoPro() {
        assertEquals(ProAccess.FIRST_SESSION, access(null, logged = false), "first run: add the stack, tap the first dose")
        assertEquals(ProAccess.FIRST_SESSION, access(notPro, logged = false))
        assertEquals(ProAccess.FIRST_SESSION, access(null, settled = false, logged = false), "never waits on the store for it")
        assertTrue(ProAccess.FIRST_SESSION.allowsLogging)
    }

    @Test
    fun testAfterTheFirstDoseLoggingNeedsPro() {
        assertEquals(ProAccess.LOCKED, access(notPro))
        assertFalse(ProAccess.LOCKED.allowsLogging)
        assertEquals(ProAccess.LOCKED, access(null), "a missing cache counts as not Pro")
        assertEquals(ProAccess.PRO, access(pro))
        assertTrue(ProAccess.PRO.allowsLogging)
    }

    private val loggedState: StackState
        get() {
            val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 1, 8))
            val state = StackState(items = listOf(vd3))
            state.logDose(vd3.id, at(2026, 10, 12, 8), london)
            return state
        }

    @Test
    fun testCachedProHoldsUntilItExpires() {
        // A renewing plan whose period ended an hour ago: the renewal is on its way, and only the app can see it.
        val renewing = pro.copy(expiresAt = at(2026, 10, 13, 8))
        assertEquals(ProAccess.PRO, access(renewing), "a payer is never locked out at a renewal")
        assertEquals(
            ProAccess.PRO,
            ProGate.access(ProLedger(status = renewing, firstSeenAt = now), loggedState, now),
            "widgets, the tile and the nudge too",
        )
        val lapsed = renewing.copy(expiresAt = now.minus(ProStatus.renewalMargin).minusSeconds(60))
        assertEquals(ProAccess.LOCKED, access(lapsed), "the margin is capped")
        assertEquals(ProAccess.CHECKING, access(lapsed, settled = false), "the app asks the store before it shows the lock")

        val cancelled = renewing.copy(willRenew = false)
        assertEquals(ProAccess.LOCKED, access(cancelled), "a plan set not to renew ends on time")
        val billing = renewing.copy(billingIssue = true)
        assertEquals(ProAccess.LOCKED, access(billing), "a billing issue ends on time")
        assertEquals(
            ProAccess.PRO,
            access(ProStatus(isPro = true, reason = ProReason.LIFETIME, checkedAt = at(2020, 1, 1, 0))),
            "lifetime never expires",
        )
    }

    @Test
    fun testTheFirstSessionEndsWithTheFirstDoseEver() {
        // Erasing the log or deleting items after the first dose never opens logging again without Pro.
        val created = at(2026, 10, 1, 8)
        val erased = StackState(items = listOf(makeItem("Vitamin D3", "VD3", created = created)))
        var ledger = ProLedger(status = notPro, firstSeenAt = created)
        assertEquals(ProAccess.FIRST_SESSION, ProGate.access(ledger, erased, now), "nothing logged yet")
        ledger = ledger.copy(firstDoseAt = at(2026, 10, 2, 8))
        assertEquals(ProAccess.LOCKED, ProGate.access(ledger, erased, now), "the log was erased afterwards")
        assertEquals(ProAccess.LOCKED, ProGate.access(ledger, StackState(), now), "every item deleted")
        assertTrue(ProGate.hasLogged(StackState(), ledger))
        assertTrue(ProGate.hasLogged(loggedState, null))
        assertFalse(ProGate.hasLogged(erased, null))
        ledger = ledger.copy(status = pro)
        assertEquals(ProAccess.PRO, ProGate.access(ledger, erased, now))
    }

    @Test
    fun testTheFirstDoseIsRecordedOnceInTheLedger() {
        assertNull(ProLedgers.noteFirstDose(null, now), "never creates the ledger")
        var ledger = ProLedgers.noteFirstDose(ProLedger(firstSeenAt = now), now)
        assertEquals(now, ledger?.firstDoseAt)
        ledger = ProLedgers.noteFirstDose(ledger, at(2026, 10, 20, 9))
        assertEquals(now, ledger?.firstDoseAt, "the first one stays")
        val written = ProLedger(firstSeenAt = now, firstDoseAt = now)
        assertEquals(written, ProLedgerCodec.decode(ProLedgerCodec.encode(written)), "round trip")
    }

    @Test
    fun testTheAppWaitsForTheStoreBeforeLocking() {
        assertEquals(ProAccess.CHECKING, access(null, settled = false), "no lock flashes before the store answers")
        assertEquals(ProAccess.CHECKING, access(notPro, settled = false), "a stale no may have renewed since")
        assertFalse(ProAccess.CHECKING.allowsLogging)
        assertEquals(ProAccess.PRO, access(pro, settled = false))
    }

    @Test
    fun testWidgetsAndTheTileReadTheLedger() {
        val created = at(2026, 10, 1, 8)
        val vd3 = makeItem("Vitamin D3", "VD3", created = created)
        val state = StackState(items = listOf(vd3))
        assertEquals(ProAccess.FIRST_SESSION, ProGate.access(null, state, now))
        val ledger = ProLedger(status = notPro, firstSeenAt = created)
        assertEquals(ProAccess.FIRST_SESSION, ProGate.access(ledger, state, now))

        state.logDose(vd3.id, at(2026, 10, 12, 8), london)
        assertEquals(ProAccess.LOCKED, ProGate.access(ledger, state, now))
        assertEquals(ProAccess.PRO, ProGate.access(ProLedger(status = pro, firstSeenAt = created), state, now))
        assertEquals(
            ProAccess.LOCKED,
            ProGate.access(null, state, now),
            "no ledger yet reads as not legacy on Android: there is no 1.0 log to protect",
        )
        assertEquals(ProAccess.LOCKED, ProGate.access(ProLedger(firstSeenAt = created), state, now), "a new install whose check is still open is not Pro")
    }

    @Test
    fun testNudgesFollowPro() {
        assertEquals(NudgeWindow.Closed, ProGate.nudgeWindow(ProAccess.LOCKED, notPro))
        assertEquals(NudgeWindow.Open, ProGate.nudgeWindow(ProAccess.PRO, pro), "a renewing plan keeps its nudges")
        assertEquals(NudgeWindow.Open, ProGate.nudgeWindow(ProAccess.FIRST_SESSION, null))
        // Android: a paid plan's expiresAt is only a check horizon, not the end of the period paid for, so a cancelled
        // plan keeps its nudges; the rebuild asks Play once the horizon has passed (SPEC-ANDROID 9.4).
        val cancelled = pro.copy(willRenew = false)
        assertEquals(NudgeWindow.Open, ProGate.nudgeWindow(ProAccess.PRO, cancelled), "a cancelled paid plan is nudged until Play says it ended")
        // A trial's end is recorded on this phone when it is bought: real, so its nudges stop then.
        val cancelledTrial = cancelled.copy(reason = ProReason.TRIAL)
        assertEquals(NudgeWindow.Until(at(2027, 10, 13, 9)), ProGate.nudgeWindow(ProAccess.PRO, cancelledTrial))
        assertEquals(NudgeWindow.Until(cancelledTrial.activeUntil!!), ProGate.nudgeWindow(ProAccess.PRO, cancelledTrial), "nudges stop when a cancelled trial does")
        assertEquals(
            NudgeWindow.Open,
            ProGate.nudgeWindow(ProAccess.PRO, ProStatus(isPro = true, reason = ProReason.LIFETIME, checkedAt = now)),
        )
    }

    @Test
    fun testNoNudgesWhenLockedAndNoneAfterACancelledPlanEnds() {
        val created = at(2026, 10, 1, 8)
        val state = StackState(items = listOf(makeItem("Vitamin D3", "VD3", created = created)))
        state.settings.reminderEnabled = true
        state.settings.reminderMinutes = 21 * 60
        assertEquals(14, Reminders.plan(state, now, london, NudgeWindow.Open).size)
        assertTrue(Reminders.plan(state, now, london, NudgeWindow.Closed).isEmpty())
        val ends = at(2026, 10, 16, 12)
        val plans = Reminders.plan(state, now, london, NudgeWindow.Until(ends))
        assertEquals(listOf(13, 14, 15).map { DayKey(2026, 10, it) }, plans.map { it.day }, "nudges up to the day the plan ends")
        assertTrue(plans.all { it.fireDate < ends })
    }

    @Test
    fun testLockedNoteIsWithdrawnLikeTheStaleOne() {
        val withdrawn = Reminders.staleDelivered(listOf("other", Reminders.LOCKED_IDENTIFIER), StackState(), now, london)
        assertEquals(listOf(Reminders.LOCKED_IDENTIFIER), withdrawn)
    }

    @Test
    fun testLedgerRoundTripThroughTheFile() {
        val id = UUID.fromString("6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F")
        val status = ProStatus(isPro = true, reason = ProReason.TRIAL, checkedAt = now, expiresAt = at(2026, 10, 20, 9), willRenew = true, plan = ProPlan.YEARLY)
        val ledger = ProLedgers.recordPending(ProLedger(status = status, firstSeenAt = now), ProPendingAction.Log(id), now)!!.copy(
            prices = mapOf(ProPlan.YEARLY.productId to PlanPrice("$19.99", PlanPeriod(1, PlanPeriod.PeriodUnit.YEAR))),
            trialReminder = TrialReminderMark(trialEnd = at(2026, 10, 20, 9), fireAt = at(2026, 10, 17, 9)),
            trialEnds = mapOf("1791000000000" to at(2026, 10, 20, 9)),
        )
        val text = ProLedgerCodec.encode(ledger)
        val reread = ProLedgerCodec.decode(text)
        assertEquals(ledger, reread, "the widget and the tile read what the app wrote")
        assertEquals(PendingLog(ProPendingAction.Log(id), now), reread.pending)
        assertTrue(text.contains("\"log\":{\"_0\":\"6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F\"}"), "Swift's enum shape: $text")
        assertTrue(text.contains("\"legacyLog\":false"), "always written false on Android: $text")
        val takeAll = ProLedgers.recordPending(ProLedger(firstSeenAt = now), ProPendingAction.TakeAll, now)!!
        assertTrue(ProLedgerCodec.encode(takeAll).contains("\"takeAll\":{}"))
        assertEquals(takeAll, ProLedgerCodec.decode(ProLedgerCodec.encode(takeAll)))
    }

    @Test
    fun testLedgerDecodesWithMissingKeys() {
        val json = """{"firstSeenAt":1791000000,"status":{"isPro":true,"reason":"founding","checkedAt":1791000000}}"""
        val ledger = ProLedgerCodec.decode(json)
        assertEquals(ProReason.FOUNDING, ledger.status?.reason)
        assertNull(ledger.status?.expiresAt)
        assertEquals(false, ledger.status?.billingIssue)
        assertFalse(ledger.legacyLog)
        assertNull(ledger.pending)
        assertNull(ledger.firstDoseAt, "a ledger from before the first dose was recorded")
        assertEquals(false, ledger.status?.renewingSubscription)
        val unknown = """{"firstSeenAt":1791000000,"status":{"isPro":false,"reason":"someday","checkedAt":1791000000}}"""
        assertEquals(ProReason.NONE, ProLedgerCodec.decode(unknown).status?.reason, "a reason from a later version reads as none")
        assertEquals(Instant.ofEpochSecond(1_791_000_000), ledger.firstSeenAt)
    }

    @Test
    fun testProRouteURLs() {
        assertEquals("taken://pro", ProRoute().url)
        assertEquals("taken://pro?then=take-all", ProRoute(ProPendingAction.TakeAll).url)
        val id = UUID.fromString("6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F")
        val log = ProRoute(ProPendingAction.Log(id))
        assertEquals("taken://pro?then=log&item=6F1C2D3E-4A5B-4C6D-8E9F-0A1B2C3D4E5F", log.url)
        assertEquals(log, ProRoute.parse(log.url))
        assertEquals(ProPendingAction.TakeAll, ProRoute.parse("taken://pro?then=take-all")?.then)
        assertEquals(ProRoute(), ProRoute.parse("taken://pro"))
        assertNull(ProRoute.parse("taken://pro?then=log&item=nope")?.then)
        assertNull(ProRoute.parse("taken://today"))
        assertNull(ProRoute.parse("https://pro"))
    }

    /** The locked bar's three lines (ProCopyTests' locked bar case; the rest of ProCopy is NEXT 2). */
    @Test
    fun testTheLockedBarSaysWhatATapOpens() {
        val week = com.tombaxter.taken.core.pro.IntroTerms(
            com.tombaxter.taken.core.pro.IntroTerms.Mode.ON_US, PlanPeriod(1, PlanPeriod.PeriodUnit.WEEK), 1, "$0.00",
        )
        assertEquals("Start 7 days on us", ProCopy.lockedBar(eligible = true, intro = week))
        assertEquals("Pro ended. Tap to continue", ProCopy.lockedBar(eligible = false, intro = week))
        assertEquals("Taken Pro. Tap to continue", ProCopy.lockedBar(eligible = null, intro = null))
        for (line in listOf("Start 7 days on us", "Pro ended. Tap to continue", "Taken Pro. Tap to continue")) assertCopyRules(line)
    }
}
