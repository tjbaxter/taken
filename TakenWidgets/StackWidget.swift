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
            completion(StackEntry(date: now, snapshot: .demo(now: now, theme: state.settings.theme)))
        } else {
            let ledger = ProLedgerStore.shared.load()
            completion(StackEntry(date: now, snapshot: Self.snapshot(state: state, ledger: ledger, at: now)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<StackEntry>) -> Void) {
        let now = Date()
        let state = TakenStore.shared.load()
        let ledger = ProLedgerStore.shared.load()
        let rollover = DayClock(dayStartHour: state.settings.dayStartHour).nextRollover(after: now)
        let current = Self.snapshot(state: state, ledger: ledger, at: now)
        var entries = [StackEntry(date: now, snapshot: current)]
        // An item logged in the last hour turns tappable again once the repeat guard is over.
        if let ready = current.nextReady, ready > now, ready < rollover {
            entries.append(StackEntry(date: ready, snapshot: Self.snapshot(state: state, ledger: ledger, at: ready)))
        }
        // Cached Pro that runs out before the day does: the widget turns read-only at that moment. A plan set to renew
        // runs past its period end by the renewal margin (ProStatus.activeUntil), so a renewal never locks it.
        if !current.locked, let end = ledger?.status?.activeUntil, end > now, end < rollover {
            entries.append(StackEntry(date: end, snapshot: Self.snapshot(state: state, ledger: ledger, at: end)))
        }
        entries.append(StackEntry(date: rollover, snapshot: Self.snapshot(state: state, ledger: ledger, at: rollover)))
        entries.sort { $0.date < $1.date }
        completion(Timeline(entries: entries, policy: .after(rollover)))
    }

    /// The widget's view of the stack at a moment, locked when logging needs Taken Pro (PRO.md).
    static func snapshot(state: StackState, ledger: ProLedger?, at date: Date) -> WidgetSnapshot {
        let locked = !ProGate.access(ledger: ledger, state: state, now: date).allowsLogging
        return WidgetSnapshot(state: state, now: date, locked: locked)
    }
}

// MARK: - Widget

struct StackWidget: Widget {
    static let kind = TakenWidgetKind.stack

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
    @Environment(\.showsWidgetContainerBackground) private var showsBackground
    let entry: StackEntry

    init(entry: StackEntry) {
        self.entry = entry
    }

    /// The look chosen in the app, read from the App Group store with the stack. Where the system removes the canvas
    /// and draws the widget on black (StandBy, CarPlay), a light look switches to its dark-canvas text.
    private var theme: Theme {
        let look = entry.snapshot.theme.theme
        return showsBackground ? look : look.withoutBackground
    }

    var body: some View {
        content
            .environment(\.theme, theme)
            .widgetURL(entry.snapshot.url)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemMedium:
            MediumStackView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { theme.bg }
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
                .containerBackground(for: .widget) { theme.bg }
        }
    }
}
