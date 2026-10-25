package com.tombaxter.taken.core.retention

import com.tombaxter.taken.core.day.DayKey
import com.tombaxter.taken.core.format.Fmt
import com.tombaxter.taken.core.model.StackSettings
import com.tombaxter.taken.core.stack.DayStatus
import com.tombaxter.taken.core.stack.DaySummary
import com.tombaxter.taken.core.stack.StackEngine

// Today's one quiet row (SPEC 3.1, the 1.1 retention build), as pure rules. Ported from Shared/Retention.swift and the
// Weight tab's `TodayPrompts.pick` extension. Copy rules: no em or en dash, never the word for no charge, no exclamation
// marks.

/** The one quiet line Today may show under its progress line. At most one at a time, never in the capture path. */
sealed class TodayPrompt {
    /** "Nudge me at 20:00 if anything's left", with Turn on and Not now: once, while the nudge is off. */
    data class NudgeOffer(val minutes: Int) : TodayPrompt()

    /** "Forgot to log yesterday? Fill it in": yesterday is partly or not logged and something was logged the week before. */
    data class Repair(val day: DayKey) : TodayPrompt()

    /** "Log from your home screen: add the Taken widget": once, on the first day that reaches All taken. */
    data object WidgetInvite : TodayPrompt()

    /** The trial reminder's own words, while notifications are not allowed (NEXT: Taken Pro). */
    data class TrialEnds(val text: String) : TodayPrompt()

    /** "Log your weight here too: add a Weight tab", once, after every other row (NEXT: Weight). */
    data object WeightOffer : TodayPrompt()
}

object TodayPrompts {
    /**
     * Which row Today shows, if any. The trial notice first (only while notifications cannot deliver the trial
     * reminder), then the nudge offer, then the repair, then the widget invite, then the weight offer. None while locked:
     * the Taken Pro bar sits there. `widgetPlaced`: a Taken stack widget is already on the home screen (Android reads
     * Taken's placed widgets where the iPhone reads Lock Screen families), so the invite would be noise.
     */
    fun pick(
        settings: StackSettings,
        hasStack: Boolean,
        today: DaySummary,
        repairDay: DayKey?,
        locked: Boolean,
        widgetPlaced: Boolean = false,
        trialNotice: String? = null,
        weightOffer: Boolean = false,
    ): TodayPrompt? {
        if (!hasStack || locked) return null
        if (trialNotice != null) return TodayPrompt.TrialEnds(trialNotice)
        if (!settings.reminderEnabled && !settings.nudgeOfferDone) return TodayPrompt.NudgeOffer(settings.reminderMinutes)
        if (repairDay != null && settings.repairClosedDay != repairDay.ordinal) return TodayPrompt.Repair(repairDay)
        if (today.allTaken && !settings.widgetInviteDone && !widgetPlaced &&
            (settings.widgetInviteDay == null || settings.widgetInviteDay == today.day.ordinal)
        ) {
            return TodayPrompt.WidgetInvite
        }
        if (weightOffer) return TodayPrompt.WeightOffer
        return null
    }

    /**
     * Yesterday, when the repair line belongs on Today: it is partial or missed (a weekly item's open week counts neither
     * way), and something counts for one of the 7 days before it, or for yesterday itself. It goes once yesterday is
     * complete, or when today ends.
     */
    fun repairDay(engine: StackEngine, today: DayKey): DayKey? {
        val yesterday = today.adding(-1)
        val status = engine.summary(yesterday, asOf = today).status
        if (status != DayStatus.PARTIAL && status != DayStatus.MISSED) return null
        if (!engine.loggedAnything(from = yesterday.adding(-7), through = yesterday)) return null
        return yesterday
    }
}

/** Today's one-time rows, in words. Android wording where the iPhone names its own surfaces (SPEC-ANDROID 6.4). */
object RetentionCopy {
    /** "Nudge me at 20:00 if anything's left", at the person's own nudge time. */
    fun nudgeOffer(minutes: Int): String = "Nudge me at ${Fmt.minutes(minutes)} if anything's left"
    const val TURN_ON = "Turn on"
    const val NOT_NOW = "Not now"
    /** The toast after Turn on, before the time in Geist Mono: "Nudge on at" "20:00". */
    const val NUDGE_ON = "Nudge on at"
    /** Turn on, and Android has notifications off for Taken. */
    const val NOTIFICATIONS_OFF = "Notifications are off for Taken in Settings"

    const val REPAIR_QUESTION = "Forgot to log yesterday?"
    const val REPAIR_ACTION = "Fill it in"
    val repair: String get() = "$REPAIR_QUESTION $REPAIR_ACTION"

    /** Android's home screen widget invite (the iPhone's names the Lock Screen). */
    const val WIDGET_INVITE = "Log from your home screen: add the Taken widget"
    const val CLOSE = "Close"

    /** Every line, for the copy rules test. */
    val all: List<String>
        get() = listOf(nudgeOffer(20 * 60), TURN_ON, NOT_NOW, NUDGE_ON, NOTIFICATIONS_OFF, repair, WIDGET_INVITE, CLOSE)
}
