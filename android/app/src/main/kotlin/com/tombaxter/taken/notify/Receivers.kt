package com.tombaxter.taken.notify

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import com.tombaxter.taken.AppContainer
import com.tombaxter.taken.ProSource
import com.tombaxter.taken.TakenApp
import com.tombaxter.taken.core.day.DayClock
import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.model.Dose
import com.tombaxter.taken.core.pro.ProCopy
import com.tombaxter.taken.core.pro.ProGate
import com.tombaxter.taken.core.pro.ProLedgers
import com.tombaxter.taken.core.pro.ProPendingAction
import com.tombaxter.taken.core.reminders.NudgeLink
import com.tombaxter.taken.core.reminders.Reminders
import com.tombaxter.taken.core.stack.takeAllPending
import com.tombaxter.taken.data.LedgerFile
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import java.io.IOException
import java.time.Instant
import java.time.ZoneId

/**
 * Runs `work` past `onReceive` on the app's scope, inside the broadcast's time: "once you use goAsync ... the broadcast
 * execution limit still applies, and that includes the time spent between calling this method and ultimately
 * PendingResult.finish()" (https://developer.android.com/reference/android/content/BroadcastReceiver#goAsync()). A
 * rebuild reads three small files and sets three alarms, well inside it.
 */
private fun BroadcastReceiver.runAsync(context: Context, work: suspend (AppContainer) -> Unit) {
    val container = (context.applicationContext as TakenApp).container
    val pending = goAsync()
    container.scope.launch {
        try {
            work(container)
        } finally {
            pending.finish()
        }
    }
}

/** A kind's alarm went off: the rebuild posts what came due and arms that kind's next moment. */
class ReminderAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val kind = AndroidAlarms.kind(intent.action) ?: return
        val armedAt = intent.getLongExtra(AndroidAlarms.EXTRA_ARMED_AT, -1L).takeIf { it >= 0 }?.let(Instant::ofEpochMilli)
        runAsync(context) { it.reminders.alarmWentOff(kind, armedAt) }
    }
}

/**
 * The reminders are rebuilt after a restart, a change of the time or the time zone, and an update of Taken. Allowed for
 * exactly this: `BOOT_COMPLETED` is exempt because apps "need to receive these broadcasts, such as to schedule jobs and
 * alarms", and `TIME_SET` and `TIMEZONE_CHANGED` because apps "might need to receive these broadcasts to update alarms"
 * (https://developer.android.com/develop/background-work/background-tasks/broadcasts/broadcast-exceptions);
 * `MY_PACKAGE_REPLACED` "is only sent to the application that was replaced"
 * (https://developer.android.com/reference/android/content/Intent#ACTION_MY_PACKAGE_REPLACED). Not the locked boot
 * broadcast: the files live in credential-encrypted storage, which `BOOT_COMPLETED` can read ("both device-protected and
 * credential-protected storage can accessed safely", same Intent page).
 *
 * Off in the manifest and enabled only while an alarm is armed, as Google's alarm guide does with its boot receiver
 * ("the receiver will not be called unless the application explicitly enables it", and it "will stay enabled until your
 * app disables it", https://developer.android.com/develop/background-work/services/alarms/schedule).
 */
class RescheduleReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> runAsync(context) { it.reminders.rebuild() }
            else -> return
        }
    }

    companion object {
        val ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
        )

        /** Enables the receiver while any reminder is armed, and disables it when none is. */
        fun setEnabled(context: Context, enabled: Boolean) {
            val component = ComponentName(context, RescheduleReceiver::class.java)
            val wanted = if (enabled) PackageManager.COMPONENT_ENABLED_STATE_ENABLED else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            val packages = context.packageManager
            if (packages.getComponentEnabledSetting(component) == wanted) return
            packages.setComponentEnabledSetting(component, wanted, PackageManager.DONT_KILL_APP)
        }
    }
}

/**
 * The nudge's TAKE ALL, run without opening Taken (Taken/TakenApp.swift `NotificationHandler`), from the lock screen too.
 * The tapped nudge goes, as an action's notification goes on the iPhone, and then:
 * - last night's nudge logs nothing and says so, with a tap that opens that day ([Reminders.staleBody]);
 * - while logging needs Taken Pro, nothing is written: the Take all is kept in pro.json for Taken to offer when it opens
 *   (10 minutes), and the note says "Logging needs Taken Pro. Open Taken to continue.";
 * - otherwise every quick-loggable pending dose is logged at this moment (`takeAllPending`), the first dose ever is noted,
 *   and the rebuild withdraws what no longer applies.
 */
class NudgeActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_TAKE_ALL) return
        val day = intent.data?.toString()?.let(NudgeLink::day)
        runAsync(context) { NudgeActions.takeAll(it, day) }
    }

    companion object {
        const val ACTION_TAKE_ALL = "com.tombaxter.taken.nudge.TAKE_ALL"

        /** TAKE ALL on the nudge for `day`: one broadcast per day, told apart by its data. */
        fun takeAll(context: Context, day: DayKey): PendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, NudgeActionReceiver::class.java).setAction(ACTION_TAKE_ALL).setData(Uri.parse(NudgeLink.url(day))),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}

/** What a nudge's TAKE ALL did. */
sealed interface TakeAllOutcome {
    data class Logged(val count: Int) : TakeAllOutcome
    data object Stale : TakeAllOutcome
    data object Locked : TakeAllOutcome
    data object Failed : TakeAllOutcome
}

object NudgeActions {
    suspend fun takeAll(
        container: AppContainer,
        day: DayKey?,
        now: Instant = container.clock(),
        zone: ZoneId = container.zone(),
        pro: ProSource = container.pro,
    ): TakeAllOutcome {
        val notifications = container.notifications
        if (day != null) notifications.withdraw(listOf(Reminders.REQUEST_PREFIX + day.ordinal))
        val stores = container.stores
        return try {
            val state = stores.stack.data.first()
            // A nudge left over from an earlier day never logs today's doses.
            if (!Reminders.isCurrent(day, state, now, zone)) {
                if (day != null) notifications.postNote(Reminders.STALE_IDENTIFIER, Reminders.staleBody(day), NudgeLink.url(day))
                return TakeAllOutcome.Stale
            }
            val ledger = stores.ledger.data.first().ledger
            val status = pro.status ?: ledger?.status
            // The iPhone's `ProGate.mayLog` asks the store once more for a renewing plan whose cache ran out; on Android that
            // recheck is Taken Pro's `ProSource.refresh()`, inside this broadcast's time (SPEC-ANDROID 9.3), for the
            // integrator to add here.
            val access = ProGate.access(status, settled = true, legacyLog = false, hasLogged = ProGate.hasLogged(state, ledger), now = now)
            if (!access.allowsLogging) {
                stores.ledger.updateData { file -> LedgerFile(ProLedgers.recordPending(file.ledger, ProPendingAction.TakeAll, now)) }
                notifications.postNote(Reminders.LOCKED_IDENTIFIER, ProCopy.LOCKED_DIALOG, AndroidNotifications.TODAY)
                return TakeAllOutcome.Locked
            }
            var logged: List<Dose> = emptyList()
            stores.stack.updateData { latest ->
                latest.clone().also { s -> logged = s.takeAllPending(now, DayClock(s.settings.dayStartHour, zone)) }
            }
            if (logged.isNotEmpty()) {
                stores.ledger.updateData { file -> LedgerFile(ProLedgers.noteFirstDose(file.ledger, now)) }
            }
            container.reminders.rebuild()
            TakeAllOutcome.Logged(logged.size)
        } catch (e: IOException) {
            TakeAllOutcome.Failed
        }
    }
}
