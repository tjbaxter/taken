import SwiftUI

/// One item on TODAY. Tap a pending row to take it; tap a taken row for the detail line.
struct ItemRowView: View {
    let row: ItemDay
    let now: Date
    let clock: DayClock
    let expanded: Bool
    var notDueLabel: String? = nil
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    CodeTag(code: row.item.code, lit: row.isDue && row.isDone, dim: notDueLabel != nil && row.doses.isEmpty)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(row.item.name)
                            .font(.sans(17, .sansMedium))
                            .foregroundStyle(notDueLabel != nil && row.doses.isEmpty ? Palette.fgMuted : Palette.fg)
                            .lineLimit(1)
                        Text(Fmt.frequency(row.item.frequency)).hud(10.5, Palette.fgSubtle, tracking: 0.12)
                    }
                    Spacer(minLength: 8)
                    readout
                    StateMark(row: row)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 70)

                if expanded {
                    detailLine
                        .padding(.leading, 74)
                        .padding(.trailing, 14)
                        .padding(.bottom, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(row.isPending || (!row.isDue && row.doses.isEmpty) ? "Double tap to mark taken." : "Double tap for details.")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var readout: some View {
        if let last = row.lastDose {
            VStack(alignment: .trailing, spacing: 5) {
                Text(Fmt.clock(last.takenAt, clock))
                    .font(.monoFixed(15, .monoMedium))
                    .foregroundStyle(Palette.signal)
                Text(row.dosesPerDay > 1 ? "\(row.takenCount)/\(row.dosesPerDay) \u{00B7} \(Fmt.ago(last.takenAt, now: now))" : Fmt.ago(last.takenAt, now: now))
                    .hud(10, Palette.fgSubtle, tracking: 0.1)
            }
        } else if let notDueLabel {
            Text(notDueLabel).hud(10, Palette.fgFaint, tracking: 0.1)
        } else {
            Text("PENDING").hud(10.5, Palette.fgFaint, tracking: 0.14)
        }
    }

    private var detailLine: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(row.doses.enumerated()), id: \.element.id) { index, dose in
                HStack(spacing: 8) {
                    Rectangle().fill(Palette.signal).frame(width: 5, height: 5)
                    Text(detailText(index: index, dose: dose)).hud(11, Palette.fgMuted, tracking: 0.1)
                }
            }
        }
    }

    private func detailText(index: Int, dose: Dose) -> String {
        let prefix = row.doses.count > 1 ? "DOSE \(index + 1) " : ""
        return "\(prefix)TAKEN \(Fmt.clock(dose.takenAt, clock)) \u{00B7} \(Fmt.agoDetailed(dose.takenAt, now: now))"
    }

    private var accessibilityLabel: String {
        let name = row.item.name
        if row.doses.isEmpty {
            if notDueLabel != nil { return "\(name), not due today." }
            return "\(name), pending."
        }
        let times = Fmt.list(row.doses.map { Fmt.spoken($0.takenAt) })
        if row.isPending {
            return "\(name), \(row.takenCount) of \(row.dosesPerDay) taken, at \(times). Pending."
        }
        return "\(name), taken at \(times)."
    }
}

/// Right-hand state: a dashed ring when pending, a lit disc with a check when taken, pips for multi-dose.
struct StateMark: View {
    let row: ItemDay

    var body: some View {
        if row.dosesPerDay > 1 && row.isDue {
            HStack(spacing: 5) {
                ForEach(0..<row.dosesPerDay, id: \.self) { index in
                    Pip(lit: index < row.takenCount)
                }
            }
            .frame(minWidth: 28)
        } else {
            Disc(lit: !row.doses.isEmpty)
        }
    }
}

struct Pip: View {
    let lit: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Palette.fgFaint, style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 2.5]))
                .opacity(lit ? 0 : 1)
            if lit {
                Circle()
                    .fill(Palette.signal)
                    .shadow(color: Palette.signal.opacity(0.6), radius: 4)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: 12, height: 12)
        .animation(.spring(response: 0.28, dampingFraction: 0.6), value: lit)
    }
}

struct Disc: View {
    let lit: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Palette.fgFaint, style: StrokeStyle(lineWidth: 1.4, dash: [3, 3]))
                .opacity(lit ? 0 : 1)
            if lit {
                ZStack {
                    Circle()
                        .fill(Palette.signal)
                        .shadow(color: Palette.signal.opacity(0.6), radius: 6)
                    CheckShape()
                        .stroke(Palette.bg, style: StrokeStyle(lineWidth: 2.4, lineCap: .square, lineJoin: .miter))
                        .frame(width: 15, height: 15)
                }
                .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .frame(width: 28, height: 28)
        .animation(.spring(response: 0.28, dampingFraction: 0.58), value: lit)
    }
}
