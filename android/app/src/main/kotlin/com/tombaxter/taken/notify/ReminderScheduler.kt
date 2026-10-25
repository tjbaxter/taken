package com.tombaxter.taken.notify

import com.tombaxter.taken.core.reminders.Reminder
import com.tombaxter.taken.core.reminders.ReminderKind
import com.tombaxter.taken.core.reminders.ReminderSchedule
import com.tombaxter.taken.core.reminders.ReminderSnapshot
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.time.Instant

/** One inexact alarm per kind (AlarmManager in the app, a fake in tests). */
interface AlarmPort {
    /** Arms `kind`'s one alarm for `at`, replacing the one it had. */
    fun arm(kind: ReminderKind, at: Instant)

    /** Cancels `kind`'s alarm, if it has one. */
    fun cancel(kind: ReminderKind)
}

/** Posting and withdrawing Taken's notifications (NotificationManager in the app, a fake in tests). */
interface NotificationPort {
    /** Android will show Taken's notifications: on for the app, and POST_NOTIFICATIONS granted on Android 13 and later. */
    val allowed: Boolean

    /** The tags of Taken's notifications on screen now. */
    fun active(): List<String>

    fun post(reminder: Reminder)

    fun withdraw(tags: List<String>)
}

/** The moment each kind's alarm was armed for, kept across process deaths and restarts (not user data, never backed up). */
interface ArmedMoments {
    operator fun get(kind: ReminderKind): Instant?

    operator fun set(kind: ReminderKind, at: Instant?)
}

/**
 * Taken's reminders on Android (SPEC-ANDROID 10.4): the scheduling API every kind goes through. [rebuild] is the one entry
 * point, and it is safe to call at any moment, from any surface:
 * 1. for each kind whose alarm moment has come (on time, late in Doze, or missed across a restart), it posts what came due
 *    since ([ReminderSchedule.due]);
 * 2. it arms each kind's one alarm for its next planned moment, or cancels it ([ReminderSchedule.nextAlarm]);
 * 3. it withdraws posted notifications that no longer apply ([ReminderSchedule.withdrawn]);
 * 4. it tells [onArmed] whether any alarm is armed, so the receiver for restarts and clock changes is enabled only then.
 *
 * Nothing is armed or posted while Android will not show Taken's notifications (the iPhone adds its requests "only with
 * permission"). Rebuilds run one at a time, off the main thread (they read files and talk to the system's alarm and
 * notification services), and a caller returns once a rebuild that began after its call has finished; calls that arrive
 * while one runs share the next one. Callers: every write to taken.json or todos.json (the stores'
 * changes, AppContainer), Taken coming to the front, permission granted, Pro changing (`AppModel.onProChanged`), an alarm
 * going off, a nudge's TAKE ALL, a restart, a clock or time zone change, and an update of the app.
 *
 * The trial reminder plugs in through the snapshot's [com.tombaxter.taken.core.reminders.TrialReminderSlot]; once one is
 * posted, the slot hears of it ([com.tombaxter.taken.core.reminders.TrialReminderSlot.posted]).
 */
class ReminderScheduler(
    private val snapshot: suspend () -> ReminderSnapshot?,
    private val alarms: AlarmPort,
    private val notifications: NotificationPort,
    private val armed: ArmedMoments,
    private val clock: () -> Instant = { Instant.now() },
    private val onArmed: (Boolean) -> Unit = {},
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
) {
    private val mutex = Mutex()
    private val lock = Any()
    private var requested = 0L
    private var finished = 0L

    /** Brings the alarms and the posted notifications in line with the files, as described above. */
    suspend fun rebuild(): Unit = withContext(dispatcher) {
        val ticket = synchronized(lock) { ++requested }
        mutex.withLock {
            if (synchronized(lock) { finished >= ticket }) return@withContext
            val covers = synchronized(lock) { requested }
            try {
                rebuildOnce()
            } finally {
                synchronized(lock) { finished = covers }
            }
        }
    }

    private suspend fun rebuildOnce() {
        // A file that cannot be read now (a full disk mid-read): leave everything as it is until the next rebuild.
        val s = snapshot() ?: return
        val now = clock()
        val allowed = notifications.allowed
        for (kind in ReminderKind.entries) {
            val armedAt = armed[kind]
            if (allowed && armedAt != null && armedAt <= now) {
                for (reminder in ReminderSchedule.due(s, kind, armedAt, now)) {
                    notifications.post(reminder)
                    if (kind == ReminderKind.TRIAL) s.trial.posted(reminder, now)
                }
            }
            val next = if (allowed) ReminderSchedule.nextAlarm(s, kind, now) else null
            if (next == null) {
                alarms.cancel(kind)
                armed[kind] = null
            } else {
                alarms.arm(kind, next)
                armed[kind] = next
            }
        }
        val stale = ReminderSchedule.withdrawn(notifications.active(), s, now)
        if (stale.isNotEmpty()) notifications.withdraw(stale)
        onArmed(ReminderKind.entries.any { armed[it] != null })
    }
}
