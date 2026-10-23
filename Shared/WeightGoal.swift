import Foundation

// The Weight tab's optional goal and its moments (REDESIGN.md, "Goal and moments, 2026-10-22"): the goal, its start and
// direction, the BMI 18.5 floor, at most three lit points on the trend (5% and 10% below the start, and the goal
// reached), the one line that says how close the trend is, the y axis ticks, the change line for the selected range and
// every word they show, as pure rules (TakenTests/WeightGoalTests.swift). Copy rules: no em or en dash, no exclamation
// mark, and never lose, lost, loss, ideal, great, should, missed, behind or off track.

// MARK: - The goal

/// An optional goal weight, set only from the Weight tab's More menu: kilograms, and the day whose trend is the start
/// weight. `startPicked` once the person moved the start in the Goal sheet. No date, pace, rate or plan, ever.
struct WeightGoal: Codable, Hashable, Sendable {
    var kg: Double
    var startDay: DayKey
    var startPicked: Bool

    init(kg: Double, startDay: DayKey, startPicked: Bool = false) {
        self.kg = kg
        self.startDay = startDay
        self.startPicked = startPicked
    }

    private enum CodingKeys: String, CodingKey { case kg, startDay, startPicked }

    /// The weight and the start day are required; a goal that cannot be read decodes as none (`WeightState`).
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kg = try c.decode(Double.self, forKey: .kg)
        startDay = try c.decode(DayKey.self, forKey: .startDay)
        startPicked = (try? c.decodeIfPresent(Bool.self, forKey: .startPicked)) ?? false
        guard kg.isFinite, kg > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .kg, in: c, debugDescription: "Not a weight")
        }
    }
}

/// Which way the goal lies from the start, inferred and never asked: more than 0.68 kg below is lower, more than 0.68 kg
/// above is higher, anything else is near (MacroFactor's maintenance tolerance).
enum GoalDirection: Equatable, Sendable {
    case lower
    case higher
    case near
}

/// A lit point on the trend: the first weigh-in day on or after the start on which the trend sat 5% or 10% below the
/// start, or reached the goal. Worked out from the weigh-ins, the goal and the height; nothing is stored.
struct WeightMoment: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case percent(Int)
        case goal
    }

    let kind: Kind
    let day: DayKey
    let trendKg: Double

    init(kind: Kind, day: DayKey, trendKg: Double) {
        self.kind = kind
        self.day = day
        self.trendKg = trendKg
    }

    /// "pct5", "pct10", "goal"
    var id: String {
        switch kind {
        case .percent(let percent): return "pct\(percent)"
        case .goal: return "goal"
        }
    }

    /// When two arrive together, the goal outranks 10% and 10% outranks 5% (own choice).
    var rank: Int {
        switch kind {
        case .percent(let percent): return percent
        case .goal: return 1_000
        }
    }

    var isGoal: Bool { kind == .goal }
}

/// What the headline card's slot says about the goal, in kilograms.
enum GoalReadout: Equatable, Sendable {
    /// "Goal 87.0": the trend has not moved 0.1 towards it yet, or sits on the far side of the start.
    case goalOnly
    /// "4.2 kg closer to 87.0": less than half the way covered.
    case closer(Double)
    /// "1.1 kg to 87.0": half or more covered, not yet reached.
    case toGo(Double)
    /// "Holding near 87.0": reached, or a near goal, within 0.68 kg.
    case holding
    /// "0.9 kg from 87.0": reached, or a near goal, more than 0.68 kg away.
    case from(Double)
}

/// The goal's rules (REDESIGN.md, "Goal and moments"): the start, the direction, the floor, the points, the readout and
/// which point a weigh-in just lit.
enum WeightGoals {
    /// Within this of the goal the trend is holding (MacroFactor: 1.5 lb either way, on the trend weight).
    static let holdBandKg = 0.68
    /// A goal counts as reached within this of it, so "0.0 kg to 87.0" never shows (own choice).
    static let reachToleranceKg = 0.05
    /// The lowest goal is BMI 18.5 at the person's height (Honary et al. 2019).
    static let floorBMI = 18.5
    /// The 5% and 10% points need a start at BMI 25 or more (ACC/AHA 2013, adults with overweight or obesity).
    static let percentPointsMinBMI = 25.0
    /// The guideline's "sustained weight loss of 5 percent to 10 percent".
    static let percents = [5, 10]

    private static let epsilon = 1e-9

    /// 18.5 x (height in metres) squared.
    static func floorKg(heightCm: Double) -> Double {
        let metres = heightCm / 100
        return floorBMI * metres * metres
    }

    static func bmi(kg: Double, heightCm: Double) -> Double {
        let metres = heightCm / 100
        return kg / (metres * metres)
    }

    /// The first weigh-in day, unless the trend has already been at the goal since then (the goal lies between its lowest
    /// and highest values), when it is the last weigh-in day, so a long imported history never turns a regain into a
    /// finished goal (own rule). Nil without weigh-ins.
    static func defaultStartDay(goalKg: Double, trend: [WeightPoint]) -> DayKey? {
        guard let first = trend.first, let last = trend.last else { return nil }
        let values = trend.map(\.kg)
        let low = values.min() ?? first.kg
        let high = values.max() ?? first.kg
        return goalKg >= low && goalKg <= high ? last.day : first.day
    }

    /// The Goal sheet's start day: the day picked in its Start row; else, for Change Goal, the stored start while the value
    /// is unchanged (or the field is empty) or once the start was picked by hand (`startPicked`); else the default for
    /// what is typed, and the first weigh-in day before anything is typed. Nil without weigh-ins.
    static func sheetStartDay(existing: WeightGoal?, typedKg: Double?, pickedDay: DayKey?, trend: [WeightPoint]) -> DayKey? {
        guard let first = trend.first else { return nil }
        if let pickedDay { return pickedDay }
        if let existing, existing.startPicked || typedKg == nil || typedKg == existing.kg { return existing.startDay }
        return typedKg.flatMap { defaultStartDay(goalKg: $0, trend: trend) } ?? first.day
    }

    /// The goal's start on the trend: its day, clamped to the first and last weigh-in days after edits or deletes, and
    /// the trend that day. Nil without weigh-ins: the goal waits for the next one.
    static func start(of goal: WeightGoal, trend: [WeightPoint]) -> WeightPoint? {
        guard let first = trend.first, let last = trend.last else { return nil }
        let day = min(max(goal.startDay, first.day), last.day)
        let index = first.day.distance(to: day)
        if trend.indices.contains(index), trend[index].day == day { return trend[index] }
        return trend.first { $0.day == day }
    }

    static func direction(startKg: Double, goalKg: Double) -> GoalDirection {
        if startKg - goalKg > holdBandKg + epsilon { return .lower }
        if goalKg - startKg > holdBandKg + epsilon { return .higher }
        return .near
    }

    /// Whether the floor stops this goal: a lower or near goal below BMI 18.5 at this height. A goal above the start,
    /// gaining towards a healthier weight, is never blocked (own judgement: the floor stops unsafe loss, not recovery).
    static func floorBlocks(goalKg: Double, startKg: Double, heightCm: Double) -> Bool {
        guard heightCm > 0 else { return false }
        guard direction(startKg: startKg, goalKg: goalKg) != .higher else { return false }
        return goalKg < floorKg(heightCm: heightCm) - epsilon
    }

    /// At most three points, oldest first. 5% and 10% only for a lower goal, only from a start at BMI 25 or more, and only
    /// where the threshold lies between the start and the goal, more than 0.05 kg from the goal; the goal point in
    /// either direction; a near goal gets none. Each lands on the first real weigh-in day on or after the start on which
    /// the trend is at or past it (never a day the trend filled in), and stays even if the trend rises again.
    static func moments(goal: WeightGoal, trend: [WeightPoint], weighInDays: Set<DayKey>, heightCm: Double?) -> [WeightMoment] {
        guard let start = start(of: goal, trend: trend) else { return [] }
        let direction = direction(startKg: start.kg, goalKg: goal.kg)
        guard direction != .near else { return [] }
        let days = trend.filter { $0.day >= start.day && weighInDays.contains($0.day) }
        var out: [WeightMoment] = []
        if direction == .lower, let heightCm, heightCm > 0, bmi(kg: start.kg, heightCm: heightCm) >= percentPointsMinBMI {
            for percent in percents {
                let threshold = start.kg * (1 - Double(percent) / 100)
                guard threshold > goal.kg + reachToleranceKg else { continue }
                if let hit = days.first(where: { $0.kg <= threshold }) {
                    out.append(WeightMoment(kind: .percent(percent), day: hit.day, trendKg: hit.kg))
                }
            }
        }
        let reached = direction == .lower
            ? days.first { $0.kg <= goal.kg + reachToleranceKg }
            : days.first { $0.kg >= goal.kg - reachToleranceKg }
        if let reached { out.append(WeightMoment(kind: .goal, day: reached.day, trendKg: reached.kg)) }
        return out.sorted { ($0.day, $0.rank) < ($1.day, $1.rank) }
    }

    /// The slot's reading, on the trend: T is the trend on the last weigh-in day. Covered is how far T has moved from the
    /// start towards the goal; under 0.1 in the chosen unit, or on the far side, it is just the goal. Less than half the
    /// way is "closer", half or more is "to go", and a reached or near goal holds within 0.68 kg.
    static func readout(goal: WeightGoal, trend: [WeightPoint], moments: [WeightMoment], unit: WeightUnit = .kg) -> GoalReadout {
        guard let start = start(of: goal, trend: trend), let last = trend.last else { return .goalOnly }
        let direction = direction(startKg: start.kg, goalKg: goal.kg)
        if direction == .near || moments.contains(where: \.isGoal) {
            let away = abs(last.kg - goal.kg)
            return away <= holdBandKg + epsilon ? .holding : .from(away)
        }
        let covered = direction == .lower ? start.kg - last.kg : last.kg - start.kg
        guard unit.value(fromKilograms: covered) >= 0.1 - epsilon else { return .goalOnly }
        let distance = abs(start.kg - goal.kg)
        if covered * 2 < distance - epsilon { return .closer(covered) }
        return .toGo(max(0, direction == .lower ? last.kg - goal.kg : goal.kg - last.kg))
    }

    /// The point a weigh-in saved from Log weigh-in just lit: new since before the save and dated that weigh-in's day; the
    /// highest-ranked if two arrive together. Nil otherwise (a backdated weigh-in, an edit, an import or a goal change
    /// makes points appear silently).
    static func fresh(before: [WeightMoment], after: [WeightMoment], savedDay: DayKey) -> WeightMoment? {
        let old = Set(before.map(\.id))
        return after.filter { !old.contains($0.id) && $0.day == savedDay }.max { $0.rank < $1.rank }
    }
}

// MARK: - Height

/// Centimetres, or feet and inches where Foundation's person-height unit is feet (en_US, en_GB, en_CA, en_IN). Stored
/// in centimetres; asked only in the Goal sheet, to keep goals in a healthy range.
enum HeightUnit: Equatable, Sendable {
    case centimetres
    case feetInches

    static let centimetreRange = 100...230
    static let feetRange = 3...7
    static let inchRange = 0...11
    static let centimetresPerInch = 2.54
    /// Where the wheel starts with no height stored: 170 cm, or 5 ft 7 in.
    static let defaultCentimetres = 170.0
    static let defaultFeetInches = (feet: 5, inches: 7)

    /// https://developer.apple.com/documentation/foundation/unitlength/init(forlocale:usage:)
    static func preferred(for locale: Locale) -> HeightUnit {
        let unit = UnitLength(forLocale: locale, usage: .personHeight)
        return unit == UnitLength.feet || unit == UnitLength.inches ? .feetInches : .centimetres
    }

    static func centimetres(feet: Int, inches: Int) -> Double {
        Double(feet * 12 + inches) * centimetresPerInch
    }

    /// The nearest whole inch.
    static func feetInches(centimetres: Double) -> (feet: Int, inches: Int) {
        let total = Int((centimetres / centimetresPerInch).rounded())
        return (total / 12, total % 12)
    }

    /// "183 cm", "6 ft 0 in"
    func text(_ centimetres: Double) -> String {
        switch self {
        case .centimetres:
            return "\(Int(centimetres.rounded())) cm"
        case .feetInches:
            let height = Self.feetInches(centimetres: centimetres)
            return "\(height.feet) ft \(height.inches) in"
        }
    }

    /// "183 centimetres", "6 feet 0 inches", for VoiceOver.
    func spoken(_ centimetres: Double) -> String {
        switch self {
        case .centimetres:
            return "\(Int(centimetres.rounded())) centimetres"
        case .feetInches:
            let height = Self.feetInches(centimetres: centimetres)
            return "\(height.feet) feet \(height.inches) inches"
        }
    }
}

// MARK: - The y axis

/// The chart's y ticks as explicit values, so a tick next to the goal's own label can give way.
enum WeightAxis {
    static let steps: [Double] = [0.5, 1, 2, 5, 10, 20]
    /// A tick closer than this to the goal's label loses its label and its grid line.
    static let clearance = 12.0

    /// The smallest step of 0.5, 1, 2, 5, 10 or 20 that gives four or fewer ticks inside the domain, in the unit shown.
    static func ticks(lower: Double, upper: Double) -> [Double] {
        guard upper > lower, lower.isFinite, upper.isFinite else { return [] }
        // Past 20 (a domain wider than any one person's record) the steps carry on, so there are never more than four.
        for step in steps + [50, 100, 200] {
            let values = ticks(lower: lower, upper: upper, step: step)
            if values.count <= 4 { return values }
        }
        return []
    }

    /// One decimal only for half steps ("88.5"), else whole numbers.
    static func decimals(_ ticks: [Double]) -> Int {
        ticks.contains { abs($0 - $0.rounded()) > 1e-9 } ? 1 : 0
    }

    /// The ticks more than `gap` points from `mark` on a plot `plotHeight` tall showing `lower` to `upper`.
    static func clear(_ ticks: [Double], of mark: Double, lower: Double, upper: Double, plotHeight: Double,
                      gap: Double = clearance) -> [Double] {
        guard upper > lower, plotHeight > 0 else { return ticks }
        let pointsPerUnit = plotHeight / (upper - lower)
        return ticks.filter { abs($0 - mark) * pointsPerUnit >= gap - 1e-9 }
    }

    private static func ticks(lower: Double, upper: Double, step: Double) -> [Double] {
        let first = Int((lower / step - 1e-9).rounded(.up))
        let last = Int((upper / step + 1e-9).rounded(.down))
        guard first <= last else { return [] }
        return (first...last).map { Double($0) * step }
    }
}

// MARK: - The change line

/// The trend's change for the selected range, one line under the range control: over 7, 30 or 90 days or the year,
/// ending on the last weigh-in day; since the first trend day in view when the trend is shorter than the range, and
/// always on All. Hidden with fewer than two trend days in view.
enum WeightChangeLine {
    enum Span: Hashable, Sendable {
        case days(Int)
        case year
        case since(DayKey)
    }

    static func make(range: WeightRange, trend: [WeightPoint], window: WeightWindow) -> (kg: Double, span: Span)? {
        guard window.trend.count >= 2, let first = window.trend.first, let last = window.trend.last else { return nil }
        guard let days = range.days, let change = WeightTrend.change(trend, days: days) else {
            return (last.kg - first.kg, .since(first.day))
        }
        return (change, range == .year ? .year : .days(days))
    }
}

// MARK: - Copy

/// Every word the goal, its points and the change line show. "Goal" is Tom's word; never lose, lost, loss, ideal, great,
/// should, missed, behind or off track (whole words: "closer" holds "lose"), and no exclamation mark.
enum WeightGoalCopy {
    static let setGoal = "Set Goal\u{2026}"
    static let changeGoal = "Change Goal\u{2026}"
    static let clearGoal = "Clear Goal"
    static let title = "Goal"
    static let start = "Start"
    static let height = "Height"
    static let setButton = "Set"
    static let save = "Save"
    static let footnote = "Shows as a line on your chart, measured on your trend, not single weigh-ins. No dates, no pace, no reminders. Goals are for adults."
    static let heightFootnote = "Height is used only to keep goals in a healthy range. Kept on this iPhone."
    static let tooLow = "Too low for your height. Taken keeps goals in a healthy range."
    static let cleared = "Goal cleared"
    static let clearedSpoken = "Goal cleared."
    static let trend = "Trend"
    static let weighIn = "Weigh-in"
    static let goalLine = "Goal"

    /// A piece of a line: a number with its unit, in Geist Mono, or words, in Geist.
    struct Part: Hashable, Sendable {
        let text: String
        let isNumber: Bool

        init(_ text: String, number: Bool = false) {
            self.text = text
            self.isNumber = number
        }
    }

    private static let monthsShort = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    private static let monthsLong = ["January", "February", "March", "April", "May", "June", "July", "August",
                                     "September", "October", "November", "December"]

    /// One decimal, in the locale, no grouping.
    static func oneDecimal(_ value: Double, locale: Locale = .current) -> String {
        value.formatted(.number.precision(.fractionLength(1)).grouping(.never).locale(locale))
    }

    /// The goal as the slot and the axis name it: "87.0".
    static func goal(_ kg: Double, unit: WeightUnit, locale: Locale = .current) -> String {
        oneDecimal(unit.value(fromKilograms: kg), locale: locale)
    }

    /// Down to a tenth (closer), up to a tenth (to go), in the unit shown.
    static func roundedDown(_ value: Double) -> Double { (value * 10 + 1e-6).rounded(.down) / 10 }
    static func roundedUp(_ value: Double) -> Double { (value * 10 - 1e-6).rounded(.up) / 10 }

    private static func amount(_ value: Double, unit: WeightUnit, locale: Locale) -> String {
        "\(oneDecimal(value, locale: locale)) \(unit.symbol)"
    }

    // MARK: The slot

    /// "Goal 87.0", "4.2 kg closer to 87.0", "1.1 kg to 87.0", "Holding near 87.0", "0.9 kg from 87.0".
    static func slot(_ readout: GoalReadout, goalKg: Double, unit: WeightUnit, locale: Locale = .current) -> [Part] {
        let target = goal(goalKg, unit: unit, locale: locale)
        switch readout {
        case .goalOnly:
            return [Part("Goal "), Part(target, number: true)]
        case .closer(let kg):
            return [Part(amount(roundedDown(unit.value(fromKilograms: kg)), unit: unit, locale: locale), number: true),
                    Part(" closer to "), Part(target, number: true)]
        case .toGo(let kg):
            return [Part(amount(roundedUp(unit.value(fromKilograms: kg)), unit: unit, locale: locale), number: true),
                    Part(" to "), Part(target, number: true)]
        case .holding:
            return [Part("Holding near "), Part(target, number: true)]
        case .from(let kg):
            return [Part(amount(unit.value(fromKilograms: kg), unit: unit, locale: locale), number: true),
                    Part(" from "), Part(target, number: true)]
        }
    }

    static func text(_ parts: [Part]) -> String { parts.map(\.text).joined() }

    /// For VoiceOver: "1.1 kilograms to your goal, 87.0".
    static func spokenSlot(_ readout: GoalReadout, goalKg: Double, unit: WeightUnit, locale: Locale = .current) -> String {
        let target = goal(goalKg, unit: unit, locale: locale)
        switch readout {
        case .goalOnly:
            return "Goal, \(target) \(unit.spoken)"
        case .closer(let kg):
            return "\(oneDecimal(roundedDown(unit.value(fromKilograms: kg)), locale: locale)) \(unit.spoken) closer to your goal, \(target)"
        case .toGo(let kg):
            return "\(oneDecimal(roundedUp(unit.value(fromKilograms: kg)), locale: locale)) \(unit.spoken) to your goal, \(target)"
        case .holding:
            return "Holding near your goal, \(target)"
        case .from(let kg):
            return "\(oneDecimal(unit.value(fromKilograms: kg), locale: locale)) \(unit.spoken) from your goal, \(target)"
        }
    }

    /// Screen one's small line after a save on this visit: the slot with "Trend" in front, so it never reads as
    /// arithmetic on the big number. "Trend 1.1 kg to 87.0", "Trend holding near 87.0". Nil for "Goal 87.0".
    static func visit(_ readout: GoalReadout, goalKg: Double, unit: WeightUnit, locale: Locale = .current) -> [Part]? {
        switch readout {
        case .goalOnly:
            return nil
        case .holding:
            return [Part("Trend holding near "), Part(goal(goalKg, unit: unit, locale: locale), number: true)]
        default:
            return [Part("Trend ")] + slot(readout, goalKg: goalKg, unit: unit, locale: locale)
        }
    }

    /// For VoiceOver: "Trend 1.1 kilograms to your goal, 87.0", "Trend holding near your goal, 87.0". Nil for goal only.
    static func spokenVisit(_ readout: GoalReadout, goalKg: Double, unit: WeightUnit, locale: Locale = .current) -> String? {
        switch readout {
        case .goalOnly: return nil
        case .holding: return "Trend holding near your goal, \(goal(goalKg, unit: unit, locale: locale))"
        default: return "Trend \(spokenSlot(readout, goalKg: goalKg, unit: unit, locale: locale))"
        }
    }

    // MARK: Moments

    /// The slot for one visit after a crossing: "Trend is now 10% below where you started.", "Trend reached 87.0."
    static func moment(_ moment: WeightMoment, goalKg: Double, unit: WeightUnit, locale: Locale = .current) -> [Part] {
        switch moment.kind {
        case .percent(let percent):
            return [Part("Trend is now \(percent)% below where you started.")]
        case .goal:
            return [Part("Trend reached "), Part(goal(goalKg, unit: unit, locale: locale), number: true), Part(".")]
        }
    }

    /// The announcement's second sentence: "Trend is now 10 percent below where you started.", "Trend reached your goal,
    /// 87.0 kilograms."
    static func spokenMoment(_ moment: WeightMoment, goalKg: Double, unit: WeightUnit, locale: Locale = .current) -> String {
        switch moment.kind {
        case .percent(let percent):
            return "Trend is now \(percent) percent below where you started."
        case .goal:
            return "Trend reached your goal, \(goal(goalKg, unit: unit, locale: locale)) \(unit.spoken)."
        }
    }

    /// A point's VoiceOver label: "5 percent below where you started", "Trend reached your goal".
    static func pointLabel(_ moment: WeightMoment) -> String {
        switch moment.kind {
        case .percent(let percent): return "\(percent) percent below where you started"
        case .goal: return "Trend reached your goal"
        }
    }

    /// A point's VoiceOver value: "3 August, trend 92.9 kilograms".
    static func pointValue(_ moment: WeightMoment, unit: WeightUnit, locale: Locale = .current) -> String {
        "\(spokenDay(moment.day)), trend \(oneDecimal(unit.value(fromKilograms: moment.trendKg), locale: locale)) \(unit.spoken)"
    }

    /// The scrub popover's line on a point's day: "5% below where you started", "Reached 87.0".
    static func pointFact(_ moment: WeightMoment, goalKg: Double, unit: WeightUnit, locale: Locale = .current) -> String {
        switch moment.kind {
        case .percent(let percent): return "\(percent)% below where you started"
        case .goal: return "Reached \(goal(goalKg, unit: unit, locale: locale))"
        }
    }

    /// The one label on the chart, on the newest percent point in view: "−5%", "−10%" (U+2212). The goal point has none.
    static func chartLabel(_ moment: WeightMoment) -> String? {
        switch moment.kind {
        case .percent(let percent): return "\u{2212}\(percent)%"
        case .goal: return nil
        }
    }

    /// The chart summary's last clause: "Marked: 5 percent below where you started, 3 August."
    static func marked(_ moments: [WeightMoment]) -> String? {
        guard !moments.isEmpty else { return nil }
        return "Marked: " + moments.map { "\(pointLabel($0)), \(spokenDay($0.day))" }.joined(separator: "; ") + "."
    }

    // MARK: The goal

    /// "Goal set, 87.0 kilograms."
    static func goalSet(_ kg: Double, unit: WeightUnit, locale: Locale = .current) -> String {
        "Goal set, \(goal(kg, unit: unit, locale: locale)) \(unit.spoken)."
    }

    /// The goal line for VoiceOver: "87.0 kilograms".
    static func goalValue(_ kg: Double, unit: WeightUnit, locale: Locale = .current) -> String {
        "\(goal(kg, unit: unit, locale: locale)) \(unit.spoken)"
    }

    /// "Set 183 cm", "Set 6 ft 0 in"
    static func setHeight(_ centimetres: Double, unit: HeightUnit) -> String {
        "\(setButton) \(unit.text(centimetres))"
    }

    // MARK: The change line

    /// "over 7 days", "over 30 days", "over 90 days", "over the year", "since 4 Mar", "since 4 Mar 2025".
    static func span(_ span: WeightChangeLine.Span, today: DayKey) -> String {
        switch span {
        case .days(let days): return "over \(days) days"
        case .year: return "over the year"
        case .since(let day): return "since \(shortDay(day, today: today))"
        }
    }

    /// "−1.2 kg" and " over 30 days", or no number and "No change over 30 days" when it rounds to 0.0. One neutral
    /// colour both ways: the U+2212 minus or a plus, no arrow, no word for which way.
    static func changeLine(_ kg: Double, span: WeightChangeLine.Span, unit: WeightUnit, today: DayKey,
                           locale: Locale = .current) -> [Part] {
        let shown = (unit.value(fromKilograms: kg) * 10).rounded() / 10
        let words = self.span(span, today: today)
        guard shown != 0 else { return [Part("No change \(words)")] }
        let sign = shown < 0 ? "\u{2212}" : "+"
        return [Part("\(sign)\(amount(abs(shown), unit: unit, locale: locale))", number: true), Part(" \(words)")]
    }

    /// "Down 1.2 kilograms over 30 days", "Up 0.5 kilograms since 4 March", "No change over 30 days".
    static func spokenChange(_ kg: Double, span: WeightChangeLine.Span, unit: WeightUnit, today: DayKey,
                             locale: Locale = .current) -> String {
        let shown = (unit.value(fromKilograms: kg) * 10).rounded() / 10
        let words: String
        switch span {
        case .since(let day): words = "since \(spokenDay(day))"
        default: words = self.span(span, today: today)
        }
        guard shown != 0 else { return "No change \(words)" }
        return "\(shown < 0 ? "Down" : "Up") \(oneDecimal(abs(shown), locale: locale)) \(unit.spoken) \(words)"
    }

    // MARK: Days

    /// "4 Mar", and "4 Mar 2025" from another year.
    static func shortDay(_ day: DayKey, today: DayKey) -> String {
        let (year, month, dayOfMonth) = day.ymd
        let base = "\(dayOfMonth) \(monthsShort[max(0, min(11, month - 1))])"
        return year == today.ymd.year ? base : "\(base) \(year)"
    }

    /// "3 August"
    static func spokenDay(_ day: DayKey) -> String {
        let (_, month, dayOfMonth) = day.ymd
        return "\(dayOfMonth) \(monthsLong[max(0, min(11, month - 1))])"
    }

    /// Every fixed line and a sample of each built one, for the copy rules test.
    static var all: [String] {
        let moments = [WeightMoment(kind: .percent(5), day: DayKey(year: 2026, month: 8, day: 3), trendKg: 92.9),
                       WeightMoment(kind: .percent(10), day: DayKey(year: 2026, month: 9, day: 4), trendKg: 88.0),
                       WeightMoment(kind: .goal, day: DayKey(year: 2026, month: 10, day: 22), trendKg: 87.0)]
        let today = DayKey(year: 2026, month: 10, day: 22)
        let readouts: [GoalReadout] = [.goalOnly, .closer(4.2), .toGo(1.1), .holding, .from(0.9)]
        let spans: [WeightChangeLine.Span] = [.days(7), .days(30), .days(90), .year, .since(DayKey(year: 2026, month: 3, day: 4))]
        var lines = [setGoal, changeGoal, clearGoal, title, start, height, setButton, save, footnote, heightFootnote, tooLow,
                     cleared, clearedSpoken, trend, weighIn, goalLine, goalSet(87, unit: .kg), goalValue(87, unit: .kg),
                     setHeight(183, unit: .centimetres), setHeight(183, unit: .feetInches)]
        lines += readouts.map { text(slot($0, goalKg: 87, unit: .kg)) }
        lines += readouts.map { spokenSlot($0, goalKg: 87, unit: .kg) }
        lines += readouts.compactMap { visit($0, goalKg: 87, unit: .kg).map(text) }
        lines += readouts.compactMap { spokenVisit($0, goalKg: 87, unit: .kg) }
        lines += moments.map { text(moment($0, goalKg: 87, unit: .kg)) }
        lines += moments.map { spokenMoment($0, goalKg: 87, unit: .kg) }
        lines += moments.map(pointLabel) + moments.map { pointValue($0, unit: .kg) }
        lines += moments.map { pointFact($0, goalKg: 87, unit: .kg) } + moments.compactMap(chartLabel)
        lines += [marked(moments) ?? ""]
        lines += spans.flatMap { span in
            [text(changeLine(-1.2, span: span, unit: .kg, today: today)), text(changeLine(0.01, span: span, unit: .kg, today: today)),
             spokenChange(0.5, span: span, unit: .kg, today: today), spokenChange(-1.2, span: span, unit: .kg, today: today)]
        }
        return lines
    }
}
