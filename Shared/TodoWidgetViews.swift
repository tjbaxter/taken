import SwiftUI
import WidgetKit

// The to-do Lock Screen widget's faces (REDESIGN.md, voice to-dos), shared by the widget extension and the app's
// widget gallery (`-demo -screen widgets-todo`). The system draws Lock Screen widgets in its own white, so these name
// no colours.

struct TodoEntry: TimelineEntry {
    let date: Date
    /// Open tasks, due first (the To-do tab's order), at most three.
    let open: [String]
    /// Every open task.
    let openCount: Int

    init(date: Date, open: [String], openCount: Int) {
        self.date = date
        self.open = open
        self.openCount = openCount
    }

    /// What the widget shows for a set of tasks at a moment: the one list in the order the To-do tab shows it, with its
    /// count, so the Lock Screen and the app agree. The app reloads the widget on every write.
    init(date: Date, state: TodoState, clock: DayClock) {
        let open = state.openTasks(clock: clock)
        self.init(date: date, open: open.prefix(3).map(\.title), openCount: open.count)
    }

    /// The rectangular header with the open count: "To-do · 4", or "To-do" with nothing open.
    var header: String {
        openCount == 0 ? "To-do" : "To-do \u{00B7} \(openCount)"
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

/// What is still open, in the To-do tab's order.
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
