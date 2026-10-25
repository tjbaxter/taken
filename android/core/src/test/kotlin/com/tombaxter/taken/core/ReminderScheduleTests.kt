package com.tombaxter.taken.core

import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.NudgeWindow
import com.tombaxter.taken.core.reminders.NudgeLink
import com.tombaxter.taken.core.reminders.Reminder
import com.tombaxter.taken.core.reminders.ReminderCopy
import com.tombaxter.taken.core.reminders.ReminderKind
import com.tombaxter.taken.core.reminders.ReminderSchedule
import com.tombaxter.taken.core.reminders.ReminderSnapshot
import com.tombaxter.taken.core.reminders.Reminders
import com.tombaxter.taken.core.reminders.TrialReminderSlot
import com.tombaxter.taken.core.stack.logDose
import com.tombaxter.taken.core.todo.TodoCaptureRoute
import com.tombaxter.taken.core.todo.TodoDue
import com.tombaxter.taken.core.todo.TodoNotifications
import com.tombaxter.taken.core.todo.TodoTask
import java.time.Duration
import java.time.Instant
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Android's delivery of the iPhone's plans (SPEC-ANDROID 10.4): one inexact alarm per kind for its soonest moment, what an
 * alarm posts when it goes off (on time, late, after a restart, or never once its day has gone), and which posted ones are
 * withdrawn. Fixtures as ReminderPlanTests: Vitamin D3 and Fish Oil in London, the nudge at 21:00, Mon 12 Oct 2026.
 */
class ReminderScheduleTests {

    private val monday = DayKey(2026, 10, 12)

    private fun stack(enabled: Boolean = true): StackState {
        val created = at(2026, 10, 1, 8)
        val state = StackState(
            items = listOf(
                makeItem("Vitamin D3", "VD3", created = created, sortIndex = 0),
                makeItem("Fish Oil", "FSH", created = created, sortIndex = 1),
            ),
        )
        state.settings.reminderEnabled = enabled
        state.settings.reminderMinutes = 21 * 60
        return state
    }

    private fun task(title: String, due: Instant?, done: Instant? = null) = TodoTask(
        title = title, due = due?.let { TodoDue.Time(it) }, createdAt = at(2026, 10, 12, 8), completedAt = done,
        noteId = UUID(1, 1),
    )

    private fun snapshot(
        stack: StackState = stack(),
        tasks: List<TodoTask> = emptyList(),
        window: NudgeWindow = NudgeWindow.Open,
        trial: TrialReminderSlot = TrialReminderSlot.none,
    ) = ReminderSnapshot(stack, tasks, window, london, trial)

    @Test
    fun testOneAlarmPerKindForItsSoonestMoment() {
        val tasks = listOf(
            task("Call the dentist", at(2026, 10, 12, 16)),
            task("Send the deck", at(2026, 10, 12, 11, 30)),
            task("Already past", at(2026, 10, 12, 8)),
            task("No time", null),
        )
        val s = snapshot(tasks = tasks)
        val now = at(2026, 10, 12, 9)
        assertEquals(at(2026, 10, 12, 21), ReminderSchedule.nextAlarm(s, ReminderKind.NUDGE, now), "tonight's nudge")
        assertEquals(at(2026, 10, 12, 11, 30), ReminderSchedule.nextAlarm(s, ReminderKind.TODO, now), "the soonest due time")
        assertNull(ReminderSchedule.nextAlarm(s, ReminderKind.TRIAL, now), "no trial reminder until the Pro lane plugs one in")
        assertEquals(Duration.ofMinutes(10), ReminderSchedule.WINDOW, "Android 12's smallest window")
    }

    @Test
    fun testNoAlarmsWhenNothingIsPlanned() {
        val now = at(2026, 10, 12, 9)
        assertNull(ReminderSchedule.nextAlarm(snapshot(stack(enabled = false)), ReminderKind.NUDGE, now), "the nudge is off")
        assertNull(ReminderSchedule.nextAlarm(snapshot(window = NudgeWindow.Closed), ReminderKind.NUDGE, now), "locked: no nudge")
        assertNull(ReminderSchedule.nextAlarm(snapshot(StackState()), ReminderKind.NUDGE, now), "no stack")
        assertNull(ReminderSchedule.nextAlarm(snapshot(), ReminderKind.TODO, now), "no to-dos with a time")
    }

    @Test
    fun testAnAlarmThatGoesOffPostsWhatCameDue() {
        val state = stack()
        val vd3 = state.items[0]
        state.logDose(vd3.id, at(2026, 10, 12, 7, 42), london)
        val tasks = listOf(
            task("Call the dentist", at(2026, 10, 12, 16)),
            task("Book the car in", at(2026, 10, 12, 16)),
            task("Send the deck", at(2026, 10, 12, 17)),
        )
        val s = snapshot(state, tasks)
        val armed = at(2026, 10, 12, 21)
        val nudge = ReminderSchedule.due(s, ReminderKind.NUDGE, armed, at(2026, 10, 12, 21, 4))
        assertEquals(listOf("1 pending: FSH"), nudge.map { it.body }, "inside the window: tonight's nudge, what is still pending")
        assertEquals(Reminders.REQUEST_PREFIX + monday.ordinal, nudge.single().tag)
        assertEquals(monday, nudge.single().day)
        assertNull(nudge.single().title, "a body only, as on the iPhone")

        val todos = ReminderSchedule.due(s, ReminderKind.TODO, at(2026, 10, 12, 16), at(2026, 10, 12, 16, 3))
        assertEquals(listOf("Call the dentist", "Book the car in"), todos.map { it.title }, "both due at 16:00, not 17:00's")
        assertEquals(listOf("Due 16:00", "Due 16:00"), todos.map { it.body })
        assertEquals(tasks.take(2).map { TodoNotifications.identifier(it.id) }, todos.map { it.tag })
        assertEquals(tasks.take(2).map { it.id }, todos.map { it.taskId })

        assertTrue(ReminderSchedule.due(s, ReminderKind.NUDGE, armed, at(2026, 10, 12, 20, 59)).isEmpty(), "never early")
    }

    @Test
    fun testANudgeThatComesDueAfterTheRolloverPostsNothing() {
        val s = snapshot()
        val armed = at(2026, 10, 12, 21)
        assertEquals(1, ReminderSchedule.due(s, ReminderKind.NUDGE, armed, at(2026, 10, 13, 1, 30)).size, "01:30 is still Monday")
        assertTrue(
            ReminderSchedule.due(s, ReminderKind.NUDGE, armed, at(2026, 10, 13, 8)).isEmpty(),
            "the phone slept through it: Monday's nudge on Tuesday morning is last night's",
        )
        assertEquals(at(2026, 10, 13, 21), ReminderSchedule.nextAlarm(s, ReminderKind.NUDGE, at(2026, 10, 13, 8)), "Tuesday's is next")
    }

    @Test
    fun testWhatWasDoneBeforeALateAlarmIsLeftOut() {
        val state = stack()
        val armed = at(2026, 10, 12, 21)
        state.items.forEach { state.logDose(it.id, at(2026, 10, 12, 21, 2), london) }
        val dentist = task("Call the dentist", at(2026, 10, 12, 16), done = at(2026, 10, 12, 16, 1))
        val s = snapshot(state, listOf(dentist))
        assertTrue(ReminderSchedule.due(s, ReminderKind.NUDGE, armed, at(2026, 10, 12, 21, 6)).isEmpty(), "all taken at 21:02")
        assertTrue(ReminderSchedule.due(s, ReminderKind.TODO, at(2026, 10, 12, 16), at(2026, 10, 12, 16, 5)).isEmpty(), "done at 16:01")
    }

    @Test
    fun testWhatCameDueWhileThePhoneWasOffIsPostedWhenItIsBack() {
        val tasks = listOf(task("Call the dentist", at(2026, 10, 12, 16)), task("Send the deck", at(2026, 10, 12, 17)))
        val s = snapshot(tasks = tasks)
        // Armed for 16:00; the phone was off from 15:50 to 18:00, which cancels every alarm; the boot rebuild catches up.
        val due = ReminderSchedule.due(s, ReminderKind.TODO, at(2026, 10, 12, 16), at(2026, 10, 12, 18))
        assertEquals(listOf("Call the dentist", "Send the deck"), due.map { it.title })
        assertNull(ReminderSchedule.nextAlarm(s, ReminderKind.TODO, at(2026, 10, 12, 18)), "nothing left to arm")
        assertEquals(1, ReminderSchedule.due(snapshot(), ReminderKind.NUDGE, at(2026, 10, 12, 21), at(2026, 10, 12, 22)).size)
    }

    @Test
    fun testADueTimeFromAnEarlierDateIsNeverPostedLate() {
        val s = snapshot(tasks = listOf(task("Call the dentist", at(2026, 10, 12, 16))))
        assertEquals(1, ReminderSchedule.due(s, ReminderKind.TODO, at(2026, 10, 12, 16), at(2026, 10, 12, 23, 59)).size)
        assertTrue(
            ReminderSchedule.due(s, ReminderKind.TODO, at(2026, 10, 12, 16), at(2026, 10, 13, 0, 1)).isEmpty(),
            "off until after midnight: \"Due 16:00\" would read as today's",
        )
    }

    @Test
    fun testNothingIsDueBeforeItsArmedMoment() {
        val s = snapshot(tasks = listOf(task("Call the dentist", at(2026, 10, 12, 16))))
        assertTrue(ReminderSchedule.due(s, ReminderKind.TODO, at(2026, 10, 12, 16), at(2026, 10, 12, 15)).isEmpty())
        assertTrue(ReminderSchedule.due(s, ReminderKind.NUDGE, at(2026, 10, 12, 21), at(2026, 10, 12, 9)).isEmpty())
    }

    @Test
    fun testANudgeStopsWhereAPlanSetNotToRenewEnds() {
        val ends = at(2026, 10, 15, 12)
        val s = snapshot(window = NudgeWindow.Until(ends))
        assertEquals(at(2026, 10, 12, 21), ReminderSchedule.nextAlarm(s, ReminderKind.NUDGE, at(2026, 10, 12, 9)))
        assertNull(ReminderSchedule.nextAlarm(s, ReminderKind.NUDGE, at(2026, 10, 14, 22)), "no nudge after the plan ends")
    }

    /** The trial reminder's slot: the Pro lane's plan plugs in, and Reminders delivers and withdraws it. */
    @Test
    fun testTheTrialReminderPlugsIntoItsSlot() {
        val fireAt = at(2026, 10, 31, 9, 14)
        var applies = true
        val slot = object : TrialReminderSlot {
            override fun planned(at: Instant): Reminder? =
                Reminder(ReminderKind.TRIAL, TrialReminderSlot.TAG, fireAt, title = null, body = "Your trial ends Wed 4 Nov.")
                    .takeIf { fireAt > at }
            override fun stillApplies(now: Instant): Boolean = applies
            override suspend fun posted(reminder: Reminder, now: Instant) = Unit
        }
        val s = snapshot(trial = slot)
        assertEquals(fireAt, ReminderSchedule.nextAlarm(s, ReminderKind.TRIAL, at(2026, 10, 28, 9, 14)))
        assertEquals(
            listOf("Your trial ends Wed 4 Nov."),
            ReminderSchedule.due(s, ReminderKind.TRIAL, fireAt, at(2026, 10, 31, 9, 20)).map { it.body },
        )
        assertTrue(ReminderSchedule.withdrawn(listOf(TrialReminderSlot.TAG), s, at(2026, 10, 31, 10)).isEmpty())
        applies = false
        assertEquals(listOf(TrialReminderSlot.TAG), ReminderSchedule.withdrawn(listOf(TrialReminderSlot.TAG), s, at(2026, 10, 31, 10)))
    }

    @Test
    fun testPostedOnesAreWithdrawnOnceTheyNoLongerApply() {
        val open = task("Call the dentist", at(2026, 10, 12, 16))
        val done = task("Send the deck", at(2026, 10, 12, 11), done = at(2026, 10, 12, 11, 5))
        val gone = UUID(9, 9)
        val active = listOf(
            Reminders.REQUEST_PREFIX + monday.adding(-1).ordinal,
            Reminders.REQUEST_PREFIX + monday.ordinal,
            Reminders.STALE_IDENTIFIER,
            Reminders.LOCKED_IDENTIFIER,
            TodoNotifications.identifier(open.id),
            TodoNotifications.identifier(done.id),
            TodoNotifications.identifier(gone),
            TrialReminderSlot.TAG,
        )
        val withdrawn = ReminderSchedule.withdrawn(active, snapshot(tasks = listOf(open, done)), at(2026, 10, 12, 21, 30))
        assertEquals(
            listOf(
                Reminders.REQUEST_PREFIX + monday.adding(-1).ordinal, Reminders.STALE_IDENTIFIER, Reminders.LOCKED_IDENTIFIER,
                TodoNotifications.identifier(done.id), TodoNotifications.identifier(gone), TrialReminderSlot.TAG,
            ),
            withdrawn,
            "yesterday's nudge, the one-off notes, a done or deleted to-do's, a trial reminder nobody plans; tonight's stays",
        )
        // Erase all data: no stack and no to-dos, so every one goes.
        val erased = ReminderSchedule.withdrawn(active, snapshot(StackState(), emptyList()), at(2026, 10, 12, 21, 30))
        assertEquals(active.toSet(), erased.toSet(), "Erase all data withdraws every notification")
    }

    @Test
    fun testTheLinksANotificationOpens() {
        assertEquals("taken://nudge?day=${monday.ordinal}", NudgeLink.url(monday))
        assertEquals(monday, NudgeLink.day(NudgeLink.url(monday)))
        assertNull(NudgeLink.day("taken://nudge"))
        assertNull(NudgeLink.day("taken://nudge?day=x"))
        assertNull(NudgeLink.day("taken://today?day=20738"))

        val id = UUID.fromString("7A4E0000-0000-4000-8000-000000000BAD")
        val reveal = TodoCaptureRoute.revealUrl(id)
        assertEquals("taken://todo?task=7A4E0000-0000-4000-8000-000000000BAD", reveal)
        assertEquals(TodoCaptureRoute.Route.LIST, TodoCaptureRoute.route(reveal), "it opens the list, never the mic")
        assertEquals(id, TodoCaptureRoute.taskId(reveal))
        assertNull(TodoCaptureRoute.taskId("taken://todo"))
        assertNull(TodoCaptureRoute.taskId("taken://todo?task=nope"))
        assertNull(TodoCaptureRoute.taskId("taken://pro?task=${id}"))
    }

    @Test
    fun testTheRemindersWordsKeepTheCopyRules() {
        ReminderCopy.all.forEach(::assertCopyRules)
        assertEquals("2 pending", ReminderCopy.nudgePublic("2 pending: VD3, FSH"), "a hidden lock screen shows the count only")
        assertEquals(
            "Taken nudges you at 20:00 if anything is still pending, and tells you when a to-do with a time is due. Nothing else.",
            ReminderCopy.askBody(20 * 60),
        )
        assertEquals(
            "Taken nudges you at 21:00 if anything is still pending, tells you when a to-do with a time is due, and reminds you once, 3 days before your trial ends. Nothing else.",
            ReminderCopy.askBody(21 * 60, trialReminder = true),
            "while the trial reminder can still come under the same permission, the explanation names it",
        )
        assertEquals(listOf("Evening nudge", "Trial reminder", "To-do due times"), ReminderKind.entries.map { it.channelName })
        assertEquals(3, ReminderKind.entries.map { it.channelId }.toSet().size, "one channel each, so each can be silenced")
    }
}
