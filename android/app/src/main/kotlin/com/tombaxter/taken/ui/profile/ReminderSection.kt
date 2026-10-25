package com.tombaxter.taken.ui.profile

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.tombaxter.taken.AppModel
import com.tombaxter.taken.NotificationsModel
import com.tombaxter.taken.PaywallOrigin
import com.tombaxter.taken.core.reminders.ReminderCopy
import com.tombaxter.taken.core.reminders.ReminderKind
import com.tombaxter.taken.core.reminders.TrialReminder
import com.tombaxter.taken.ui.components.Card
import com.tombaxter.taken.ui.components.MonoTimeButton
import com.tombaxter.taken.ui.components.RowDivider
import com.tombaxter.taken.ui.components.SettingRow
import com.tombaxter.taken.ui.components.SwitchRow
import com.tombaxter.taken.ui.components.Symbols
import com.tombaxter.taken.ui.theme.Taken
import com.tombaxter.taken.ui.theme.TakenType

/**
 * Profile > Reminder (SPEC-ANDROID 10.4), the iPhone's section in its order (Taken/Views/ProfileView.swift
 * `reminderSection`): the Nudge switch; its Time while on; "The nudge needs Taken Pro" while locked, which opens the
 * plans; "Notifications are off for Taken. Open Settings" once Android will not show them, the only link to Settings.
 * Android adds one row: when only the "Evening nudge" channel is off, its own settings page. Taken Pro's Trial reminder
 * switch sits under the nudge while a trial is on and set to renew (SPEC-ANDROID 9.7, the iPhone's `showsTrialReminder`),
 * the in-app setting for its own kind of notification. The footnote says what the nudge does, and then what the trial
 * reminder does while its switch shows.
 */
@Composable
internal fun ReminderSection(model: AppModel) {
    val settings = model.settings
    val notifications = model.notifications
    val showsTrial = model.showsTrialReminderSwitch
    Section(ReminderCopy.SECTION)
    Card(Modifier.testTag("reminder")) {
        Column {
            // Without Pro the switch opens the paywall, and the nudge, with Android's prompt, comes on once Pro does.
            SwitchRow(ReminderCopy.NUDGE, checked = settings.reminderEnabled) { model.setReminder(it) }
            if (settings.reminderEnabled) {
                RowDivider()
                SettingRow(ReminderCopy.TIME) {
                    MonoTimeButton(ReminderCopy.NUDGE_TIME, settings.reminderMinutes) { model.setReminderMinutes(it) }
                }
            }
            if (showsTrial) {
                // The one reminder before a trial ends has its own switch; the nudge's never turns it off.
                RowDivider()
                Box(Modifier.testTag("trial-reminder")) {
                    SwitchRow(ReminderCopy.TRIAL_REMINDER, checked = settings.trialReminderEnabled) { model.setTrialReminder(it) }
                }
            }
            if (model.isLocked) {
                RowDivider()
                LockedNudgeRow { model.presentPaywall(PaywallOrigin.SETTINGS) }
            }
            if (notifications.notificationsDenied) {
                RowDivider()
                LinkRow(ReminderCopy.NOTIFICATIONS_OFF) { notifications.openSettings() }
            } else if (notifications.nudgeChannelOff) {
                RowDivider()
                LinkRow(ReminderCopy.NUDGE_CHANNEL_OFF) { notifications.openSettings(ReminderKind.NUDGE.channelId) }
            }
        }
    }
    Footnote(if (showsTrial) "${ReminderCopy.FOOTNOTE} ${TrialReminder.SETTING_FOOTNOTE}" else ReminderCopy.FOOTNOTE)
}

/** No nudge is scheduled without Pro: said where it is set, and a tap opens the plans (the iPhone's lock row). */
@Composable
private fun LockedNudgeRow(onClick: () -> Unit) {
    val colors = Taken.colors
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            // One TalkBack node: "The nudge needs Taken Pro, button, double tap to open Taken Pro".
            .clickable(role = Role.Button, onClickLabel = "open Taken Pro", onClick = onClick)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Symbols.LockFill, contentDescription = null, tint = colors.signalInk, modifier = Modifier.size(14.dp))
        Spacer(Modifier.width(10.dp))
        Text(ReminderCopy.NUDGE_LOCKED, style = TakenType.sans(15, FontWeight.Medium), color = colors.signalInk, modifier = Modifier.weight(1f))
        Icon(Symbols.ChevronRight, contentDescription = null, tint = colors.fgSubtle, modifier = Modifier.size(18.dp))
    }
}

/**
 * Taken's explanation before Android's notification prompt comes again, only when Android says one is due, with a way
 * to say no: "include a 'cancel' or 'no thanks' button that lets the user continue using your app without granting the
 * permission" (https://developer.android.com/training/permissions/requesting). Continue shows Android's prompt.
 */
@Composable
fun NotificationRationale(notifications: NotificationsModel, nudgeMinutes: Int, trialReminder: Boolean = false) {
    val colors = Taken.colors
    AlertDialog(
        onDismissRequest = { notifications.answerRationale(false) },
        containerColor = colors.bgRaised,
        titleContentColor = colors.fg,
        textContentColor = colors.fgMuted,
        shape = RoundedCornerShape(Taken.shapes.card),
        title = { Text(ReminderCopy.ASK_TITLE, style = TakenType.sans(20, FontWeight.SemiBold)) },
        text = { Text(ReminderCopy.askBody(nudgeMinutes, trialReminder), style = TakenType.sans(15)) },
        confirmButton = {
            TextButton(onClick = { notifications.answerRationale(true) }) {
                Text(ReminderCopy.CONTINUE, style = TakenType.sans(16, FontWeight.SemiBold), color = colors.signalInk)
            }
        },
        dismissButton = {
            TextButton(onClick = { notifications.answerRationale(false) }) {
                Text(ReminderCopy.NOT_NOW, style = TakenType.sans(16, FontWeight.Medium), color = colors.fgMuted)
            }
        },
        modifier = Modifier.testTag("notify-rationale"),
    )
}
