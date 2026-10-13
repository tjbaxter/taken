import SwiftUI

/// The History tab (REDESIGN.md): the streak and 30-day completion, then five weeks of days. A tap on a day opens it, to
/// see when everything was taken or to log a dose that was forgotten.
struct HistoryScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TabHeader(title: "History", subtitle: "The last five weeks")
                if model.hasStack || !model.state.doses.isEmpty {
                    StatsRow(streak: model.streak, adherence: model.adherence)
                        .padding(.top, 22)
                    Card {
                        HistoryGrid(rows: model.history) { day in
                            model.sheet = .day(day)
                        }
                        .padding(14)
                    }
                    .padding(.top, 16)
                    Text("Tap a day to see it, or to log a dose you forgot.")
                        .font(.sans(14, .sans, relativeTo: .footnote))
                        .foregroundStyle(theme.fgSubtle)
                        .padding(.top, 12)
                    Label("Your log stays on this iPhone. No account, no ads, no tracking.", systemImage: "lock")
                        .font(.sans(14, .sans, relativeTo: .footnote))
                        .foregroundStyle(theme.fgSubtle)
                        .padding(.top, 28)
                } else {
                    Text("Your days show up here once your stack is in.")
                        .font(.sans(16, .sans, relativeTo: .body))
                        .foregroundStyle(theme.fgMuted)
                        .padding(.top, 28)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(theme.bg.ignoresSafeArea())
    }
}

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
                        .font(.sans(12, .sansMedium, relativeTo: .caption))
                        .foregroundStyle(theme.fgSubtle)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
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
        let date = Fmt.longDay(cell.day)
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
        let shape = RoundedRectangle(cornerRadius: theme.radius.card / 2, style: .continuous)
        ZStack(alignment: .topLeading) {
            background(shape)
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
                shape.strokeBorder(theme.fg, lineWidth: 1.5)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func background(_ shape: RoundedRectangle) -> some View {
        switch cell.status {
        case .complete:
            shape
                .fill(theme.signalWash)
                .overlay(shape.strokeBorder(theme.signalEdge, lineWidth: 1))
        case .partial, .missed, .nothingDue:
            shape
                .fill(theme.bgInset)
        case .future:
            shape
                .strokeBorder(theme.line, lineWidth: 1)
        }
    }

    /// A lit check when everything due was taken, a half-lit bar for some, a dim dot for none.
    @ViewBuilder
    private var mark: some View {
        switch cell.status {
        case .complete:
            CheckShape()
                .stroke(theme.signalInk, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .frame(width: 16, height: 16)
                .offset(y: 3)
        case .partial:
            Capsule()
                .fill(theme.signalInk.opacity(0.7))
                .frame(width: 11, height: 3)
                .offset(y: 3)
        case .missed, .nothingDue:
            Circle()
                .fill(theme.fgFaint)
                .frame(width: 3, height: 3)
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
        case .missed, .nothingDue: return theme.fgSubtle
        case .future: return theme.fgFaint
        }
    }
}

/// The streak and 30-day completion.
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
            stat(label: "Streak", value: "\(streak)", unit: streak == 1 ? "day" : "days",
                 spoken: "Streak, \(streak) \(streak == 1 ? "day" : "days")")
            stat(label: "Last 30 days", value: adherence.percent.map { "\($0)" } ?? "--", unit: adherence.percent == nil ? "" : "%",
                 spoken: adherence.percent.map { "Last 30 days, \($0) percent taken" } ?? "Last 30 days, nothing due yet")
        }
    }

    private func stat(label: String, value: String, unit: String, spoken: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.sans(14, .sansMedium, relativeTo: .footnote))
                .foregroundStyle(theme.fgSubtle)
            HStack(alignment: .firstTextBaseline, spacing: unit == "%" ? 1 : 5) {
                Text(value)
                    .font(.mono(28, .monoMedium, relativeTo: .title))
                    .foregroundStyle(theme.fg)
                Text(unit)
                    .font(.sans(16, .sans, relativeTo: .body))
                    .foregroundStyle(theme.fgMuted)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}
