import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct StackEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct StackProvider: TimelineProvider {
    func placeholder(in context: Context) -> StackEntry {
        let now = Date()
        return StackEntry(date: now, snapshot: .demo(now: now))
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (StackEntry) -> Void) {
        let now = Date()
        let state = TakenStore.shared.load()
        if context.isPreview && state.items.isEmpty {
            completion(StackEntry(date: now, snapshot: .demo(now: now)))
        } else {
            completion(StackEntry(date: now, snapshot: WidgetSnapshot(state: state, now: now)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<StackEntry>) -> Void) {
        let now = Date()
        let state = TakenStore.shared.load()
        let rollover = DayClock(dayStartHour: state.settings.dayStartHour).nextRollover(after: now)
        let current = WidgetSnapshot(state: state, now: now)
        var entries = [StackEntry(date: now, snapshot: current)]
        // An item logged in the last hour turns tappable again once the repeat guard is over.
        if let ready = current.nextReady, ready > now, ready < rollover {
            entries.append(StackEntry(date: ready, snapshot: WidgetSnapshot(state: state, now: ready)))
        }
        entries.append(StackEntry(date: rollover, snapshot: WidgetSnapshot(state: state, now: rollover)))
        completion(Timeline(entries: entries, policy: .after(rollover)))
    }
}

// MARK: - Widget

struct StackWidget: Widget {
    static let kind = "TakenStack"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: StackProvider()) { entry in
            StackWidgetView(entry: entry)
        }
        .configurationDisplayName("Taken")
        .description("Did I take it? Tap to log.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct StackWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StackEntry

    init(entry: StackEntry) {
        self.entry = entry
    }

    var body: some View {
        content
            .widgetURL(URL(string: "taken://today"))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemMedium:
            MediumStackView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Palette.bg }
        case .accessoryCircular:
            CircularStackView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            RectangularStackView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            InlineStackView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Color.clear }
        default:
            SmallStackView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Palette.bg }
        }
    }
}
