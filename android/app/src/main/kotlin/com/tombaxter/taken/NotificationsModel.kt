package com.tombaxter.taken

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.tombaxter.taken.core.reminders.NotificationPermission
import com.tombaxter.taken.notify.NotificationHost

/**
 * Taken's notification permission on screen (SPEC-ANDROID 10.4), the iPhone's `setReminderEnabled` and
 * `notificationsDenied` in Android's shape:
 * - **Asked in context only**: from the nudge offer's Turn on and Profile's Nudge switch ("Ask for a permission in
 *   context, when the user starts to interact with the feature that requires it",
 *   https://developer.android.com/training/permissions/requesting). The trial ask's Continue (Taken Pro's, 9.7) asks
 *   through [request] too. Due times never ask: they come only when notifications are already allowed, as on the iPhone.
 * - **The explanation** shows only when Android says one is due (`shouldShowRequestPermissionRationale`: "Unless
 *   shouldShowRequestPermissionRationale() returns true, your app doesn't need to display the middle screen",
 *   https://developer.android.com/develop/ui/views/notifications/notification-permission), with Continue and Not now.
 *   Not now changes nothing, and the next Turn on asks again the same way, as the microphone's does.
 * - **A no**: once Android will not ask again (two denials, or notifications turned off in Settings), Profile shows
 *   "Notifications are off for Taken. Open Settings", the only link to Settings, at the person's own tap ("Don't link to
 *   system settings in an effort to convince the user", same page). A first no is taken as said: nothing nags.
 *
 * The answer to Android's prompt comes back through MainActivity's launcher, so it reaches here after a rotation; one
 * answer goes with each prompt, and an answer lost to a process restart leaves nothing waiting.
 */
class NotificationsModel(
    /** Rebuilds the reminders: on every return to the front, and the moment notifications are allowed. */
    private val rebuild: () -> Unit = {},
    /** Withdraws posted notifications by tag (`AndroidNotifications.withdraw`). */
    private val withdraw: (List<String>) -> Unit = {},
    val isDemo: Boolean = false,
) {
    /** Android's side, from the activity on screen. */
    var host: NotificationHost = NotificationHost.none

    /** Taken's explanation is up, before Android's prompt comes again. */
    var asking: Boolean by mutableStateOf(false)
        private set

    /** Profile's "Notifications are off for Taken. Open Settings" row. */
    var notificationsDenied: Boolean by mutableStateOf(false)
        private set

    /** Profile's row for a nudge whose own channel is turned off in Android's settings. */
    var nudgeChannelOff: Boolean by mutableStateOf(false)
        private set

    /**
     * The trial reminder can reach the person as a notification: Android shows Taken's notifications and the "Trial
     * reminder" channel is on. While it cannot, Today carries the reminder's words (`AppModel.trialReminderDeliverable`,
     * SPEC-ANDROID 9.7). Read on every return to the front and after each answer.
     */
    var trialDeliverable: Boolean by mutableStateOf(false)
        private set

    /** Android's answer in the shape the trial ask reads (`TrialAsk.shows`): its prompt may still come, or not. */
    val permission: NotificationPermission
        get() = when {
            host.notificationsAllowed -> NotificationPermission.ALLOWED
            host.notificationsAskable -> NotificationPermission.NOT_DETERMINED
            else -> NotificationPermission.DENIED
        }

    private var app: AppModel? = null
    private var waiting: ((Boolean) -> Unit)? = null
    private var awaitingPrompt = false

    fun attach(app: AppModel) {
        this.app = app
    }

    /** Taken came to the front: what Android says now, and the reminders rebuilt (permission may have changed meanwhile). */
    fun didBecomeActive() {
        if (isDemo) return
        refresh()
        rebuild()
    }

    /**
     * Reads Android's answer again, as the iPhone does on every return to the front: the row shows while notifications
     * are off and the nudge is on (`notificationsDenied = permission == .denied && reminderEnabled`).
     */
    fun refresh() {
        if (isDemo) return
        val nudgeOn = app?.settings?.reminderEnabled == true
        val allowed = host.notificationsAllowed
        notificationsDenied = !allowed && nudgeOn
        nudgeChannelOff = allowed && nudgeOn && host.nudgeChannelOff
        trialDeliverable = allowed && !host.trialChannelOff
    }

    /**
     * A nudge was opened (a tap, or its OPEN): it goes from the shade, as an answered notification goes on the iPhone. A
     * tap dismisses it already (`setAutoCancel`); an action button does not on Android.
     */
    fun nudgeOpened(day: com.tombaxter.taken.core.day.DayKey) {
        if (isDemo) return
        withdraw(listOf(com.tombaxter.taken.core.reminders.Reminders.REQUEST_PREFIX + day.ordinal))
    }

    /** The nudge was turned off in Profile: its row goes with it, as the iPhone's does. */
    fun nudgeTurnedOff() {
        notificationsDenied = false
        nudgeChannelOff = false
    }

    /**
     * Notifications for a feature the person just turned on: `then(true)` once Android shows them, `then(false)` when it
     * answers no. Nothing at all after the explanation's Not now. `explained`: the person has just read why, on the trial
     * ask, so Android's prompt comes without Taken's explanation before it.
     */
    fun request(explained: Boolean = false, then: (Boolean) -> Unit) {
        if (isDemo || host.notificationsAllowed) {
            notificationsDenied = false
            refresh()
            then(true)
            return
        }
        if (!host.notificationsAskable) {
            notificationsDenied = true
            then(false)
            return
        }
        waiting = then
        if (host.notificationRationaleDue && !explained) asking = true else prompt()
    }

    /** The explanation's Continue (Android's prompt next) or Not now (nothing changes). */
    fun answerRationale(proceed: Boolean) {
        asking = false
        if (proceed) prompt() else waiting = null
    }

    /** Android's prompt was answered. */
    fun answered(granted: Boolean) {
        if (!awaitingPrompt) return
        awaitingPrompt = false
        val then = waiting
        waiting = null
        if (granted) {
            notificationsDenied = false
            refresh()
            // To-dos with a time get theirs now, and a trial its reminder.
            rebuild()
        } else if (!host.notificationRationaleDue) {
            // Android will not show its prompt again (a second no): only Settings can turn them on now.
            notificationsDenied = true
        }
        then?.invoke(granted)
    }

    private fun prompt() {
        awaitingPrompt = true
        host.requestNotifications()
    }

    /** The Settings link in Profile: Taken's notification settings, or the nudge channel's own page. */
    fun openSettings(channelId: String? = null) {
        host.openNotificationSettings(channelId)
    }

    /** Debug captures only: Profile's row and the explanation, drawn without Android. */
    internal fun stageDemo(denied: Boolean = false, channelOff: Boolean = false, asking: Boolean = false) {
        notificationsDenied = denied
        nudgeChannelOff = channelOff
        this.asking = asking
    }
}
