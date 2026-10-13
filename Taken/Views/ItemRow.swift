import SwiftUI

/// One item on Today: the name and a small frequency line on the left, and on the right the ring that logs (empty while
/// pending, the look's signal with a check and the time once taken). The name opens the item sheet; only the ring logs.
struct ItemRowView: View {
    let row: ItemDay
    let now: Date
    let clock: DayClock
    let expanded: Bool
    /// The Not today group: "Next: Thursday" under the name, and a quiet ring.
    var nextLabel: String?
    /// Locked mode: a tap on the ring opens Taken Pro instead of logging.
    var locked: Bool = false
    let onTake: () -> Void
    let onOpen: () -> Void

    @Environment(\.theme) private var theme

    init(row: ItemDay, now: Date, clock: DayClock, expanded: Bool, nextLabel: String? = nil, locked: Bool = false,
         onTake: @escaping () -> Void, onOpen: @escaping () -> Void) {
        self.row = row
        self.now = now
        self.clock = clock
        self.expanded = expanded
        self.nextLabel = nextLabel
        self.locked = locked
        self.onTake = onTake
        self.onOpen = onOpen
    }

    private var quiet: Bool { nextLabel != nil && row.doses.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.item.name)
                            .font(.sans(17, .sansMedium, relativeTo: .body))
                            .foregroundStyle(quiet ? theme.fgMuted : theme.fg)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(subtitle)
                            .font(.sans(14, .sans, relativeTo: .footnote))
                            .foregroundStyle(theme.fgSubtle)
                            .lineLimit(1)
                    }
                    .padding(.leading, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RowPressStyle())
                Button(action: onTake) {
                    HStack(spacing: 10) {
                        if let last = row.lastDose {
                            Text(Fmt.clock(last.takenAt, clock))
                                .font(.mono(15, .monoMedium, relativeTo: .body))
                                .foregroundStyle(theme.signalInk)
                                .fixedSize()
                        }
                        DoseRing(total: row.isDue ? row.dosesPerDay : 1, taken: row.takenCount, quiet: quiet,
                                 locked: locked && (row.isPending || quiet))
                    }
                    .padding(.trailing, 16)
                    .padding(.leading, 8)
                    .frame(minWidth: 72, minHeight: 60, alignment: .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(RingPressStyle())
            }
            if expanded {
                detail
                    .padding(.leading, 16)
                    .padding(.trailing, 16)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTake() }
        .accessibilityAction(named: "Edit item") { onOpen() }
    }

    /// "Daily", "2x daily · 1 of 2", "Every other day · Next: Thursday".
    private var subtitle: String {
        let frequency = Fmt.frequency(row.frequency)
        if let nextLabel, row.doses.isEmpty { return "\(frequency) \u{00B7} \(nextLabel)" }
        if row.isDue && row.dosesPerDay > 1 { return "\(frequency) \u{00B7} \(row.takenCount) of \(row.dosesPerDay)" }
        return frequency
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(row.doses.enumerated()), id: \.element.id) { index, dose in
                HStack(spacing: 6) {
                    Text(row.doses.count > 1 ? "Dose \(index + 1) taken at" : "Taken at")
                        .font(.sans(14, .sans, relativeTo: .footnote))
                    Text(Fmt.clock(dose.takenAt, clock))
                        .font(.mono(14, .monoMedium, relativeTo: .footnote))
                    Text("\u{00B7} \(Fmt.agoDetailed(dose.takenAt, now: now))")
                        .font(.sans(14, .sans, relativeTo: .footnote))
                }
                .foregroundStyle(theme.fgMuted)
            }
        }
    }

    private var accessibilityHint: String {
        guard row.isPending || quiet else { return "Double tap for the times. Actions has Edit item." }
        return locked ? "Logging needs Taken Pro. Double tap to see plans." : "Double tap to mark taken."
    }

    private var accessibilityLabel: String {
        let name = row.item.name
        if row.doses.isEmpty {
            if let nextLabel { return "\(name), not due today. \(nextLabel)." }
            return "\(name), pending."
        }
        let times = Fmt.list(row.doses.map { Fmt.spoken($0.takenAt) })
        if row.isPending {
            return "\(name), \(row.takenCount) of \(row.dosesPerDay) taken, at \(times). Pending."
        }
        return "\(name), taken at \(times)."
    }
}

/// The ring on the right of a row: empty while pending, one arc per dose for a 2x or 3x item, and the look's signal with
/// a check once everything due is taken.
struct DoseRing: View {
    let total: Int
    let taken: Int
    var quiet: Bool = false
    var locked: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme

    init(total: Int, taken: Int, quiet: Bool = false, locked: Bool = false) {
        self.total = max(total, 1)
        self.taken = taken
        self.quiet = quiet
        self.locked = locked
    }

    private var done: Bool { taken >= total }

    var body: some View {
        ZStack {
            if done {
                Circle()
                    .fill(theme.signal)
                    .shadow(color: theme.glow(0.35), radius: 6)
                CheckShape()
                    .stroke(theme.onSignal, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 15, height: 15)
            } else {
                Circle()
                    .strokeBorder(quiet ? theme.line : theme.lineStrong, lineWidth: 1.5)
                if total > 1 {
                    ForEach(0..<total, id: \.self) { index in
                        Arc(index: index, count: total)
                            .stroke(index < taken ? theme.signal : Color.clear,
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .padding(1.5)
                    }
                }
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(theme.fgSubtle)
                }
            }
        }
        .frame(width: 30, height: 30)
        .scaleEffect(done ? 1 : 0.94)
        .animation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.3, dampingFraction: 0.55), value: done)
        .animation(.snappy(duration: 0.25), value: taken)
        .accessibilityHidden(true)
    }

    /// One dose's share of the ring, with a small gap either side, starting at the top.
    private struct Arc: Shape {
        let index: Int
        let count: Int

        func path(in rect: CGRect) -> Path {
            let gap = 14.0
            let share = 360.0 / Double(count)
            let start = -90 + share * Double(index) + gap / 2
            let end = start + share - gap
            var path = Path()
            path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2,
                        startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
            return path
        }
    }
}

/// The ring's press: it gives a little, like a button you can feel.
private struct RingPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}
