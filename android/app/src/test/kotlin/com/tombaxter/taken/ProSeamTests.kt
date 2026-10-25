package com.tombaxter.taken

import android.Manifest
import android.app.AlarmManager
import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.Item
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.PlanPeriod
import com.tombaxter.taken.core.pro.PlanPrice
import com.tombaxter.taken.core.pro.ProAccess
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.pro.ProPendingAction
import com.tombaxter.taken.core.pro.ProPlan
import com.tombaxter.taken.core.pro.ProReason
import com.tombaxter.taken.core.pro.ProStatus
import com.tombaxter.taken.core.pro.TrialReminderMark
import com.tombaxter.taken.core.profile.Profile
import com.tombaxter.taken.core.reminders.ReminderKind
import com.tombaxter.taken.core.reminders.TrialAsk
import com.tombaxter.taken.core.reminders.TrialReminder
import com.tombaxter.taken.core.retention.RetentionCopy
import com.tombaxter.taken.core.retention.TodayPrompt
import com.tombaxter.taken.core.stack.logDose
import com.tombaxter.taken.core.todo.TodoState
import com.tombaxter.taken.data.LedgerFile
import com.tombaxter.taken.data.MemoryPersistence
import com.tombaxter.taken.data.MemoryTodoPersistence
import com.tombaxter.taken.notify.AndroidAlarms
import com.tombaxter.taken.notify.AndroidNotifications
import com.tombaxter.taken.notify.NotificationHost
import com.tombaxter.taken.notify.NudgeActions
import com.tombaxter.taken.notify.RescheduleReceiver
import com.tombaxter.taken.notify.TakeAllOutcome
import com.tombaxter.taken.widget.SurfaceActions
import com.tombaxter.taken.widget.SurfaceOutcome
import com.tombaxter.taken.widget.SurfaceRefreshReceiver
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.Locale
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Where Taken Pro meets the reminders, the widgets, the tile and the to-dos (SPEC-ANDROID 9.7, 10.1, 10.2 and 10.4), as
 * wired when the lanes were merged: the trial reminder planned, posted, marked, withdrawn and armed again after a restart or
 * a time zone change through the reminders' own scheduler and channel; Pro's change reaching the alarms and the surfaces
 * through `AppModel.onProChanged`; the one recheck before a widget, the tile or a nudge refuses a log (the iPhone's
 * `ProGate.mayLog`); the trial ask with Continue and Not now; Today's notice only while the reminder cannot come as a
 * notification; and a voice note waiting for Play as a dose does. TrialReminderTests' trial: yearly, London, ending Wed 4
 * Nov 2026 at 09:14, so its reminder is Sun 1 Nov at 09:14.
 */
@RunWith(RobolectricTestRunner::class)
class ProSeamTests {
    private val app: TakenApp get() = ApplicationProvider.getApplicationContext()
    private val london: ZoneId = ZoneId.of("Europe/London")
    private var zone: ZoneId = london
    private var now: Instant = at(2026, 10, 28, 9, 20)

    private fun at(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0): Instant =
        ZonedDateTime.of(year, month, day, hour, minute, 0, 0, london).toInstant()

    private val ends = at(2026, 11, 4, 9, 14)
    private val fires = at(2026, 11, 1, 9, 14)
    private val yearlyPrice = PlanPrice("$19.99", PlanPeriod(1, PlanPeriod.PeriodUnit.YEAR))
    private val vd3 = Item(name = "Vitamin D3", code = "VD3", frequency = Frequency.Daily(1), createdAt = at(2026, 10, 20, 8), sortIndex = 0)

    private val container: AppContainer
        get() = app.container.also { c ->
            c.clock = { now }
            c.zone = { zone }
        }

    /** Taken Pro as each test says: a status, whether Play has answered, Play's answer to a recheck, the app's listener. */
    private class FakePro(
        var current: ProStatus?,
        var settledNow: Boolean = true,
        private val onRefresh: (FakePro) -> Boolean = { false },
    ) : ProSource {
        override val status: ProStatus? get() = current
        override val settled: Boolean get() = settledNow
        override val introEligible: Boolean? = true
        var refreshes = 0
        var listener: () -> Unit = {}
        var onSettle: () -> Unit = {}

        override suspend fun refresh(): Boolean {
            refreshes += 1
            return onRefresh(this)
        }

        override fun listen(onChange: () -> Unit) {
            listener = onChange
        }

        override suspend fun settle() {
            onSettle()
            settledNow = true
        }
    }

    /** Android's notification side, as each test says. */
    private class Host(
        var allowed: Boolean = false,
        var askable: Boolean = true,
        var rationale: Boolean = false,
        var trialOff: Boolean = false,
    ) : NotificationHost {
        var prompts = 0
        override val notificationsAllowed: Boolean get() = allowed
        override val notificationsAskable: Boolean get() = askable
        override val notificationRationaleDue: Boolean get() = rationale
        override val nudgeChannelOff: Boolean = false
        override val trialChannelOff: Boolean get() = trialOff
        override fun requestNotifications() {
            prompts += 1
        }
        override fun openNotificationSettings(channelId: String?) = Unit
    }

    private fun trial(willRenew: Boolean? = true, reason: ProReason = ProReason.TRIAL) = ProStatus(
        isPro = true, reason = reason, checkedAt = at(2026, 10, 28, 9, 14), expiresAt = ends, willRenew = willRenew,
        plan = ProPlan.YEARLY,
    )

    /** A yearly plan whose cached answer ran out a month ago, set to renew: only Play knows whether it did. */
    private fun lapsed() = ProStatus(
        isPro = true, reason = ProReason.YEARLY, checkedAt = now.minus(Duration.ofDays(40)), expiresAt = now.minus(Duration.ofDays(30)),
        willRenew = true, plan = ProPlan.YEARLY,
    )

    private fun renewed() = lapsed().copy(checkedAt = now, expiresAt = now.plus(Duration.ofDays(30)))

    private fun ledger(status: ProStatus? = null) = ProLedger(
        status = status, firstSeenAt = at(2026, 10, 20, 9), firstDoseAt = at(2026, 10, 21, 9),
        prices = mapOf(ProPlan.YEARLY.productId to yearlyPrice),
    )

    /** Vitamin D3 taken once today; the nudge off unless asked for; pro.json with the yearly price. */
    private fun seed(nudge: Boolean = false, trialSwitch: Boolean = true, status: ProStatus? = trial(), takenToday: Boolean = true) = runBlocking {
        val state = StackState(items = listOf(vd3))
        state.logDose(vd3.id, at(2026, 10, 21, 9), london)
        if (takenToday) state.logDose(vd3.id, at(2026, 10, 28, 9), london)
        state.settings.reminderEnabled = nudge
        state.settings.nudgeOfferDone = true
        state.settings.reminderMinutes = 21 * 60
        state.settings.trialReminderEnabled = trialSwitch
        container.stores.stack.updateData { state }
        container.stores.ledger.updateData { LedgerFile(ledger(status)) }
        state
    }

    private fun storedLedger(): ProLedger? = runBlocking { container.stores.ledger.data.first() }.ledger

    private val notificationManager get() = app.getSystemService(NotificationManager::class.java)
    private val alarmManager get() = app.getSystemService(AlarmManager::class.java)

    private fun allowNotifications() = shadowOf(app as Application).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)

    private fun posted(tag: String): Notification? = shadowOf(notificationManager).getNotification(tag, AndroidNotifications.ID)

    private fun Notification.text(): String? = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()

    @Suppress("DEPRECATION")
    private fun alarm(kind: ReminderKind) = shadowOf(alarmManager).scheduledAlarms.firstOrNull {
        shadowOf(it.operation).savedIntent.action == AndroidAlarms.ACTION_PREFIX + kind.name
    }

    @Suppress("DEPRECATION")
    private fun surfaceAlarm() = shadowOf(alarmManager).scheduledAlarms.firstOrNull {
        shadowOf(it.operation).savedIntent.action == SurfaceRefreshReceiver.ACTION
    }

    private fun rebuild() = runBlocking { container.reminders.rebuild() }

    /** Runs the main looper until `done` holds: the stores and the rebuilds hand back to the main thread. */
    private fun awaitMain(what: String, done: () -> Boolean) {
        val end = System.currentTimeMillis() + 10_000
        while (true) {
            shadowOf(Looper.getMainLooper()).idle()
            if (done()) return
            check(System.currentTimeMillis() < end) { "never: $what" }
            Thread.sleep(10)
        }
    }

    /** Lets every write's own rebuild and refresh finish, so what follows is the only thing that can change the alarms. */
    private fun settle() {
        val end = System.currentTimeMillis() + 400
        while (System.currentTimeMillis() < end) {
            shadowOf(Looper.getMainLooper()).idle()
            Thread.sleep(10)
        }
    }

    // MARK: The trial reminder through the reminders' scheduler and channel

    @Test
    fun testTheTrialReminderIsArmedPostedOnItsChannelAndMarkedInProJson() {
        allowNotifications()
        container.pro = FakePro(trial())
        seed()
        rebuild()
        val armed = assertNotNull(alarm(ReminderKind.TRIAL), "the trial reminder's one alarm")
        assertEquals(fires.toEpochMilli(), armed.triggerAtMs, "Sun 1 Nov 09:14, 72 hours before the end")
        assertEquals(10 * 60 * 1000L, armed.windowLengthMs, "inexact, as every reminder")
        assertNull(posted(TrialReminder.IDENTIFIER), "nothing before its moment")

        now = fires.plusSeconds(180)
        rebuild()
        val reminder = assertNotNull(posted(TrialReminder.IDENTIFIER), "posted when its alarm goes off")
        assertEquals(ReminderKind.TRIAL.channelId, reminder.channelId, "on the Trial reminder channel")
        assertEquals(TrialReminder.body(ends, yearlyPrice, 2, london), reminder.text(), "the Pro lane's words, with pro.json's price")
        assertEquals(AndroidNotifications.TODAY, shadowOf(reminder.contentIntent).savedIntent.data.toString(), "a tap opens Taken")
        assertEquals(TrialReminderMark(trialEnd = ends, fireAt = fires), storedLedger()?.trialReminder, "TrialReminder.nextMark, written once posted")
        assertNull(alarm(ReminderKind.TRIAL), "nothing left to arm")

        // A later nudge time the same day would put the moment ahead again: the mark keeps it from coming twice.
        runBlocking {
            container.stores.stack.updateData { s ->
                s.clone().also {
                    it.settings.setReminder(true)
                    it.settings.reminderMinutes = 23 * 60
                }
            }
        }
        rebuild()
        assertNull(alarm(ReminderKind.TRIAL), "never twice for one trial")
    }

    @Test
    fun testAPostedTrialReminderGoesWhenTheTrialIsCancelledThroughProsChange() {
        allowNotifications()
        val pro = FakePro(trial())
        container.pro = pro
        seed()
        rebuild()
        now = fires.plusSeconds(180)
        rebuild()
        assertNotNull(posted(TrialReminder.IDENTIFIER))

        // Cancelled in Google Play: Pro's answer changes, and onProChanged rebuilds the alarms.
        pro.current = trial(willRenew = false)
        container.proChanged()
        awaitMain("withdrawn once the trial no longer renews") { posted(TrialReminder.IDENTIFIER) == null }
    }

    @Test
    fun testTurningTheTrialReminderOffWithdrawsItsAlarm() {
        allowNotifications()
        container.pro = FakePro(trial())
        seed()
        rebuild()
        assertNotNull(alarm(ReminderKind.TRIAL))
        // Profile's switch is a write to taken.json, and every write rebuilds the reminders.
        runBlocking { container.stores.stack.updateData { s -> s.clone().also { it.settings.trialReminderEnabled = false } } }
        awaitMain("the alarm cancelled") { alarm(ReminderKind.TRIAL) == null }
    }

    @Test
    fun testARestartOrATimeZoneChangeArmsTheTrialReminderAgain() {
        allowNotifications()
        container.pro = FakePro(trial())
        val state = seed()
        rebuild()
        assertEquals(fires.toEpochMilli(), alarm(ReminderKind.TRIAL)?.triggerAtMs)
        val receiver = ComponentName(app, RescheduleReceiver::class.java)
        assertEquals(
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED, app.packageManager.getComponentEnabledSetting(receiver),
            "the restart receiver is on while the trial reminder is armed",
        )
        settle()

        // A restart clears every alarm; BOOT_COMPLETED rebuilds them.
        AndroidAlarms(app).cancel(ReminderKind.TRIAL)
        assertNull(alarm(ReminderKind.TRIAL))
        app.sendBroadcast(Intent(Intent.ACTION_BOOT_COMPLETED).setComponent(receiver))
        awaitMain("armed again after the restart") { alarm(ReminderKind.TRIAL)?.triggerAtMs == fires.toEpochMilli() }

        // Flown to New York: the moment is planned again where the phone is now.
        zone = ZoneId.of("America/New_York")
        val there = assertNotNull(TrialReminder.fireDate(ends, state.settings, zone))
        assertTrue(there != fires, "a different moment in New York")
        app.sendBroadcast(Intent(Intent.ACTION_TIMEZONE_CHANGED).setComponent(receiver))
        awaitMain("moved with the time zone") { alarm(ReminderKind.TRIAL)?.triggerAtMs == there.toEpochMilli() }
    }

    // MARK: Pro's change reaches the alarms, the widgets and the tile

    @Test
    fun testProChangingRefreshesTheAlarmsAndTheSurfacesThroughTheAppModel() {
        allowNotifications()
        val pro = FakePro(null)
        container.pro = pro
        seed(nudge = true, status = null, takenToday = false)
        container.surfaces.tileAdded = true
        val viewModel = AppViewModel(container)
        awaitMain("the app model") { viewModel.model != null }
        val model = assertNotNull(viewModel.model)
        assertEquals(ProAccess.LOCKED, model.access, "locked after the first dose, without Pro")
        rebuild()
        settle()
        assertNull(alarm(ReminderKind.NUDGE), "no nudge is scheduled while locked")
        PendingIntent.getBroadcast(
            app, 0, Intent(app, SurfaceRefreshReceiver::class.java).setAction(SurfaceRefreshReceiver.ACTION),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        ).let { alarmManager.cancel(it) }
        assertNull(surfaceAlarm())

        // Play's answer arrives: ProStore tells its one listener, the app model, which runs onProChanged.
        pro.current = ProStatus(isPro = true, reason = ProReason.LIFETIME, checkedAt = now)
        pro.listener()
        awaitMain("the nudge armed once Pro is on") { alarm(ReminderKind.NUDGE) != null }
        awaitMain("the widgets and the tile redrawn, their refresh armed again") { surfaceAlarm() != null }
    }

    // MARK: The one recheck before a log from outside Taken is refused

    @Test
    fun testTheRecheckAsksPlayOnlyForARenewalItHasNotSeen() {
        val state = StackState(items = listOf(vd3)).also { it.logDose(vd3.id, at(2026, 10, 21, 9), london) }
        var changes = 0
        val renewing = FakePro(lapsed()) { it.current = renewed(); true }
        assertTrue(runBlocking { ProRecheck.mayLog(renewing, state, now, { ledger() }) { changes += 1 } })
        assertEquals(1, renewing.refreshes, "one question to Play")
        assertEquals(1, changes, "Pro changed: the widgets, the tile and the alarms follow")

        val ended = FakePro(lapsed()) { false }
        assertFalse(runBlocking { ProRecheck.mayLog(ended, state, now, { ledger() }) { changes += 1 } }, "Play says it ended")
        assertEquals(1, ended.refreshes)
        assertEquals(1, changes)

        val none = FakePro(null)
        assertFalse(runBlocking { ProRecheck.mayLog(none, state, now, { ledger() }) })
        assertEquals(0, none.refreshes, "no Pro to renew: refused without asking, as on the iPhone")
        val cancelled = FakePro(lapsed().copy(willRenew = false))
        assertFalse(runBlocking { ProRecheck.mayLog(cancelled, state, now, { ledger() }) })
        assertEquals(0, cancelled.refreshes, "a cancelled plan that ran out is not rechecked")

        // A fresh process: the source has no answer yet, so pro.json's cached one is read, and rechecked.
        val fresh = FakePro(null) { it.current = renewed(); true }
        assertTrue(runBlocking { ProRecheck.mayLog(fresh, state, now, { ledger(lapsed()) }) })
        assertEquals(1, fresh.refreshes)
    }

    @Test
    fun testAWidgetsOrTheTilesTakeAllRechecksBeforeRefusingAndKeepsARefusal() {
        seed(status = null, takenToday = false)
        val renewing = FakePro(lapsed()) { it.current = renewed(); true }
        assertEquals(SurfaceOutcome.Logged(1), runBlocking { SurfaceActions.takeAll(container, now, london, renewing) })
        assertEquals(1, renewing.refreshes, "Play asked once, then the Take all logged")
        assertNull(storedLedger()?.pending)

        seed(status = null, takenToday = false)
        val none = FakePro(null)
        assertEquals(SurfaceOutcome.Locked, runBlocking { SurfaceActions.takeAll(container, now, london, none) })
        assertEquals(0, none.refreshes)
        val pending = assertNotNull(storedLedger()?.pending, "the refused Take all is kept (ProLedgers.recordPending)")
        assertEquals(ProPendingAction.TakeAll, pending.action)
        assertEquals(now, pending.at)
    }

    @Test
    fun testAWidgetRowRechecksAndARefusedRowLeavesItsLogToTheRowsLink() {
        seed(status = null, takenToday = false)
        val renewing = FakePro(lapsed()) { it.current = renewed(); true }
        assertEquals(SurfaceOutcome.Logged(1), runBlocking { SurfaceActions.logNext(container, vd3.id, now, london, renewing) })
        assertEquals(1, renewing.refreshes)

        seed(status = null, takenToday = false)
        assertEquals(SurfaceOutcome.Locked, runBlocking { SurfaceActions.logNext(container, vd3.id, now, london, FakePro(null)) })
        assertNull(storedLedger()?.pending, "as the iPhone's LogNextDoseIntent: the locked row's taken://pro?then=log link carries it")
    }

    @Test
    fun testANudgesTakeAllRechecksInsideItsBroadcast() {
        allowNotifications()
        val state = seed(nudge = true, status = null, takenToday = false)
        now = at(2026, 10, 28, 21, 4)
        val today = DayClock(state.settings.dayStartHour, london).day(now)
        val renewing = FakePro(lapsed()) { it.current = renewed(); true }
        assertEquals(TakeAllOutcome.Logged(1), runBlocking { NudgeActions.takeAll(container, today, now, london, renewing) })
        assertEquals(1, renewing.refreshes)

        seed(nudge = true, status = null, takenToday = false)
        val ended = FakePro(lapsed()) { false }
        assertIs<TakeAllOutcome.Locked>(runBlocking { NudgeActions.takeAll(container, today, now, london, ended) })
        assertEquals(1, ended.refreshes, "refused only after the one recheck")
        assertEquals(ProPendingAction.TakeAll, storedLedger()?.pending?.action)
    }

    // MARK: The trial ask (Continue and Not now)

    private fun model(pro: ProSource, host: Host, ledger: ProLedger = ledger(trial())): AppModel {
        val state = StackState(items = listOf(vd3))
        state.logDose(vd3.id, at(2026, 10, 21, 9), london)
        state.settings.reminderEnabled = false
        state.settings.nudgeOfferDone = false
        val notifications = NotificationsModel()
        val model = AppModel(
            MemoryPersistence(stack = state, ledger = ledger), state, ledger, Profile(), null, pro,
            clockNow = { now }, zone = { london }, locale = { Locale.US }, notificationsModel = notifications,
        )
        notifications.host = host
        return model
    }

    /** A trial bought in the paywall, which then closes. */
    private fun startTrial(model: AppModel) {
        model.presentPaywall(PaywallOrigin.SETTINGS)
        model.paywallUnlocked(trialStarted = true)
        assertFalse(model.showsTrialAsk, "never over the paywall")
        model.closePaywall()
    }

    @Test
    fun testTheTrialAskComesOnceAndContinueGoesStraightToAndroidsPrompt() {
        val host = Host()
        val model = model(FakePro(trial()), host)
        startTrial(model)
        assertTrue(model.showsTrialAsk, "the paywall has closed on a new trial, and Android can still ask")
        assertEquals(TrialAsk.BODY, model.trialAskBody, "the nudge and the heads-up, 7 days left")
        model.sheet = Sheet.Add
        assertFalse(model.showsTrialAsk, "it waits while a sheet holds the screen")
        model.sheet = null
        assertTrue(model.showsTrialAsk, "and comes back once it has gone")
        model.trialAskDidAppear()
        assertEquals(now, model.ledger?.trialAskAt, "used up only once on screen")

        // The ask is the explanation: Android's prompt comes next, with no second explanation before it.
        host.rationale = true
        model.answerTrialAsk(proceed = true)
        assertFalse(model.showsTrialAsk)
        assertEquals(1, host.prompts, "POST_NOTIFICATIONS asked in context")
        assertFalse(model.notifications.asking)
        host.allowed = true
        model.notifications.answered(true)
        assertTrue(model.settings.reminderEnabled, "the evening nudge comes on")
        assertTrue(model.settings.nudgeOfferDone, "and Today's nudge offer is answered")
        assertEquals(RetentionCopy.NUDGE_ON, model.toast?.message)
        assertTrue(model.notifications.trialDeliverable, "the trial reminder can come as a notification now")
        assertTrue(model.trialReminderDeliverable())

        // One ask, ever: a later trial never asks again.
        startTrial(model)
        assertFalse(model.showsTrialAsk)
    }

    @Test
    fun testNotNowChangesNothingAndASecondNoSaysWhereNotificationsAre() {
        val host = Host()
        val model = model(FakePro(trial()), host)
        startTrial(model)
        model.answerTrialAsk(proceed = false)
        assertFalse(model.showsTrialAsk)
        assertEquals(0, host.prompts, "Not now: no prompt")
        assertFalse(model.settings.reminderEnabled)
        assertFalse(model.settings.nudgeOfferDone, "Today's nudge offer may still ask, in its own context")

        val second = Host()
        val other = model(FakePro(trial()), second)
        startTrial(other)
        other.answerTrialAsk(proceed = true)
        // Android will not ask again (a second no).
        second.askable = false
        other.notifications.answered(false)
        assertFalse(other.settings.reminderEnabled)
        assertTrue(other.settings.nudgeOfferDone, "either answer to Android answers the nudge offer")
        assertEquals(RetentionCopy.NOTIFICATIONS_OFF, other.toast?.message)
    }

    @Test
    fun testNoAskWhenAndroidHasAnsweredOrItWasAlreadyShown() {
        val allowed = model(FakePro(trial()), Host(allowed = true))
        startTrial(allowed)
        assertFalse(allowed.showsTrialAsk, "notifications already on: the reminder simply follows")
        val refused = model(FakePro(trial()), Host(allowed = false, askable = false))
        startTrial(refused)
        assertFalse(refused.showsTrialAsk, "Android will not show its prompt")
        val shown = model(FakePro(trial()), Host(), ledger = ledger(trial()).copy(trialAskAt = at(2026, 9, 1, 9)))
        startTrial(shown)
        assertFalse(shown.showsTrialAsk, "the one ask was used on an earlier trial")
        val short = model(FakePro(trial().copy(expiresAt = now.plus(Duration.ofDays(2)))), Host())
        startTrial(short)
        assertEquals(TrialAsk.BODY_NUDGE_ONLY, short.trialAskBody, "a trial too short for the reminder asks for the nudge only")
    }

    // MARK: Today's notice while the reminder cannot come

    @Test
    fun testTodayCarriesTheReminderOnlyWhileItCannotComeAsANotification() {
        now = fires.plus(Duration.ofHours(2))
        val host = Host(allowed = false, askable = false)
        val model = model(FakePro(trial()), host)
        model.notifications.refresh()
        assertFalse(model.trialReminderDeliverable())
        val notice = assertIs<TodayPrompt.TrialEnds>(model.todayPrompt, "the reminder's words on Today")
        assertTrue(notice.text.startsWith("Your Taken trial ends Wednesday 4 Nov."), notice.text)

        host.allowed = true
        model.notifications.refresh()
        assertTrue(model.trialReminderDeliverable(), "notifications on, the Trial reminder channel on")
        assertFalse(model.todayPrompt is TodayPrompt.TrialEnds, "the notification carries it")

        host.trialOff = true
        model.notifications.refresh()
        assertFalse(model.trialReminderDeliverable(), "the Trial reminder channel turned off in Android's settings")
        assertIs<TodayPrompt.TrialEnds>(model.todayPrompt)
    }

    // MARK: To-dos and doses wait for Play by one rule

    @Test
    fun testAVoiceNoteWaitsForPlaysFirstAnswerAsADoseDoes() {
        val pro = FakePro(null, settledNow = false)
        pro.onSettle = { pro.current = ProStatus(isPro = true, reason = ProReason.LIFETIME, checkedAt = now) }
        val todos = TodoState(firstNoteAt = now.minus(Duration.ofDays(1)))
        val todo = TodoModel(MemoryTodoPersistence(todos), todos, clockNow = { now }, zone = { london }, locale = { Locale.US })
        val ledger = ledger()
        val state = StackState(items = listOf(vd3)).also { it.logDose(vd3.id, at(2026, 10, 21, 9), london) }
        val model = AppModel(
            MemoryPersistence(stack = state, ledger = ledger), state, ledger, Profile(), null, pro,
            clockNow = { now }, zone = { london }, locale = { Locale.US }, todoModel = todo,
        )
        assertEquals(ProAccess.CHECKING, todo.access(), "the first note is used; Play has not answered")
        assertEquals(ProAccess.CHECKING, model.access, "the same answer for a dose")
        var ran = false
        todo.whenAllowed { ran = true }
        awaitMain("the note goes ahead once Play says Pro") { ran }
        assertNull(model.paywall)

        val lockedPro = FakePro(null, settledNow = false)
        val lockedTodo = TodoModel(MemoryTodoPersistence(todos), todos, clockNow = { now }, zone = { london }, locale = { Locale.US })
        val locked = AppModel(
            MemoryPersistence(stack = state, ledger = ledger), state, ledger, Profile(), null, lockedPro,
            clockNow = { now }, zone = { london }, locale = { Locale.US }, todoModel = lockedTodo,
        )
        lockedTodo.whenAllowed { ran = false }
        awaitMain("Play says no Pro: the paywall, as for a dose") { locked.paywall != null }
        assertEquals(PaywallOrigin.ACTION, locked.paywall?.origin)
    }
}
