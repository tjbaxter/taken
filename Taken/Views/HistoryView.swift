import SwiftUI

/// Five weeks, Monday first, today in the last row. Lit = everything due was taken.
struct HistoryGrid: View {
    let rows: [[HistoryCell]]
    let onSelect: (DayKey) -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { index in
                    Text(Fmt.weekdayLetters[index])
                        .hudFixed(10, Palette.fgFaint, tracking: 0.1)
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
    let cell: HistoryCell

    var body: some View {
        ZStack {
            background
            VStack(spacing: 3) {
                Text("\(cell.day.dayOfMonth)")
                    .font(.monoFixed(11, cell.status == .complete ? .monoSemibold : .monoMedium))
                    .foregroundStyle(numberColor)
                if cell.status == .missed || cell.status == .nothingDue {
                    Rectangle().fill(Palette.tick).frame(width: 7, height: 1)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay {
            if cell.isToday {
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(cell.status == .complete ? Palette.fg : Palette.fgMuted, lineWidth: 1.5)
                    .padding(-3)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var background: some View {
        switch cell.status {
        case .complete:
            RoundedRectangle(cornerRadius: 3)
                .fill(Palette.signal)
                .shadow(color: Palette.signal.opacity(0.35), radius: 6)
        case .partial:
            RoundedRectangle(cornerRadius: 3)
                .fill(Palette.signal.opacity(0.18))
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.signalEdge, lineWidth: 1))
        case .missed, .nothingDue:
            RoundedRectangle(cornerRadius: 3)
                .fill(Palette.bgInset)
        case .future:
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Palette.lineDash, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    private var numberColor: Color {
        switch cell.status {
        case .complete: return Palette.buttonText
        case .partial: return Palette.fg
        case .missed, .nothingDue: return Palette.fgFaint
        case .future: return Palette.fgFaint.opacity(0.6)
        }
    }
}

/// STREAK 14D and 30D 97%.
struct StatsRow: View {
    let streak: Int
    let adherence: Adherence

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
                Text(label).hud(10.5, Palette.fgSubtle)
            }
            Text(value)
                .font(.monoFixed(28, .monoMedium))
                .tracking(-0.5)
                .foregroundStyle(Palette.fg)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.bgRaised, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
