package com.tombaxter.taken

import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.Item
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.profile.Profile
import com.tombaxter.taken.core.reminders.NudgeLink
import com.tombaxter.taken.core.reminders.ReminderKind
import com.tombaxter.taken.core.retention.RetentionCopy
import com.tombaxter.taken.core.retention.TodayPrompt
import com.tombaxter.taken.core.retention.TodayPrompts
import com.tombaxter.taken.core.stack.logDose
import com.tombaxter.taken.core.todo.TodoCaptureRoute
import com.tombaxter.taken.data.MemoryPersistence
import com.tombaxter.taken.notify.NotificationHost
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Android's notification answers, as the activity would give them. */
class FakeNotificationHost(
    var allowed: Boolean = false,
    var askable: Boolean = true,
    var rationale: Boolean = false,
    var channelOff: Boolean = false,
) : NotificationHost {
    var prompts = 0
    val opened = mutableListOf<String?>()

    override val notificationsAllowed get() = allowed
    override val notificationsAskable get() = askable
    override val notificationRationaleDue get() = rationale
    override val nudgeChannelOff get() = channelOff
    override fun requestNotifications() {
        prompts += 1
    }
    override fun openNotificationSettings(channelId: String?) {
        opened += channelId
    }
}

/**
 * The nudge's permission flow (SPEC-ANDROID 10.4), the iPhone's `setReminderEnabled` and the nudge offer in Android's
 * shape: asked in context from Turn on and Profile's switch, the explanation only when Android says one is due, a first
 * no taken as said, the Settings row once Android will not ask again, and the nudge on only once notifications show.
 * Also the links a notification opens. A fake [NotificationHost] stands in for the activity.
 */
@RunWith(RobolectricTestRunner::class)
class NotificationFlowTests {
    private val zone: ZoneId = ZoneId.of("Europe/London")
    private val now: Instant = ZonedDateTime.of(2026, 10, 21, 9, 0, 0, 0, zone).toInstant()

    private class Rig(val model: AppModel, val host: FakeNotificationHost, val rebuilds: () -> Int)

    private fun rig(
        host: FakeNotificationHost = FakeNotificationHost(),
        pro: ProSource = ProSource.untilBilling,
        nudgeOn: Boolean = false,
        logged: Boolean = false,
    ): Rig {
        val vd3 = Item(name = "Vitamin D3", code = "VD3", frequency = Frequency.Daily(1), createdAt = now.minusSeconds(86_400), sortIndex = 0)
        val state = StackState(items = listOf(vd3))
        state.settings.reminderEnabled = nudgeOn
        if (logged) state.logDose(vd3.id, now.minusSeconds(86_400), zone)
        var rebuilds = 0
        val notifications = NotificationsModel(rebuild = { rebuilds += 1 })
        notifications.host = host
        val model = AppModel(
            MemoryPersistence(stack = state), state, ProLedger(firstSeenAt = now), Profile(), null, pro,
            clockNow = { now }, zone = { zone }, locale = { Locale.US }, notificationsModel = notifications,
        )
        return Rig(model, host) { rebuilds }
    }

    @Test
    fun testTurnOnAsksInContextAndTheNudgeComesOnOnceAllowed() {
        val rig = rig()
        val model = rig.model
        assertEquals(TodayPrompt.NudgeOffer(20 * 60), model.todayPrompt)
        assertEquals(0, rig.host.prompts, "nothing is asked before the person taps")

        model.answerNudgeOffer(turnOn = true)
        assertEquals(1, rig.host.prompts, "Turn on shows Android's prompt at once: no explanation is due")
        assertFalse(model.notifications.asking)
        assertFalse(model.settings.reminderEnabled, "not on until Android says yes")
        assertTrue(model.settings.nudgeOfferDone, "either answer is final")
        assertNull(model.todayPrompt)

        rig.host.allowed = true
        model.notifications.answered(true)
        assertTrue(model.settings.reminderEnabled)
        assertEquals(RetentionCopy.NUDGE_ON, model.toast?.message)
        assertEquals("20:00", model.toast?.time, "Nudge on at 20:00")
        assertEquals(1, rig.rebuilds(), "allowed: the reminders are rebuilt, so to-dos with a time get theirs too")

        model.notifications.answered(true)
        assertEquals(1, rig.rebuilds(), "one answer goes with each prompt")
    }

    @Test
    fun testAFirstNoIsTakenAsSaidAndASecondLinksToSettings() {
        val rig = rig()
        val model = rig.model
        model.answerNudgeOffer(turnOn = true)
        rig.host.rationale = true // after a first no, Android asks for an explanation next time
        model.notifications.answered(false)
        assertFalse(model.settings.reminderEnabled)
        assertFalse(model.notifications.notificationsDenied, "a first no: no Settings row, nothing nags")
        assertNull(model.toast, "and no toast")

        // Profile's switch: the explanation first, then Android's prompt, which says no again.
        model.setReminder(true)
        assertTrue(model.notifications.asking, "Android says an explanation is due")
        assertEquals(1, rig.host.prompts)
        model.notifications.answerRationale(true)
        assertFalse(model.notifications.asking)
        assertEquals(2, rig.host.prompts, "Continue shows Android's prompt")
        rig.host.rationale = false // a second no: Android will not show its prompt again
        model.notifications.answered(false)
        assertFalse(model.settings.reminderEnabled)
        assertTrue(model.notifications.notificationsDenied, "Notifications are off for Taken. Open Settings")
        assertNull(model.toast, "Profile's switch shows the row, not a toast, as on the iPhone")
    }

    @Test
    fun testTheExplanationsNotNowChangesNothing() {
        val rig = rig(FakeNotificationHost(rationale = true))
        val model = rig.model
        model.setReminder(true)
        assertTrue(model.notifications.asking)
        model.notifications.answerRationale(false)
        assertFalse(model.notifications.asking)
        assertEquals(0, rig.host.prompts, "Not now: no prompt")
        assertFalse(model.settings.reminderEnabled)
        assertFalse(model.notifications.notificationsDenied)
        model.notifications.answered(true)
        assertFalse(model.settings.reminderEnabled, "an answer nobody asked for changes nothing")
        model.setReminder(true)
        assertTrue(model.notifications.asking, "the next tap asks again the same way")
    }

    @Test
    fun testNotificationsAlreadyAllowedTurnTheNudgeOnAtOnce() {
        val rig = rig(FakeNotificationHost(allowed = true))
        rig.model.answerNudgeOffer(turnOn = true)
        assertEquals(0, rig.host.prompts)
        assertTrue(rig.model.settings.reminderEnabled)
        assertEquals(RetentionCopy.NUDGE_ON, rig.model.toast?.message)
    }

    @Test
    fun testNotificationsTurnedOffInSettingsSaySoWithoutAPrompt() {
        val rig = rig(FakeNotificationHost(allowed = false, askable = false))
        rig.model.answerNudgeOffer(turnOn = true)
        assertEquals(0, rig.host.prompts, "Android will not ask: only Settings turns them back on")
        assertFalse(rig.model.settings.reminderEnabled)
        assertEquals(RetentionCopy.NOTIFICATIONS_OFF, rig.model.toast?.message)
        assertTrue(rig.model.notifications.notificationsDenied)
        rig.model.notifications.openSettings()
        assertEquals(listOf<String?>(null), rig.host.opened, "the row opens Taken's notification settings")
    }

    /** RetentionTests.testTheNudgeToggleInProfileAnswersTheOffer's model half: on, then off, the offer stays away. */
    @Test
    fun testTheNudgeToggleInProfileAnswersTheOffer() {
        val rig = rig(FakeNotificationHost(allowed = true))
        val model = rig.model
        model.setReminder(true)
        assertTrue(model.settings.reminderEnabled)
        assertNull(model.toast, "Profile's switch turns it on quietly")
        model.setReminder(false)
        assertFalse(model.settings.reminderEnabled)
        assertTrue(model.settings.nudgeOfferDone, "on, then off, in Profile")
        val offer = TodayPrompts.pick(model.settings, hasStack = model.hasStack, today = model.today, repairDay = null, locked = false)
        assertFalse(offer is TodayPrompt.NudgeOffer, "the offer never comes back after the nudge was turned off in Profile")
    }

    @Test
    fun testTurningTheNudgeOffAlwaysWorksAndOnNeedsPro() {
        val rig = rig(FakeNotificationHost(allowed = true), pro = ProSource.locked, nudgeOn = true, logged = true)
        val model = rig.model
        assertTrue(model.isLocked)
        model.setReminder(false)
        assertFalse(model.settings.reminderEnabled, "off works without Pro")
        model.setReminder(true)
        assertNotNull(model.paywall, "locked: the switch opens the paywall")
        assertFalse(model.settings.reminderEnabled)
        assertEquals(0, rig.host.prompts, "no prompt behind the paywall")
    }

    @Test
    fun testComingBackShowsWhatAndroidSaysNow() {
        val rig = rig(FakeNotificationHost(allowed = false, askable = false), nudgeOn = true)
        val model = rig.model
        model.didBecomeActive()
        assertTrue(model.notifications.notificationsDenied, "the nudge is on and notifications were turned off in Settings")
        assertEquals(1, rig.rebuilds(), "every return to the front rebuilds the reminders")

        rig.host.allowed = true
        rig.host.channelOff = true
        model.didBecomeActive()
        assertFalse(model.notifications.notificationsDenied)
        assertTrue(model.notifications.nudgeChannelOff, "only the Evening nudge channel is off")
        model.notifications.openSettings(ReminderKind.NUDGE.channelId)
        assertEquals(listOf<String?>(ReminderKind.NUDGE.channelId), rig.host.opened, "its row opens that channel's page")

        model.setReminder(false)
        assertFalse(model.notifications.nudgeChannelOff, "the row goes with the nudge")
    }

    @Test
    fun testTheNudgeTimeMovesTheNudge() {
        val rig = rig(FakeNotificationHost(allowed = true), nudgeOn = true)
        assertEquals(20 * 60, rig.model.settings.reminderMinutes, "13 hours after a 07:00 wake-up")
        rig.model.setReminderMinutes(21 * 60 + 30)
        assertEquals(21 * 60 + 30, rig.model.settings.reminderMinutes)
    }

    /** A tapped nudge opens its day; a tapped due time opens To-do on its task with the wash. */
    @Test
    fun testTheLinksANotificationCarries() {
        val model = DemoScreens.make("todo")
        val task = model.todo.state.tasks.first { !it.isDone }
        model.openProfile()
        model.handle(TodoCaptureRoute.revealUrl(task.id))
        assertEquals(AppTab.TODO, model.tab)
        assertEquals(listOf<Route>(Route.Main), model.backStack.toList())
        assertEquals(task.id, model.todo.scrollTarget, "the list scrolls to it")
        assertEquals(setOf(task.id), model.todo.arrived, "and washes it")

        model.handle(NudgeLink.url(model.today.day))
        assertEquals(AppTab.TODAY, model.tab)
        assertNull(model.sheet)
    }
}
