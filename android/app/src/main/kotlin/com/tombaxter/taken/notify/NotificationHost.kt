package com.tombaxter.taken.notify

/**
 * What Taken asks of Android for its notifications (SPEC-ANDROID 10.4): their state, Android 13's prompt and the settings
 * pages. [com.tombaxter.taken.MainActivity] is the real one; tests and captures fake it, as [com.tombaxter.taken.voice.VoiceHost]
 * does for the microphone.
 */
interface NotificationHost {
    /** Android shows Taken's notifications now. */
    val notificationsAllowed: Boolean

    /**
     * Android 13 and later, POST_NOTIFICATIONS not granted: Android's prompt may still come (Android decides; after two
     * denials it answers no at once, https://developer.android.com/training/permissions/requesting). False below 13, and
     * when notifications were turned off in Settings while the permission stands: only Settings turns them back on.
     */
    val notificationsAskable: Boolean

    /** `shouldShowRequestPermissionRationale(POST_NOTIFICATIONS)`: Taken explains before Android asks again. */
    val notificationRationaleDue: Boolean

    /** The "Evening nudge" channel is turned off in Android's settings. */
    val nudgeChannelOff: Boolean

    /** Android's notification prompt. The answer comes back to `NotificationsModel.answered`. */
    fun requestNotifications()

    /** Taken's notification settings, or one channel's page when `channelId` is given. */
    fun openNotificationSettings(channelId: String? = null)

    companion object {
        /** No notifications at all (tests, captures). */
        val none: NotificationHost = object : NotificationHost {
            override val notificationsAllowed = false
            override val notificationsAskable = false
            override val notificationRationaleDue = false
            override val nudgeChannelOff = false
            override fun requestNotifications() = Unit
            override fun openNotificationSettings(channelId: String?) = Unit
        }
    }
}
