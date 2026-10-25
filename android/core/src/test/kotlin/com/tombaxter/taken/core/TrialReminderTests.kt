package com.tombaxter.taken.core

import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.model.StackSettings
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.model.StackCodec
import com.tombaxter.taken.core.pro.Entitlement
import com.tombaxter.taken.core.pro.IntroTerms
import com.tombaxter.taken.core.pro.PlanOffer
import com.tombaxter.taken.core.pro.PlanPeriod
import com.tombaxter.taken.core.pro.PlanPeriod.PeriodUnit
import com.tombaxter.taken.core.pro.PlanPrice
import com.tombaxter.taken.core.pro.ProCopy
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.pro.ProLedgerCodec
import com.tombaxter.taken.core.pro.ProPlan
import com.tombaxter.taken.core.pro.ProReason
import com.tombaxter.taken.core.pro.ProStatus
import com.tombaxter.taken.core.pro.PurchaseFact
import com.tombaxter.taken.core.pro.TrialReminderMark
import com.tombaxter.taken.core.reminders.NotificationPermission
import com.tombaxter.taken.core.reminders.Reminders
import com.tombaxter.taken.core.reminders.TrialAsk
import com.tombaxter.taken.core.reminders.TrialReminder
import com.tombaxter.taken.core.retention.TodayPrompt
import com.tombaxter.taken.core.retention.TodayPrompts
import com.tombaxter.taken.core.stack.StackEngine
import com.tombaxter.taken.core.stack.eraseAll
import com.tombaxter.taken.core.stack.logDose
import java.math.BigDecimal
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/TrialReminderTests.swift: the one reminder before a trial ends, on the day the paywall promised,
 * at least 72 hours before the end, at the nudge time or 10:00, with the end date, the price, what was logged and how to
 * cancel; never twice; withdrawn when the trial is cancelled, converts, hits a billing issue, Pro is for good or Profile's
 * Trial reminder is off. London clock. The words are Android's (how to cancel in Google Play, SPEC-ANDROID 6.4). Left out:
 * the ask's orchestration around sheets and voice notes (the iPhone's AppModel), which the Reminders phase builds with the
 * Android sheet (SPEC-ANDROID 10.4); its rules are here.
 */
class TrialReminderTests {
    private val yearlyPrice = PlanPrice("$19.99", PlanPeriod(1, PeriodUnit.YEAR))
    private val monthlyPrice = PlanPrice("$3.99", PlanPeriod(1, PeriodUnit.MONTH))

    /** A yearly trial that started Wed 28 Oct and ends Wed 4 Nov 2026 at 09:14 in London. */
    private fun trial(
        willRenew: Boolean? = true,
        reason: ProReason = ProReason.TRIAL,
        billingIssue: Boolean = false,
        ends: Instant? = null,
        renewsTo: ProPlan? = null,
    ) = ProStatus(
        isPro = true, reason = reason, checkedAt = at(2026, 10, 28, 9, 14), expiresAt = ends ?: at(2026, 11, 4, 9, 14),
        willRenew = willRenew, billingIssue = billingIssue, plan = ProPlan.YEARLY, renewsTo = renewsTo,
    )

    private fun logged(count: Int, nudge: Boolean = false): StackState {
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 28, 9))
        val state = StackState(items = listOf(vd3))
        for (index in 0 until count) state.logDose(vd3.id, at(2026, 10, 28, 10).plusSeconds(index * 3600L), london)
        state.settings.reminderEnabled = nudge
        return state
    }

    private fun plan(
        status: ProStatus?,
        state: StackState,
        now: Instant = at(2026, 10, 28, 9, 20),
        price: PlanPrice? = null,
        sent: TrialReminderMark? = null,
    ): TrialReminder.Plan? = TrialReminder.plan(status, price ?: yearlyPrice, state, now, london, sent)

    private fun daysBetween(start: Instant, end: Instant): Long =
        ChronoUnit.DAYS.between(start.atZone(london).toLocalDate(), end.atZone(london).toLocalDate())

    // MARK: When

    @Test
    fun testTheReminderComesOnDayFourAtLeast72HoursBeforeTheEndWhileTheNudgeIsOff() {
        val reminder = assertNotNull(plan(trial(), logged(12)))
        assertEquals(at(2026, 11, 1, 9, 14), reminder.fireAt, "Sunday, day 4: 10:00 would be under 72 hours before Wednesday 09:14, so 09:14")
        assertTrue(Duration.between(reminder.fireAt, at(2026, 11, 4, 9, 14)) >= Duration.ofHours(72))
        assertEquals(1, reminder.at.dayOfMonth)
        assertEquals(9, reminder.at.hour)
        assertEquals(14, reminder.at.minute)
        assertEquals(london, reminder.at.zone)

        val afternoon = assertNotNull(plan(trial(ends = at(2026, 11, 4, 15, 30)), logged(12)))
        assertEquals(at(2026, 11, 1, 10, 0), afternoon.fireAt, "a trial started at 15:30: day 4 at 10:00")
        val exactly = assertNotNull(plan(trial(ends = at(2026, 11, 4, 10, 0)), logged(12)))
        assertEquals(at(2026, 11, 1, 10, 0), exactly.fireAt, "exactly 72 hours counts as at least 72 hours")
        val seconds = assertNotNull(plan(trial(ends = at(2026, 11, 4, 9, 14).plusSeconds(42)), logged(12)))
        assertEquals(at(2026, 11, 1, 9, 14), seconds.fireAt, "down to the minute, never under 72 hours")
    }

    @Test
    fun testTheReminderComesAtTheNudgeTimeWhileTheNudgeIsOn() {
        val nudged = logged(12, nudge = true)
        assertEquals(20 * 60, nudged.settings.reminderMinutes)
        assertEquals(at(2026, 11, 1, 9, 14), assertNotNull(plan(trial(), nudged)).fireAt, "day 4 still: Sunday at 20:00 is under 72 hours")
        assertEquals(at(2026, 11, 1, 20, 0), assertNotNull(plan(trial(ends = at(2026, 11, 4, 21, 0)), nudged)).fireAt, "a trial started at 21:00: day 4 at the nudge time")
        nudged.settings.reminderMinutes = 7 * 60 + 30
        assertEquals(at(2026, 11, 1, 7, 30), assertNotNull(plan(trial(), nudged)).fireAt, "a morning nudge: day 4")
        nudged.settings.reminderEnabled = false
        assertEquals(at(2026, 11, 1, 10, 0), assertNotNull(plan(trial(ends = at(2026, 11, 4, 21, 0)), nudged)).fireAt, "the nudge turned off: 10:00 again")
    }

    @Test
    fun testTheReminderKeepsTheDayThePaywallPromised() {
        val week = IntroTerms(IntroTerms.Mode.ON_US, PlanPeriod(1, PeriodUnit.WEEK), 1, "$0.00")
        val offer = PlanOffer(ProPlan.YEARLY, "$19.99", BigDecimal("19.99"), "USD", Locale.US, PlanPeriod(1, PeriodUnit.YEAR), week)
        val starts = listOf(
            Triple(9, 14, true), Triple(9, 14, false), Triple(8, 30, false), Triple(8, 30, true), Triple(15, 30, false),
            Triple(15, 30, true), Triple(21, 0, true), Triple(23, 40, false), Triple(7, 5, true),
        )
        for ((hour, minute, nudge) in starts) {
            val start = at(2026, 10, 28, hour, minute)
            val promised = assertNotNull(ProCopy.trialTimeline(offer, eligible = true, now = start, zone = london).firstOrNull { it.text == "we remind you" }?.day)
            val end = start.plus(Duration.ofDays(7))
            val reminder = assertNotNull(plan(trial(ends = end), logged(1, nudge), now = start.plusSeconds(60)))
            assertEquals(promised, "Day ${daysBetween(start, reminder.fireAt)}", "started $hour:$minute, nudge ${if (nudge) "on" else "off"}")
            assertTrue(Duration.between(reminder.fireAt, end) >= Duration.ofHours(72))
        }
        // A 4-day trial started at 09:14: day 1 at 09:14, as its timeline says.
        val start = at(2026, 10, 28, 9, 14)
        val four = assertNotNull(plan(trial(ends = start.plus(Duration.ofDays(4))), logged(1), now = start.plusSeconds(60)))
        assertEquals(at(2026, 10, 29, 9, 14), four.fireAt)
    }

    @Test
    fun testANightTimeStartMovesTheReminderToTheEveningBeforeNeverIntoTheNight() {
        val start = at(2026, 10, 28, 2, 30)
        val end = start.plus(Duration.ofDays(7))
        val off = assertNotNull(plan(trial(ends = end), logged(1), now = start.plusSeconds(60)))
        assertEquals(at(2026, 10, 31, 10, 0), off.fireAt, "day 3 at 10:00: earlier than the promise, never later")
        val on = assertNotNull(plan(trial(ends = end), logged(1, nudge = true), now = start.plusSeconds(60)))
        assertEquals(at(2026, 10, 31, 20, 0), on.fireAt, "day 3 at the nudge time")
        val early = logged(1)
        early.settings.wakeMinutes = 2 * 60
        assertEquals(at(2026, 11, 1, 2, 30), assertNotNull(plan(trial(ends = end), early, now = start.plusSeconds(60))).fireAt, "someone up at 02:00")
    }

    @Test
    fun testTheReminderCountsHoursAcrossAClockChange() {
        // Ends Sun 25 Oct 2026 at 09:14 GMT; the clocks go back that night. Thu 22 Oct at 10:00 BST is 72 h 14 min before.
        val status = trial(ends = at(2026, 10, 25, 9, 14))
        val reminder = assertNotNull(plan(status, logged(3), now = at(2026, 10, 18, 9, 20)))
        assertEquals(at(2026, 10, 22, 10, 0), reminder.fireAt)
        assertTrue(Duration.between(reminder.fireAt, at(2026, 10, 25, 9, 14)) >= Duration.ofHours(72))
    }

    @Test
    fun testATrialShorterThanFourDaysGetsNoReminder() {
        val start = at(2026, 10, 28, 9, 14)
        for (days in listOf(1L, 2L, 3L)) {
            val short = trial(ends = start.plus(Duration.ofDays(days)))
            assertNull(plan(short, logged(1), now = start), "$days days")
            assertNull(plan(short, logged(1), now = start.plusSeconds(60)), "$days days")
            assertNull(plan(short, logged(1, nudge = true), now = start.plusSeconds(60)), "$days days, nudge on")
        }
        assertNotNull(plan(trial(ends = start.plus(Duration.ofDays(4)).plusSeconds(3600)), logged(1), now = start.plusSeconds(60)), "a little over 4 days: one reminder")
    }

    @Test
    fun testNeverLateAndAtMostOne() {
        val state = logged(12)
        assertNull(plan(trial(), state, now = at(2026, 11, 1, 9, 15)), "the moment has passed: never late")
        assertNull(plan(trial(), state, now = at(2026, 11, 3, 10)))
        assertNull(plan(trial(), state, now = at(2026, 11, 4, 10)), "after the end")
        assertEquals("taken.pro.trial-end", TrialReminder.IDENTIFIER, "one identifier: at most one")
        assertFalse(TrialReminder.IDENTIFIER.startsWith(Reminders.REQUEST_PREFIX))
    }

    @Test
    fun testOnceItHasGoneOutItNeverComesAgain() {
        val end = at(2026, 11, 4, 21, 0)
        val first = assertNotNull(plan(trial(ends = end), logged(2), now = at(2026, 10, 29, 9)))
        assertEquals(at(2026, 11, 1, 10, 0), first.fireAt)
        val sent = assertNotNull(TrialReminder.nextMark(first, end, previous = null, now = at(2026, 10, 29, 9)))
        assertEquals(TrialReminderMark(trialEnd = end, fireAt = at(2026, 11, 1, 10, 0)), sent)

        val noon = at(2026, 11, 1, 12, 0)
        assertNotNull(plan(trial(ends = end), logged(2, nudge = true), now = noon), "without the record: a second one")
        assertNull(plan(trial(ends = end), logged(2, nudge = true), now = noon, sent = sent), "with it: it has gone out, so never again")
        assertEquals(sent, TrialReminder.nextMark(null, end, previous = sent, now = noon), "kept once gone out")

        val before = at(2026, 10, 30, 12, 0)
        val moved = assertNotNull(plan(trial(ends = end), logged(2, nudge = true), now = before, sent = sent))
        assertEquals(at(2026, 11, 1, 20, 0), moved.fireAt)
        assertEquals(TrialReminderMark(trialEnd = end, fireAt = at(2026, 11, 1, 20, 0)), TrialReminder.nextMark(moved, end, previous = sent, now = before))
        assertNull(TrialReminder.nextMark(null, end, previous = sent, now = before), "a pending one withdrawn without a replacement is forgotten")
        assertNotNull(plan(trial(ends = at(2026, 11, 6, 21, 0)), logged(2), now = noon, sent = sent), "a record for another trial's end blocks nothing")
    }

    // MARK: Withdrawn

    @Test
    fun testTheReminderGoesWhenTheTrialIsCancelledConvertsOrIsForGood() {
        val now = at(2026, 10, 28, 9, 20)
        val state = logged(12)
        assertNotNull(plan(trial(), state, now = now))
        assertNull(plan(trial(willRenew = false), state, now = now), "auto-renew off: no reminder")
        assertNotNull(plan(trial(willRenew = null), state, now = now), "Play did not say: still a trial set to renew")
        assertNull(plan(trial(reason = ProReason.YEARLY), state, now = now), "converted: no reminder")
        assertNull(plan(trial(billingIssue = true), state, now = now), "a billing issue: no reminder")
        assertNull(plan(ProStatus(isPro = true, reason = ProReason.LIFETIME, checkedAt = now), state, now = now), "lifetime")
        assertNull(plan(ProStatus.notPro(now), state, now = now))
        assertNull(plan(null, state, now = now))

        assertTrue(TrialReminder.isRenewingTrial(trial(), now))
        for (status in listOf(trial(willRenew = false), trial(reason = ProReason.YEARLY), trial(billingIssue = true))) {
            assertFalse(TrialReminder.isRenewingTrial(status, now), "a delivered reminder is withdrawn too")
        }
        assertFalse(TrialReminder.isRenewingTrial(trial(), at(2026, 11, 4, 9, 15)), "the trial is over")
    }

    @Test
    fun testProfilesTrialReminderSwitchTurnsItOff() {
        val state = logged(12, nudge = true)
        assertTrue(state.settings.trialReminderEnabled, "on unless turned off")
        assertNotNull(plan(trial(), state))
        state.settings.trialReminderEnabled = false
        assertNull(plan(trial(), state), "the switch off: no reminder")
        assertNull(TrialReminder.notice(trial(), yearlyPrice, state, at(2026, 11, 2, 9), london), "and no line on Today")
        state.settings.reminderEnabled = false
        assertNull(plan(trial(), state), "whatever the nudge")

        // Old files read as on; it is written only once turned off.
        val old = StackCodec.decode("""{"items":[],"doses":[],"settings":{"reminderEnabled":true}}""")
        assertTrue(old.settings.trialReminderEnabled)
        assertFalse(StackCodec.encode(StackState()).contains("trialReminderEnabled"))
        val off = StackState(settings = StackSettings(trialReminderEnabled = false))
        assertFalse(StackCodec.decode(StackCodec.encode(off)).settings.trialReminderEnabled)
        off.eraseAll()
        assertTrue(off.settings.trialReminderEnabled, "Erase all data puts it back to on with the other settings")
    }

    @Test
    fun testTheEntitlementRuleKeepsThePlanForThePrice() {
        val now = at(2026, 10, 28, 9, 20)
        val fact = PurchaseFact(ProPlan.YEARLY.productId, expiresAt = at(2026, 11, 4, 9, 14), isIntroOffer = true, willRenew = true)
        val status = Entitlement.evaluate(listOf(fact), now)
        assertEquals(ProReason.TRIAL, status.reason)
        assertEquals(ProPlan.YEARLY, status.plan)
        val prices = mapOf(ProPlan.YEARLY.productId to yearlyPrice, ProPlan.MONTHLY.productId to monthlyPrice)
        assertEquals(yearlyPrice, ProLedger(status = status, firstSeenAt = now, prices = prices).renewalPrice, "the trial's own plan's price")
        assertNull(ProLedger(status = status, firstSeenAt = now).renewalPrice, "no price until Play has given one")
        assertNull(Entitlement.evaluate(listOf(PurchaseFact(ProPlan.LIFETIME.productId)), now).plan)
    }

    @Test
    fun testATrialSwitchedToMonthlyNamesTheMonthlyPrice() {
        // On Play a change of plan waiting for the renewal shows as the purchase's PendingPurchaseUpdate.
        val now = at(2026, 10, 28, 9, 20)
        val fact = PurchaseFact(
            ProPlan.YEARLY.productId, expiresAt = at(2026, 11, 4, 9, 14), isIntroOffer = true, willRenew = true,
            renewsTo = ProPlan.MONTHLY.productId,
        )
        val status = Entitlement.evaluate(listOf(fact), now)
        assertEquals(ProPlan.YEARLY, status.plan)
        assertEquals(ProPlan.MONTHLY, status.renewsTo)
        val prices = mapOf(ProPlan.YEARLY.productId to yearlyPrice, ProPlan.MONTHLY.productId to monthlyPrice)
        val ledger = ProLedger(status = status, firstSeenAt = now, prices = prices)
        assertEquals(monthlyPrice, ledger.renewalPrice)
        val reminder = assertNotNull(TrialReminder.plan(status, ledger.renewalPrice, logged(0), now, london))
        assertEquals(
            "Your Taken trial ends Wednesday 4 Nov. Unless cancelled, it then renews at $3.99 a month. Cancel before then in Google Play > Subscriptions.",
            reminder.body,
        )
        val odd = fact.copy(renewsTo = ProPlan.LIFETIME.productId)
        assertNull(Entitlement.evaluate(listOf(odd), now).renewsTo, "only a subscription renews")
        assertFalse(status.sameEntitlement(Entitlement.evaluate(listOf(fact.copy(renewsTo = null)), now)), "a switch counts as a change")
    }

    @Test
    fun testTheLedgerKeepsThePricesTheAskAndTheReminder() {
        val now = at(2026, 10, 28, 9, 20)
        val mark = TrialReminderMark(trialEnd = at(2026, 11, 4, 9, 14), fireAt = at(2026, 11, 1, 9, 14))
        val ledger = ProLedger(
            status = trial(renewsTo = ProPlan.MONTHLY), firstSeenAt = now,
            prices = mapOf(ProPlan.YEARLY.productId to yearlyPrice), trialAskAt = now, trialReminder = mark,
        )
        val again = ProLedgerCodec.decode(ProLedgerCodec.encode(ledger))
        assertEquals(ledger, again, "round trip")
        assertEquals(ProPlan.YEARLY, again.status?.plan)
        assertEquals(ProPlan.MONTHLY, again.status?.renewsTo)
        assertEquals(mark, again.trialReminder)

        val before = """{"firstSeenAt":1791000000,"legacyLog":false,"status":{"isPro":true,"reason":"trial","checkedAt":1791000000,"expiresAt":1791600000,"willRenew":true}}"""
        val old = ProLedgerCodec.decode(before)
        assertNull(old.status?.plan, "a file from before this build")
        assertNull(old.status?.renewsTo)
        assertEquals(emptyMap(), old.prices)
        assertNull(old.trialAskAt)
        assertNull(old.trialReminder)
        assertNull(old.renewalPrice)
        val later = """{"firstSeenAt":1791000000,"status":{"isPro":true,"reason":"trial","checkedAt":1791000000,"plan":"weekly","renewsTo":"weekly"}}"""
        assertNull(ProLedgerCodec.decode(later).status?.plan, "a plan from a later version")
        assertNull(ProLedgerCodec.decode(later).status?.renewsTo)
        assertEquals(ProReason.TRIAL, ProLedgerCodec.decode(later).status?.reason, "and the rest still reads")
    }

    // MARK: What it says

    @Test
    fun testTheReminderSaysTheEndThePriceWhatWasLoggedAndHowToCancel() {
        val cancel = "Cancel before then in Google Play > Subscriptions."
        assertEquals(
            "Your Taken trial ends Wednesday 4 Nov. Unless cancelled, it then renews at $19.99 a year. 12 doses logged so far. $cancel",
            assertNotNull(plan(trial(), logged(12))).body,
        )
        assertEquals(
            "Your Taken trial ends Sunday 1 Nov. Unless cancelled, it then renews at $19.99 a year. 12 doses logged so far. $cancel",
            TrialReminder.body(at(2026, 11, 1, 9), yearlyPrice, 12, london),
        )
        assertEquals(
            "Your Taken trial ends Sunday 1 Nov. Unless cancelled, it then renews at $19.99 a year. 1 dose logged so far. $cancel",
            TrialReminder.body(at(2026, 11, 1, 9), yearlyPrice, 1, london),
        )
        assertEquals(
            "Your Taken trial ends Sunday 1 Nov. Unless cancelled, it then renews at $19.99 a year. $cancel",
            TrialReminder.body(at(2026, 11, 1, 9), yearlyPrice, 0, london),
        )
        assertEquals(
            "Your Taken trial ends Sunday 1 Nov. Unless cancelled, it then renews. 2 doses logged so far. $cancel",
            TrialReminder.body(at(2026, 11, 1, 9), null, 2, london),
            "no price until Play has given one: never made up",
        )
        val pounds = PlanPrice("£19.99", PlanPeriod(1, PeriodUnit.YEAR))
        assertEquals(
            "Your Taken trial ends Sunday 1 Nov. Unless cancelled, it then renews at £19.99 a year. $cancel",
            TrialReminder.body(at(2026, 11, 1, 9), pounds, 0, london),
            "the storefront's own price",
        )
        assertEquals(
            "Your Taken trial ends Monday 2 Nov. Unless cancelled, it then renews at $19.99 a year. $cancel",
            TrialReminder.body(at(2026, 11, 1, 18), yearlyPrice, 0, ZoneId.of("Asia/Tokyo")),
            "the day and date where the phone is",
        )
    }

    @Test
    fun testTheTrialCopyKeepsTheRules() {
        val lines = ArrayList(TrialAsk.all)
        for (doses in listOf(0, 1, 12)) {
            lines.add(TrialReminder.body(at(2026, 11, 1, 9), yearlyPrice, doses, london))
            lines.add(TrialReminder.body(at(2026, 11, 1, 9), null, doses, london))
        }
        for (text in lines) {
            assertCopyRules(text)
            for (sales in listOf("discount", "% off", "offer", "hurry", "last chance", "don't miss", "save ")) {
                assertFalse(text.lowercase().contains(sales), "no sales copy: $text")
            }
        }
        assertEquals("Continue", TrialAsk.ALLOW, "a pre-prompt button titled like Continue")
        assertNotEquals("Allow", TrialAsk.ALLOW)
        assertEquals("Not now", TrialAsk.NOT_NOW, "Android: always a way out of an educational screen")
        assertEquals("Get the evening nudge and a heads-up 3 days before your trial ends.", TrialAsk.BODY)
        assertEquals("Cancel before then in Google Play > Subscriptions.", TrialReminder.HOW_TO_CANCEL, "Play's own place to cancel")
    }

    // MARK: Today's line while notifications cannot carry it

    @Test
    fun testTodayCarriesTheReminderWhileNotificationsCannot() {
        val state = logged(12)
        fun notice(status: ProStatus?, now: Instant, state: StackState) = TrialReminder.notice(status, yearlyPrice, state, now, london)
        assertNull(notice(trial(), at(2026, 11, 1, 9, 13), state), "not before the reminder's own moment")
        assertEquals(
            "Your Taken trial ends Wednesday 4 Nov. Unless cancelled, it then renews at $19.99 a year. 12 doses logged so far. Cancel before then in Google Play > Subscriptions.",
            notice(trial(), at(2026, 11, 1, 9, 14), state),
            "the reminder's own words",
        )
        assertNotNull(notice(trial(), at(2026, 11, 4, 9, 13), state), "until the trial ends")
        assertNull(notice(trial(), at(2026, 11, 4, 9, 14), state))
        assertNull(notice(trial(willRenew = false), at(2026, 11, 2, 9), state), "cancelled: gone")
        assertNull(notice(trial(reason = ProReason.YEARLY), at(2026, 11, 2, 9), state), "converted: gone")

        val today = StackEngine(state, londonClock()).todaySummary(at(2026, 11, 2, 9))
        val line = assertNotNull(notice(trial(), at(2026, 11, 2, 9), state))
        assertEquals(
            TodayPrompt.TrialEnds(line),
            TodayPrompts.pick(state.settings, hasStack = true, today = today, repairDay = null, locked = false, trialNotice = line),
            "it comes before the other rows",
        )
        assertEquals(
            TodayPrompt.NudgeOffer(20 * 60),
            TodayPrompts.pick(state.settings, hasStack = true, today = today, repairDay = null, locked = false),
            "without it, the rows as before",
        )
    }

    @Test
    fun testThePlanForWhatTheAppWrote() {
        // The Reminders phase plans from pro.json alone (SPEC-ANDROID 10.4).
        val now = at(2026, 10, 28, 9, 20)
        val state = logged(12)
        val ledger = ProLedger(
            status = trial(), firstSeenAt = now,
            prices = mapOf(ProPlan.YEARLY.productId to yearlyPrice),
        )
        val planned = assertNotNull(TrialReminder.planFor(ledger, state, now, london))
        assertEquals(at(2026, 11, 1, 9, 14), planned.fireAt)
        assertTrue(planned.body.contains("$19.99 a year"))
        val sent = TrialReminderMark(at(2026, 11, 4, 9, 14), at(2026, 11, 1, 9, 14))
        assertNull(TrialReminder.planFor(ledger.copy(trialReminder = sent), state, at(2026, 11, 1, 12), london), "gone out: never again")
        assertNull(TrialReminder.planFor(null, state, now, london))
        assertEquals(DayKey(2026, 11, 1), DayKey.calendarDateOf(planned.fireAt, london))
    }

    // MARK: The one ask

    @Test
    fun testTheAskShowsOnlyWhileAndroidHasNotAsked() {
        assertTrue(TrialAsk.shows(trialStarted = true, permission = NotificationPermission.NOT_DETERMINED, alreadyShown = false))
        assertFalse(TrialAsk.shows(true, NotificationPermission.ALLOWED, false), "already allowed: the reminder is simply planned")
        assertFalse(TrialAsk.shows(true, NotificationPermission.DENIED, false), "already refused")
        assertFalse(TrialAsk.shows(true, NotificationPermission.NOT_DETERMINED, true), "once")
        assertFalse(TrialAsk.shows(false, NotificationPermission.NOT_DETERMINED, false), "a plan bought without a trial")

        val now = at(2026, 10, 28, 9, 20)
        assertTrue(TrialAsk.mentionsReminder(trial(), now))
        assertFalse(TrialAsk.mentionsReminder(trial(ends = now.plus(Duration.ofDays(3))), now), "a 3 day trial gets no reminder, so the ask does not promise one")
        assertEquals("Get the evening nudge if anything's left.", TrialAsk.body(mentionsReminder = false))
    }
}
