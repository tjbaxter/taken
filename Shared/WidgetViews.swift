import AppIntents
import SwiftUI
import WidgetKit

// Widget content, shared by the widget extension and the app's preview gallery (`-demo -screen widgets`). Every colour
// comes from `@Environment(\.theme)`: the widget extension sets it from the look in the App Group store, the gallery
// from the app's.

// MARK: - Snapshot

struct WidgetRow: Identifiable, Sendable {
    let id: UUID
    let code: String
    let name: String
    let taken: Int
    let due: Int
    let lastTime: Date?
    /// A tap may log it now: still pending, and not logged in the last hour (StackEngine.repeatGuard).
    let ready: Bool

    var done: Bool { taken >= due }
}

struct WidgetSnapshot: Sendable {
    let takenDue: Int
    let dueDoses: Int
    let pendingItems: Int
    /// Items TAKE ALL logs right now. Fewer than `pendingItems` while one was logged in the last hour.
    let readyItems: Int
    let rows: [WidgetRow]
    let lastDose: Date?
    let hasStack: Bool
    let clock: DayClock
    /// When a pending item held back by the repeat guard can be tapped again, for the timeline.
    let nextReady: Date?
    /// Logging needs Taken Pro: the stack shows read-only with a small PRO glyph, and a tap opens the paywall.
    let locked: Bool
    /// The look chosen in the app (Settings > LOOK).
    let theme: ThemeID

    var allTaken: Bool { dueDoses > 0 && takenDue >= dueDoses }

    /// Where a tap on the widget goes: TODAY, or the paywall when locked.
    var url: URL { locked ? ProRoute().url : URL(string: "taken://today")! }

    init(state: StackState, now: Date, timeZone: TimeZone = .autoupdatingCurrent, locked: Bool = false) {
        let clock = DayClock(dayStartHour: state.settings.dayStartHour, timeZone: timeZone)
        let engine = StackEngine(state: state, clock: clock)
        let summary = engine.todaySummary(now: now)
        self.clock = clock
        takenDue = summary.takenDueDoses
        dueDoses = summary.dueDoses
        pendingItems = summary.pendingItems.count
        readyItems = engine.quickLogRows(summary, now: now).count
        nextReady = summary.pendingItems.compactMap { engine.quickLogResumes($0, now: now) }.min()
        let all = summary.due.map { row in
            WidgetRow(id: row.item.id, code: row.item.code, name: row.item.name,
                      taken: row.takenCount, due: row.dosesPerDay, lastTime: row.lastDose?.takenAt,
                      ready: engine.canQuickLog(row, now: now))
        }
        // What is still to take comes first, so the rows a widget has room for are the ones worth tapping.
        rows = all.filter { !$0.done } + all.filter { $0.done }
        lastDose = summary.lastDose?.takenAt
        hasStack = !summary.isEmpty
        self.locked = locked && !summary.isEmpty
        theme = state.settings.theme
    }

    /// The widget gallery's preview, in the look chosen in the app.
    static func demo(now: Date, theme: ThemeID = .signal) -> WidgetSnapshot {
        var state = DemoData.state(now: now, allTaken: false)
        state.settings.theme = theme
        return WidgetSnapshot(state: state, now: now)
    }
}

// MARK: - Home Screen

private struct WidgetHeader: View {
    @Environment(\.theme) private var theme
    let snapshot: WidgetSnapshot

    init(snapshot: WidgetSnapshot) {
        self.snapshot = snapshot
    }

    var body: some View {
        HStack(spacing: 6) {
            CapsuleGlyph()
                .frame(width: 13, height: 13)
                .widgetAccentable()
            Text("TAKEN")
                .hudFixed(10, theme.fg, face: .monoSemibold, tracking: 0.24)
            Spacer(minLength: 0)
            if snapshot.locked { ProLockGlyph() }
        }
    }
}

/// The small PRO lock glyph on a locked widget.
struct ProLockGlyph: View {
    @Environment(\.theme) private var theme

    init() {}

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "lock.fill")
                .font(.system(size: 7, weight: .bold))
            Text("PRO")
                .font(.monoFixed(8.5, .monoSemibold))
                .tracking(8.5 * 0.14)
        }
        .foregroundStyle(theme.signalInk)
        .padding(.horizontal, 5)
        .frame(height: 15)
        .overlay(RoundedRectangle(cornerRadius: theme.radius.mark).strokeBorder(theme.signalEdge, lineWidth: 1))
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Logging needs Taken Pro")
    }
}

private struct MiniBar: View {
    let total: Int
    let lit: Int
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.theme) private var theme

    init(total: Int, lit: Int) {
        self.total = total
        self.lit = lit
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: min(theme.radius.segment, 2))
        HStack(spacing: 3) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                if total > 0 && index < lit {
                    shape.fill(theme.signal).frame(height: 4).widgetAccentable()
                } else {
                    // Tinted and clear Home Screens draw every opaque fill white: an unlit segment
                    // keeps its meaning only as a faint one.
                    shape.fill(renderingMode == .fullColor ? theme.bgInset : theme.accentedFaint)
                        .overlay(shape.strokeBorder(theme.line, lineWidth: 1))
                        .frame(height: 4)
                }
            }
        }
    }
}

private struct Counter: View {
    let snapshot: WidgetSnapshot
    let size: CGFloat
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.theme) private var theme

    init(snapshot: WidgetSnapshot, size: CGFloat) {
        self.snapshot = snapshot
        self.size = size
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(snapshot.takenDue)").foregroundStyle(theme.fg)
            Text("/\(snapshot.dueDoses)")
                .foregroundStyle(renderingMode == .fullColor ? theme.fgFaint : theme.fg.opacity(0.45))
        }
        .font(.monoFixed(size, .monoMedium))
        .tracking(-1)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

private struct TakeAllWidgetButton: View {
    let pending: Int
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.theme) private var theme

    init(pending: Int) {
        self.pending = pending
    }

    var body: some View {
        // Full colour: the solid button. Tinted and clear Home Screens draw every opaque fill and label
        // white, so there the button is an outline and the label stays readable.
        let fullColor = renderingMode == .fullColor
        let shape = RoundedRectangle(cornerRadius: min(theme.radius.panel, 10))
        Button(intent: TakeAllIntent()) {
            HStack(spacing: 6) {
                LampShape(roundness: theme.radius.lampRoundness).fill(fullColor ? theme.buttonLamp : theme.signal)
                    .frame(width: 5, height: 5)
                    .widgetAccentable()
                Text("TAKE ALL")
                    .font(.monoFixed(11, .monoSemibold))
                    .tracking(11 * 0.1)
                if pending > 1 {
                    Text("\(pending)")
                        .font(.monoFixed(11, .monoMedium))
                        .opacity(0.6)
                }
            }
            .foregroundStyle(fullColor ? theme.buttonText : theme.fg)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background {
                if fullColor {
                    shape.fill(theme.button)
                } else {
                    shape
                        .fill(theme.accentedFill)
                        .overlay(shape.strokeBorder(theme.accentedStroke, lineWidth: 1))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// The small widget's bottom line when there is no TAKE ALL to show.
private struct StatusLine: View {
    @Environment(\.theme) private var theme
    let text: String
    var lit: Bool = true

    init(text: String, lit: Bool = true) {
        self.text = text
        self.lit = lit
    }

    var body: some View {
        HStack(spacing: 6) {
            LampShape(roundness: theme.radius.lampRoundness).fill(lit ? theme.signal : theme.fgFaint)
                .frame(width: 5, height: 5).widgetAccentable()
            Text(text)
                .hudFixed(9.5, theme.fgMuted, tracking: 0.12)
        }
        .frame(height: 34, alignment: .leading)
    }
}

/// A finished day: LOCKED 21:12. Without Pro the widget's lock is Taken Pro's, so the finished day reads DONE 21:12.
private struct LockedLine: View {
    let snapshot: WidgetSnapshot

    init(snapshot: WidgetSnapshot) {
        self.snapshot = snapshot
    }

    var body: some View {
        let word = snapshot.locked ? "DONE" : "LOCKED"
        StatusLine(text: snapshot.lastDose.map { "\(word) \(Fmt.clock($0, snapshot.clock))" } ?? word)
    }
}

private struct EmptyWidgetLine: View {
    @Environment(\.theme) private var theme

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NO STACK YET").hudFixed(10, theme.fgMuted, tracking: 0.12)
            Text("OPEN TAKEN TO ADD").hudFixed(9, theme.fgFaint, tracking: 0.12)
        }
    }
}

struct SmallStackView: View {
    @Environment(\.theme) private var theme
    let snapshot: WidgetSnapshot

    init(snapshot: WidgetSnapshot) {
        self.snapshot = snapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(snapshot: snapshot)
            Spacer(minLength: 4)
            if !snapshot.hasStack {
                EmptyWidgetLine()
                Spacer(minLength: 0)
            } else if snapshot.allTaken {
                Text("ALL\nTAKEN")
                    .font(.monoFixed(24, .monoSemibold))
                    .foregroundStyle(theme.signalInk)
                    .widgetAccentable()
                Spacer(minLength: 6)
                MiniBar(total: snapshot.dueDoses, lit: snapshot.takenDue)
                LockedLine(snapshot: snapshot)
            } else {
                Counter(snapshot: snapshot, size: 38)
                Spacer(minLength: 6)
                MiniBar(total: snapshot.dueDoses, lit: snapshot.takenDue)
                    .padding(.bottom, 10)
                if snapshot.locked {
                    // Read-only: the tap opens Taken Pro (the widget's URL), never logs.
                    StatusLine(text: "\(snapshot.pendingItems) PENDING", lit: false)
                } else if snapshot.readyItems > 0 {
                    TakeAllWidgetButton(pending: snapshot.readyItems)
                } else if snapshot.pendingItems > 0 {
                    // Logged in the last hour, its next dose still to come: a second tap here would log
                    // that next dose too early, so the button returns when the hour is up.
                    StatusLine(text: snapshot.lastDose.map { "LOGGED \(Fmt.clock($0, snapshot.clock))" } ?? "LOGGED")
                } else {
                    LockedLine(snapshot: snapshot)
                }
            }
        }
    }
}

struct MediumStackView: View {
    @Environment(\.theme) private var theme
    let snapshot: WidgetSnapshot

    init(snapshot: WidgetSnapshot) {
        self.snapshot = snapshot
    }

    var body: some View {
        HStack(spacing: 14) {
            SmallStackView(snapshot: snapshot)
                .frame(width: 124)
            Rectangle().fill(theme.line).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                if snapshot.rows.isEmpty {
                    Text(snapshot.hasStack ? "NOTHING DUE TODAY" : "ADD YOUR STACK IN TAKEN")
                        .hudFixed(10, theme.fgSubtle, tracking: 0.12)
                    Spacer(minLength: 0)
                } else {
                    ForEach(Array(snapshot.rows.prefix(4).enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            HLine()
                                .stroke(theme.lineDash, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .frame(height: 1)
                        }
                        MediumRow(row: row, clock: snapshot.clock, locked: snapshot.locked)
                    }
                    if snapshot.rows.count > 4 {
                        Text("+\(snapshot.rows.count - 4) MORE")
                            .hudFixed(9, theme.fgFaint, tracking: 0.12)
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct MediumRow: View {
    @Environment(\.theme) private var theme
    let row: WidgetRow
    let clock: DayClock
    let locked: Bool

    init(row: WidgetRow, clock: DayClock, locked: Bool) {
        self.row = row
        self.clock = clock
        self.locked = locked
    }

    var body: some View {
        if locked && !row.done {
            // Locked: the row opens Taken Pro, and the dose it asked for is logged once Pro is on.
            Link(destination: ProRoute(then: .log(row.id)).url) { label }
        } else if row.done || !row.ready {
            label
        } else {
            Button(intent: LogNextDoseIntent(itemID: row.id)) { label }
                .buttonStyle(.plain)
        }
    }

    private var label: some View {
        HStack(spacing: 8) {
            mark
            Text(row.code)
                .font(.monoFixed(11, .monoSemibold))
                .tracking(0.8)
                .foregroundStyle(row.done ? theme.signalInk : theme.fgMuted)
                .frame(width: 30, alignment: .leading)
            Text(row.name)
                .font(.custom(Face.sans.rawValue, fixedSize: 12))
                .foregroundStyle(row.done ? theme.fg : theme.fgMuted)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let last = row.lastTime {
                Text(row.due > 1 && !row.done ? "\(row.taken)/\(row.due)" : Fmt.clock(last, clock))
                    .font(.monoFixed(11, .monoMedium))
                    .foregroundStyle(theme.signalInk)
                    .widgetAccentable()
            } else {
                Text(row.ready && !locked ? "TAP" : "--:--")
                    .hudFixed(9, theme.fgFaint, tracking: 0.14)
            }
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var mark: some View {
        if row.done {
            Circle().fill(theme.signal).frame(width: 9, height: 9).widgetAccentable()
        } else {
            Circle()
                .strokeBorder(theme.fgFaint, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .frame(width: 9, height: 9)
        }
    }
}

// MARK: - Lock Screen

// The system draws Lock Screen widgets in its own vibrant white (and the accent on `widgetAccentable` parts), so
// these name no colours: they look the same in every look.

struct CircularStackView: View {
    let snapshot: WidgetSnapshot

    init(snapshot: WidgetSnapshot) {
        self.snapshot = snapshot
    }

    var body: some View {
        if !snapshot.hasStack || snapshot.dueDoses == 0 {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "pill").font(.system(size: 18, weight: .semibold))
            }
        } else if snapshot.allTaken {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .widgetAccentable()
                    Text("ALL").font(.monoFixed(9, .monoSemibold))
                }
            }
            .accessibilityLabel("All taken")
        } else if snapshot.locked {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .widgetAccentable()
                    Text("\(snapshot.takenDue)/\(snapshot.dueDoses)")
                        .font(.monoFixed(13, .monoSemibold))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(snapshot.takenDue) of \(snapshot.dueDoses) taken. Logging needs Taken Pro.")
        } else if snapshot.readyItems > 0 {
            Button(intent: TakeAllIntent()) { gauge }
                .buttonStyle(.plain)
                .accessibilityLabel("\(snapshot.takenDue) of \(snapshot.dueDoses) taken. Tap to take all.")
        } else {
            gauge
                .accessibilityLabel("\(snapshot.takenDue) of \(snapshot.dueDoses) taken.")
        }
    }

    private var gauge: some View {
        Gauge(value: Double(snapshot.takenDue), in: 0...Double(max(snapshot.dueDoses, 1))) {
            Text("TAKEN")
        } currentValueLabel: {
            Text("\(snapshot.takenDue)/\(snapshot.dueDoses)")
                .font(.monoFixed(12, .monoSemibold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }
}

struct RectangularStackView: View {
    let snapshot: WidgetSnapshot

    init(snapshot: WidgetSnapshot) {
        self.snapshot = snapshot
    }

    var body: some View {
        if !snapshot.hasStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("TAKEN").font(.monoFixed(13, .monoSemibold))
                Text("Add your stack in the app.").font(.custom(Face.sans.rawValue, fixedSize: 12))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if snapshot.readyItems == 0 || snapshot.locked {
            content
        } else {
            Button(intent: TakeAllIntent()) { content }
                .buttonStyle(.plain)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(snapshot.allTaken ? "ALL TAKEN" : "TAKEN \(snapshot.takenDue)/\(snapshot.dueDoses)")
                    .font(.monoFixed(13, .monoSemibold))
                    .widgetAccentable()
                Spacer(minLength: 0)
                if snapshot.locked {
                    HStack(spacing: 2) {
                        Image(systemName: "lock.fill").font(.system(size: 9, weight: .semibold))
                        Text("PRO").font(.monoFixed(10, .monoSemibold))
                    }
                    .widgetAccentable()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Logging needs Taken Pro")
                }
            }
            ForEach(snapshot.rows.prefix(3)) { row in
                HStack(spacing: 5) {
                    Text(row.done ? "\u{25CF}" : "\u{25CB}")
                        .font(.system(size: 10))
                    Text(row.code)
                        .font(.monoFixed(12, .monoMedium))
                    Spacer(minLength: 2)
                    Text(rowValue(row))
                        .font(.monoFixed(12, .monoMedium))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rowValue(_ row: WidgetRow) -> String {
        if let last = row.lastTime {
            return row.done ? Fmt.clock(last, snapshot.clock) : "\(row.taken)/\(row.due)"
        }
        return "--:--"
    }
}

struct InlineStackView: View {
    let snapshot: WidgetSnapshot

    init(snapshot: WidgetSnapshot) {
        self.snapshot = snapshot
    }

    var body: some View {
        if !snapshot.hasStack {
            Text("TAKEN \u{00B7} ADD YOUR STACK")
        } else if snapshot.allTaken {
            Text(snapshot.lastDose.map { "ALL TAKEN \(Fmt.clock($0, snapshot.clock))" } ?? "ALL TAKEN")
        } else if snapshot.locked {
            Label("\(snapshot.takenDue)/\(snapshot.dueDoses) TAKEN \u{00B7} PRO", systemImage: "lock.fill")
        } else {
            Text("\(snapshot.takenDue)/\(snapshot.dueDoses) TAKEN")
        }
    }
}
