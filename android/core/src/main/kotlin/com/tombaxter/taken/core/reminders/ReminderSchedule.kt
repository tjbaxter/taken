package com.tombaxter.taken.core.reminders

import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.NudgeWindow
import com.tombaxter.taken.core.todo.TodoNotifications
import com.tombaxter.taken.core.todo.TodoTask
import java.net.URI
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.util.UUID

/**
 * The three kinds of notification Taken posts (SPEC-ANDROID 10.4). Each has its own channel, so each can be silenced in
 * Android's settings (https://developer.android.com/develop/ui/views/notifications/channels), and its own alarm.
 */
enum class ReminderKind(val channelId: String, val channelName: String, val channelDescription: String) {
    NUDGE("taken.nudge", "Evening nudge", "At your nudge time, only while something is still pending."),
    TRIAL("taken.trial", "Trial reminder", "Once, 3 days before a Taken Pro trial ends."),
    TODO("taken.todo", "To-do due times", "A to-do with a time, at that time."),
}

/**
 * One notification Taken means to post at a moment: the iPhone's notification request, in Android's shape. `tag` is the
 * iPhone's request identifier ("taken.nudge.day.20738", "taken.todo.<UUID>"), used as the notification's tag, so the
 * iPhone's withdrawal rules ([Reminders.staleDelivered], [TodoNotifications.staleDelivered]) read Android's posted ones.
 */
data class Reminder(
    val kind: ReminderKind,
    val tag: String,
    val fireAt: Instant,
    /** The to-do's words; the nudge and the trial reminder have none (the iPhone sets a body only). */
    val title: String?,
    val body: String,
    /** A nudge: the logical day it is for. */
    val day: DayKey? = null,
    /** A due-time notification: its to-do. */
    val taskId: UUID? = null,
)

/**
 * Where the trial reminder plugs in. Taken Pro (NEXT 2, SPEC-ANDROID 9.7) owns its rules (`TrialReminder.plan`, the mark
 * in pro.json); Reminders owns its delivery: the "Trial reminder" channel and its alarm. Until the integrator plugs the
 * Pro lane's plan in here, [none] plans nothing and the trial reminder's words stay on Today (`trialReminderDeliverable`).
 * The scheduler calls it off the main thread, one rebuild at a time.
 */
interface TrialReminderSlot {
    /** The trial reminder that should exist with its moment after `at` (a [Reminder] of kind TRIAL, tag [TAG]), or null. */
    fun planned(at: Instant): Reminder?

    /** A delivered trial reminder still applies at `now` (a renewing trial, Profile's Trial reminder on). */
    fun stillApplies(now: Instant): Boolean

    /** It was posted at `now`: the Pro lane records it in pro.json (`ProLedgers.withTrialReminder`), so it never comes twice. */
    fun posted(reminder: Reminder, now: Instant)

    companion object {
        /** The iPhone's identifier for the one trial reminder (Shared/TrialReminder.swift). */
        const val TAG = "taken.pro.trial-end"

        /** No trial reminder planned (until the Pro lane's plan is plugged in). */
        val none: TrialReminderSlot = object : TrialReminderSlot {
            override fun planned(at: Instant): Reminder? = null
            override fun stillApplies(now: Instant): Boolean = false
            override fun posted(reminder: Reminder, now: Instant) = Unit
        }
    }
}

/** Everything the reminders are planned from, read at one moment. */
data class ReminderSnapshot(
    val stack: StackState,
    val tasks: List<TodoTask>,
    /** How far ahead the nudge may go: `ProGate.nudgeWindow` (closed while locked). */
    val window: NudgeWindow,
    val zone: ZoneId,
    val trial: TrialReminderSlot = TrialReminderSlot.none,
)

/**
 * How the iPhone's plans become Android alarms (SPEC-ANDROID 10.4). The plans decide what and when, exactly as on the
 * iPhone ([Reminders.plan]: 14 nudge days; [TodoNotifications.plan]: up to 30 due times; the trial reminder from its
 * slot). Android keeps **one alarm per kind**, for the soonest planned moment, and when it goes off posts what has come
 * due and arms the next. [Own choice, the shape Tasks.org ships: one PendingIntent, set for the next reminder time,
 * https://github.com/tasks/tasks/blob/main/app/src/main/java/org/tasks/jobs/WorkManagerImpl.kt `scheduleNotification`.]
 *
 * An alarm is inexact (`setWindow`, [WINDOW]): Android delivers it in the window "unless any battery-saving restrictions
 * are in effect", and "alarms don't fire when the device is in Doze mode" but are "deferred until the device exits Doze"
 * (https://developer.android.com/develop/background-work/services/alarms/schedule). So the moment an alarm was armed for
 * is kept ("armed"), and whatever came due since it is posted whenever the plans are rebuilt after it: when the alarm
 * goes off late, when Taken opens first, or after a restart that cleared it ("all alarms are canceled when a device
 * shuts down", same page). [Own choice: nothing that was due is lost to a rebuild that ran before its alarm.]
 */
object ReminderSchedule {
    /**
     * The delivery window. "If your app targets Android 12 or higher, the smallest allowed window length is 10 minutes"
     * (https://developer.android.com/develop/background-work/services/alarms/schedule): a 20:00 nudge lands 20:00 to 20:10.
     */
    val WINDOW: Duration = Duration.ofMinutes(10)

    /** One kind's notifications planned with their moment after `at`, soonest first. */
    fun planned(snapshot: ReminderSnapshot, kind: ReminderKind, at: Instant): List<Reminder> = when (kind) {
        ReminderKind.NUDGE -> Reminders.plan(snapshot.stack, at, snapshot.zone, snapshot.window).map {
            Reminder(ReminderKind.NUDGE, it.identifier, it.fireDate, title = null, body = it.body, day = it.day)
        }
        // The iPhone formats the due time with `DayClock(dayStartHour: 4)`: only the zone matters for "Due 16:00".
        ReminderKind.TODO -> TodoNotifications.plan(snapshot.tasks, at, DayClock(4, snapshot.zone)).map {
            Reminder(ReminderKind.TODO, it.identifier, it.fireDate, title = it.title, body = it.body, taskId = it.taskId)
        }
        ReminderKind.TRIAL -> listOfNotNull(snapshot.trial.planned(at)).filter { it.kind == ReminderKind.TRIAL && it.fireAt > at }
    }.sortedBy { it.fireAt }

    /** The moment a kind's one alarm is armed for: its soonest planned moment after `now`, or null when it plans none. */
    fun nextAlarm(snapshot: ReminderSnapshot, kind: ReminderKind, now: Instant): Instant? =
        planned(snapshot, kind, now).firstOrNull()?.fireAt

    /**
     * What a kind posts at `now`, its alarm having been armed for `armedAt`: the notifications planned, just before that
     * moment, to come from it on, and due by now, read from the stack and the to-dos as they are now (a dose logged or a
     * to-do done since leaves its notification out). A nudge is posted only on the day it is for: one that comes due
     * after the day has rolled over is last night's, which the iPhone never shows either. A due time is posted only on
     * its own date, since "Due 16:00" names no day [Own choice]. Nothing when `armedAt` is still to come.
     */
    fun due(snapshot: ReminderSnapshot, kind: ReminderKind, armedAt: Instant, now: Instant): List<Reminder> {
        if (armedAt > now) return emptyList()
        val today = now.atZone(snapshot.zone).toLocalDate()
        return planned(snapshot, kind, armedAt.minusMillis(1))
            .filter { it.fireAt <= now }
            .filter { it.kind != ReminderKind.NUDGE || Reminders.isCurrent(it.day, snapshot.stack, now, snapshot.zone) }
            .filter { it.kind != ReminderKind.TODO || it.fireAt.atZone(snapshot.zone).toLocalDate() == today }
    }

    /**
     * Posted notifications to withdraw at `now`: the iPhone's rules for each kind. Earlier days' nudges, and today's once
     * nothing is pending ([Reminders.staleDelivered], which also takes the one-off stale and locked notes); due times
     * whose to-do is done or deleted ([TodoNotifications.staleDelivered]); the trial reminder once it no longer applies.
     */
    fun withdrawn(active: List<String>, snapshot: ReminderSnapshot, now: Instant): List<String> {
        val nudges = Reminders.staleDelivered(active, snapshot.stack, now, snapshot.zone)
        val todos = TodoNotifications.staleDelivered(active, snapshot.tasks)
        val trial = active.filter { it == TrialReminderSlot.TAG && !snapshot.trial.stillApplies(now) }
        return (nudges + todos + trial).distinct()
    }
}

/**
 * `taken://nudge?day=<ordinal>`: where a tapped nudge (or its OPEN, or the stale note) sends Taken, the day it was for
 * (Taken/TakenApp.swift `NudgeRoute`). Today's opens Today; an earlier day's opens its day sheet over History. Android
 * only; the notification's own intent carries it to MainActivity (SPEC-ANDROID 10.3).
 */
object NudgeLink {
    const val SCHEME = "taken"
    const val HOST = "nudge"

    fun url(day: DayKey): String = "$SCHEME://$HOST?day=${day.ordinal}"

    /** The day a nudge link is for, or null for any other link. */
    fun day(url: String): DayKey? {
        val uri = try {
            URI(url)
        } catch (e: Exception) {
            return null
        }
        if (uri.scheme != SCHEME || uri.host != HOST) return null
        val value = (uri.rawQuery ?: "").split("&").map { it.split("=", limit = 2) }
            .firstOrNull { it.firstOrNull() == "day" }?.getOrNull(1) ?: return null
        return value.toIntOrNull()?.let { DayKey(it) }
    }
}

/** The words of the reminders on Android (no dashes, never the word for no charge, no exclamation marks). */
object ReminderCopy {
    const val SECTION = "Reminder"
    const val NUDGE = "Nudge"
    const val TIME = "Time"
    const val NUDGE_TIME = "Nudge time"

    /** Profile's footnote under Reminder (Taken/Views/ProfileView.swift `nudgeFootnote`). */
    const val FOOTNOTE = "If anything is still pending at this time, Taken nudges you."

    /** Profile > Reminder without Pro: no nudge is scheduled (Shared/ProCopy.swift `nudgeLocked`). */
    const val NUDGE_LOCKED = "The nudge needs Taken Pro"

    /** Profile > Reminder once Android will not show Taken's notifications (the iPhone's row, word for word). */
    const val NOTIFICATIONS_OFF = "Notifications are off for Taken. Open Settings"

    /** Profile > Reminder while only the "Evening nudge" channel is turned off in Android's settings. [Own choice] */
    const val NUDGE_CHANNEL_OFF = "Nudge notifications are off for Taken. Open Settings"

    /** The nudge's two actions (Shared/Reminders.swift `registerCategories`). */
    const val TAKE_ALL = "TAKE ALL"
    const val OPEN = "OPEN"

    /**
     * The explanation Android asks for before its notification prompt comes again (`shouldShowRequestPermissionRationale`,
     * https://developer.android.com/develop/ui/views/notifications/notification-permission), with Continue and Not now.
     * [Own choice for the words, Tom may edit]
     */
    const val ASK_TITLE = "Notifications for Taken"

    fun askBody(minutes: Int): String =
        "Taken nudges you at ${Fmt.minutes(minutes)} if anything is still pending, and tells you when a to-do with a time is due. Nothing else."

    const val CONTINUE = "Continue"
    const val NOT_NOW = "Not now"

    /**
     * What a lock screen set to hide sensitive content shows instead (Android's public version,
     * https://developer.android.com/develop/ui/views/notifications/build-notification): the count, never the codes, as the
     * Quick Settings tile never names items over the lock screen (SPEC-ANDROID 10.2). [Own choice]
     */
    fun nudgePublic(body: String): String = body.substringBefore(':')

    /** A due to-do on such a lock screen: the time, never the words. */
    fun todoPublic(body: String): String = body

    val all: List<String>
        get() = listOf(
            SECTION, NUDGE, TIME, NUDGE_TIME, FOOTNOTE, NUDGE_LOCKED, NOTIFICATIONS_OFF, NUDGE_CHANNEL_OFF, TAKE_ALL, OPEN,
            ASK_TITLE, askBody(20 * 60), CONTINUE, NOT_NOW, nudgePublic(Reminders.body(listOf("VD3", "FSH"))), ReminderKind.NUDGE.channelName,
            ReminderKind.NUDGE.channelDescription, ReminderKind.TRIAL.channelName, ReminderKind.TRIAL.channelDescription,
            ReminderKind.TODO.channelName, ReminderKind.TODO.channelDescription,
        )
}
