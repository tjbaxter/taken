import AppIntents
import SwiftUI
import WidgetKit

// Widget content, shared by the widget extension and the app's preview gallery (`-demo -screen widgets`).

// MARK: - Snapshot

struct WidgetRow: Identifiable, Sendable {
    let id: UUID
    let code: String
    let name: String
    let taken: Int
    let due: Int
    let lastTime: Date?

    var done: Bool { taken >= due }
}

struct WidgetSnapshot: Sendable {
    let takenDue: Int
    let dueDoses: Int
    let pendingItems: Int
    let rows: [WidgetRow]
    let lastDose: Date?
    let hasStack: Bool
    let clock: DayClock

    var allTaken: Bool { dueDoses > 0 && takenDue >= dueDoses }

    init(state: StackState, now: Date) {
        let clock = DayClock(dayStartHour: state.settings.dayStartHour)
        let summary = StackEngine(state: state, clock: clock).todaySummary(now: now)
        self.clock = clock
        takenDue = summary.takenDueDoses
        dueDoses = summary.dueDoses
        pendingItems = summary.pendingItems.count
        rows = summary.due.map { row in
            WidgetRow(id: row.item.id, code: row.item.code, name: row.item.name,
                      taken: row.takenCount, due: row.dosesPerDay, lastTime: row.lastDose?.takenAt)
        }
        lastDose = summary.lastDose?.takenAt
        hasStack = !summary.isEmpty
    }

    static func demo(now: Date) -> WidgetSnapshot {
        WidgetSnapshot(state: DemoData.state(now: now, allTaken: false), now: now)
    }
}

// MARK: - Home Screen

private struct WidgetHeader: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 6) {
            CapsuleGlyph()
                .frame(width: 13, height: 13)
                .widgetAccentable()
            Text("TAKEN")
                .hudFixed(10, Palette.fg, face: .monoSemibold, tracking: 0.24)
            Spacer(minLength: 0)
        }
    }
}

private struct MiniBar: View {
    let total: Int
    let lit: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                if total > 0 && index < lit {
                    Rectangle().fill(Palette.signal).frame(height: 4).widgetAccentable()
                } else {
                    Rectangle().fill(Palette.bgInset)
                        .overlay(Rectangle().strokeBorder(Palette.line, lineWidth: 1))
                        .frame(height: 4)
                }
            }
        }
    }
}

private struct Counter: View {
    let snapshot: WidgetSnapshot
    var size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("\(snapshot.takenDue)").foregroundStyle(Palette.fg)
            Text("/\(snapshot.dueDoses)").foregroundStyle(Palette.fgFaint)
        }
        .font(.monoFixed(size, .monoMedium))
        .tracking(-1)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

private struct TakeAllWidgetButton: View {
    let pending: Int

    var body: some View {
        Button(intent: TakeAllIntent()) {
            HStack(spacing: 6) {
                Rectangle().fill(Palette.signal).frame(width: 5, height: 5).widgetAccentable()
                Text("TAKE ALL")
                    .font(.monoFixed(11, .monoSemibold))
                    .tracking(11 * 0.1)
                if pending > 1 {
                    Text("\(pending)")
                        .font(.monoFixed(11, .monoMedium))
                        .opacity(0.6)
                }
            }
            .foregroundStyle(Palette.buttonText)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(Palette.button, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}

private struct LockedLine: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 6) {
            Rectangle().fill(Palette.signal).frame(width: 5, height: 5).widgetAccentable()
            Text(snapshot.lastDose.map { "LOCKED \(Fmt.clock($0, snapshot.clock))" } ?? "LOCKED")
                .hudFixed(9.5, Palette.fgMuted, tracking: 0.12)
        }
        .frame(height: 34, alignment: .leading)
    }
}

private struct EmptyWidgetLine: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NO STACK YET").hudFixed(10, Palette.fgMuted, tracking: 0.12)
            Text("OPEN TAKEN TO ADD").hudFixed(9, Palette.fgFaint, tracking: 0.12)
        }
    }
}

struct SmallStackView: View {
    let snapshot: WidgetSnapshot

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
                    .foregroundStyle(Palette.signal)
                    .widgetAccentable()
                Spacer(minLength: 6)
                MiniBar(total: snapshot.dueDoses, lit: snapshot.takenDue)
                LockedLine(snapshot: snapshot)
            } else {
                Counter(snapshot: snapshot, size: 38)
                Spacer(minLength: 6)
                MiniBar(total: snapshot.dueDoses, lit: snapshot.takenDue)
                    .padding(.bottom, 10)
                if snapshot.pendingItems > 0 {
                    TakeAllWidgetButton(pending: snapshot.pendingItems)
                } else {
                    LockedLine(snapshot: snapshot)
                }
            }
        }
    }
}

struct MediumStackView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 14) {
            SmallStackView(snapshot: snapshot)
                .frame(width: 124)
            Rectangle().fill(Palette.line).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                if snapshot.rows.isEmpty {
                    Text(snapshot.hasStack ? "NOTHING DUE TODAY" : "ADD YOUR STACK IN TAKEN")
                        .hudFixed(10, Palette.fgSubtle, tracking: 0.12)
                    Spacer(minLength: 0)
                } else {
                    ForEach(Array(snapshot.rows.prefix(4).enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            HLine()
                                .stroke(Palette.lineDash, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                .frame(height: 1)
                        }
                        MediumRow(row: row, clock: snapshot.clock)
                    }
                    if snapshot.rows.count > 4 {
                        Text("+\(snapshot.rows.count - 4) MORE")
                            .hudFixed(9, Palette.fgFaint, tracking: 0.12)
                            .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct MediumRow: View {
    let row: WidgetRow
    let clock: DayClock

    var body: some View {
        if row.done {
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
                .foregroundStyle(row.done ? Palette.signal : Palette.fgMuted)
                .frame(width: 30, alignment: .leading)
            Text(row.name)
                .font(.custom(Face.sans.rawValue, fixedSize: 12))
                .foregroundStyle(row.done ? Palette.fg : Palette.fgMuted)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let last = row.lastTime {
                Text(row.due > 1 && !row.done ? "\(row.taken)/\(row.due)" : Fmt.clock(last, clock))
                    .font(.monoFixed(11, .monoMedium))
                    .foregroundStyle(Palette.signal)
                    .widgetAccentable()
            } else {
                Text("TAP")
                    .hudFixed(9, Palette.fgFaint, tracking: 0.14)
            }
        }
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var mark: some View {
        if row.done {
            Circle().fill(Palette.signal).frame(width: 9, height: 9).widgetAccentable()
        } else {
            Circle()
                .strokeBorder(Palette.fgFaint, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .frame(width: 9, height: 9)
        }
    }
}

// MARK: - Lock Screen

struct CircularStackView: View {
    let snapshot: WidgetSnapshot

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
        } else {
            Button(intent: TakeAllIntent()) {
                Gauge(value: Double(snapshot.takenDue), in: 0...Double(max(snapshot.dueDoses, 1))) {
                    Text("TAKEN")
                } currentValueLabel: {
                    Text("\(snapshot.takenDue)/\(snapshot.dueDoses)")
                        .font(.monoFixed(12, .monoSemibold))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(snapshot.takenDue) of \(snapshot.dueDoses) taken. Tap to take all.")
        }
    }
}

struct RectangularStackView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        if !snapshot.hasStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("TAKEN").font(.monoFixed(13, .monoSemibold))
                Text("Add your stack in the app.").font(.custom(Face.sans.rawValue, fixedSize: 12))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if snapshot.allTaken || snapshot.pendingItems == 0 {
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

    var body: some View {
        if !snapshot.hasStack {
            Text("TAKEN \u{00B7} ADD YOUR STACK")
        } else if snapshot.allTaken {
            Text(snapshot.lastDose.map { "ALL TAKEN \(Fmt.clock($0, snapshot.clock))" } ?? "ALL TAKEN")
        } else {
            Text("\(snapshot.takenDue)/\(snapshot.dueDoses) TAKEN")
        }
    }
}
