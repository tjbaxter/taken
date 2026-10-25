import SwiftUI

/// One item on Today, all of it one button: the name and a small frequency line on the left, and on the right the ring
/// (empty while pending, the look's signal with a check and the time once taken). A tap anywhere on the row logs while
/// pending and shows the times once taken; it never un-takes. In edit mode (Edit beside the Stack title) a chevron
/// stands where the ring was and a tap opens the item sheet instead (REDESIGN.md, "Tap the row to log").
struct ItemRowView: View {
    let row: ItemDay
    let now: Date
    let clock: DayClock
    let expanded: Bool
    /// The Not today group: "Next: Thursday" for VoiceOver, and a quiet ring.
    var nextLabel: String?
    /// The Not today group: the whole line under the name ("Every other day · Next: Thursday", "Weekly · Thu · Not
    /// logged", "Weekly · Counts for Thursday"). Nil on a Stack row.
    var note: String?
    /// Locked mode: a tap opens Taken Pro instead of logging.
    var locked: Bool = false
    /// Edit mode: a chevron instead of the time and the ring, and a tap opens the item sheet.
    var editing: Bool = false
    /// How many doses a tap on this row has logged (`AppModel.rowLogs`): each time it goes up, the logging moment plays
    /// once.
    var logs: Int = 0
    let onTake: () -> Void
    let onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    /// The logging moment: how many have played, the signal's wash over the row, and the ring lifted above its size.
    @State private var moments = 0
    @State private var washed = false
    @State private var lifted = false

    init(row: ItemDay, now: Date, clock: DayClock, expanded: Bool, nextLabel: String? = nil, note: String? = nil,
         locked: Bool = false, editing: Bool = false, logs: Int = 0, onTake: @escaping () -> Void,
         onOpen: @escaping () -> Void) {
        self.row = row
        self.now = now
        self.clock = clock
        self.expanded = expanded
        self.nextLabel = nextLabel
        self.note = note
        self.locked = locked
        self.editing = editing
        self.logs = logs
        self.onTake = onTake
        self.onOpen = onOpen
    }

    /// The day being lived, which every time on the row is read against.
    private var today: DayKey { clock.day(for: now) }

    private var quiet: Bool { nextLabel != nil && row.doses.isEmpty }

    var body: some View {
        // One Button, so a scroll that starts on the row cancels the touch before it logs, as UIScrollView does for
        // every control inside it.
        Button(action: editing ? onOpen : onTake) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
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
                    trailing
                        .padding(.trailing, 16)
                        .padding(.leading, 8)
                        .frame(minWidth: 72, minHeight: 60, alignment: .trailing)
                }
                if expanded && !editing {
                    detail
                        .padding(.leading, 16)
                        .padding(.trailing, 16)
                        .padding(.bottom, 14)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(theme.signalWash.opacity(washed ? 1 : 0))
            // The gap between the name and the ring counts as the row too.
            .contentShape(Rectangle())
        }
        .buttonStyle(ItemRowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if editing { onOpen() } else { onTake() }
        }
        .accessibilityAction(named: "Edit item") { onOpen() }
        .onChange(of: logs) { old, new in
            if new > old { moments += 1 }
        }
        .task(id: moments) { await playMoment() }
    }

    /// The time and the ring, or in edit mode a chevron where the ring sits. They cross-fade as edit mode comes and
    /// goes.
    @ViewBuilder
    private var trailing: some View {
        if editing {
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.fgSubtle)
                .frame(width: 30, height: 30)
                .transition(.opacity)
        } else {
            RingSlot(row: row, today: today, clock: clock, quiet: quiet, locked: locked, lifted: lifted)
                .transition(.opacity)
        }
    }

    /// A tap just logged a dose here: the row washes in the look's signal and fades, and the ring lifts and settles on
    /// DoseRing's spring, with the haptic AppModel plays. Reduce Motion keeps the wash, a fade, and drops the lift.
    private func playMoment() async {
        guard moments > 0 else { return }
        withAnimation(.easeOut(duration: 0.1)) {
            washed = true
            if !reduceMotion { lifted = true }
        }
        try? await Task.sleep(for: .milliseconds(100))
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { lifted = false }
        withAnimation(.easeOut(duration: 0.6)) { washed = false }
    }

    /// "Daily", "2x daily · 1 of 2", "Every other day · Next: Thursday", "Weekly · Thu · Not logged".
    private var subtitle: String {
        if let note { return note }
        let frequency = Fmt.frequency(row.frequency)
        if row.isDue && row.dosesPerDay > 1 { return "\(frequency) \u{00B7} \(row.takenCount) of \(row.dosesPerDay)" }
        return frequency
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(row.doses.enumerated()), id: \.element.id) { index, dose in
                HStack(spacing: 6) {
                    Text(row.doses.count > 1 ? "Dose \(index + 1) taken at" : "Taken at")
                        .font(.sans(14, .sans, relativeTo: .footnote))
                    Text(Fmt.doseClock(dose, viewing: today, clock))
                        .font(.mono(14, .monoMedium, relativeTo: .footnote))
                    Text("\u{00B7} \(Fmt.agoDetailed(dose.takenAt, now: now))")
                        .font(.sans(14, .sans, relativeTo: .footnote))
                }
                .foregroundStyle(theme.fgMuted)
            }
        }
    }

    private var accessibilityHint: String {
        Self.accessibilityHint(row: row, quiet: quiet, locked: locked, editing: editing)
    }

    private var accessibilityLabel: String {
        Self.accessibilityLabel(row: row, today: today, clock: clock, nextLabel: nextLabel)
    }

    /// What a double tap does: the same as a tap anywhere on the row.
    nonisolated static func accessibilityHint(row: ItemDay, quiet: Bool, locked: Bool,
                                              editing: Bool = false) -> String {
        if editing { return "Double tap to edit." }
        guard row.isPending || quiet else { return "Double tap for the times. Actions has Edit item." }
        return locked ? "Logging needs Taken Pro. Double tap to see plans." : "Double tap to mark taken."
    }

    /// VoiceOver's one sentence for the row. A weekly row in Not today speaks for its week: "Semaglutide, Thursday's
    /// dose not logged." while open, "Semaglutide, taken Friday at 8:12 AM." once logged, with "Counts for Thursday."
    /// after an early dose. On the due day itself an early dose keeps its day too, "Semaglutide, taken Tuesday at 8:12
    /// AM.", as the row shows "Tue 08:12".
    nonisolated static func accessibilityLabel(row: ItemDay, today: DayKey, clock: DayClock, nextLabel: String?,
                                   locale: Locale = .current) -> String {
        let name = row.item.name
        if row.isOpen { return "\(name), \(Fmt.weekday(row.day))'s dose not logged." }
        if row.day != today, let last = row.lastDose {
            let taken = "\(name), taken \(Fmt.spokenDose(last, viewing: today, clock, locale: locale))."
            return row.day > today ? "\(taken) Counts for \(Fmt.weekday(row.day))." : taken
        }
        if row.doses.isEmpty {
            if let nextLabel { return "\(name), not due today. \(nextLabel)." }
            return "\(name), pending."
        }
        let times = Fmt.spokenDoses(row.doses, viewing: today, clock, locale: locale)
        if row.isPending {
            return "\(name), \(row.takenCount) of \(row.dosesPerDay) taken, \(times). Pending."
        }
        return "\(name), taken \(times)."
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

/// The time and the ring on the right of a row. The ring gives a little while the row is held, like a button you can
/// feel, and lifts when a tap logs.
private struct RingSlot: View {
    let row: ItemDay
    let today: DayKey
    let clock: DayClock
    let quiet: Bool
    let locked: Bool
    let lifted: Bool

    @Environment(\.rowPressed) private var pressed
    @Environment(\.theme) private var theme

    init(row: ItemDay, today: DayKey, clock: DayClock, quiet: Bool, locked: Bool, lifted: Bool) {
        self.row = row
        self.today = today
        self.clock = clock
        self.quiet = quiet
        self.locked = locked
        self.lifted = lifted
    }

    var body: some View {
        HStack(spacing: 10) {
            if let last = row.lastDose {
                Text(Fmt.doseClock(last, viewing: today, clock))
                    .font(.mono(15, .monoMedium, relativeTo: .body))
                    .foregroundStyle(theme.signalInk)
                    .fixedSize()
            }
            DoseRing(total: row.isDue ? row.dosesPerDay : 1, taken: row.takenCount, quiet: quiet,
                     locked: locked && (row.isPending || quiet))
                .scaleEffect(pressed ? 0.9 : (lifted ? 1.12 : 1))
                .animation(.snappy(duration: 0.16), value: pressed)
        }
    }
}

/// The row's press: the flat inset highlight every row has, and the ring gives a little (`RingSlot`).
private struct ItemRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowPressStyle().makeBody(configuration: configuration)
            .environment(\.rowPressed, configuration.isPressed)
    }
}

private struct RowPressedKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    /// A Today row is held down (`ItemRowPressStyle`).
    var rowPressed: Bool {
        get { self[RowPressedKey.self] }
        set { self[RowPressedKey.self] = newValue }
    }
}
