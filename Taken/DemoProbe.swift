import Foundation

/// CI only (`-demo`): what is in front, written to `tmp/taken-ui-state.txt` in the app's container whenever it changes,
/// so scripts/screenshots.sh can fail a link check that lands on the wrong screen instead of saving a picture of it.
/// Lines: `tab=today|todo|history|weight`, `sheet=<route or none>`, `paywall=0|1`, `todo=idle|starting|listening|sorting`,
/// `ask=0|1` (the notification ask after a trial starts), and in builds with the Weight tab `weight=0|1` (the tab is on),
/// `offer=0|1` (Today's one-time weight offer is showing), `goal=0|1` (a weight goal is set) and `points=N` (the goal's
/// lit points in the chart's range).
@MainActor
enum DemoProbe {
    static let fileName = "taken-ui-state.txt"
    /// Whether the paywall's plans and the trial timeline fit above the button without scrolling:
    /// `content=<pt>`, `area=<pt>`, `fits=0|1`.
    static let paywallFitFileName = "taken-paywall-fit.txt"
    #if DEBUG || TAKEN_INTERNAL
    /// Whether the Weight tab's chart card ends above the tab bar: `chart=<pt>`, `visible=<pt>`, `fits=0|1`.
    static let weightFitFileName = "taken-weight-fit.txt"
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
                "goal=\(model.weight.goal == nil ? 0 : 1)", "points=\(points)"]
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
    #endif
}
