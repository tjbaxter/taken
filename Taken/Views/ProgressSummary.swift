import SwiftUI

/// Today's one calm progress line: "4 of 6 taken" with a slim bar, in doses as the widgets count them. When everything
/// due is taken it becomes the All taken moment: the check springs in with the success haptic (AppModel plays it).
struct ProgressSummary: View {
    let summary: DaySummary
    let clock: DayClock
    /// Goes up each time a tap finishes the day, so the check springs in once.
    let lockInCount: Int
    let streak: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme
    @State private var popped = true

    init(summary: DaySummary, clock: DayClock, lockInCount: Int, streak: Int) {
        self.summary = summary
        self.clock = clock
        self.lockInCount = lockInCount
        self.streak = streak
    }

    var body: some View {
        Group {
            if summary.dueDoses == 0 {
                Text("Nothing due today")
                    .font(.sans(17, .sans, relativeTo: .body))
                    .foregroundStyle(theme.fgMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if summary.allTaken {
                allTaken
            } else {
                counting
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .onChange(of: lockInCount) { _, _ in pop() }
    }

    private var counting: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(summary.takenDueDoses)")
                    .font(.mono(22, .monoMedium, relativeTo: .title3))
                    .foregroundStyle(theme.fg)
                    .contentTransition(.numericText())
                Text(" of ")
                    .font(.sans(18, .sans, relativeTo: .body))
                    .foregroundStyle(theme.fgMuted)
                Text("\(summary.dueDoses)")
                    .font(.mono(22, .monoMedium, relativeTo: .title3))
                    .foregroundStyle(theme.fg)
                Text(" taken")
                    .font(.sans(18, .sans, relativeTo: .body))
                    .foregroundStyle(theme.fgMuted)
                Spacer(minLength: 8)
                if let last = Self.lastTime(summary, clock: clock) {
                    Text("Last ")
                        .font(.sans(14, .sans, relativeTo: .footnote))
                        .foregroundStyle(theme.fgSubtle)
                    Text(last)
                        .font(.mono(14, .monoMedium, relativeTo: .footnote))
                        .foregroundStyle(theme.fgSubtle)
                }
            }
            ProgressBar(fraction: Double(summary.takenDueDoses) / Double(max(summary.dueDoses, 1)))
        }
    }

    private var allTaken: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(theme.signal)
                    .shadow(color: theme.glow(popped ? 0.35 : 0.7), radius: popped ? 6 : 14)
                CheckShape()
                    .stroke(theme.onSignal, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .frame(width: 20, height: 20)
            }
            .frame(width: 40, height: 40)
            .scaleEffect(popped ? 1 : 0.55)
            VStack(alignment: .leading, spacing: 3) {
                Text("All taken")
                    .font(.sans(24, .sansSemibold, relativeTo: .title2))
                    .foregroundStyle(theme.signalInk)
                HStack(spacing: 0) {
                    if let last = Self.lastTime(summary, clock: clock) {
                        Text("Last dose ")
                        Text(last)
                            .font(.mono(14, .monoMedium, relativeTo: .footnote))
                    }
                    if streak > 1 {
                        Text(summary.lastDose == nil ? "" : " \u{00B7} ")
                        Text("\(streak)")
                            .font(.mono(14, .monoMedium, relativeTo: .footnote))
                        Text("-day streak")
                    }
                }
                .font(.sans(14, .sans, relativeTo: .footnote))
                .foregroundStyle(theme.fgSubtle)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
    }

    /// The time after "Last": "08:12", or "Tue 08:12" for an early weekly dose logged on another day that counts for
    /// today (SPEC 3.3), as its row shows it, so it never reads as a time today.
    nonisolated static func lastTime(_ summary: DaySummary, clock: DayClock) -> String? {
        summary.lastDose.map { Fmt.doseClock($0, viewing: summary.day, clock) }
    }

    /// The day finished with a tap: the check springs in.
    private func pop() {
        guard summary.allTaken, !reduceMotion else { return }
        popped = false
        withAnimation(.spring(response: 0.38, dampingFraction: 0.55)) { popped = true }
    }

    private var accessibilityText: String {
        if summary.dueDoses == 0 { return "Nothing due today." }
        if summary.allTaken { return "All taken. \(summary.takenDueDoses) of \(summary.dueDoses) doses." }
        return "\(summary.takenDueDoses) of \(summary.dueDoses) doses taken today. \(summary.pendingDoses) pending."
    }
}

/// A slim bar that fills with the day.
struct ProgressBar: View {
    @Environment(\.theme) private var theme
    let fraction: Double

    init(fraction: Double) {
        self.fraction = min(max(fraction, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.bgInset)
                Capsule()
                    .fill(theme.signal)
                    .frame(width: fraction > 0 ? max(6, geo.size.width * fraction) : 0)
            }
        }
        .frame(height: 6)
        .animation(.snappy(duration: 0.3), value: fraction)
        .accessibilityHidden(true)
    }
}
