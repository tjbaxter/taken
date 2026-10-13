import SwiftUI

/// One item on TODAY. Tap a pending row to take it; tap a taken row for the detail line.
struct ItemRowView: View {
    let row: ItemDay
    let now: Date
    let clock: DayClock
    let expanded: Bool
    var notDueLabel: String? = nil
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    init(row: ItemDay, now: Date, clock: DayClock, expanded: Bool, notDueLabel: String? = nil,
         onTap: @escaping () -> Void) {
        self.row = row
        self.now = now
        self.clock = clock
        self.expanded = expanded
        self.notDueLabel = notDueLabel
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                if typeSize.isAccessibilitySize {
                    stackedLine
                } else {
                    line
                }

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

    /// The row on one line: tag, name, readout, state.
    private var line: some View {
        HStack(spacing: 14) {
            CodeTag(code: row.item.code, lit: row.isDue && row.isDone, dim: notDueLabel != nil && row.doses.isEmpty)
            VStack(alignment: .leading, spacing: 5) {
                nameText.lineLimit(1)
                frequencyText
            }
            Spacer(minLength: 8)
            readout
            StateMark(row: row)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 70)
    }

    /// Accessibility text sizes: the readout moves under the name, so the name keeps the width it needs.
    private var stackedLine: some View {
        HStack(spacing: 14) {
            CodeTag(code: row.item.code, lit: row.isDue && row.isDone, dim: notDueLabel != nil && row.doses.isEmpty)
            VStack(alignment: .leading, spacing: 6) {
                nameText.lineLimit(2)
                frequencyText
                stackedReadout
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            StateMark(row: row)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 70)
    }

    private var nameText: some View {
        Text(row.item.name)
            .font(.sans(17, .sansMedium))
            .foregroundStyle(notDueLabel != nil && row.doses.isEmpty ? Palette.fgMuted : Palette.fg)
    }

    private var frequencyText: some View {
        Text(Fmt.frequency(row.frequency)).hud(10.5, Palette.fgSubtle, tracking: 0.12)
    }

    private func agoText(_ last: Dose) -> String {
        row.dosesPerDay > 1 ? "\(row.takenCount)/\(row.dosesPerDay) \u{00B7} \(Fmt.ago(last.takenAt, now: now))" : Fmt.ago(last.takenAt, now: now)
    }

    @ViewBuilder
    private var readout: some View {
        if let last = row.lastDose {
            VStack(alignment: .trailing, spacing: 5) {
                Text(Fmt.clock(last.takenAt, clock))
                    .font(.monoFixed(15, .monoMedium))
                    .foregroundStyle(Palette.signal)
                Text(agoText(last))
                    .hud(10, Palette.fgSubtle, tracking: 0.1)
            }
        } else if let notDueLabel {
            Text(notDueLabel).hud(10, Palette.fgSubtle, tracking: 0.1)
        } else {
            Text("PENDING").hud(10.5, Palette.fgSubtle, tracking: 0.14)
        }
    }

    @ViewBuilder
    private var stackedReadout: some View {
        if let last = row.lastDose {
            HStack(spacing: 8) {
                Text(Fmt.clock(last.takenAt, clock))
                    .font(.monoFixed(15, .monoMedium))
                    .foregroundStyle(Palette.signal)
                Text(agoText(last))
                    .hud(10, Palette.fgSubtle, tracking: 0.1)
            }
        } else if let notDueLabel {
            Text(notDueLabel).hud(10, Palette.fgSubtle, tracking: 0.1)
        } else {
            Text("PENDING").hud(10.5, Palette.fgSubtle, tracking: 0.14)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(lit: Bool) {
        self.lit = lit
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Palette.fgFaint, style: StrokeStyle(lineWidth: 1.2, dash: [2.5, 2.5]))
                .opacity(lit ? 0 : 1)
            if lit {
                Circle()
                    .fill(Palette.signal)
                    .shadow(color: Palette.signal.opacity(0.6), radius: 4)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: 12, height: 12)
        .animation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.28, dampingFraction: 0.6), value: lit)
    }
}

struct Disc: View {
    let lit: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(lit: Bool) {
        self.lit = lit
    }

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
                .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .frame(width: 28, height: 28)
        .animation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.28, dampingFraction: 0.58), value: lit)
    }
}
