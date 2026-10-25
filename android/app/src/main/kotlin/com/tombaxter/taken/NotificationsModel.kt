package com.tombaxter.taken

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
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
     * Reads Android's answer again. The iPhone shows the row when notifications are denied while the nudge is on; a row
     * shown after a no stays until notifications are allowed.
     */
    fun refresh() {
        if (isDemo) return
        val nudgeOn = app?.settings?.reminderEnabled == true
        val allowed = host.notificationsAllowed
        if (allowed) notificationsDenied = false else if (nudgeOn) notificationsDenied = true
        nudgeChannelOff = allowed && nudgeOn && host.nudgeChannelOff
    }

    /** The nudge was turned off in Profile: its row goes with it, as the iPhone's does. */
    fun nudgeTurnedOff() {
        notificationsDenied = false
        nudgeChannelOff = false
    }

    /**
     * Notifications for a feature the person just turned on: `then(true)` once Android shows them, `then(false)` when it
     * answers no. Nothing at all after the explanation's Not now.
     */
    fun request(then: (Boolean) -> Unit) {
        if (isDemo || host.notificationsAllowed) {
            notificationsDenied = false
            then(true)
            return
        }
        if (!host.notificationsAskable) {
            notificationsDenied = true
            then(false)
            return
        }
        waiting = then
        if (host.notificationRationaleDue) asking = true else prompt()
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
            // To-dos with a time get theirs now.
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
