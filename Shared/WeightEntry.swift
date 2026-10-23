import Foundation

// The Weight tab's page, entry first (REDESIGN.md, "Weight tab page: entry first, 2026-10-22"): what the big number shows,
// what the small line under it says, when the range hint shows, and where a scroll comes to rest, as pure rules
// (TakenTests/WeightEntryTests.swift).

/// The page's scroll anchors: screen one, the number's block, and screen two.
enum WeightAnchor: Hashable, Sendable {
    case entry
    case block
    case trend
}

/// What the big number shows. It always shows a weigh-in, never the trend.
enum WeightFigure: Equatable, Sendable {
    /// Never weighed in: no digits, the caret and the unit.
    case empty
    /// The last weigh-in in grey: on an earlier day, or as the hint while nothing is typed yet. It can never be saved.
    case ghost(kg: Double)
    /// Today's latest weigh-in, in the look's ink.
    case today(kg: Double)
    /// What is being typed.
    case typing(String)

    /// For DemoProbe: "empty", "ghost", "today", "typing".
    var kind: String {
        switch self {
        case .empty: return "empty"
        case .ghost: return "ghost"
        case .today: return "today"
        case .typing: return "typing"
        }
    }
}

/// What the small line under the number says.
enum WeightLine: Equatable, Sendable {
    /// "Last weigh-in yesterday, 07:42", or "No weigh-ins yet".
    case last
    /// "Between 20 and 350 kg": typing, a finished-looking number outside the bounds.
    case range
    /// "Trend 1.1 kg to 87.0": after a save on this visit, with a goal.
    case closing(GoalReadout)
    /// The lit dot and "Trend is now 10% below where you started.": a save on this visit lit a point.
    case moment(WeightMoment)

    /// For DemoProbe: "last", "range", "closing", "moment".
    var kind: String {
        switch self {
        case .last: return "last"
        case .range: return "range"
        case .closing: return "closing"
        case .moment: return "moment"
        }
    }
}

enum WeightEntry {
    /// The big number: typing shows the draft, or the last weigh-in in grey (today's included) until a key is pressed;
    /// otherwise today's latest weigh-in, the last one in grey, or nothing.
    static func figure(last: WeighIn?, today: DayKey, clock: DayClock, draft: String, focused: Bool) -> WeightFigure {
        if focused {
            if !draft.isEmpty { return .typing(draft) }
            return last.map { .ghost(kg: $0.kg) } ?? .empty
        }
        guard let last else { return .empty }
        return clock.day(of: last) == today ? .today(kg: last.kg) : .ghost(kg: last.kg)
    }

    /// Whether the draft looks finished (own rule): a decimal separator followed by a digit, or 3 or more whole digits.
    /// So "8" on the way to "88" never shows a warning.
    static func looksFinished(_ draft: String, locale: Locale) -> Bool {
        let separators: Set<Character> = Set([".", ",", "\u{066B}"] + Array(locale.decimalSeparator ?? "."))
        var whole = 0
        var fraction = 0
        var separated = false
        for character in draft {
            if separators.contains(character) {
                separated = true
            } else if character.isNumber {
                if separated { fraction += 1 } else { whole += 1 }
            }
        }
        return whole >= 3 || (separated && fraction >= 1)
    }

    /// "Between 20 and 350 kg" shows while typing once the number looks finished and parses outside the unit's bounds.
    static func showsRangeHint(_ draft: String, unit: WeightUnit, locale: Locale) -> Bool {
        guard looksFinished(draft, locale: locale), let value = WeightFormat.parse(draft, locale: locale) else { return false }
        return !unit.bounds.contains(value)
    }

    /// The small line, first rule that applies: the range hint while typing; else, while typing, the last weigh-in;
    /// else the point a save on this visit lit; else, after a save on this visit with a goal, how close the trend is
    /// (never for "Goal 87.0"); else the last weigh-in.
    static func line(focused: Bool, draft: String, unit: WeightUnit, locale: Locale, hasGoal: Bool,
                     justSaved: Bool, justReached: WeightMoment?, readout: GoalReadout?) -> WeightLine {
        if focused { return showsRangeHint(draft, unit: unit, locale: locale) ? .range : .last }
        if let justReached { return .moment(justReached) }
        if justSaved, hasGoal, let readout, readout != .goalOnly { return .closing(readout) }
        return .last
    }

    /// The string that sizes the digits box: the longer of the grey value and the draft, so nothing re-centres while
    /// typing.
    static func sizing(ghost: String, draft: String) -> String {
        draft.count > ghost.count ? draft : ghost
    }
}

/// Where a scroll comes to rest: between the top and the fold (the bottom of screen one), the nearer of the two, so a
/// flick goes all the way to the trend; anywhere else, where the scroll was going.
enum WeightFold {
    static func snap(_ y: CGFloat, fold: CGFloat) -> CGFloat {
        guard fold > 0, y > 0, y < fold else { return y }
        return y < fold / 2 ? 0 : fold
    }
}
