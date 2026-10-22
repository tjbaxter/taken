import Foundation

/// CI only (`-demo`): what is in front, written to `tmp/taken-ui-state.txt` in the app's container whenever it changes,
/// so scripts/screenshots.sh can fail a link check that lands on the wrong screen instead of saving a picture of it.
/// Lines: `tab=today|todo|history|weight`, `sheet=<route or none>`, `paywall=0|1`, `todo=idle|starting|listening|sorting`,
/// `ask=0|1` (the notification ask after a trial starts), and in builds with the Weight tab `weight=0|1` (the tab is on),
/// `offer=0|1` (Today's one-time weight offer is showing), `goal=0|1` (a weight goal is set), `points=N` (the goal's
/// lit points in the chart's range), `focus=0|1` (the big number is being typed into), `figure=empty|ghost|today|typing`,
/// `line=last|range|closing|moment` (the small line under it), `scroll=entry|trend` (screen two at the top) and
/// `weightlock=0|1` (logging a weigh-in needs Taken Pro).
@MainActor
enum DemoProbe {
    static let fileName = "taken-ui-state.txt"
    /// Whether the paywall's plans and the trial timeline fit above the button without scrolling:
    /// `content=<pt>`, `area=<pt>`, `fits=0|1`.
    static let paywallFitFileName = "taken-paywall-fit.txt"
    #if DEBUG || TAKEN_INTERNAL
    /// Whether the Weight tab's chart card ends above the tab bar: `chart=<pt>`, `visible=<pt>`, `fits=0|1`.
    static let weightFitFileName = "taken-weight-fit.txt"
    /// Whether the small line stays clear of the Weigh in bar, and the number still, while typing: `line=<pt>`,
    /// `button=<pt>`, `shift=<pt>`, `fits=0|1`, `still=0|1`.
    static let weightEntryFitFileName = "taken-weight-entry-fit.txt"
    #endif

    static func record(_ model: AppModel, todo: TodoModel = .shared) {
        guard model.isDemo else { return }
        let lines = [
            "tab=\(model.tab.rawValue)",
            "sheet=\(model.sheet?.id ?? "none")",
            "paywall=\(model.paywall == nil ? 0 : 1)",
            "todo=\(todo.phase)",
            "ask=\(model.trialAsk == nil ? 0 : 1)",
        ] + weightLines(model)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
    }

    /// The Weight tab's lines, in the builds that have it (SPEC 3.12).
    private static func weightLines(_ model: AppModel) -> [String] {
        #if DEBUG || TAKEN_INTERNAL
        let points = model.weight.goal == nil ? 0 : model.weightPicture(range: model.weight.range).momentsInView.count
        return ["weight=\(model.weight.showsTab ? 1 : 0)", "offer=\(model.todayPrompt == .weightOffer ? 1 : 0)",
                "goal=\(model.weight.goal == nil ? 0 : 1)", "points=\(points)",
                "focus=\(model.weight.entryFocused ? 1 : 0)", "figure=\(model.weightFigure.kind)",
                "line=\(model.weightLine().kind)", "scroll=\(model.weight.onTrend ? "trend" : "entry")",
                "weightlock=\(model.weightAccess == .locked ? 1 : 0)"]
        #else
        return []
        #endif
    }

    /// The paywall's scrolling content against the room it has: it fits when the content is no taller than the area
    /// (the spacer above the plans then takes the spare height).
    static func recordPaywallFit(content: CGFloat, area: CGFloat) {
        let lines = [
            "content=\(String(format: "%.1f", content))",
            "area=\(String(format: "%.1f", area))",
            "fits=\(content <= area + 0.5 ? 1 : 0)",
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(paywallFitFileName)
        try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
    }

    #if DEBUG || TAKEN_INTERNAL
    /// The Weight tab's chart card against the top of the tab bar (the scroll view's visible bottom less its bottom
    /// safe-area inset), in global points: it fits when the card ends at or above it (REDESIGN.md, "Goal and moments").
    static func recordWeightFit(chartBottom: CGFloat, visibleBottom: CGFloat) {
        let lines = [
            "chart=\(String(format: "%.1f", chartBottom))",
            "visible=\(String(format: "%.1f", visibleBottom))",
            "fits=\(chartBottom <= visibleBottom + 0.5 ? 1 : 0)",
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(weightFitFileName)
        try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
    }

    /// The keypad up: the small line's bottom against the Weigh in bar's top (it fits with 16 pt clear), and how far the
    /// number's block moved when focus came (still within half a point). Global points.
    static func recordWeightEntryFit(lineBottom: CGFloat, buttonTop: CGFloat, shift: CGFloat) {
        let lines = [
            "line=\(String(format: "%.1f", lineBottom))",
            "button=\(String(format: "%.1f", buttonTop))",
            "shift=\(String(format: "%.1f", shift))",
            "fits=\(lineBottom <= buttonTop - 16 + 0.5 ? 1 : 0)",
            "still=\(abs(shift) <= 0.5 ? 1 : 0)",
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(weightEntryFitFileName)
        try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
    }
    #endif
}
