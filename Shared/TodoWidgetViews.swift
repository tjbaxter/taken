import SwiftUI
import WidgetKit

// The to-do Lock Screen widget's faces (REDESIGN.md, voice to-dos), shared by the widget extension and the app's
// widget gallery (`-demo -screen widgets-todo`). The system draws Lock Screen widgets in its own white, so these name
// no colours.

struct TodoEntry: TimelineEntry {
    let date: Date
    /// Open tasks, due first (the To-do tab's order), at most three.
    let open: [String]
    let openCount: Int
    /// The list it shows: the one last in view in the app.
    let area: TodoArea

    init(date: Date, open: [String], openCount: Int, area: TodoArea = .personal) {
        self.date = date
        self.open = open
        self.openCount = openCount
        self.area = area
    }

    /// What the widget shows for a set of tasks at a moment: the list last in view in the app (`lastArea`), so the
    /// Lock Screen never mixes Personal and Work. The app reloads the widget whenever that list changes.
    init(date: Date, state: TodoState, clock: DayClock) {
        let open = state.openTasks(in: state.lastArea, clock: clock)
        self.init(date: date, open: open.prefix(3).map(\.title), openCount: open.count, area: state.lastArea)
    }

    /// The rectangular header with the open count: "To-do · 2" for Personal, as before lists, and "Work · 2".
    var header: String {
        let name = area == .work ? TodoArea.work.title : "To-do"
        return openCount == 0 ? name : "\(name) \u{00B7} \(openCount)"
    }
}

/// The round mic: opens Taken listening.
struct TodoCircularView: View {
    init() {}

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "mic.fill")
                .font(.system(size: 22, weight: .semibold))
                .widgetAccentable()
        }
        .accessibilityLabel("New voice to-do")
    }
}

/// What is still open, newest due first.
struct TodoRectangularView: View {
    let entry: TodoEntry

    init(entry: TodoEntry) {
        self.entry = entry
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 11, weight: .bold))
                    .widgetAccentable()
                Text(entry.header)
                    .font(.sans(13, .sansSemibold))
                    .widgetAccentable()
            }
            if entry.open.isEmpty {
                Text("Tap to see your list")
                    .font(.sans(13))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(entry.open.prefix(2).enumerated()), id: \.offset) { _, title in
                    Text(title)
                        .font(.sans(13))
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// "3 to-dos", with the mic.
struct TodoInlineView: View {
    let entry: TodoEntry

    init(entry: TodoEntry) {
        self.entry = entry
    }

    var body: some View {
        Label(entry.openCount == 1 ? "1 to-do" : "\(entry.openCount) to-dos", systemImage: "mic.fill")
    }
}
