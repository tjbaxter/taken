import Charts
import SwiftUI

#if DEBUG || TAKEN_INTERNAL
/// The weight chart (SPEC 3.12), in Swift Charts: each weigh-in a small dot in the look's subtle ink, the trend a smooth
/// line in the look's signal colour (monotone interpolation, "a cubic spline that preserves monotonicity of the data", so
/// it never swings past the days it joins), a small unlabelled tick on the baseline on each day a weekly dose was logged,
/// and a y axis fitted to what is in view, never from zero. No goal line, forecast, milestones, BMI, red or green.
/// Swift Charts gives VoiceOver an element per weigh-in and an Audio Graph; the chart adds its title and a one-line
/// summary.
struct WeightChart: View {
    @Environment(\.theme) private var theme
    let window: WeightWindow
    let unit: WeightUnit
    let range: WeightRange
    let clock: DayClock
    /// "Trend 88.1 kilograms, down 1.2 over 30 days"
    let summary: String

    init(window: WeightWindow, unit: WeightUnit, range: WeightRange, clock: DayClock, summary: String) {
        self.window = window
        self.unit = unit
        self.range = range
        self.clock = clock
        self.summary = summary
    }

    var body: some View {
        Group {
            if window.isEmpty {
                Text(WeightCopy.emptyRange)
                    .font(.sans(15, .sans, relativeTo: .subheadline))
                    .foregroundStyle(theme.fgSubtle)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chart
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Weight chart. \(summary)")
    }

    private var chart: some View {
        let lower = unit.value(fromKilograms: window.lower)
        let upper = unit.value(fromKilograms: window.upper)
        // A short mark on the baseline: about a twentieth of the chart's height, so weekly ticks read as marks, not a ruler.
        let tickTop = lower + (upper - lower) * 0.05
        return Chart {
            ForEach(window.ticks, id: \.self) { day in
                RuleMark(x: .value("Day", clock.noon(of: day)),
                         yStart: .value("Weight", lower),
                         yEnd: .value("Weight", tickTop))
                    .foregroundStyle(theme.fgSubtle)
                    .lineStyle(StrokeStyle(lineWidth: 1.25, lineCap: .round))
                    .accessibilityLabel(Fmt.longDay(day))
                    .accessibilityValue("Weekly dose")
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
        }
        .chartXScale(domain: clock.start(of: window.firstDay)...clock.end(of: window.lastDay))
        .chartYScale(domain: lower...upper)
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
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                    .foregroundStyle(theme.line)
                AxisValueLabel()
                    .font(.mono(11, .monoMedium, relativeTo: .caption2))
                    .foregroundStyle(theme.fgSubtle)
            }
        }
    }

    /// Days for a week or a month ("21 Oct"), months for longer ranges ("Oct").
    private var xFormat: Date.FormatStyle {
        switch range {
        case .week, .month: return .dateTime.day().month(.abbreviated)
        case .quarter, .year, .all: return .dateTime.month(.abbreviated)
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
