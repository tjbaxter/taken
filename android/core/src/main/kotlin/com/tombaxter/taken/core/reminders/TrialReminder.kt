package com.tombaxter.taken.core.reminders

import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.model.StackSettings
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.pro.PlanPrice
import com.tombaxter.taken.core.pro.ProCopy
import com.tombaxter.taken.core.pro.ProLedger
import com.tombaxter.taken.core.pro.ProReason
import com.tombaxter.taken.core.pro.ProStatus
import com.tombaxter.taken.core.pro.TrialReminderMark
import java.time.Duration
import java.time.Instant
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.temporal.ChronoUnit

// The trial promise and its one reminder (2026-10-21, SPEC 3.9, PRO.md), ported from Shared/TrialReminder.swift. The
// paywall promises the reminder under the yearly plan (`ProCopy.trialTimeline`); one notification ask may follow a trial
// purchase (`TrialAsk`); one notification comes at least 3 days before the trial ends (`TrialReminder`). Utah asks for a
// notice "at least three days before the day on which" a trial ends, with its date, price and how to cancel
// (https://le.utah.gov/~2024/bills/hbillenr/HB0174.pdf).
//
// Android: these are the rules and the words. Posting the notification, its channel and the permission prompt are the
// Reminders' (SPEC-ANDROID 10.4): `PlannedTrialReminder` hands `TrialReminder.plan` to the scheduler's alarm, and the
// trial ask is `AppModel.offerTrialAsk` with `TrialAskSheet`.
// A trial is known only on the phone that bought it (SPEC-ANDROID 9.4), so only that phone plans a reminder; Google Play
// itself emails before a trial ends (https://android-developers.googleblog.com/2020/04/building-user-trust-through-more.html).
// Copy rules: no em or en dash, never the word for no charge, no exclamation marks.

/**
 * The one notification before an introductory trial ends: on the day the paywall promised (the trial's length minus 3), at
 * least 72 hours before the trial's end, at the nudge time when the nudge is on and 10:00 when it is off, with the end
 * date, the price it turns into, what was logged and how to cancel. Only while the trial is set to renew and Profile's
 * Trial reminder is on; at most one.
 */
object TrialReminder {
    /** The notification's tag, one per trial: at most one is ever planned. */
    const val IDENTIFIER = "taken.pro.trial-end"

    /** The paywall promises the reminder this many days before the trial ends (Utah's minimum). */
    const val LEAD_DAYS = 3

    /** At least this long before the end. */
    val LEAD: Duration = Duration.ofDays(LEAD_DAYS.toLong())

    /** When the nudge is off: 10:00 (own choice on the iPhone, from the brief; no source tests a time of day). */
    const val DEFAULT_MINUTES = 10 * 60

    /**
     * The reminder to hand the system: when (`fireAt`, and the same moment as a wall-clock time where the phone is) and
     * what it says (`body`, the notification's text; its title is the app's name).
     */
    data class Plan(val fireAt: Instant, val at: ZonedDateTime, val body: String)

    /**
     * An introductory trial that is still on and set to renew: not cancelled (`willRenew == false`), not in a billing
     * issue, not converted (the reason becomes yearly or monthly) and not Pro for good (lifetime beats it).
     */
    fun isRenewingTrial(status: ProStatus?, now: Instant): Boolean {
        if (status == null || !status.isPro || status.reason != ProReason.TRIAL || status.willRenew == false ||
            status.billingIssue
        ) {
            return false
        }
        val end = status.expiresAt ?: return false
        return end > now
    }

    /**
     * The reminder that should exist now, or null: no renewing trial, Profile's Trial reminder off, the moment already
     * past, or this trial's reminder already gone out (`sent`, so it never comes twice, even when a later nudge time or a
     * flight west would put the moment in the future again). A trial of 3 days or less never gets one: 72 hours before
     * its end is its start, which is already past.
     */
    fun plan(
        status: ProStatus?,
        price: PlanPrice?,
        state: StackState,
        now: Instant,
        zone: ZoneId = ZoneId.systemDefault(),
        sent: TrialReminderMark? = null,
    ): Plan? {
        if (!state.settings.trialReminderEnabled || !isRenewingTrial(status, now)) return null
        val end = status?.expiresAt ?: return null
        if (sent != null && sent.trialEnd == end && sent.fireAt <= now) return null
        val fire = fireDate(end, state.settings, zone) ?: return null
        if (fire <= now) return null
        return Plan(fireAt = fire, at = fire.atZone(zone), body = body(end, price, state.doses.size, zone))
    }

    /**
     * The plan for what the app last wrote: pro.json's status, the price its plan renews at and the reminder already
     * handed over. This is what the Reminders phase calls when it rebuilds its alarms (SPEC-ANDROID 10.4).
     */
    fun planFor(ledger: ProLedger?, state: StackState, now: Instant, zone: ZoneId = ZoneId.systemDefault()): Plan? =
        plan(ledger?.status, ledger?.renewalPrice, state, now, zone, ledger?.trialReminder)

    /**
     * What `ProLedger.trialReminder` says after a rebuild: the reminder just handed to the system; else the earlier one
     * once its moment has passed (it has gone out, so it never comes again for that trial); else nothing (a pending one
     * was withdrawn without a replacement).
     */
    fun nextMark(trial: Plan?, end: Instant?, previous: TrialReminderMark?, now: Instant): TrialReminderMark? {
        if (trial != null && end != null) return TrialReminderMark(trialEnd = end, fireAt = trial.fireAt)
        if (previous != null && previous.fireAt <= now) return previous
        return null
    }

    /** The fire moment for these settings: the nudge time while the nudge is on, 10:00 while it is off. */
    fun fireDate(end: Instant, settings: StackSettings, zone: ZoneId = ZoneId.systemDefault()): Instant? = fireDate(
        end = end,
        minutes = if (settings.reminderEnabled) settings.reminderMinutes else DEFAULT_MINUTES,
        wakeMinutes = settings.wakeMinutes,
        zone = zone,
    )

    /**
     * On the day the paywall promised: the calendar day, where the phone is, of the moment 72 hours before `end` (day 4
     * of a 7-day trial). At `minutes` past midnight when that is at least 72 hours before the end; otherwise at that
     * 72-hour moment itself, to the minute, which is the time of day the trial began. Only when that moment falls before
     * the person's wake-up time does it move to the day before at `minutes` (never in the night, and earlier than the
     * promise, never later).
     */
    fun fireDate(
        end: Instant,
        minutes: Int,
        wakeMinutes: Int = StackSettings.DEFAULT_WAKE_MINUTES,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Instant? {
        // Down to the minute, so a moment set to the minute is never under 72 hours.
        val latest = end.minus(LEAD).atZone(zone).truncatedTo(ChronoUnit.MINUTES)
        val chosen = StackSettings.clampMinutes(minutes)
        val time = LocalTime.of(chosen / 60, chosen % 60)
        val onDay = ZonedDateTime.of(latest.toLocalDate(), time, zone)
        if (!onDay.isAfter(latest)) return onDay.toInstant()
        val latestMinutes = latest.hour * 60 + latest.minute
        if (latestMinutes >= StackSettings.clampMinutes(wakeMinutes)) return latest.toInstant()
        return ZonedDateTime.of(latest.toLocalDate().minusDays(1), time, zone).toInstant()
    }

    /**
     * "Your Taken trial ends Sunday 1 Nov. Unless cancelled, it then renews at $19.99 a year. 12 doses logged so far.
     * Cancel before then in Google Play > Subscriptions." The day and date the trial really ends, where the phone is; the
     * price as Play last gave it for the plan that renews (left out if it never has, never made up); no count with
     * nothing logged. Worded to stay true when the trial was cancelled where Taken has not seen it yet. No sales copy.
     */
    fun body(end: Instant, price: PlanPrice?, doses: Int, zone: ZoneId = ZoneId.systemDefault()): String {
        val day = DayKey.calendarDateOf(end, zone)
        val parts = mutableListOf("Your Taken trial ends ${Fmt.weekday(day)} ${Fmt.shortDate(end, year = false, zone = zone)}.")
        parts.add(if (price != null) "Unless cancelled, it then renews at ${ProCopy.renewal(price)}." else "Unless cancelled, it then renews.")
        when (doses) {
            0 -> Unit
            1 -> parts.add("1 dose logged so far.")
            else -> parts.add("$doses doses logged so far.")
        }
        parts.add(HOW_TO_CANCEL)
        return parts.joinToString(" ")
    }

    /**
     * How to cancel, as the reminder says it. Google: "On your Android device, go to subscriptions in Google Play", then
     * "Cancel subscription" (https://support.google.com/googleplay/answer/7018481); a trial cancelled before its end is
     * not charged ("they aren't charged when the free trial period ends",
     * https://developer.android.com/google/play/billing/subscriptions). Play has no 24-hour rule, so "before then".
     */
    const val HOW_TO_CANCEL = "Cancel before then in Google Play > Subscriptions."

    /** Profile > Reminder's footnote while the Trial reminder switch shows. */
    const val SETTING_FOOTNOTE = "The trial reminder comes once, 3 days before your trial ends."

    /**
     * The same notice as a line on Today while notifications cannot carry it: from the moment the reminder would have
     * come until the trial ends, under the same rules, so the paywall's "we remind you" holds without notifications.
     */
    fun notice(status: ProStatus?, price: PlanPrice?, state: StackState, now: Instant, zone: ZoneId = ZoneId.systemDefault()): String? {
        if (!state.settings.trialReminderEnabled || !isRenewingTrial(status, now)) return null
        val end = status?.expiresAt ?: return null
        val from = fireDate(end, state.settings, zone) ?: end.minus(LEAD)
        if (now < from) return null
        return body(end, price, state.doses.size, zone)
    }
}

/** Whether notifications may be posted, as Android last said. */
enum class NotificationPermission {
    /** Android can still show its prompt (Android 13+ and not yet answered for good). */
    NOT_DETERMINED,
    DENIED,
    ALLOWED,
}

/**
 * The one notification ask right after a trial starts. Android's guidance differs from Apple's: "Always provide the
 * option to cancel an educational UI flow" (https://developer.android.com/training/permissions/requesting), so the
 * Android sheet has Continue and Not now (SPEC-ANDROID 10.4). `AppModel.offerTrialAsk` shows it; these are its rules and
 * words.
 */
object TrialAsk {
    /** Show the sheet: a trial just started, Android can still show its prompt, and the sheet never showed. */
    fun shows(trialStarted: Boolean, permission: NotificationPermission, alreadyShown: Boolean): Boolean =
        trialStarted && permission == NotificationPermission.NOT_DETERMINED && !alreadyShown

    /** The reminder is part of the ask while the trial is long enough to get one (more than 3 days left). */
    fun mentionsReminder(status: ProStatus?, now: Instant): Boolean {
        if (status == null || status.reason != ProReason.TRIAL) return true
        val end = status.expiresAt ?: return true
        return Duration.between(now, end) > TrialReminder.LEAD
    }

    const val TITLE = "Your trial has started."
    const val BODY = "Get the evening nudge and a heads-up 3 days before your trial ends."

    /** For a trial too short for the reminder. */
    const val BODY_NUDGE_ONLY = "Get the evening nudge if anything's left."

    /** Opens Android's own prompt. */
    const val ALLOW = "Continue"
    const val NOT_NOW = "Not now"
    const val ALLOW_HINT = "Shows Android's notification prompt."

    /** TalkBack's action on Continue: "Double tap to show Android's notification prompt". */
    const val ALLOW_ACTION = "show Android's notification prompt"

    fun body(mentionsReminder: Boolean): String = if (mentionsReminder) BODY else BODY_NUDGE_ONLY

    /** Every line, for the copy rules test. */
    val all: List<String>
        get() = listOf(
            TITLE, BODY, BODY_NUDGE_ONLY, ALLOW, NOT_NOW, ALLOW_HINT, ALLOW_ACTION, TrialReminder.HOW_TO_CANCEL,
            TrialReminder.SETTING_FOOTNOTE,
        )
}
