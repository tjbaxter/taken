import Foundation

/// CI only (`-demo`): what is in front, written to `tmp/taken-ui-state.txt` in the app's container whenever it changes,
/// so scripts/screenshots.sh can fail a link check that lands on the wrong screen instead of saving a picture of it.
/// Lines: `tab=today|todo|history`, `sheet=<route or none>`, `paywall=0|1`, `todo=idle|starting|listening|sorting`.
@MainActor
enum DemoProbe {
    static let fileName = "taken-ui-state.txt"

    static func record(_ model: AppModel, todo: TodoModel = .shared) {
        guard model.isDemo else { return }
        let lines = [
            "tab=\(model.tab.rawValue)",
            "sheet=\(model.sheet?.id ?? "none")",
            "paywall=\(model.paywall == nil ? 0 : 1)",
            "todo=\(todo.phase)",
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
    }
}
