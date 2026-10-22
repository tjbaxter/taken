import Charts
import SwiftUI

#if DEBUG || TAKEN_INTERNAL
/// The weight chart (SPEC 3.12; REDESIGN.md, "Goal and moments"), in Swift Charts, one chart at the card's width with the
/// plot fixed at 196 pt: each weigh-in a small dot in the look's subtle ink, the trend a smooth line in the look's signal
/// colour (monotone interpolation, "a cubic spline that preserves monotonicity of the data"), a small unlabelled tick on
/// the baseline on each day a weekly dose was logged, and a y axis fitted to what is in view, never from zero. With a
/// goal: one quiet solid line at the goal, its number on the trailing axis one step brighter than the other labels (or
/// pinned to the top or bottom edge with an arrow when it is far off the data), and at most three lit points on the trend
/// line, always drawn lit (the moment itself plays on screen one), the newest percent point labelled "−5%" or "−10%". It
/// lives on screen two (REDESIGN.md, "Weight tab page: entry first"). A scrub shows the day's trend, weigh-in and point. No
/// stars, badges, dashed lines, forecast, BMI, expand button, red or green. Swift Charts gives VoiceOver an element per
/// weigh-in and an Audio Graph; the chart adds its title and a summary with the goal and the points.
struct WeightChart: View {
    @Environment(\.theme) private var theme
    let picture: WeightPicture
    let unit: WeightUnit
    let range: WeightRange
    let clock: DayClock
    let today: DayKey
    let goalKg: Double?

    @State private var selection: Date?

    /// The plot's height, fixed so the points per kilogram are known (own choice).
    static let plotHeight: CGFloat = 196

    init(picture: WeightPicture, unit: WeightUnit, range: WeightRange, clock: DayClock, today: DayKey, goalKg: Double?) {
        self.picture = picture
        self.unit = unit
        self.range = range
        self.clock = clock
        self.today = today
        self.goalKg = goalKg
    }

    private var window: WeightWindow { picture.window }

    var body: some View {
        Group {
            if window.isEmpty {
                Text(WeightCopy.emptyRange)
                    .font(.sans(15, .sans, relativeTo: .subheadline))
                    .foregroundStyle(theme.fgSubtle)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.plotHeight + 24)
            } else {
                chart
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Weight chart. \(summary)")
    }

    /// "Trend 88.1 kilograms. 1.1 kilograms to your goal, 87.0. Down 9.7 kilograms since 4 March. Marked: 5 percent below
    /// where you started, 3 August."
    private var summary: String {
        var sentences = [WeightCopy.spokenTrend(picture.trend.last?.kg, unit: unit)]
        if let goalKg, let readout = picture.readout {
            sentences.append(WeightGoalCopy.spokenSlot(readout, goalKg: goalKg, unit: unit) + ".")
        }
        if let change = picture.change {
            sentences.append(WeightGoalCopy.spokenChange(change.kg, span: change.span, unit: unit, today: today) + ".")
        }
        if let marked = WeightGoalCopy.marked(picture.momentsInView) { sentences.append(marked) }
        return sentences.joined(separator: " ")
    }

    // MARK: The y axis

    /// The y axis in the unit shown: the domain, the goal and whether it is drawn or pinned, and the ticks that keep
    /// 12 pt clear of the goal's label.
    private struct YAxis {
        let lower: Double
        let upper: Double
        let goal: Double?
        let goalShown: Bool
        let pinnedTop: Bool?
        let ticks: [Double]
        let decimals: Int
    }

    private var axis: YAxis {
        let lower = unit.value(fromKilograms: window.lower)
        let upper = unit.value(fromKilograms: window.upper)
        let goal = goalKg.map { unit.value(fromKilograms: $0) }
        let all = WeightAxis.ticks(lower: lower, upper: upper)
        var ticks = all
        var pinnedTop: Bool?
        let plot = Double(Self.plotHeight)
        if let goal {
            if window.goalInDomain {
                ticks = WeightAxis.clear(ticks, of: goal, lower: lower, upper: upper, plotHeight: plot)
            } else {
                let top = goal > upper
                pinnedTop = top
                // The pinned label sits 8 pt inside the edge.
                let inset = 8 / plot * (upper - lower)
                ticks = WeightAxis.clear(ticks, of: top ? upper - inset : lower + inset, lower: lower, upper: upper,
                                         plotHeight: plot)
            }
        }
        return YAxis(lower: lower, upper: upper, goal: goal, goalShown: goal != nil && window.goalInDomain,
                    pinnedTop: pinnedTop, ticks: ticks, decimals: WeightAxis.decimals(all))
    }

    private func tickLabel(_ value: Double, decimals: Int) -> String {
        value.formatted(.number.precision(.fractionLength(decimals)).grouping(.never))
    }

    // MARK: The chart

    private var chart: some View {
        let axis = self.axis
        let tickTop = axis.lower + (axis.upper - axis.lower) * 0.05
        let selectedDay = selection.flatMap(snap)
        return Chart {
            ForEach(window.ticks, id: \.self) { day in
                RuleMark(x: .value("Day", clock.noon(of: day)),
                         yStart: .value("Weight", axis.lower),
                         yEnd: .value("Weight", tickTop))
                    .foregroundStyle(theme.fgSubtle)
                    .lineStyle(StrokeStyle(lineWidth: 1.25, lineCap: .round))
                    .accessibilityLabel(Fmt.longDay(day))
                    .accessibilityValue("Weekly dose")
            }
            if let goal = axis.goal, axis.goalShown, let goalKg {
                // One quiet solid line at the goal: never dashed, never green, no flag.
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(theme.fgFaint)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .accessibilityLabel(WeightGoalCopy.goalLine)
                    .accessibilityValue(WeightGoalCopy.goalValue(goalKg, unit: unit))
            }
            ForEach(Array(window.dots.enumerated()), id: \.offset) { _, dot in
                PointMark(x: .value("Day", clock.noon(of: dot.day)),
                          y: .value("Weight", unit.value(fromKilograms: dot.kg)))
                    .symbolSize(22)
                    .foregroundStyle(theme.fgSubtle)
                    .accessibilityLabel(Fmt.longDay(dot.day))
                    .accessibilityValue(WeightFormat.spoken(dot.kg, unit: unit))
            }
            ForEach(window.trend, id: \.day) { point in
                LineMark(x: .value("Day", clock.noon(of: point.day)),
                         y: .value("Trend", unit.value(fromKilograms: point.kg)))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(theme.signal)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    // One element per day of trend would bury the weigh-ins; the summary says where it is.
                    .accessibilityHidden(true)
            }
            if let day = selectedDay {
                RuleMark(x: .value("Day", clock.noon(of: day)))
                    .foregroundStyle(theme.lineStrong)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 0,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        popover(day)
                    }
                    .accessibilityHidden(true)
            }
        }
        .chartXScale(domain: clock.start(of: window.firstDay)...clock.end(of: window.lastDay))
        .chartYScale(domain: axis.lower...axis.upper)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(theme.line)
                AxisValueLabel(format: xFormat)
                    .font(.mono(11, .monoMedium, relativeTo: .caption2))
                    .foregroundStyle(theme.fgSubtle)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: axis.ticks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(theme.line)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(tickLabel(number, decimals: axis.decimals))
                            .font(.mono(11, .monoMedium, relativeTo: .caption2))
                            .foregroundStyle(theme.fgSubtle)
                    }
                }
            }
            // The goal's own label, one step brighter, with no grid line of its own.
            AxisMarks(position: .trailing, values: axis.goalShown ? [axis.goal ?? 0] : []) { _ in
                AxisValueLabel {
                    if let goalKg {
                        Text(WeightGoalCopy.goal(goalKg, unit: unit))
                            .font(.mono(11, .monoMedium, relativeTo: .caption2))
                            .foregroundStyle(theme.fgMuted)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .chartPlotStyle { plot in
            plot.frame(height: Self.plotHeight)
        }
        .chartXSelection(value: $selection)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                overlay(proxy: proxy, geometry: geometry, axis: axis)
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: Points and labels

    @ViewBuilder
    private func overlay(proxy: ChartProxy, geometry: GeometryProxy, axis: YAxis) -> some View {
        if let plotAnchor = proxy.plotFrame {
            let plot = geometry[plotAnchor]
            let points = picture.momentsInView
            ForEach(points) { moment in
                if let position = proxy.position(for: (x: clock.noon(of: moment.day),
                                                       y: unit.value(fromKilograms: moment.trendKg))) {
                    WeightLitPoint(springs: false)
                        .position(x: plot.minX + position.x, y: plot.minY + position.y)
                        .accessibilityElement()
                        .accessibilityLabel(WeightGoalCopy.pointLabel(moment))
                        .accessibilityValue(WeightGoalCopy.pointValue(moment, unit: unit))
                }
            }
            if let label = newestLabel(points), let position = proxy.position(
                for: (x: clock.noon(of: label.moment.day), y: unit.value(fromKilograms: label.moment.trendKg))) {
                let width = CGFloat(label.text.count) * 6.8
                let x = plot.minX + position.x
                let y = plot.minY + position.y
                // 8 pt right of and 12 pt above the point, flipped left or below if it would leave the plot.
                let right = x + 8 + width <= plot.maxX
                let above = y - 12 - 7 >= plot.minY
                Text(label.text)
                    .font(.mono(11, .monoMedium, relativeTo: .caption2))
                    .foregroundStyle(theme.fgMuted)
                    .fixedSize()
                    .position(x: right ? x + 8 + width / 2 : x - 8 - width / 2, y: above ? y - 12 : y + 12)
                    .accessibilityHidden(true)
            }
            if let top = axis.pinnedTop, let goalKg {
                // A goal far off the data: its number pinned 8 pt inside the edge it lies beyond, with an arrow.
                HStack(spacing: 2) {
                    Image(systemName: top ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8, weight: .semibold))
                    Text(WeightGoalCopy.goal(goalKg, unit: unit))
                        .font(.mono(11, .monoMedium, relativeTo: .caption2))
                }
                .foregroundStyle(theme.fgMuted)
                .fixedSize()
                .frame(width: geometry.size.width, alignment: .trailing)
                .position(x: geometry.size.width / 2, y: top ? plot.minY + 8 : plot.maxY - 8)
                .accessibilityHidden(true)
            }
        }
    }

    /// The one label: on the newest point in view, if it is 5% or 10%, and never once the goal is reached.
    private func newestLabel(_ points: [WeightMoment]) -> (moment: WeightMoment, text: String)? {
        guard !picture.moments.contains(where: \.isGoal), let newest = points.last,
              let text = WeightGoalCopy.chartLabel(newest) else { return nil }
        return (newest, text)
    }

    // MARK: Scrub

    /// The trend day nearest the finger.
    private func snap(_ date: Date) -> DayKey? {
        window.trend.min { abs(clock.noon(of: $0.day).timeIntervalSince(date)) < abs(clock.noon(of: $1.day).timeIntervalSince(date)) }?.day
    }

    /// "3 Aug", the trend, the day's weigh-in and, on a point's day, its fact.
    private func popover(_ day: DayKey) -> some View {
        let trend = window.trend.first { $0.day == day }
        let weighIn = window.dots.filter { $0.day == day }.map(\.kg).min()
        let moment = picture.moments.first { $0.day == day }
        return VStack(alignment: .leading, spacing: 2) {
            Text(WeightGoalCopy.shortDay(day, today: today))
                .font(.sans(12, .sans, relativeTo: .caption))
                .foregroundStyle(theme.fgSubtle)
            if let trend {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(WeightGoalCopy.trend)
                        .font(.sans(12, .sans, relativeTo: .caption))
                        .foregroundStyle(theme.fgMuted)
                    Text(WeightFormat.trend(trend.kg, unit: unit))
                        .font(.mono(15, .monoMedium, relativeTo: .subheadline))
                        .foregroundStyle(theme.fg)
                }
            }
            if let weighIn {
                Text("\(WeightGoalCopy.weighIn) \(WeightFormat.value(weighIn, unit: unit))")
                    .font(.mono(13, .monoMedium, relativeTo: .footnote))
                    .foregroundStyle(theme.fgMuted)
            }
            if let moment, let goalKg {
                Text(WeightGoalCopy.pointFact(moment, goalKg: goalKg, unit: unit))
                    .font(.sans(12, .sans, relativeTo: .caption))
                    .foregroundStyle(theme.signalInk)
            }
        }
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(theme.bgInset, in: RoundedRectangle(cornerRadius: theme.radius.card / 2, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.radius.card / 2, style: .continuous)
            .strokeBorder(theme.lineStrong, lineWidth: 1))
    }

    /// Days when the window spans two months or less ("21 Oct"), months beyond that ("Oct"), so a short All never reads
    /// "Oct Oct Oct".
    private var xFormat: Date.FormatStyle {
        window.firstDay.distance(to: window.lastDay) <= 62 ? .dateTime.day().month(.abbreviated) : .dateTime.month(.abbreviated)
    }
}

/// A lit point: an 8 pt circle in the look's signal colour with its glow. On the chart it sits on a 12 pt circle in the
/// card's colour that cuts the line, like a bead; beside the moment sentence on screen one it stands alone and springs in
/// 0.35 s after the save, once the keypad is down, with Today's All taken spring (a fade under Reduce Motion). Never
/// hit-testable.
struct WeightLitPoint: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let springs: Bool
    let bead: Bool
    @State private var lit: Bool

    init(springs: Bool, bead: Bool = true) {
        self.springs = springs
        self.bead = bead
        _lit = State(initialValue: !springs)
    }

    var body: some View {
        ZStack {
            if bead {
                Circle()
                    .fill(theme.bgRaised)
                    .frame(width: 12, height: 12)
            }
            Circle()
                .fill(theme.signal)
                .frame(width: 8, height: 8)
                .shadow(color: theme.glow(lit ? 0.35 : 0.7), radius: lit ? 4 : 8)
        }
        .scaleEffect(reduceMotion || lit ? 1 : 0.55)
        .opacity(lit ? 1 : 0)
        .allowsHitTesting(false)
        .task {
            guard springs, !lit else { return }
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(response: 0.38, dampingFraction: 0.55)) {
                lit = true
            }
        }
    }
}

/// W, 30D, 90D, Y and All as one segmented control in the look's own tokens: the chosen range on the inset surface,
/// the rest in subtle ink. It filters the chart; the last choice is remembered.
struct WeightRangePicker: View {
    @Environment(\.theme) private var theme
    let selection: WeightRange
    let onSelect: (WeightRange) -> Void

    init(selection: WeightRange, onSelect: @escaping (WeightRange) -> Void) {
        self.selection = selection
        self.onSelect = onSelect
    }

    var body: some View {
        let inner = RoundedRectangle(cornerRadius: theme.radius.card / 2, style: .continuous)
        let outer = RoundedRectangle(cornerRadius: theme.radius.card / 2 + 3, style: .continuous)
        HStack(spacing: 2) {
            ForEach(WeightRange.allCases) { range in
                let selected = range == selection
                Button {
                    onSelect(range)
                } label: {
                    Text(range.label)
                        .font(.mono(13, .monoMedium, relativeTo: .footnote))
                        .foregroundStyle(selected ? theme.fg : theme.fgSubtle)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if selected {
                                inner.fill(theme.bgInset)
                                    .overlay(inner.strokeBorder(theme.lineStrong, lineWidth: 1))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(range.spoken)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(theme.bg, in: outer)
        .overlay(outer.strokeBorder(theme.line, lineWidth: 1))
        .animation(.snappy(duration: 0.2), value: selection)
    }
}
#endif
