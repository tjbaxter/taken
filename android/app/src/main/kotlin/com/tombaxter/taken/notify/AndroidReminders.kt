package com.tombaxter.taken.notify

import android.Manifest
import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.tombaxter.taken.R
import com.tombaxter.taken.core.reminders.NudgeLink
import com.tombaxter.taken.core.reminders.Reminder
import com.tombaxter.taken.core.reminders.ReminderCopy
import com.tombaxter.taken.core.reminders.ReminderKind
import com.tombaxter.taken.core.reminders.ReminderSchedule
import com.tombaxter.taken.core.todo.TodoCaptureRoute
import com.tombaxter.taken.widget.takenIntent
import java.time.Instant

/**
 * The three channels, one per kind, so each can be silenced on its own (SPEC-ANDROID 10.4). Created when Taken starts:
 * "Because you must create the notification channel before posting notifications on Android 8.0 and higher, execute
 * this code when your app starts. It's safe to call repeatedly because creating an existing channel does nothing"
 * (https://developer.android.com/develop/ui/views/notifications/build-notification).
 *
 * Importance DEFAULT ("Makes a sound", https://developer.android.com/develop/ui/views/notifications/channels): the iPhone
 * plays the default sound for each and never asks for Time Sensitive, so no heads-up [Own choice for the mapping].
 */
object ReminderChannels {
    fun ensure(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannels(
            ReminderKind.entries.map { kind ->
                NotificationChannel(kind.channelId, kind.channelName, NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = kind.channelDescription
                }
            },
        )
    }

    /** The person turned this channel off in Android's settings ("None": no sound, not in the shade). */
    fun isOff(context: Context, kind: ReminderKind): Boolean =
        context.getSystemService(NotificationManager::class.java)?.getNotificationChannel(kind.channelId)?.importance ==
            NotificationManager.IMPORTANCE_NONE
}

/**
 * One inexact alarm per kind: `setWindow(RTC_WAKEUP, at, 10 minutes)`. Google: create "an inexact alarm whenever
 * possible", and `setWindow()` "never goes off before the supplied trigger time"; no exact-alarm permission, which Play
 * keeps for alarm, timer and calendar apps (SPEC-ANDROID 10.4, https://developer.android.com/develop/background-work/services/alarms/schedule).
 * RTC_WAKEUP because each moment is a time on the wall clock (a nudge at 20:00 where the phone is). Each kind has its own
 * PendingIntent to [ReminderAlarmReceiver], so arming replaces that kind's alarm and nothing else.
 */
class AndroidAlarms(private val context: Context) : AlarmPort {
    private val manager: AlarmManager? get() = context.getSystemService(AlarmManager::class.java)

    override fun arm(kind: ReminderKind, at: Instant) {
        manager?.setWindow(AlarmManager.RTC_WAKEUP, at.toEpochMilli(), ReminderSchedule.WINDOW.toMillis(), operation(kind, at))
    }

    override fun cancel(kind: ReminderKind) {
        manager?.cancel(operation(kind, null))
    }

    /** The kind's one PendingIntent (told apart by its action), carrying the moment it was armed for. */
    private fun operation(kind: ReminderKind, at: Instant?): PendingIntent {
        val intent = Intent(context, ReminderAlarmReceiver::class.java).setAction(ACTION_PREFIX + kind.name)
        if (at != null) intent.putExtra(EXTRA_ARMED_AT, at.toEpochMilli())
        return PendingIntent.getBroadcast(context, kind.ordinal, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    companion object {
        const val ACTION_PREFIX = "com.tombaxter.taken.reminder."
        const val EXTRA_ARMED_AT = "com.tombaxter.taken.reminder.ARMED_AT"

        /** The kind an alarm's intent is for, from its action. */
        fun kind(action: String?): ReminderKind? =
            action?.takeIf { it.startsWith(ACTION_PREFIX) }?.removePrefix(ACTION_PREFIX)?.let { name ->
                ReminderKind.entries.firstOrNull { it.name == name }
            }
    }
}

/**
 * The armed moments in the app's own SharedPreferences (`taken.reminders.xml`): a few numbers about alarms, not the
 * person's data, and outside Auto Backup's include list (SPEC-ANDROID 5.4), so a restored phone never posts the old
 * phone's reminders. [Own choice]
 */
class PreferenceArmedMoments(context: Context) : ArmedMoments {
    private val prefs = context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    override fun get(kind: ReminderKind): Instant? =
        prefs.getLong(key(kind), -1L).takeIf { it >= 0 }?.let(Instant::ofEpochMilli)

    /** Written at once (`commit`): rebuilds run off the main thread, and an alarm must find its moment after a kill. */
    @SuppressLint("ApplySharedPref")
    override fun set(kind: ReminderKind, at: Instant?) {
        if (get(kind) == at) return
        val edit = prefs.edit()
        if (at == null) edit.remove(key(kind)) else edit.putLong(key(kind), at.toEpochMilli())
        edit.commit()
    }

    private fun key(kind: ReminderKind) = "armed.${kind.name.lowercase()}"

    companion object {
        const val FILE = "taken.reminders"
    }
}

/**
 * Taken's notifications through NotificationManager. Every one has the same id and its iPhone identifier as the tag, so
 * the iPhone's withdrawal rules read what Android shows (`getActiveNotifications`).
 *
 * - **The nudge**: "2 pending: VD3, FSH" with TAKE ALL (a broadcast to [NudgeActionReceiver], allowed from the lock
 *   screen with `setAuthenticationRequired(false)`) and OPEN (`PendingIntent.getActivity` straight to MainActivity, as
 *   notification trampolines are blocked from Android 12, https://developer.android.com/about/versions/12/behavior-changes-12).
 *   A tap and OPEN open that day (`taken://nudge?day=`).
 * - **A due time**: the to-do's words as the title, "Due 16:00"; a tap opens To-do scrolled to it (`taken://todo?task=`).
 * - **The trial reminder**: its words; a tap opens Taken.
 *
 * On a lock screen set to hide sensitive content, the public version shows the count or the time only (`VISIBILITY_PRIVATE`
 * with `setPublicVersion`, https://developer.android.com/develop/ui/views/notifications/build-notification).
 *
 * Activities open with `FLAG_ACTIVITY_NEW_TASK` on MainActivity, the task's root and only activity (`singleTask`): a
 * running Taken gets the link through `onNewIntent` and keeps its screen [Own choice: TaskStackBuilder's parent stack
 * would be MainActivity alone, and its CLEAR_TASK restarts the screen].
 */
class AndroidNotifications(private val context: Context) : NotificationPort {
    private val manager: NotificationManager? get() = context.getSystemService(NotificationManager::class.java)

    override val allowed: Boolean get() = allowed(context)

    override fun active(): List<String> =
        manager?.activeNotifications.orEmpty().filter { it.id == ID }.mapNotNull { it.tag }

    override fun post(reminder: Reminder) {
        val link = when (reminder.kind) {
            ReminderKind.NUDGE -> reminder.day?.let(NudgeLink::url) ?: TODAY
            ReminderKind.TODO -> reminder.taskId?.let(TodoCaptureRoute::revealUrl) ?: TodoCaptureRoute.LIST_URL
            ReminderKind.TRIAL -> TODAY
        }
        val publicText = when (reminder.kind) {
            ReminderKind.NUDGE -> ReminderCopy.nudgePublic(reminder.body)
            ReminderKind.TODO -> ReminderCopy.todoPublic(reminder.body)
            ReminderKind.TRIAL -> null
        }
        val builder = base(reminder.kind, reminder.body, link)
            .setWhen(reminder.fireAt.toEpochMilli())
            .setShowWhen(true)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
        reminder.title?.let { builder.setContentTitle(it) }
        if (publicText != null) {
            builder.setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
                .setPublicVersion(base(reminder.kind, publicText, link).build())
        }
        val day = reminder.day
        if (reminder.kind == ReminderKind.NUDGE && day != null) {
            builder.addAction(
                NotificationCompat.Action.Builder(0, ReminderCopy.TAKE_ALL, NudgeActionReceiver.takeAll(context, day))
                    // TAKE ALL works from the lock screen, like the iPhone's background action (SPEC-ANDROID 10.4).
                    .setAuthenticationRequired(false)
                    .build(),
            )
            builder.addAction(NotificationCompat.Action.Builder(0, ReminderCopy.OPEN, activity(link)).build())
        }
        notify(reminder.tag, builder)
    }

    /** A one-off line on the nudge's channel: the stale TAKE ALL ("Nothing logged...") or the locked one. */
    fun postNote(tag: String, body: String, link: String) {
        notify(tag, base(ReminderKind.NUDGE, body, link))
    }

    override fun withdraw(tags: List<String>) {
        val manager = manager ?: return
        for (tag in tags) manager.cancel(tag, ID)
    }

    private fun base(kind: ReminderKind, body: String, link: String): NotificationCompat.Builder =
        NotificationCompat.Builder(context, kind.channelId)
            .setSmallIcon(R.drawable.ic_stat_taken)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(activity(link))
            .setAutoCancel(true)

    private fun activity(link: String): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        takenIntent(context, link),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun notify(tag: String, builder: NotificationCompat.Builder) {
        // Android 13 and later post nothing without POST_NOTIFICATIONS; Google's own sample checks it right before
        // notify() (https://developer.android.com/develop/ui/views/notifications/build-notification).
        if (Build.VERSION.SDK_INT >= 33 &&
            ActivityCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        NotificationManagerCompat.from(context).notify(tag, ID, builder.build())
    }

    companion object {
        /** One id for all of Taken's notifications; the tag tells them apart. */
        const val ID = 1

        const val TODAY = "taken://today"

        /**
         * Android shows Taken's notifications: "Before your app sends a notification, confirm whether the user has
         * enabled notifications for your app. To do so, call `areNotificationsEnabled()`"
         * (https://developer.android.com/develop/ui/views/notifications/notification-permission), and from Android 13
         * POST_NOTIFICATIONS is granted.
         */
        fun allowed(context: Context): Boolean {
            if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
            if (Build.VERSION.SDK_INT < 33) return true
            return ActivityCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        }
    }
}
