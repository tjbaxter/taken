import Foundation
import WidgetKit

// The 1.1 retention build (SPEC 3.1, 2026-10-21): what keeps people logging and renewing, as pure rules. Today's one
// quiet row: the evening nudge offered once, the honest repair, the widget invite. Copy rules: no em or en dash, never
// the word for no charge, no exclamation marks.

/// The one quiet line Today may show under its progress line. At most one at a time, never in the capture path.
enum TodayPrompt: Equatable, Sendable {
    /// "Nudge me at 20:00 if anything's left", with Turn on and Not now: once, right after the stack is first added,
    /// while the nudge is off. Apple's guidance is to ask for notifications in context, after the person schedules a
    /// first task (https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications).
    case nudgeOffer(minutes: Int)
    /// "Forgot to log yesterday? Fill it in": yesterday is partly or not logged and something was logged in the week
    /// before. It opens yesterday's day sheet, the existing backfill, and its close hides it for that day, so nobody who
    /// really missed a dose is pushed to record one. No freeze, no paid save, no "streak broken".
    case repair(DayKey)
    /// "Log from your Lock Screen: add the Taken widget": once, on the first day that reaches All taken, and never to
    /// someone whose Lock Screen already has the Taken widget.
    case widgetInvite
    /// The trial reminder's own words ("Your Taken trial ends Sunday 1 Nov. ..."), while notifications are not allowed
    /// for Taken, from the moment the reminder would have come until the trial ends (`TrialReminder.notice`). A tap
    /// opens Apple's Manage subscription sheet. It keeps the paywall's "we remind you" without notifications.
    case trialEnds(String)
    #if DEBUG || TAKEN_INTERNAL
    /// "Log your weight here too: add a Weight tab", with Not now and Add tab: once, after every other row, to a stack
    /// with a GLP-1 medicine on a later All taken day (`WeightOffer`, SPEC 3.12). Internal builds only until 1.2.
    case weightOffer
    #endif
}

enum TodayPrompts {
    /// Which row Today shows, if any. The nudge offer first (the lever with clinical evidence), then the repair, then the
    /// widget invite. None while locked: the Taken Pro bar sits there, and each of them leads to something Pro unlocks.
    /// `lockScreenWidget`: a Taken stack widget is already on the Lock Screen (WidgetKit's configured widgets), so the
    /// invite would be noise. A repair line closed for its day stays closed that day. The trial notice
    /// (`trialNotice`, only while notifications cannot deliver the trial reminder) comes before all of them: it is
    /// the reminder the paywall promised, and it lasts at most 3 days.
    static func pick(settings: StackSettings, hasStack: Bool, today: DaySummary, repairDay: DayKey?,
                     locked: Bool, lockScreenWidget: Bool = false, trialNotice: String? = nil) -> TodayPrompt? {
        guard hasStack, !locked else { return nil }
        if let trialNotice { return .trialEnds(trialNotice) }
        if !settings.reminderEnabled && !settings.nudgeOfferDone { return .nudgeOffer(minutes: settings.reminderMinutes) }
        if let repairDay, settings.repairClosedDay != repairDay.ordinal { return .repair(repairDay) }
        if today.allTaken && !settings.widgetInviteDone && !lockScreenWidget
            && (settings.widgetInviteDay == nil || settings.widgetInviteDay == today.day.ordinal) {
            return .widgetInvite
        }
        return nil
    }

    /// Whether the configured widgets (`WidgetCenter.getCurrentConfigurations`,
    /// https://developer.apple.com/documentation/widgetkit/widgetcenter/getcurrentconfigurations(_:)) include the Taken
    /// stack widget (`TakenWidgetKind.stack`) in a Lock Screen family. The To-do widget does not count: it does not log
    /// doses.
    static func hasLockScreenWidget(_ widgets: [(kind: String, family: WidgetFamily)]) -> Bool {
        widgets.contains { widget in
            guard widget.kind == TakenWidgetKind.stack else { return false }
            switch widget.family {
            case .accessoryCircular, .accessoryRectangular, .accessoryInline: return true
            default: return false
            }
        }
    }

    /// Yesterday, when the repair line belongs on Today: it is partial or missed (a weekly item's open week counts
    /// neither way), and something counts for one of the 7 days before it, or for yesterday itself. It goes once
    /// yesterday is complete, or when today ends.
    static func repairDay(engine: StackEngine, today: DayKey) -> DayKey? {
        let yesterday = today.adding(-1)
        let status = engine.summary(for: yesterday, asOf: today).status
        guard status == .partial || status == .missed else { return nil }
        guard engine.loggedAnything(from: yesterday.adding(-7), through: yesterday) else { return nil }
        return yesterday
    }
}

enum RetentionCopy {
    /// "Nudge me at 20:00 if anything's left", at the person's own nudge time.
    static func nudgeOffer(minutes: Int) -> String {
        "Nudge me at \(Fmt.minutes(minutes)) if anything's left"
    }
    static let turnOn = "Turn on"
    static let notNow = "Not now"
    /// The toast after Turn on, before the time in Geist Mono: "Nudge on at" "20:00".
    static let nudgeOn = "Nudge on at"
    /// Turn on, and iOS has notifications off for Taken.
    static let notificationsOff = "Notifications are off for Taken in Settings"

    static let repairQuestion = "Forgot to log yesterday?"
    static let repairAction = "Fill it in"
    static var repair: String { "\(repairQuestion) \(repairAction)" }

    static let widgetInvite = "Log from your Lock Screen: add the Taken widget"
    static let widgetTitle = "Log from your Lock Screen"
    static let widgetSubtitle = "Add the Taken widget in three steps."
    /// As Apple's guide gives them (https://support.apple.com/en-us/118610), with the Lock Screen chosen after Customize.
    static let widgetSteps = [
        "Touch and hold your Lock Screen, then tap Customize and Lock Screen.",
        "Tap Add Widgets, then Taken.",
        "Tap the widget you want, then Done.",
    ]
    static let widgetFootnote = "A tap on it logs everything pending. The Home Screen has Taken widgets too."

    /// Every line, for the copy rules test.
    static var all: [String] {
        [nudgeOffer(minutes: 20 * 60), turnOn, notNow, nudgeOn, notificationsOff, repair, widgetInvite, widgetTitle,
         widgetSubtitle, widgetFootnote] + widgetSteps
    }
}
