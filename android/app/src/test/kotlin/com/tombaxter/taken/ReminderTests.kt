package com.tombaxter.taken

import android.Manifest
import android.app.AlarmManager
import android.app.Application
import android.app.Notification
import android.app.NotificationManager
import android.content.ComponentName
import android.content.pm.PackageManager
import androidx.test.core.app.ApplicationProvider
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.model.Frequency
import com.tombaxter.taken.core.model.Item
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.ProCopy
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.pro.ProPendingAction
import com.tombaxter.taken.core.reminders.NudgeLink
import com.tombaxter.taken.core.reminders.ReminderKind
import com.tombaxter.taken.core.reminders.Reminders
import com.tombaxter.taken.core.stack.logDose
import com.tombaxter.taken.core.todo.TodoCaptureRoute
import com.tombaxter.taken.core.todo.TodoDue
import com.tombaxter.taken.core.todo.TodoNotifications
import com.tombaxter.taken.core.todo.TodoState
import com.tombaxter.taken.core.todo.TodoTask
import com.tombaxter.taken.data.LedgerFile
import com.tombaxter.taken.notify.AndroidAlarms
import com.tombaxter.taken.notify.AndroidNotifications
import com.tombaxter.taken.notify.NudgeActionReceiver
import com.tombaxter.taken.notify.NudgeActions
import com.tombaxter.taken.notify.RescheduleReceiver
import com.tombaxter.taken.notify.TakeAllOutcome
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.time.Instant
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * The reminders on Android's own services (SPEC-ANDROID 10.4), through the app's real container: the three channels; the
 * nudge armed as one inexact alarm and posted with TAKE ALL and OPEN when it goes off; due times; nothing without
 * notifications; a missed alarm caught up after a restart; last night's nudge never shown the next morning; the restart
 * receiver on only while something is armed; and the nudge's TAKE ALL (logged, last night's, locked). The fixtures are
 * ReminderPlanTests': Vitamin D3 (taken at 07:42) and Fish Oil in London, the nudge at 21:00, Mon 12 Oct 2026.
 */
@RunWith(RobolectricTestRunner::class)
class ReminderTests {
    private val app: TakenApp get() = ApplicationProvider.getApplicationContext()
    private val london: ZoneId = ZoneId.of("Europe/London")
    private val monday = DayKey(2026, 10, 12)
    private var now: Instant = at(2026, 10, 12, 9)

    private fun at(year: Int, month: Int, day: Int, hour: Int, minute: Int = 0): Instant =
        ZonedDateTime.of(year, month, day, hour, minute, 0, 0, london).toInstant()

    private val container: AppContainer
        get() = app.container.also { c ->
            c.clock = { now }
            c.zone = { london }
        }

    private val notificationManager get() = app.getSystemService(NotificationManager::class.java)
    private val alarmManager get() = app.getSystemService(AlarmManager::class.java)

    private fun allowNotifications() = shadowOf(app as Application).grantPermissions(Manifest.permission.POST_NOTIFICATIONS)

    private fun posted(tag: String): Notification? = shadowOf(notificationManager).getNotification(tag, AndroidNotifications.ID)

    private fun Notification.text(): String? = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()

    private fun Notification.title(): String? = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()

    /** The armed alarm of one kind: its moment, its window and its type. */
    @Suppress("DEPRECATION")
    private fun alarm(kind: ReminderKind) = shadowOf(alarmManager).scheduledAlarms.firstOrNull {
        shadowOf(it.operation).savedIntent.action == AndroidAlarms.ACTION_PREFIX + kind.name
    }

    private fun seedStack(nudgeOn: Boolean = true): StackState = runBlocking {
        val created = at(2026, 10, 1, 8)
        val vd3 = Item(name = "Vitamin D3", code = "VD3", frequency = Frequency.Daily(1), createdAt = created, sortIndex = 0)
        val fish = Item(name = "Fish Oil", code = "FSH", frequency = Frequency.Daily(1), createdAt = created, sortIndex = 1)
        val state = StackState(items = listOf(vd3, fish))
        state.settings.reminderEnabled = nudgeOn
        state.settings.reminderMinutes = 21 * 60
        state.logDose(vd3.id, at(2026, 10, 12, 7, 42), london)
        container.stores.stack.updateData { state }
    }

    private fun rebuild() = runBlocking { container.reminders.rebuild() }

    @Test
    fun testOneChannelPerKindMadeWhenTakenStarts() {
        val channels = notificationManager.notificationChannels.associateBy { it.id }
        for (kind in ReminderKind.entries) {
            val channel = assertNotNull(channels[kind.channelId], "the ${kind.channelName} channel")
            assertEquals(kind.channelName, channel.name.toString())
            assertEquals(kind.channelDescription, channel.description)
            assertEquals(NotificationManager.IMPORTANCE_DEFAULT, channel.importance, "a sound, as the iPhone's default sound")
        }
        assertEquals(listOf("Evening nudge", "Trial reminder", "To-do due times"), ReminderKind.entries.map { channels[it.channelId]?.name.toString() })
    }

    @Test
    fun testTheNudgeIsArmedInexactlyAndPostedWithTakeAllAndOpen() {
        allowNotifications()
        seedStack()
        rebuild()
        val armed = assertNotNull(alarm(ReminderKind.NUDGE), "tonight's nudge is armed")
        assertEquals(at(2026, 10, 12, 21).toEpochMilli(), armed.triggerAtMs)
        assertEquals(10 * 60 * 1000L, armed.windowLengthMs, "setWindow, 10 minutes: 21:00 to 21:10")
        assertEquals(AlarmManager.RTC_WAKEUP, armed.getType())
        assertNull(alarm(ReminderKind.TODO), "no to-do has a time")
        assertNull(alarm(ReminderKind.TRIAL), "no trial reminder is planned")
        assertNull(posted(Reminders.REQUEST_PREFIX + monday.ordinal), "nothing before its moment")

        // The alarm goes off inside its window: its receiver runs the rebuild.
        now = at(2026, 10, 12, 21, 4)
        rebuild()
        val nudge = assertNotNull(posted(Reminders.REQUEST_PREFIX + monday.ordinal))
        assertEquals("1 pending: FSH", nudge.text())
        assertEquals(ReminderKind.NUDGE.channelId, nudge.channelId)
        assertEquals(Notification.CATEGORY_REMINDER, nudge.category)
        assertEquals(Notification.VISIBILITY_PRIVATE, nudge.visibility)
        assertEquals("1 pending", nudge.publicVersion?.text(), "a lock screen that hides sensitive content shows the count only")
        val tap = shadowOf(nudge.contentIntent)
        assertTrue(tap.isActivityIntent, "a tap opens the activity directly, no trampoline")
        assertEquals(NudgeLink.url(monday), tap.savedIntent.data.toString())
        assertEquals(ComponentName(app, MainActivity.INTERNAL_LINK), tap.savedIntent.component, "Taken's own way in")

        assertEquals(listOf("TAKE ALL", "OPEN"), nudge.actions.map { it.title.toString() })
        val takeAll = shadowOf(nudge.actions[0].actionIntent)
        assertTrue(takeAll.isBroadcastIntent, "TAKE ALL runs without opening Taken")
        assertEquals(NudgeActionReceiver.ACTION_TAKE_ALL, takeAll.savedIntent.action)
        assertEquals(ComponentName(app, NudgeActionReceiver::class.java), takeAll.savedIntent.component)
        assertEquals(NudgeLink.url(monday), takeAll.savedIntent.data.toString())
        assertFalse(nudge.actions[0].isAuthenticationRequired, "TAKE ALL works from the lock screen")
        val open = shadowOf(nudge.actions[1].actionIntent)
        assertTrue(open.isActivityIntent)
        assertEquals(NudgeLink.url(monday), open.savedIntent.data.toString())

        assertEquals(at(2026, 10, 13, 21).toEpochMilli(), alarm(ReminderKind.NUDGE)?.triggerAtMs, "tomorrow's is armed next")
        rebuild()
        assertNotNull(posted(Reminders.REQUEST_PREFIX + monday.ordinal), "a rebuild leaves tonight's nudge while something is pending")
    }

    /** An alarm carries its own moment, so a lost record of it (a kill before it was written) never loses the nudge. */
    @Test
    fun testAnAlarmThatGoesOffPostsEvenIfItsRecordWasLost() {
        allowNotifications()
        seedStack()
        rebuild()
        @Suppress("DEPRECATION")
        val operation = assertNotNull(alarm(ReminderKind.NUDGE)).operation
        val carried = shadowOf(operation).savedIntent.getLongExtra(AndroidAlarms.EXTRA_ARMED_AT, -1L)
        assertEquals(at(2026, 10, 12, 21).toEpochMilli(), carried, "the alarm carries the moment it was armed for")

        com.tombaxter.taken.notify.PreferenceArmedMoments(app)[ReminderKind.NUDGE] = null
        now = at(2026, 10, 12, 21, 3)
        runBlocking { container.reminders.alarmWentOff(ReminderKind.NUDGE, java.time.Instant.ofEpochMilli(carried)) }
        assertEquals("1 pending: FSH", posted(Reminders.REQUEST_PREFIX + monday.ordinal)?.text())
        assertEquals(ReminderKind.NUDGE, AndroidAlarms.kind(AndroidAlarms.ACTION_PREFIX + "NUDGE"))
        assertNull(AndroidAlarms.kind("something.else"))
    }

    @Test
    fun testNothingIsArmedOrPostedWithoutNotifications() {
        seedStack()
        rebuild()
        assertNull(alarm(ReminderKind.NUDGE), "Android would not show it: no alarm")
        now = at(2026, 10, 12, 21, 4)
        rebuild()
        assertEquals(0, shadowOf(notificationManager).size())
        val receiver = ComponentName(app, RescheduleReceiver::class.java)
        assertTrue(app.packageManager.getComponentEnabledSetting(receiver) != PackageManager.COMPONENT_ENABLED_STATE_ENABLED)
    }

    @Test
    fun testTheRestartReceiverIsOnOnlyWhileSomethingIsArmed() {
        allowNotifications()
        val receiver = ComponentName(app, RescheduleReceiver::class.java)
        seedStack()
        rebuild()
        assertEquals(PackageManager.COMPONENT_ENABLED_STATE_ENABLED, app.packageManager.getComponentEnabledSetting(receiver))
        runBlocking { container.stores.stack.updateData { s -> s.clone().also { it.settings.setReminder(false) } } }
        rebuild()
        assertNull(alarm(ReminderKind.NUDGE), "the nudge turned off cancels its alarm")
        // The widgets and the tile say too (no widget, no tile: nothing of theirs is armed): only then does it go off.
        runBlocking { container.surfaces.refresh() }
        assertEquals(PackageManager.COMPONENT_ENABLED_STATE_DISABLED, app.packageManager.getComponentEnabledSetting(receiver))
        assertEquals(
            setOf("android.intent.action.BOOT_COMPLETED", "android.intent.action.TIME_SET", "android.intent.action.TIMEZONE_CHANGED", "android.intent.action.MY_PACKAGE_REPLACED"),
            RescheduleReceiver.ACTIONS,
        )
    }

    /**
     * A cold start never turns the restart receiver off and on again from half the facts: each change of a component's
     * state broadcasts PACKAGE_CHANGED, which makes Android reset and update every placed widget. And nothing is written
     * when nothing changes, the manifest's default (off) included.
     */
    @Test
    fun testTheRestartReceiverIsDecidedFromBothFactsAndNeverWrittenForNothing() {
        assertEquals(true, RescheduleReceiver.wanted(remindersArmed = true, surfacesArmed = null), "either armed: on at once")
        assertEquals(true, RescheduleReceiver.wanted(remindersArmed = null, surfacesArmed = true))
        assertEquals(true, RescheduleReceiver.wanted(remindersArmed = false, surfacesArmed = true))
        assertNull(RescheduleReceiver.wanted(remindersArmed = false, surfacesArmed = null), "the surfaces have not said yet: left as it is")
        assertNull(RescheduleReceiver.wanted(remindersArmed = null, surfacesArmed = false), "the reminders have not said yet")
        assertEquals(false, RescheduleReceiver.wanted(remindersArmed = false, surfacesArmed = false), "off once both say nothing is armed")

        val receiver = ComponentName(app, RescheduleReceiver::class.java)
        assertEquals(PackageManager.COMPONENT_ENABLED_STATE_DEFAULT, app.packageManager.getComponentEnabledSetting(receiver), "the manifest's off")
        RescheduleReceiver.setEnabled(app, false)
        assertEquals(PackageManager.COMPONENT_ENABLED_STATE_DEFAULT, app.packageManager.getComponentEnabledSetting(receiver), "already off: nothing written")
        RescheduleReceiver.setEnabled(app, true)
        assertEquals(PackageManager.COMPONENT_ENABLED_STATE_ENABLED, app.packageManager.getComponentEnabledSetting(receiver))
        RescheduleReceiver.setEnabled(app, false)
        assertEquals(PackageManager.COMPONENT_ENABLED_STATE_DISABLED, app.packageManager.getComponentEnabledSetting(receiver))
    }

    @Test
    fun testLastNightsNudgeIsNeverShownTheNextMorning() {
        allowNotifications()
        seedStack()
        rebuild()
        // The phone slept through 21:00 (Doze) and wakes on Tuesday at 08:00.
        now = at(2026, 10, 13, 8)
        rebuild()
        assertNull(posted(Reminders.REQUEST_PREFIX + monday.ordinal))
        assertEquals(at(2026, 10, 13, 21).toEpochMilli(), alarm(ReminderKind.NUDGE)?.triggerAtMs)
    }

    @Test
    fun testDueTimesPostAtTheirTimeAndGoOnceDone() {
        allowNotifications()
        val note = UUID(1, 1)
        val dentist = TodoTask(title = "Call the dentist", due = TodoDue.Time(at(2026, 10, 12, 16)), createdAt = now, noteId = note)
        val deck = TodoTask(title = "Send the deck", due = TodoDue.Time(at(2026, 10, 12, 17)), createdAt = now, noteId = note)
        runBlocking { container.stores.todos.updateData { TodoState(tasks = listOf(dentist, deck)) } }
        rebuild()
        assertEquals(at(2026, 10, 12, 16).toEpochMilli(), alarm(ReminderKind.TODO)?.triggerAtMs, "one alarm, the soonest")

        now = at(2026, 10, 12, 16, 2)
        rebuild()
        val due = assertNotNull(posted(TodoNotifications.identifier(dentist.id)))
        assertEquals("Call the dentist", due.title())
        assertEquals("Due 16:00", due.text())
        assertEquals(ReminderKind.TODO.channelId, due.channelId)
        assertEquals("Due 16:00", due.publicVersion?.text(), "never the words on a hidden lock screen")
        assertNull(due.publicVersion?.title())
        assertEquals(TodoCaptureRoute.revealUrl(dentist.id), shadowOf(due.contentIntent).savedIntent.data.toString())
        assertNull(posted(TodoNotifications.identifier(deck.id)), "17:00's waits for its own moment")
        assertEquals(at(2026, 10, 12, 17).toEpochMilli(), alarm(ReminderKind.TODO)?.triggerAtMs)

        runBlocking {
            container.stores.todos.updateData { s -> TodoState(tasks = s.tasks.map { if (it.id == dentist.id) it.copy(completedAt = now) else it }) }
        }
        rebuild()
        assertNull(posted(TodoNotifications.identifier(dentist.id)), "done: its notification is withdrawn")
    }

    @Test
    fun testWhatCameDueWhileThePhoneWasOffIsPostedOnceItIsBack() {
        allowNotifications()
        val note = UUID(2, 2)
        val dentist = TodoTask(title = "Call the dentist", due = TodoDue.Time(at(2026, 10, 12, 16)), createdAt = now, noteId = note)
        val deck = TodoTask(title = "Send the deck", due = TodoDue.Time(at(2026, 10, 12, 17)), createdAt = now, noteId = note)
        runBlocking { container.stores.todos.updateData { TodoState(tasks = listOf(dentist, deck)) } }
        rebuild()
        // Off from 15:50 to 18:00: every alarm went with the shutdown; BOOT_COMPLETED runs the rebuild.
        now = at(2026, 10, 12, 18)
        rebuild()
        assertNotNull(posted(TodoNotifications.identifier(dentist.id)))
        assertNotNull(posted(TodoNotifications.identifier(deck.id)))
        assertNull(alarm(ReminderKind.TODO), "nothing left to arm")
    }

    @Test
    fun testTakeAllLogsWhatIsPendingAndItsNudgeGoes() {
        allowNotifications()
        seedStack()
        rebuild()
        now = at(2026, 10, 12, 21, 4)
        rebuild()
        assertNotNull(posted(Reminders.REQUEST_PREFIX + monday.ordinal))

        val outcome = runBlocking { NudgeActions.takeAll(container, monday) }
        assertEquals(TakeAllOutcome.Logged(1), outcome)
        val state = runBlocking { container.stores.stack.data.first() }
        val fish = state.items.first { it.name == "Fish Oil" }
        assertEquals(listOf(now), state.doses.filter { it.itemId == fish.id }.map { it.takenAt }, "Fish Oil taken at 21:04")
        assertNull(posted(Reminders.REQUEST_PREFIX + monday.ordinal), "the nudge goes")

        val again = runBlocking { NudgeActions.takeAll(container, monday) }
        assertEquals(TakeAllOutcome.Logged(0), again, "a second TAKE ALL logs nothing more")
    }

    @Test
    fun testLastNightsTakeAllLogsNothingAndSaysSo() {
        allowNotifications()
        val before = seedStack()
        now = at(2026, 10, 13, 8)
        val outcome = runBlocking { NudgeActions.takeAll(container, monday) }
        assertIs<TakeAllOutcome.Stale>(outcome)
        assertEquals(before.doses, runBlocking { container.stores.stack.data.first() }.doses, "nothing logged")
        val note = assertNotNull(posted(Reminders.STALE_IDENTIFIER))
        assertEquals("Nothing logged. That nudge was for MON 12 OCT. Tap to open that day.", note.text())
        assertEquals(NudgeLink.url(monday), shadowOf(note.contentIntent).savedIntent.data.toString(), "a tap opens that day")
    }

    @Test
    fun testALockedTakeAllKeepsItForTakenAndSaysSo() {
        allowNotifications()
        val before = seedStack()
        runBlocking { container.stores.ledger.updateData { LedgerFile(ProLedger(firstSeenAt = at(2026, 9, 1, 9))) } }
        now = at(2026, 10, 12, 21, 4)
        val outcome = runBlocking { NudgeActions.takeAll(container, monday, pro = ProSource.locked) }
        assertIs<TakeAllOutcome.Locked>(outcome)
        assertEquals(before.doses, runBlocking { container.stores.stack.data.first() }.doses, "nothing is written")
        val pending = runBlocking { container.stores.ledger.data.first() }.ledger?.pending
        assertEquals(ProPendingAction.TakeAll, pending?.action, "kept for Taken to offer when it opens")
        assertEquals(now, pending?.at)
        assertEquals(ProCopy.LOCKED_DIALOG, posted(Reminders.LOCKED_IDENTIFIER)?.text())
    }
}
