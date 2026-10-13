import SwiftUI

/// Five weeks, Monday first, today in the last row. Lit = everything due was taken.
struct HistoryGrid: View {
    @Environment(\.theme) private var theme
    let rows: [[HistoryCell]]
    let onSelect: (DayKey) -> Void

    init(rows: [[HistoryCell]], onSelect: @escaping (DayKey) -> Void) {
        self.rows = rows
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { index in
                    Text(Fmt.weekdayLetters[index])
                        .hudFixed(10, theme.fgFaint, tracking: 0.1)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 2)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 6) {
                    ForEach(week) { cell in
                        Button {
                            onSelect(cell.day)
                        } label: {
                            DayCell(cell: cell)
                        }
                        .buttonStyle(PressStyle())
                        .disabled(cell.status == .future)
                        .accessibilityLabel(accessibilityLabel(for: cell))
                    }
                }
            }
        }
    }

    private func accessibilityLabel(for cell: HistoryCell) -> String {
        let date = Fmt.dayHeader(cell.day).capitalized
        switch cell.status {
        case .complete: return "\(date), all taken"
        case .partial: return "\(date), partly taken"
        case .missed: return "\(date), nothing taken"
        case .nothingDue: return "\(date), nothing due"
        case .future: return "\(date), upcoming"
        }
    }
}

struct DayCell: View {
    @Environment(\.theme) private var theme
    let cell: HistoryCell

    init(cell: HistoryCell) {
        self.cell = cell
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            background
            mark
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("\(cell.day.dayOfMonth)")
                .font(.monoFixed(9, .monoMedium))
                .foregroundStyle(numberColor)
                .padding(.leading, 5)
                .padding(.top, 4)
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            if cell.isToday {
                RoundedRectangle(cornerRadius: theme.radius.control)
                    .strokeBorder(theme.fg, lineWidth: 1.5)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var background: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius.control)
        switch cell.status {
        case .complete:
            shape
                .fill(theme.signalWash)
                .overlay(shape.strokeBorder(theme.signalEdge, lineWidth: 1))
        case .partial, .missed, .nothingDue:
            shape
                .fill(theme.bgRaised)
                .overlay(shape.strokeBorder(theme.line, lineWidth: 1))
        case .future:
            shape
                .strokeBorder(theme.lineDash, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    /// Lit check when everything due was taken, a half-lit dash for some, a dim tick for none.
    @ViewBuilder
    private var mark: some View {
        switch cell.status {
        case .complete:
            CheckShape()
                .stroke(theme.signalInk, style: StrokeStyle(lineWidth: 2.2, lineCap: .square, lineJoin: .miter))
                .frame(width: 18, height: 18)
                .shadow(color: theme.glow(0.75), radius: 5)
                .offset(y: 3)
        case .partial:
            Rectangle()
                .fill(theme.signalInk.opacity(0.7))
                .frame(width: 11, height: 2)
                .offset(y: 3)
        case .missed, .nothingDue:
            Rectangle()
                .fill(theme.tick)
                .frame(width: 6, height: 1.5)
                .offset(y: 3)
        case .future:
            EmptyView()
        }
    }

    private var numberColor: Color {
        if cell.isToday { return theme.fg }
        switch cell.status {
        // Full strength: on the signal wash the readable signal is AA in every look, a faded one is not (Blush).
        case .complete: return theme.signalInk
        case .partial: return theme.fgSubtle
        case .missed, .nothingDue: return theme.fgFaint
        case .future: return theme.fgFaint.opacity(0.6)
        }
    }
}

/// STREAK 14D and 30D 97%.
struct StatsRow: View {
    @Environment(\.theme) private var theme
    let streak: Int
    let adherence: Adherence

    init(streak: Int, adherence: Adherence) {
        self.streak = streak
        self.adherence = adherence
    }

    var body: some View {
        HStack(spacing: 10) {
            stat(label: "STREAK", value: "\(streak)D", lit: streak > 0)
            stat(label: "30D", value: adherence.percent.map { "\($0)%" } ?? "--", lit: false)
        }
    }

    private func stat(label: String, value: String, lit: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Lamp(on: lit, size: 5)
                Text(label).hud(10.5, theme.fgSubtle)
            }
            Text(value)
                .font(.monoFixed(28, .monoMedium))
                .tracking(-0.5)
                .foregroundStyle(theme.fg)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: theme.radius.panel))
        .overlay(RoundedRectangle(cornerRadius: theme.radius.panel).strokeBorder(theme.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
