package com.tombaxter.taken.core

import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.NudgeWindow
import com.tombaxter.taken.core.pro.PlanPeriod
import com.tombaxter.taken.core.pro.PlanPeriod.PeriodUnit
import com.tombaxter.taken.core.pro.PlanPrice
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.pro.ProLedgers
import com.tombaxter.taken.core.pro.ProPlan
import com.tombaxter.taken.core.pro.ProReason
import com.tombaxter.taken.core.pro.ProStatus
import com.tombaxter.taken.core.pro.TrialReminderMark
import com.tombaxter.taken.core.reminders.PlannedTrialReminder
import com.tombaxter.taken.core.reminders.ReminderKind
import com.tombaxter.taken.core.reminders.ReminderSchedule
import com.tombaxter.taken.core.reminders.ReminderSnapshot
import com.tombaxter.taken.core.reminders.TrialReminder
import com.tombaxter.taken.core.reminders.TrialReminderSlot
import com.tombaxter.taken.core.stack.logDose
import kotlinx.coroutines.runBlocking
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Taken Pro's trial reminder through the reminders' slot (SPEC-ANDROID 9.7 and 10.4, wired at integration): the plan the
 * scheduler arms is `TrialReminder.plan` over the files, with pro.json's price; posting it writes `TrialReminder.nextMark`
 * so it never comes twice; it is withdrawn when the trial converts, is cancelled or the switch goes off. TrialReminderTests'
 * fixtures: a yearly trial in London that ends Wed 4 Nov 2026 at 09:14, so the reminder is Sun 1 Nov at 09:14.
 */
class PlannedTrialReminderTests {
    private val yearlyPrice = PlanPrice("$19.99", PlanPeriod(1, PeriodUnit.YEAR))
    private val ends = at(2026, 11, 4, 9, 14)
    private val fires = at(2026, 11, 1, 9, 14)

    private fun trial(willRenew: Boolean? = true, reason: ProReason = ProReason.TRIAL) = ProStatus(
        isPro = true, reason = reason, checkedAt = at(2026, 10, 28, 9, 14), expiresAt = ends, willRenew = willRenew,
        plan = ProPlan.YEARLY,
    )

    private fun ledger(status: ProStatus?, mark: TrialReminderMark? = null) = ProLedger(
        status = status, firstSeenAt = at(2026, 10, 20, 9), firstDoseAt = at(2026, 10, 28, 10),
        prices = mapOf(ProPlan.YEARLY.productId to yearlyPrice), trialReminder = mark,
    )

    private fun stack(doses: Int = 12, switchOn: Boolean = true): StackState {
        val vd3 = makeItem("Vitamin D3", "VD3", created = at(2026, 10, 28, 9))
        val state = StackState(items = listOf(vd3))
        for (index in 0 until doses) state.logDose(vd3.id, at(2026, 10, 28, 10).plusSeconds(index * 3600L), london)
        state.settings.reminderEnabled = false
        state.settings.trialReminderEnabled = switchOn
        return state
    }

    private val written = mutableListOf<TrialReminderMark?>()

    private fun slot(status: ProStatus?, ledger: ProLedger? = ledger(status), state: StackState = stack()) =
        PlannedTrialReminder(status, ledger, state, london) { written.add(it) }

    private fun snapshot(slot: TrialReminderSlot, state: StackState = stack()) =
        ReminderSnapshot(state, emptyList(), NudgeWindow.Open, london, slot)

    @Test
    fun testTheSlotPlansTheProLanesReminderWithTheCachedPrice() {
        val status = trial()
        val now = at(2026, 10, 28, 9, 20)
        val reminder = assertNotNull(slot(status).planned(now), "a renewing trial with the switch on")
        assertEquals(ReminderKind.TRIAL, reminder.kind)
        assertEquals(TrialReminder.IDENTIFIER, reminder.tag, "the iPhone's identifier, as the notification's tag")
        assertEquals(TrialReminderSlot.TAG, reminder.tag)
        assertEquals(fires, reminder.fireAt)
        assertNull(reminder.title, "the body only, as the iPhone's")
        val planned = assertNotNull(TrialReminder.planFor(ledger(status), stack(), now, london))
        assertEquals(planned.fireAt, reminder.fireAt, "the same rule as TrialReminder.planFor and AppModel.trialReminderPlan")
        assertEquals(planned.body, reminder.body)
        assertTrue(reminder.body.contains("renews at $19.99 a year"), "pro.json's price for the plan it renews to: ${reminder.body}")
        assertTrue(reminder.body.contains("12 doses logged so far."))
        // The scheduler arms the TRIAL kind's one alarm for it.
        assertEquals(fires, ReminderSchedule.nextAlarm(snapshot(slot(status)), ReminderKind.TRIAL, now))
    }

    @Test
    fun testPostingWritesTheMarkSoItNeverComesTwice() = runBlocking {
        val status = trial()
        val first = slot(status)
        val due = ReminderSchedule.due(snapshot(first), ReminderKind.TRIAL, armedAt = fires, now = fires.plusSeconds(240))
        val reminder = due.single()
        first.posted(reminder, fires.plusSeconds(240))
        assertEquals(listOf<TrialReminderMark?>(TrialReminderMark(trialEnd = ends, fireAt = fires)), written, "nextMark, written once posted")

        // The next rebuild reads the mark: nothing planned, even when a later nudge time would move the moment ahead.
        val later = stack().also {
            it.settings.reminderEnabled = true
            it.settings.reminderMinutes = 23 * 60
        }
        val marked = ledger(status, mark = written.single())
        val after = fires.plusSeconds(600)
        assertNull(slot(status, marked, later).planned(after), "once gone out, never again for that trial")
        assertNull(ReminderSchedule.nextAlarm(snapshot(slot(status, marked, later), later), ReminderKind.TRIAL, after), "its alarm goes")

        // Posting the same reminder again writes nothing new.
        written.clear()
        slot(status, marked).posted(reminder, after)
        assertTrue(written.isEmpty(), "the mark is written only when it changes")
        assertEquals(marked, ProLedgers.withTrialReminder(marked, TrialReminderMark(ends, fires)), "pro.json's write is a no-op too")
    }

    @Test
    fun testItGoesWhenTheTrialConvertsIsCancelledOrTheSwitchIsOff() {
        val now = at(2026, 11, 1, 12)
        assertTrue(slot(trial()).stillApplies(now), "a renewing trial keeps its posted reminder")
        val cancelled = trial(willRenew = false)
        assertFalse(slot(cancelled).stillApplies(now), "cancelled in Google Play")
        assertNull(slot(cancelled).planned(at(2026, 10, 28, 9, 20)), "and none is planned")
        val converted = trial(reason = ProReason.YEARLY)
        assertFalse(slot(converted).stillApplies(now), "converted to the yearly plan")
        val off = stack(switchOn = false)
        assertFalse(slot(trial(), state = off).stillApplies(now), "Profile's Trial reminder off")
        assertNull(slot(trial(), state = off).planned(at(2026, 10, 28, 9, 20)))
        assertNull(slot(null, ledger = null).planned(at(2026, 10, 28, 9, 20)), "no Pro at all")

        val tag = TrialReminderSlot.TAG
        assertEquals(listOf(tag), ReminderSchedule.withdrawn(listOf(tag), snapshot(slot(cancelled)), now))
        assertEquals(listOf(tag), ReminderSchedule.withdrawn(listOf(tag), snapshot(slot(converted)), now))
        assertEquals(listOf(tag), ReminderSchedule.withdrawn(listOf(tag), snapshot(slot(trial(), state = off), off), now))
        assertTrue(ReminderSchedule.withdrawn(listOf(tag), snapshot(slot(trial())), now).isEmpty(), "still applies: stays")
    }

    @Test
    fun testWithoutACachedPriceTheReminderNamesNone() {
        val status = trial()
        val bare = ledger(status).copy(prices = emptyMap())
        val reminder = assertNotNull(slot(status, bare).planned(at(2026, 10, 28, 9, 20)))
        assertTrue(reminder.body.contains("Unless cancelled, it then renews."), "never a made-up price: ${reminder.body}")
    }
}
