import SwiftUI

/// The answer. Big counter, segmented bar, 24-hour ruler with every dose on it.
/// Flips to a locked ALL TAKEN state when everything due is taken.
struct StatusPanel: View {
    let summary: DaySummary
    let now: Date
    let clock: DayClock
    let lockInCount: Int
    let streak: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep: CGFloat = 0
    @State private var sweeping = false
    @State private var snap = false

    init(summary: DaySummary, now: Date, clock: DayClock, lockInCount: Int, streak: Int) {
        self.summary = summary
        self.now = now
        self.clock = clock
        self.lockInCount = lockInCount
        self.streak = streak
    }

    private var locked: Bool { summary.allTaken }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            topLine
            if locked { lockedReadout } else { counterReadout }
            SegmentBar(total: summary.dueDoses, lit: summary.takenDueDoses)
            DayRuler(dayStart: clock.start(of: summary.day), dayEnd: clock.end(of: summary.day),
                     doses: summary.allDoses.map(\.takenAt), now: now, dayStartHour: clock.dayStartHour)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(locked ? Palette.signalWash.opacity(0.35) : Palette.bgRaised.opacity(0.6))
        .overlay {
            CornerBrackets(length: snap ? 26 : 14)
                .stroke(locked ? Palette.signal : Palette.fgSubtle,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
                .shadow(color: locked ? Palette.signal.opacity(0.55) : .clear, radius: 6)
                .padding(0.75)
        }
        .overlay(alignment: .top) { scanline }
        .clipped()
        .animation(.snappy(duration: 0.3), value: locked)
        .onAppear { snap = locked }
        .onChange(of: locked) { _, isLocked in
            withAnimation(.spring(response: 0.32, dampingFraction: 0.62)) { snap = isLocked }
        }
        .onChange(of: lockInCount) { _, _ in runSweep() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var topLine: some View {
        HStack(spacing: 8) {
            Lamp(on: locked)
            Text(locked ? "LOCKED IN" : "TAKEN TODAY").hud(11, locked ? Palette.signal : Palette.fgSubtle)
            Spacer(minLength: 8)
            Text(rightLabel).hud(11, Palette.fgSubtle, tracking: 0.12)
        }
    }

    private var rightLabel: String {
        if summary.dueDoses == 0 { return "NOTHING DUE" }
        if locked { return "\(summary.takenDueDoses)/\(summary.dueDoses) DOSES" }
        let pending = summary.pendingDoses
        return "\(pending) PENDING"
    }

    private var counterReadout: some View {
        HStack(alignment: .bottom, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(summary.takenDueDoses)")
                    .foregroundStyle(Palette.fg)
                    .contentTransition(.numericText())
                Text("/\(summary.dueDoses)")
                    .foregroundStyle(Palette.fgFaint)
            }
            .font(.monoFixed(68, .monoMedium))
            .tracking(-2)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Spacer(minLength: 12)
            lastDoseBlock
                .padding(.bottom, 10)
        }
    }

    private var lockedReadout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Text("ALL TAKEN")
                    .font(.monoFixed(44, .monoSemibold))
                    .tracking(-0.5)
                    .foregroundStyle(Palette.signal)
                    .shadow(color: Palette.signal.opacity(0.45), radius: 16)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                ZStack {
                    Rectangle()
                        .fill(Palette.signal)
                        .frame(width: 34, height: 34)
                        .shadow(color: Palette.signal.opacity(0.6), radius: 10)
                    CheckShape()
                        .stroke(Palette.bg, style: StrokeStyle(lineWidth: 3.2, lineCap: .square, lineJoin: .miter))
                        .frame(width: 22, height: 22)
                }
                .scaleEffect(snap ? 1 : 0.6)
            }
            HStack(spacing: 12) {
                if streak > 0 {
                    Text("STREAK \(streak)D").hud(11, Palette.signal, tracking: 0.12)
                }
                if let last = summary.lastDose {
                    Text("LAST DOSE \(Fmt.clock(last.takenAt, clock)) \u{00B7} \(Fmt.ago(last.takenAt, now: now))")
                        .hud(11, Palette.fgMuted, tracking: 0.12)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var lastDoseBlock: some View {
        if let last = summary.lastDose {
            VStack(alignment: .trailing, spacing: 5) {
                Text("LAST DOSE").hud(10, Palette.fgFaint)
                Text(Fmt.clock(last.takenAt, clock))
                    .font(.monoFixed(20, .monoMedium))
                    .foregroundStyle(Palette.signal)
                Text(Fmt.ago(last.takenAt, now: now)).hud(10, Palette.fgSubtle, tracking: 0.12)
            }
        } else {
            VStack(alignment: .trailing, spacing: 5) {
                Text("LAST DOSE").hud(10, Palette.fgFaint)
                Text("--:--")
                    .font(.monoFixed(20, .monoMedium))
                    .foregroundStyle(Palette.fgFaint)
                Text("NONE TODAY").hud(10, Palette.fgFaint, tracking: 0.12)
            }
        }
    }

    @ViewBuilder
    private var scanline: some View {
        if sweeping {
            GeometryReader { geo in
                Rectangle()
                    .fill(Palette.signal)
                    .frame(height: 2)
                    .shadow(color: Palette.signal.opacity(0.9), radius: 8)
                    .offset(y: sweep * geo.size.height)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private func runSweep() {
        guard !reduceMotion else { return }
        sweep = 0
        sweeping = true
        withAnimation(.easeInOut(duration: 0.55)) { sweep = 1 }
        Task {
            try? await Task.sleep(for: .milliseconds(620))
            withAnimation(.easeOut(duration: 0.2)) { sweeping = false }
        }
    }

    private var accessibilitySummary: String {
        if summary.dueDoses == 0 { return "Nothing due today." }
        if locked { return "All taken. \(summary.takenDueDoses) of \(summary.dueDoses) doses." }
        return "\(summary.takenDueDoses) of \(summary.dueDoses) doses taken today. \(summary.pendingDoses) pending."
    }
}

/// One segment per due dose. Lit segments glow.
struct SegmentBar: View {
    let total: Int
    let lit: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                let on = total > 0 && index < lit
                Rectangle()
                    .fill(on ? Palette.signal : Palette.bgInset)
                    .overlay(Rectangle().strokeBorder(on ? Color.clear : Palette.line, lineWidth: 1))
                    .frame(height: 6)
                    .shadow(color: on ? Palette.signal.opacity(0.55) : .clear, radius: 5)
            }
        }
        .animation(.snappy(duration: 0.25), value: lit)
        .accessibilityHidden(true)
    }
}

/// A 24-hour tick ruler from day start to day start, with a mark at every dose and a NOW cursor.
struct DayRuler: View {
    let dayStart: Date
    let dayEnd: Date
    let doses: [Date]
    let now: Date
    let dayStartHour: Int

    var body: some View {
        VStack(spacing: 5) {
            Canvas { context, size in
                let span = max(dayEnd.timeIntervalSince(dayStart), 1)
                let width = size.width
                for hour in 0...24 {
                    let x = min(max((width - 1) * CGFloat(hour) / 24, 0), width - 1)
                    let major = hour % 6 == 0
                    let height: CGFloat = major ? size.height : 4
                    context.fill(Path(CGRect(x: x, y: size.height - height, width: 1, height: height)),
                                 with: .color(major ? Palette.tick : Palette.lineDash))
                }
                let nowFraction = now.timeIntervalSince(dayStart) / span
                if nowFraction >= 0 && nowFraction <= 1 {
                    let x = min(max(width * CGFloat(nowFraction), 3), width - 3)
                    context.fill(Path(CGRect(x: x - 0.75, y: 3, width: 1.5, height: size.height - 3)),
                                 with: .color(Palette.fg))
                    var cap = Path()
                    cap.move(to: CGPoint(x: x - 3.5, y: 0))
                    cap.addLine(to: CGPoint(x: x + 3.5, y: 0))
                    cap.addLine(to: CGPoint(x: x, y: 4.5))
                    cap.closeSubpath()
                    context.fill(cap, with: .color(Palette.fg))
                }
                for dose in doses {
                    let fraction = dose.timeIntervalSince(dayStart) / span
                    guard fraction >= 0 && fraction <= 1 else { continue }
                    let x = width * CGFloat(fraction)
                    context.drawLayer { layer in
                        layer.addFilter(.shadow(color: Palette.signal.opacity(0.8), radius: 3))
                        layer.fill(Path(CGRect(x: x - 1.5, y: 4, width: 3, height: size.height - 4)),
                                   with: .color(Palette.signal))
                    }
                }
            }
            .frame(height: 16)
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { index in
                    if index > 0 { Spacer(minLength: 0) }
                    Text(String(format: "%02d", (dayStartHour + index * 6) % 24))
                        .hudFixed(9.5, Palette.fgFaint, tracking: 0.06)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
