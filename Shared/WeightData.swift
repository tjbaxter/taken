import Foundation

// The Weight tab (SPEC 3.12; REDESIGN.md, "Weight tab, 2026-10-22"): weigh-ins, the smoothed trend, kilograms and pounds,
// the Pro rule, the one-time offer on Today and the CSV, as pure rules (TakenTests/WeightTests.swift). Compiled only into
// Debug (for the tests) and the owner's internal builds (TAKEN_INTERNAL) until 1.2 ships after 1.1 is approved, so no
// App Store build from main contains it (App Review Guideline 2.5.19: scripts/check-app-store-build.sh looks for
// WeightTabRootView). Copy rules: no em or en dash, never the word for no charge, no exclamation marks, and never lose,
// ideal or goal (the self-weighing research in REDESIGN.md).

#if DEBUG || TAKEN_INTERNAL

// MARK: - Weigh-ins

/// One weigh-in: kilograms (UnitMass's base unit), as typed or converted from pounds, and when, like a `Dose`.
struct WeighIn: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var kg: Double
    var weighedAt: Date
    /// Seconds east of UTC where it was logged, so it keeps its day after the phone changes time zone (`Dose.utcOffset`).
    var utcOffset: Int?

    init(id: UUID = UUID(), kg: Double, weighedAt: Date, utcOffset: Int? = nil) {
        self.id = id
        self.kg = kg
        self.weighedAt = weighedAt
        self.utcOffset = utcOffset
    }

    private enum CodingKeys: String, CodingKey { case id, kg, weighedAt, utcOffset }

    /// A weigh-in needs its weight and its moment; anything else missing has a default, so one odd entry never costs
    /// the file (`WeightState` drops an unreadable one).
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kg = try c.decode(Double.self, forKey: .kg)
        weighedAt = try c.decode(Date.self, forKey: .weighedAt)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        utcOffset = try? c.decodeIfPresent(Int.self, forKey: .utcOffset)
    }
}

extension DayClock {
    /// The day a weigh-in belongs to, read as a dose's day is (`day(of: Dose)`): the day that was being lived where it
    /// was logged, so "today" means what it means for doses.
    func day(of weighIn: WeighIn) -> DayKey {
        guard let offset = weighIn.utcOffset, offset != utcOffset(at: weighIn.weighedAt) else {
            return day(for: weighIn.weighedAt)
        }
        return fixed(utcOffset: offset).day(for: weighIn.weighedAt)
    }

    /// Noon on a day, where the chart draws it (the day-start hour is never after noon, so it is always that date).
    func noon(of day: DayKey) -> Date {
        date(on: day, hour: 12, minute: 0)
    }
}

// MARK: - Units

/// Kilograms or pounds (v1). Each weigh-in is stored in kilograms; this is only how it is shown and typed.
enum WeightUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case kg
    case lb

    var id: String { rawValue }

    /// The international avoirdupois pound, exactly.
    static let kilogramsPerPound = 0.45359237

    /// The unit a new person sees: pounds where Foundation's person-weight unit for the locale is pounds (en_US, es_US),
    /// kilograms everywhere else, including the locales that prefer stones (en_GB), until a UK user asks for them
    /// (https://developer.apple.com/documentation/foundation/unitmass/init(forlocale:usage:)).
    static func preferred(for locale: Locale) -> WeightUnit {
        UnitMass(forLocale: locale, usage: .personWeight) == UnitMass.pounds ? .lb : .kg
    }

    func value(fromKilograms kg: Double) -> Double {
        self == .kg ? kg : kg / Self.kilogramsPerPound
    }

    func kilograms(from value: Double) -> Double {
        self == .kg ? value : value * Self.kilogramsPerPound
    }

    /// What a weigh-in may be, in this unit: 20 to 350 kg, 44 to 770 lb (own bounds).
    var bounds: ClosedRange<Double> { self == .kg ? 20...350 : 44...770 }

    /// "kg", "lb"
    var symbol: String { rawValue }

    /// The More menu: "Kilograms", "Pounds".
    var menuTitle: String { self == .kg ? "Kilograms" : "Pounds" }

    /// VoiceOver: "kilograms", "pounds".
    var spoken: String { self == .kg ? "kilograms" : "pounds" }

    /// Decimals a weigh-in shows: kilograms as typed with up to two, pounds with one.
    var decimals: Int { self == .kg ? 2 : 1 }
}

/// Weights as numbers on screen and as typed, in the person's locale.
enum WeightFormat {
    /// A weigh-in: "88.35", "88.0" ("88,35" in de_DE), in kilograms with one or two decimals as typed; "194.8" in pounds.
    static func value(_ kg: Double, unit: WeightUnit, locale: Locale = .current) -> String {
        let value = unit.value(fromKilograms: kg)
        switch unit {
        case .kg: return value.formatted(.number.precision(.fractionLength(1...2)).grouping(.never).locale(locale))
        case .lb: return value.formatted(.number.precision(.fractionLength(1)).grouping(.never).locale(locale))
        }
    }

    /// The trend and its changes: one decimal in either unit, "88.1".
    static func trend(_ kg: Double, unit: WeightUnit, locale: Locale = .current) -> String {
        unit.value(fromKilograms: kg).formatted(.number.precision(.fractionLength(1)).grouping(.never).locale(locale))
    }

    /// "88.35 kg"
    static func withUnit(_ kg: Double, unit: WeightUnit, locale: Locale = .current) -> String {
        "\(value(kg, unit: unit, locale: locale)) \(unit.symbol)"
    }

    /// "88.35 kilograms", for VoiceOver.
    static func spoken(_ kg: Double, unit: WeightUnit, locale: Locale = .current) -> String {
        "\(value(kg, unit: unit, locale: locale)) \(unit.spoken)"
    }

    /// What was typed, as a number: digits with at most one decimal separator (the locale's, a point or a comma; a
    /// weight never needs a thousands separator) and at most two decimals. Any script's digits count, so the decimal
    /// pad works in every locale. Nil for anything else.
    static func parse(_ text: String, locale: Locale = .current) -> Double? {
        let separators = decimalSeparators(locale)
        var whole = ""
        var fraction = ""
        var seenSeparator = false
        for character in text.trimmingCharacters(in: .whitespaces) {
            if let digit = asciiDigit(character) {
                if seenSeparator { fraction.append(digit) } else { whole.append(digit) }
            } else if separators.contains(character), !seenSeparator {
                seenSeparator = true
            } else {
                return nil
            }
        }
        guard !whole.isEmpty, whole.count <= 4, fraction.count <= 2 else { return nil }
        return Double(fraction.isEmpty ? whole : "\(whole).\(fraction)")
    }

    /// The field as it is typed: digits and one separator, two decimals at most (one in the Goal sheet); anything else is
    /// dropped as it comes.
    static func sanitize(_ text: String, locale: Locale = .current, maxDecimals: Int = 2) -> String {
        let separators = decimalSeparators(locale)
        var out = ""
        var decimals = -1
        for character in text {
            if asciiDigit(character) != nil {
                if decimals >= maxDecimals || (decimals < 0 && out.count >= 4) { continue }
                out.append(character)
                if decimals >= 0 { decimals += 1 }
            } else if separators.contains(character), decimals < 0, !out.isEmpty {
                out.append(character)
                decimals = 0
            }
        }
        return out
    }

    /// The weight a typed value saves, in kilograms: it parses in the locale and sits inside the unit's bounds.
    static func kilograms(_ text: String, unit: WeightUnit, locale: Locale = .current) -> Double? {
        guard let value = parse(text, locale: locale), unit.bounds.contains(value) else { return nil }
        return unit.kilograms(from: value)
    }

    /// A point, a comma, the Arabic decimal separator and the locale's own.
    private static func decimalSeparators(_ locale: Locale) -> Set<Character> {
        Set([".", ",", "\u{066B}"] + Array(locale.decimalSeparator ?? "."))
    }

    private static func asciiDigit(_ character: Character) -> Character? {
        guard character.isNumber, let value = character.wholeNumberValue, (0...9).contains(value) else { return nil }
        return Character(String(value))
    }
}

// MARK: - The file

/// The chart's range: a week, 30 days, 90 days, a year or everything (MyNetDiary's set). It filters; it never scrolls.
enum WeightRange: String, Codable, CaseIterable, Identifiable, Sendable {
    case week
    case month = "30d"
    case quarter = "90d"
    case year
    case all

    var id: String { rawValue }

    /// "W", "30D", "90D", "Y", "All"
    var label: String {
        switch self {
        case .week: return "W"
        case .month: return "30D"
        case .quarter: return "90D"
        case .year: return "Y"
        case .all: return "All"
        }
    }

    /// For VoiceOver.
    var spoken: String {
        switch self {
        case .week: return "Week"
        case .month: return "30 days"
        case .quarter: return "90 days"
        case .year: return "Year"
        case .all: return "All"
        }
    }

    /// Days in view, ending today; nil for everything.
    var days: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        case .all: return nil
        }
    }
}

/// Everything the Weight tab keeps: `weights.json` in the App Group, next to the log (`WeightStore`). Its own file, not
/// taken.json, so a build without the tab never reads or rewrites it, and 1.2 reads what the internal builds wrote.
struct WeightState: Codable, Hashable, Sendable {
    var schemaVersion: Int = 1
    var weighIns: [WeighIn] = []
    /// The Weight tab: nil until the person chooses, which is off; true or false once they have (Profile's switch, the
    /// More menu, the offer on Today). An explicit choice is kept if the default ever changes.
    var showsTab: Bool?
    /// Kilograms or pounds, from the More menu. Nil follows the locale (`WeightUnit.preferred`).
    var unit: WeightUnit?
    /// The chart's last range. Nil is All.
    var range: WeightRange?
    /// Today's one-time offer was answered, Add tab or Not now. Either answer is final.
    var offerAnswered: Bool = false
    /// The first weigh-in ever saved. That one needs no Taken Pro; after it, logging does (`WeightGate`). Erase keeps it.
    var firstWeighInAt: Date?
    /// The optional goal, from the More menu's Set Goal (`WeightGoal`, REDESIGN.md "Goal and moments"). Erase removes it.
    var goal: WeightGoal?
    /// Centimetres, asked only in the Goal sheet, used only for the BMI 18.5 floor and the BMI 25 check. Erase removes it.
    var heightCm: Double?

    init(weighIns: [WeighIn] = [], showsTab: Bool? = nil, unit: WeightUnit? = nil, range: WeightRange? = nil,
         offerAnswered: Bool = false, firstWeighInAt: Date? = nil, goal: WeightGoal? = nil, heightCm: Double? = nil) {
        self.weighIns = weighIns
        self.showsTab = showsTab
        self.unit = unit
        self.range = range
        self.offerAnswered = offerAnswered
        self.firstWeighInAt = firstWeighInAt
        self.goal = goal
        self.heightCm = heightCm
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, weighIns, showsTab, unit, range, offerAnswered, firstWeighInAt, goal, heightCm
    }

    /// Every field has a default, an unknown unit or range reads as none, and one unreadable weigh-in never costs the rest.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? c.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? 1
        let lossy = (try? c.decodeIfPresent([LossyWeighIn].self, forKey: .weighIns)) ?? []
        weighIns = lossy.compactMap(\.weighIn).filter { $0.kg.isFinite && $0.kg > 0 }
        showsTab = try? c.decodeIfPresent(Bool.self, forKey: .showsTab)
        unit = try? c.decodeIfPresent(WeightUnit.self, forKey: .unit)
        range = try? c.decodeIfPresent(WeightRange.self, forKey: .range)
        offerAnswered = (try? c.decodeIfPresent(Bool.self, forKey: .offerAnswered)) ?? false
        firstWeighInAt = try? c.decodeIfPresent(Date.self, forKey: .firstWeighInAt)
        // A goal or height that cannot be read is none, so older and newer files still read.
        goal = (try? c.decodeIfPresent(WeightGoal.self, forKey: .goal)) ?? nil
        heightCm = (try? c.decodeIfPresent(Double.self, forKey: .heightCm)).flatMap { $0 }.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    private struct LossyWeighIn: Decodable {
        let weighIn: WeighIn?

        init(from decoder: any Decoder) throws {
            weighIn = try? WeighIn(from: decoder)
        }
    }

    // MARK: Reading

    /// Newest first: All weigh-ins.
    var newestFirst: [WeighIn] { weighIns.sorted { $0.weighedAt > $1.weighedAt } }

    /// The latest weigh-in: the grey placeholder in the log sheet and "Last 88.35 kg".
    var last: WeighIn? { weighIns.max { $0.weighedAt < $1.weighedAt } }

    func weighIn(_ id: UUID) -> WeighIn? { weighIns.first { $0.id == id } }

    // MARK: Changing

    /// Logs a weigh-in at a moment, where it was taken. The first one ever is remembered for the Pro rule.
    @discardableResult
    mutating func log(kg: Double, at date: Date, timeZone: TimeZone) -> WeighIn {
        let weighIn = WeighIn(kg: kg, weighedAt: date, utcOffset: timeZone.secondsFromGMT(for: date))
        weighIns.append(weighIn)
        if firstWeighInAt == nil { firstWeighInAt = date }
        return weighIn
    }

    /// A new weight, day or time for one weigh-in (All weigh-ins). Returns it as it was, for UNDO.
    @discardableResult
    mutating func update(_ id: UUID, kg: Double, at date: Date, timeZone: TimeZone) -> WeighIn? {
        guard let index = weighIns.firstIndex(where: { $0.id == id }) else { return nil }
        let before = weighIns[index]
        weighIns[index].kg = kg
        if date != before.weighedAt {
            weighIns[index].weighedAt = date
            weighIns[index].utcOffset = timeZone.secondsFromGMT(for: date)
        }
        return before
    }

    @discardableResult
    mutating func delete(_ id: UUID) -> WeighIn? {
        guard let index = weighIns.firstIndex(where: { $0.id == id }) else { return nil }
        return weighIns.remove(at: index)
    }

    /// UNDO: puts a weigh-in back exactly as it was, deleted or edited.
    mutating func restore(_ weighIn: WeighIn) {
        if let index = weighIns.firstIndex(where: { $0.id == weighIn.id }) {
            weighIns[index] = weighIn
        } else {
            weighIns.append(weighIn)
        }
    }

    /// Imported weigh-ins (`WeightImport`): one whose minute is already here is skipped, so importing the same file
    /// twice adds nothing. Returns how many were added and how many were already here.
    @discardableResult
    mutating func merge(_ incoming: [WeighIn], at now: Date) -> (added: Int, already: Int) {
        var minutes = Set(weighIns.map { WeightImport.minute($0.weighedAt) })
        var added = 0
        var already = 0
        for weighIn in incoming.sorted(by: { $0.weighedAt < $1.weighedAt }) {
            guard minutes.insert(WeightImport.minute(weighIn.weighedAt)).inserted else {
                already += 1
                continue
            }
            weighIns.append(weighIn)
            added += 1
        }
        if added > 0 && firstWeighInAt == nil { firstWeighInAt = now }
        return (added, already)
    }

    /// Erase all data: the weigh-ins go, and so do the chart's range, the goal and the height. The tab setting, the unit,
    /// the offer's answer and the first weigh-in's date stay, like the look and the date of the first voice note.
    mutating func eraseAll() {
        weighIns = []
        range = nil
        goal = nil
        heightCm = nil
    }

    /// The days that have a weigh-in, the only days a goal's points can land on.
    func weighInDays(clock: DayClock) -> Set<DayKey> {
        Set(weighIns.map { clock.day(of: $0) })
    }
}

// MARK: - The trend

/// A weight on a day: the day's lowest weigh-in, a day filled between two, or the trend.
struct WeightPoint: Hashable, Sendable {
    let day: DayKey
    let kg: Double

    init(day: DayKey, kg: Double) {
        self.day = day
        self.kg = kg
    }
}

/// The trend under the daily swings, worked out the way The Hacker's Diet does it by hand
/// (https://www.fourmilab.ch/hackdiet/e4/pencilpaper.html, https://www.fourmilab.ch/hackdiet/e4/signalnoise.html).
enum WeightTrend {
    /// Each day's trend moves a tenth of the way from yesterday's trend toward that day's weight (smoothing constant
    /// 0.9). It lags about 9 to 10 days: Fourmilab calls 0.9 "roughly equivalent to a 20 day simple moving average".
    static let smoothing = 0.1

    /// The changes shown under the chart, each once the trend is that long.
    static let changeSpans = [7, 30, 90]

    /// (1) One value per day, the day's lowest weigh-in (Happy Scale: "the lowest weight you achieved that day",
    /// https://happyscale.com/support), oldest first. Days are DayClock's, as for doses.
    static func daily(_ weighIns: [WeighIn], clock: DayClock) -> [WeightPoint] {
        var lowest: [DayKey: Double] = [:]
        for weighIn in weighIns where weighIn.kg.isFinite && weighIn.kg > 0 {
            let day = clock.day(of: weighIn)
            lowest[day] = min(lowest[day] ?? weighIn.kg, weighIn.kg)
        }
        return lowest.map { WeightPoint(day: $0.key, kg: $0.value) }.sorted { $0.day < $1.day }
    }

    /// (2) Every day from the first weigh-in to the last: a day with weigh-ins is its lowest, a day between two is on the
    /// straight line between them (MacroFactor: 151 on Monday and 150 on Wednesday give 150.5 on Tuesday,
    /// https://help.macrofactorapp.com/dashboard/weight_trend/).
    static func filled(_ daily: [WeightPoint]) -> [WeightPoint] {
        guard var previous = daily.first else { return [] }
        var out = [previous]
        for next in daily.dropFirst() {
            let gap = previous.day.distance(to: next.day)
            if gap > 1 {
                for step in 1..<gap {
                    let fraction = Double(step) / Double(gap)
                    out.append(WeightPoint(day: previous.day.adding(step), kg: previous.kg + (next.kg - previous.kg) * fraction))
                }
            }
            out.append(next)
            previous = next
        }
        return out
    }

    /// (3) The trend on every day from the first weigh-in to the last: it starts at the first weigh-in, then
    /// T(n) = T(n-1) + 0.1 x (W(n) - T(n-1)). (4) Nothing past the last weigh-in: no line, no forecast.
    static func trend(_ weighIns: [WeighIn], clock: DayClock) -> [WeightPoint] {
        trend(daily: daily(weighIns, clock: clock))
    }

    static func trend(daily: [WeightPoint]) -> [WeightPoint] {
        var trend: Double?
        return filled(daily).map { point in
            let next = trend.map { $0 + smoothing * (point.kg - $0) } ?? point.kg
            trend = next
            return WeightPoint(day: point.day, kg: next)
        }
    }

    /// How far the trend moved over the last `days` days up to its last day, in kilograms (negative is down). Nil until
    /// the trend is that long, so a change is never read off a few days.
    static func change(_ trend: [WeightPoint], days: Int) -> Double? {
        guard let first = trend.first, let last = trend.last else { return nil }
        let index = first.day.distance(to: last.day.adding(-days))
        guard index >= 0, index < trend.count, trend[index].day == last.day.adding(-days) else { return nil }
        return last.kg - trend[index].kg
    }

    /// Every change there is history for: 7, 30 and 90 days.
    static func changes(_ trend: [WeightPoint]) -> [WeightChange] {
        changeSpans.compactMap { days in change(trend, days: days).map { WeightChange(days: days, kg: $0) } }
    }
}

/// The trend's change over a span, one neutral arrow and a number, never red or green.
struct WeightChange: Hashable, Sendable {
    let days: Int
    let kg: Double

    init(days: Int, kg: Double) {
        self.days = days
        self.kg = kg
    }

    enum Direction: Sendable {
        case down
        case up
        case flat
    }

    /// As the number reads at one decimal in the unit: anything that rounds to 0.0 is flat.
    func direction(unit: WeightUnit) -> Direction {
        let shown = (unit.value(fromKilograms: kg) * 10).rounded() / 10
        if shown < 0 { return .down }
        if shown > 0 { return .up }
        return .flat
    }

    /// "7 days"
    var label: String { "\(days) days" }

    /// "arrow.down", "arrow.up", "arrow.right"
    func symbol(unit: WeightUnit) -> String {
        switch direction(unit: unit) {
        case .down: return "arrow.down"
        case .up: return "arrow.up"
        case .flat: return "arrow.right"
        }
    }

    /// "1.2 kg", without a sign: the arrow carries it.
    func amount(unit: WeightUnit, locale: Locale = .current) -> String {
        "\(WeightFormat.trend(abs(kg), unit: unit, locale: locale)) \(unit.symbol)"
    }

    /// "Down 1.2 kilograms over 30 days", for VoiceOver.
    func spoken(unit: WeightUnit, locale: Locale = .current) -> String {
        let amount = WeightFormat.trend(abs(kg), unit: unit, locale: locale)
        switch direction(unit: unit) {
        case .down: return "Down \(amount) \(unit.spoken) over \(days) days"
        case .up: return "Up \(amount) \(unit.spoken) over \(days) days"
        case .flat: return "No change over \(days) days"
        }
    }
}

// MARK: - The chart

/// The days a weekly dose was logged: a small unlabelled tick on the chart's baseline, as the GLP-1 trackers mark doses
/// on their weight charts. Only items on a Weekly schedule (a one-day Days set, how Taken starts Semaglutide and
/// Tirzepatide) on the day the dose was logged, never a drug name.
enum WeightTicks {
    static func days(engine: StackEngine) -> [DayKey] {
        let items = Dictionary(engine.state.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var days = Set<DayKey>()
        for dose in engine.state.doses {
            guard let item = items[dose.itemId] else { continue }
            let day = engine.clock.day(of: dose)
            if engine.isWeekly(item, on: day) { days.insert(day) }
        }
        return days.sorted()
    }
}

/// What the chart shows for a range: the days in view, the trend and the weigh-ins inside them, the dose ticks, and a y
/// axis fitted to them with padding that never starts at zero.
struct WeightWindow: Hashable, Sendable {
    let firstDay: DayKey
    let lastDay: DayKey
    let trend: [WeightPoint]
    /// Every weigh-in in view, on its day (several on one day stack up).
    let dots: [WeightPoint]
    let ticks: [DayKey]
    /// The y axis, in kilograms.
    let lower: Double
    let upper: Double
    /// The goal, in kilograms, and whether the y axis takes it in. It joins only if the padded span with it is at most twice
    /// the span without it, so the data always keeps at least half the plot (own rule); otherwise its label is pinned to
    /// the edge and nothing squashes the line.
    let goalKg: Double?
    let goalInDomain: Bool

    /// The least the y axis is padded by, either side, in kilograms (own choice).
    static let minimumPadding = 0.4

    var isEmpty: Bool { dots.isEmpty && trend.isEmpty }

    /// The y axis around `low` and `high`: 15% of the span, at least `minimumPadding`, never below zero.
    static func padded(low: Double, high: Double) -> (lower: Double, upper: Double) {
        let padding = max(minimumPadding, (high - low) * 0.15)
        return (max(0, low - padding), high + padding)
    }

    static func make(weighIns: [WeighIn], trend: [WeightPoint], ticks: [DayKey], range: WeightRange, today: DayKey,
                     clock: DayClock, goalKg: Double? = nil) -> WeightWindow {
        let days = weighIns.map { clock.day(of: $0) }
        let lastDay = max(today, days.max() ?? today)
        var firstDay = range.days.map { lastDay.adding(-($0 - 1)) } ?? (days.min() ?? lastDay)
        // At least a week across, so a single weigh-in is not a dot against the edge.
        if firstDay.distance(to: lastDay) < 6 { firstDay = lastDay.adding(-6) }
        func inView(_ day: DayKey) -> Bool { day >= firstDay && day <= lastDay }
        let dots = zip(weighIns, days).filter { inView($0.1) }.map { WeightPoint(day: $0.1, kg: $0.0.kg) }
            .sorted { $0.day < $1.day }
        let shownTrend = trend.filter { inView($0.day) }
        let values = dots.map(\.kg) + shownTrend.map(\.kg)
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        var bounds = padded(low: low, high: high)
        var goalInDomain = false
        if let goalKg, !values.isEmpty {
            let with = padded(low: min(low, goalKg), high: max(high, goalKg))
            if with.upper - with.lower <= 2 * (bounds.upper - bounds.lower) + 1e-9 {
                bounds = with
                goalInDomain = true
            }
        }
        return WeightWindow(firstDay: firstDay, lastDay: lastDay, trend: shownTrend, dots: dots,
                            ticks: ticks.filter(inView), lower: bounds.lower, upper: bounds.upper, goalKg: goalKg,
                            goalInDomain: goalInDomain)
    }

    /// Whether a day is inside the window.
    func contains(_ day: DayKey) -> Bool { day >= firstDay && day <= lastDay }
}

// MARK: - Taken Pro

/// Weigh-ins follow the rule doses and voice to-dos follow (PRO.md): the first weigh-in ever needs no Pro; after it,
/// logging, editing, backdating and importing need it. The chart, the trend, All weigh-ins and the CSV export never do.
enum WeightGate {
    static func access(firstWeighInAt: Date?, status: ProStatus?, settled: Bool, legacyLog: Bool, now: Date) -> ProAccess {
        ProGate.access(status: status, settled: settled, legacyLog: legacyLog, hasLogged: firstWeighInAt != nil, now: now)
    }
}

// MARK: - The offer on Today

/// "Log your weight here too: add a Weight tab", once: only to a stack with an active Semaglutide, Tirzepatide or Oral
/// Semaglutide item whose dose has been logged, on a day everything due is taken, on a later day than the first dose and
/// than the widget invite's day (so never in the first session), while the tab was never chosen and the offer never
/// answered. `TodayPrompts.pick` puts it after every other row, and never while locked.
enum WeightOffer {
    /// Semaglutide, Tirzepatide, Oral Semaglutide (Catalog codes; their brand names typed in full map to these).
    static let medicineCodes: Set<String> = ["SEM", "TRZ", "OSM"]

    static func shows(weight: WeightState, state: StackState, today: DaySummary, clock: DayClock) -> Bool {
        guard weight.showsTab == nil, !weight.offerAnswered, today.allTaken else { return false }
        let medicines = Set(state.items.filter { !$0.archived && medicineCodes.contains($0.code.uppercased()) }.map(\.id))
        guard !medicines.isEmpty, state.doses.contains(where: { medicines.contains($0.itemId) }) else { return false }
        guard let first = state.doses.min(by: { $0.takenAt < $1.takenAt }), clock.day(of: first) < today.day else {
            return false
        }
        // The widget invite has had its day: shown on an earlier day, or answered without showing (a Lock Screen widget
        // already there). Until then it comes first, and never on the same day as this.
        if let inviteDay = state.settings.widgetInviteDay { return inviteDay < today.day.ordinal }
        return state.settings.widgetInviteDone
    }
}

extension TodayPrompts {
    /// `pick` with the Weight tab's one-time offer after the trial notice, the nudge offer, the repair and the widget
    /// invite. `weightOffer` is `WeightOffer.shows`. None while locked, as for the others.
    static func pick(settings: StackSettings, hasStack: Bool, today: DaySummary, repairDay: DayKey?, locked: Bool,
                     lockScreenWidget: Bool, trialNotice: String?, weightOffer: Bool) -> TodayPrompt? {
        if let prompt = pick(settings: settings, hasStack: hasStack, today: today, repairDay: repairDay, locked: locked,
                             lockScreenWidget: lockScreenWidget, trialNotice: trialNotice) {
            return prompt
        }
        guard hasStack, !locked, weightOffer else { return nil }
        return .weightOffer
    }
}

// MARK: - CSV

/// Profile > Data > Export weight CSV: taken-weight.csv, one row per weigh-in, oldest first, in local wall-clock time.
enum WeightCSV {
    static let fileName = "taken-weight.csv"
    static let header = "date,time,kg"

    static func make(_ weighIns: [WeighIn], timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var lines = [header]
        for weighIn in weighIns.sorted(by: { $0.weighedAt < $1.weighedAt }) {
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: weighIn.weighedAt)
            let date = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            lines.append("\(date),\(time),\(kilograms(weighIn.kg))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// "88.35", "88.0", "88.269": up to three decimals, so a weigh-in typed in pounds comes back to the same tenth.
    static func kilograms(_ kg: Double) -> String {
        var text = String(format: "%.3f", kg)
        while text.hasSuffix("0") && !text.hasSuffix(".0") { text.removeLast() }
        return text
    }
}

/// Profile > Data > Import weight CSV: history from another app (MyNetDiary's Data Export, Weigh In, Libra) or Taken's own
/// taken-weight.csv. It reads a date column and a weight column in kilograms or pounds, by their headers: the unit from
/// the weight header ("Weight (kg)", "lbs") or from the cells ("88.35 kg"), else the person's own unit, which the result
/// names. An optional time column; a row with a date alone is noon, as Happy Scale records a day's weight. Commas,
/// semicolons or tabs; a decimal point or comma; ISO dates, day or month first (worked out from the whole column, then
/// the locale), and "21 Oct 2026" or "Oct 21, 2026". A row it cannot read, a weight outside the bounds or a moment still
/// to come is skipped and counted.
enum WeightImport {
    struct Parsed: Equatable, Sendable {
        var weighIns: [WeighIn]
        /// The unit the weights were read in.
        var unit: WeightUnit
        /// Rows with something in them that could not be read.
        var unreadable: Int
    }

    enum Failure: Error, Equatable, Sendable {
        /// No date column and weight column side by side.
        case noColumns
        /// Columns found, but not one row could be read.
        case nothingReadable
    }

    /// The minute a weigh-in falls in: two weigh-ins in the same minute are the same one (`WeightState.merge`).
    static func minute(_ date: Date) -> Int {
        Int((date.timeIntervalSince1970 / 60).rounded(.down))
    }

    /// Text from a file: UTF-8 (with or without its byte order mark), UTF-16 with a byte order mark, else Latin-1.
    static func text(from data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16)
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: .isoLatin1)
    }

    static func parse(_ text: String, fallbackUnit: WeightUnit, locale: Locale = .current,
                      timeZone: TimeZone = .current, now: Date = Date()) -> Result<Parsed, Failure> {
        let cleaned = text.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = cleaned.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // The header may sit under a title line or two.
        var found: (line: Int, delimiter: Character, columns: Columns)?
        for (index, line) in lines.prefix(12).enumerated() where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let delimiter = Self.delimiter(of: line)
            if let columns = Columns(header: split(line, delimiter: delimiter)) {
                found = (index, delimiter, columns)
                break
            }
        }
        guard let parser = DateParser(timeZone: timeZone) else { return .failure(.noColumns) }
        let rows: [[String]]
        let columns: Columns
        if let found {
            columns = found.columns
            rows = lines.dropFirst(found.line + 1).map { split($0, delimiter: found.delimiter) }
        } else {
            // No header: two columns, a date and a number, in the person's unit.
            guard let first = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
                return .failure(.noColumns)
            }
            let delimiter = Self.delimiter(of: first)
            let cells = split(first, delimiter: delimiter)
            guard cells.count >= 2, parser.looksLikeDate(cells[0]), number(in: cells[1]) != nil else {
                return .failure(.noColumns)
            }
            columns = Columns(date: 0, time: nil, weight: 1, unit: nil)
            rows = lines.map { split($0, delimiter: delimiter) }
        }

        let filled = rows.filter { row in row.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        let order = parser.order(for: filled.compactMap { $0.indices.contains(columns.date) ? $0[columns.date] : nil },
                                 locale: locale)
        var unreadable = 0
        var byMinute: [Int: WeighIn] = [:]
        var unitUsed = columns.unit ?? fallbackUnit
        for row in filled {
            guard row.indices.contains(columns.date), row.indices.contains(columns.weight),
                  let reading = number(in: row[columns.weight]) else {
                unreadable += 1
                continue
            }
            let unit = reading.unit ?? columns.unit ?? fallbackUnit
            let time = columns.time.flatMap { row.indices.contains($0) ? row[$0] : nil }
            guard unit.bounds.contains(reading.value),
                  let moment = parser.moment(date: row[columns.date], time: time, order: order),
                  moment.date <= now.addingTimeInterval(60) else {
                unreadable += 1
                continue
            }
            unitUsed = unit
            let weighIn = WeighIn(kg: unit.kilograms(from: reading.value), weighedAt: moment.date, utcOffset: moment.utcOffset)
            let key = minute(moment.date)
            // Two rows in the same minute (a date alone, twice): the lower stays, as the trend reads a day.
            if let kept = byMinute[key], kept.kg <= weighIn.kg { continue }
            byMinute[key] = weighIn
        }
        let weighIns = byMinute.values.sorted { $0.weighedAt < $1.weighedAt }
        guard !weighIns.isEmpty else { return .failure(.nothingReadable) }
        return .success(Parsed(weighIns: weighIns, unit: unitUsed, unreadable: unreadable))
    }

    // MARK: Columns

    struct Columns: Equatable, Sendable {
        let date: Int
        let time: Int?
        let weight: Int
        let unit: WeightUnit?

        init(date: Int, time: Int?, weight: Int, unit: WeightUnit?) {
            self.date = date
            self.time = time
            self.weight = weight
            self.unit = unit
        }

        /// A header row with a date column and a weight column, or nil.
        init?(header: [String]) {
            let names = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            guard let date = names.firstIndex(where: Columns.isDate),
                  let weight = names.indices.first(where: { $0 != date && Columns.isWeight(names[$0]) }) else { return nil }
            self.date = date
            self.weight = weight
            self.time = names.indices.first { $0 != date && $0 != weight && Columns.isTime(names[$0]) }
            self.unit = WeightImport.unit(named: names[weight])
        }

        /// "date", "Date/Time", "Timestamp", "Day"; "Datum", "Fecha", "Data" from a spreadsheet in another language.
        static func isDate(_ name: String) -> Bool {
            ["date", "datum", "fecha", "timestamp"].contains(where: { name.contains($0) })
                || ["day", "data", "when", "jour", "giorno"].contains(name)
        }

        static func isTime(_ name: String) -> Bool {
            name == "time" || (name.contains("time") && !name.contains("stamp") && !name.contains("zone"))
        }

        /// "weight", "Weight (kg)", "Body Weight, lbs", "kg", "Gewicht (kg)"; never a goal, a trend, a change, fat, lean
        /// mass, BMI or a percentage.
        static func isWeight(_ name: String) -> Bool {
            let excluded = ["goal", "target", "trend", "change", "fat", "lean", "bmi", "index", "muscle", "bone", "water",
                            "%", "diff", "delta", "average", "avg", "moving", "smooth", "loss", "gain", "note"]
            guard !excluded.contains(where: { name.contains($0) }) else { return false }
            let words = ["weight", "mass", "gewicht", "peso", "poids", "vikt", "vekt"]
            return words.contains(where: { name.contains($0) }) || WeightImport.unit(named: name) != nil
        }
    }

    /// The unit a header or a cell names: kg, kgs, kilograms; lb, lbs, pounds. Nil for neither.
    static func unit(named text: String) -> WeightUnit? {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        if words.contains(where: { $0 == "kg" || $0 == "kgs" || $0.hasPrefix("kilo") }) { return .kg }
        if words.contains(where: { $0 == "lb" || $0 == "lbs" || $0.hasPrefix("pound") }) { return .lb }
        return nil
    }

    /// A weight cell: "88.35", "88,35", "194.6 lbs", "\"88.35\"". The number and the unit it names, if any.
    static func number(in cell: String) -> (value: Double, unit: WeightUnit?)? {
        let trimmed = cell.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.prefix { $0.isNumber || $0 == "." || $0 == "," }
        guard !digits.isEmpty, let value = WeightFormat.parse(String(digits), locale: Locale(identifier: "en_US_POSIX"))
                ?? decimalComma(String(digits)) else { return nil }
        let rest = trimmed.dropFirst(digits.count).trimmingCharacters(in: .whitespaces)
        guard rest.isEmpty || rest.allSatisfy({ $0.isLetter || $0 == "." }) else { return nil }
        let unit = rest.isEmpty ? nil : unit(named: rest)
        if !rest.isEmpty && unit == nil { return nil }
        return (value, unit)
    }

    /// A value with more decimals than typing allows ("88.257" from another app's export): read as it is.
    private static func decimalComma(_ text: String) -> Double? {
        let parts = text.replacingOccurrences(of: ",", with: ".").split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.allSatisfy({ $0.allSatisfy(\.isNumber) }), let whole = parts.first, !whole.isEmpty
        else { return nil }
        return Double(parts.joined(separator: "."))
    }

    /// Commas, semicolons (Excel where the decimal point is a comma) or tabs, whichever the header uses most.
    static func delimiter(of line: String) -> Character {
        var counts: [Character: Int] = [",": 0, ";": 0, "\t": 0]
        var quoted = false
        for character in line {
            if character == "\"" { quoted.toggle() }
            if !quoted, counts[character] != nil { counts[character, default: 0] += 1 }
        }
        if counts["\t", default: 0] > 0 { return "\t" }
        return counts[";", default: 0] > counts[",", default: 0] ? ";" : ","
    }

    /// One line's cells, with double quotes around a cell that holds the delimiter (RFC 4180).
    static func split(_ line: String, delimiter: Character) -> [String] {
        var cells: [String] = []
        var cell = ""
        var quoted = false
        var iterator = Array(line).makeIterator()
        var pending: Character? = iterator.next()
        while let character = pending {
            pending = iterator.next()
            if character == "\"" {
                if quoted && pending == "\"" {
                    cell.append("\"")
                    pending = iterator.next()
                } else {
                    quoted.toggle()
                }
            } else if character == delimiter && !quoted {
                cells.append(cell)
                cell = ""
            } else {
                cell.append(character)
            }
        }
        cells.append(cell)
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: Dates

    /// Which comes first in a date like 03/04/2026.
    enum DateOrder: Sendable {
        case dayFirst
        case monthFirst
    }

    /// A moment from a date cell and an optional time cell, in the time zone given unless the cell names its own.
    struct DateParser {
        let calendar: Calendar
        private let iso: NSRegularExpression
        private let numeric: NSRegularExpression
        private let dayName: NSRegularExpression
        private let nameDay: NSRegularExpression
        private let clock: NSRegularExpression

        private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

        /// Nil only if a pattern fails to compile, which the tests would catch: the patterns are fixed.
        init?(timeZone: TimeZone) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            self.calendar = calendar
            func regex(_ pattern: String) -> NSRegularExpression? {
                try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            }
            let time = #"(?:[ T,]+(\d{1,2}:\d{2}(?::\d{2})?(?:\.\d+)?\s*(?:[ap]\.?m\.?)?))?"#
            guard let iso = regex(#"^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})"# + time + #"\s*(z|[+-]\d{2}:?\d{2})?$"#),
                  let numeric = regex(#"^(\d{1,2})[-/.](\d{1,2})[-/.](\d{4}|\d{2})"# + time + "$"),
                  let dayName = regex(#"^(?:[a-z]+\.?,?\s+)?(\d{1,2})(?:st|nd|rd|th)?[\s-]+([a-z]{3,})\.?,?[\s-]+(\d{4})"#
                                      + time + "$"),
                  let nameDay = regex(#"^(?:[a-z]+\.?,?\s+)?([a-z]{3,})\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})"#
                                      + time + "$"),
                  let clock = regex(#"^(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?\s*([ap])?\.?(?:m\.?)?$"#) else {
                return nil
            }
            self.iso = iso
            self.numeric = numeric
            self.dayName = dayName
            self.nameDay = nameDay
            self.clock = clock
        }

        func looksLikeDate(_ text: String) -> Bool {
            moment(date: text, time: nil, order: .dayFirst) != nil || moment(date: text, time: nil, order: .monthFirst) != nil
        }

        /// Day or month first for a numeric column: a first number over 12 means day first, a second over 12 month
        /// first; with neither (every date 12 or under), the locale's own order.
        func order(for cells: [String], locale: Locale) -> DateOrder {
            var dayFirst = false
            var monthFirst = false
            for cell in cells {
                guard let match = numeric.firstMatch(in: cell, range: NSRange(cell.startIndex..., in: cell)),
                      let a = int(cell, match, 1), let b = int(cell, match, 2) else { continue }
                if a > 12 { dayFirst = true }
                if b > 12 { monthFirst = true }
            }
            if dayFirst != monthFirst { return dayFirst ? .dayFirst : .monthFirst }
            let pattern = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: locale) ?? "M/d/y"
            let day = pattern.firstIndex(of: "d")
            let month = pattern.firstIndex(of: "M")
            if let day, let month, day < month { return .dayFirst }
            return .monthFirst
        }

        func moment(date text: String, time timeText: String?, order: DateOrder) -> (date: Date, utcOffset: Int)? {
            let cell = text.trimmingCharacters(in: .whitespaces)
            let range = NSRange(cell.startIndex..., in: cell)
            var year: Int
            var month: Int
            var day: Int
            var clockText: String?
            var zone: TimeZone?
            if let match = iso.firstMatch(in: cell, range: range) {
                guard let y = int(cell, match, 1), let m = int(cell, match, 2), let d = int(cell, match, 3) else { return nil }
                (year, month, day) = (y, m, d)
                clockText = string(cell, match, 4)
                if let offset = string(cell, match, 5) { zone = Self.zone(offset) }
            } else if let match = numeric.firstMatch(in: cell, range: range) {
                guard let a = int(cell, match, 1), let b = int(cell, match, 2), let y = int(cell, match, 3) else { return nil }
                (day, month) = order == .dayFirst ? (a, b) : (b, a)
                year = y < 100 ? 2000 + y : y
                clockText = string(cell, match, 4)
            } else if let match = dayName.firstMatch(in: cell, range: range) {
                guard let d = int(cell, match, 1), let m = monthNumber(string(cell, match, 2)), let y = int(cell, match, 3)
                else { return nil }
                (year, month, day) = (y, m, d)
                clockText = string(cell, match, 4)
            } else if let match = nameDay.firstMatch(in: cell, range: range) {
                guard let m = monthNumber(string(cell, match, 1)), let d = int(cell, match, 2), let y = int(cell, match, 3)
                else { return nil }
                (year, month, day) = (y, m, d)
                clockText = string(cell, match, 4)
            } else {
                return nil
            }
            // A separate time column wins over a time inside the date cell; a date alone is noon.
            var hour = 12
            var minute = 0
            var second = 0
            let timeCell = timeText?.trimmingCharacters(in: .whitespaces)
            if let written = timeCell?.isEmpty == false ? timeCell : clockText {
                guard let parsed = hourMinute(written) else { return nil }
                (hour, minute, second) = parsed
            }
            var calendar = self.calendar
            if let zone { calendar.timeZone = zone }
            let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
            guard (1...12).contains(month), (1...31).contains(day), (1900...2999).contains(year),
                  let date = calendar.date(from: components) else { return nil }
            // 31 February would roll into March: not a date.
            let back = calendar.dateComponents([.year, .month, .day], from: date)
            guard back.year == year, back.month == month, back.day == day else { return nil }
            return (date, calendar.timeZone.secondsFromGMT(for: date))
        }

        /// "07:42", "7:42 AM", "19:05:30": hours, minutes and seconds on the 24-hour clock.
        func hourMinute(_ text: String) -> (Int, Int, Int)? {
            let cell = text.trimmingCharacters(in: .whitespaces)
            guard let match = clock.firstMatch(in: cell, range: NSRange(cell.startIndex..., in: cell)),
                  var hour = int(cell, match, 1), let minute = int(cell, match, 2), minute < 60 else { return nil }
            let second = int(cell, match, 3) ?? 0
            if let half = string(cell, match, 4)?.lowercased() {
                guard (1...12).contains(hour) else { return nil }
                if half == "p" && hour < 12 { hour += 12 }
                if half == "a" && hour == 12 { hour = 0 }
            }
            guard hour < 24, second < 60 else { return nil }
            return (hour, minute, second)
        }

        private func monthNumber(_ name: String?) -> Int? {
            guard let name = name?.lowercased(), name.count >= 3 else { return nil }
            return Self.months.firstIndex(of: String(name.prefix(3))).map { $0 + 1 }
        }

        private static func zone(_ text: String) -> TimeZone? {
            let lower = text.lowercased()
            if lower == "z" { return TimeZone(secondsFromGMT: 0) }
            let digits = lower.filter(\.isNumber)
            guard digits.count == 4, let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)) else { return nil }
            let seconds = (hours * 60 + minutes) * 60
            return TimeZone(secondsFromGMT: lower.hasPrefix("-") ? -seconds : seconds)
        }

        private func string(_ text: String, _ match: NSTextCheckingResult, _ group: Int) -> String? {
            guard group < match.numberOfRanges, let range = Range(match.range(at: group), in: text) else { return nil }
            return String(text[range])
        }

        private func int(_ text: String, _ match: NSTextCheckingResult, _ group: Int) -> Int? {
            string(text, match, group).flatMap { Int($0) }
        }
    }
}

// MARK: - Copy

/// Every word the Weight tab shows. Weight, Trend and weigh-in; never lose, ideal or goal.
enum WeightCopy {
    static let tab = "Weight"
    /// The tab's SF Symbol.
    static let symbol = "scalemass"
    static let noWeighIns = "No weigh-ins yet"
    /// The bar above the decimal pad: Tom's word.
    static let weighIn = "Weigh in"
    static let save = "Save"
    static let trend = "Trend"
    static let trendCaption = "smooths daily swings"
    /// Screen two under its single dot, after the first weigh-in.
    static let trendStarts = "Your trend starts here."
    /// The chevron at the bottom of screen one, for VoiceOver.
    static let showTrend = "Show trend"
    /// The long-press menu on today's number, and its VoiceOver actions.
    static let edit = "Edit\u{2026}"
    static let delete = "Delete"
    static let editWeighIn = "Edit weigh-in"
    static let ticks = "Ticks: weekly doses"
    static let emptyRange = "No weigh-ins in this range"
    static let allWeighIns = "All weigh-ins"
    static let more = "More"
    static let hideTab = "Hide Weight Tab"
    /// The toast after Hide Weight Tab, on Today, with UNDO.
    static let hidden = "Weight tab hidden. Profile brings it back."
    /// The toast after a weigh-in is saved, with UNDO.
    static let weighedIn = "Weighed in"
    static let deleted = "Weigh-in deleted"
    static let updated = "Weigh-in updated"
    static let offer = "Log your weight here too: add a Weight tab"
    static let addTab = "Add tab"
    static let notNow = "Not now"
    static let profileSection = "Weight"
    static let profileSwitch = "Weight tab"
    static let profileFootnote = "Log your weight and see a smoothed trend. Kept on this iPhone."
    static let exportCSV = "Export weight CSV"
    static let importCSV = "Import weight CSV"
    static let editTitle = "Weigh-in"
    static let weightField = "Weight"
    static let when = "When"
    static let deleteWeighIn = "Delete weigh-in"
    static let couldNotSave = "Could not save. Try again."
    static let notFound = "No weigh-ins found. Taken reads a date column and a weight column in kg or lb."
    static let couldNotOpen = "Could not open that file."
    /// The field's VoiceOver hints.
    static let typeHint = "Double-tap to type today's weight."
    static let anotherHint = "Double-tap to log another weigh-in."
    static let lockedHint = "Logging needs Taken Pro. Opens Taken Pro."
    /// The field's label once today has a weigh-in.
    static let todaysWeighIn = "Today's weigh-in"

    /// The field's label: "Today's weight in kilograms", "Today's weight in pounds".
    static func fieldLabel(_ unit: WeightUnit) -> String { "Today's weight in \(unit.spoken)" }

    /// While typing, a finished-looking number outside the bounds: "Between 20 and 350 kg", "Between 44 and 770 lb".
    static func rangeHint(_ unit: WeightUnit) -> String {
        "Between \(Int(unit.bounds.lowerBound)) and \(Int(unit.bounds.upperBound)) \(unit.symbol)"
    }

    /// "Between 20 and 350 kilograms"
    static func spokenRangeHint(_ unit: WeightUnit) -> String {
        "Between \(Int(unit.bounds.lowerBound)) and \(Int(unit.bounds.upperBound)) \(unit.spoken)"
    }

    /// Under the big number: "Last weigh-in yesterday, 07:42", "Last weigh-in Tuesday, 07:42", "Last weigh-in 14 Oct,
    /// 07:42", "Last weigh-in 3 Mar 2025, 07:42". It never counts missed days.
    static func lastLine(_ weighIn: WeighIn?, now: Date, clock: DayClock) -> String {
        guard let weighIn else { return noWeighIns }
        return "Last weigh-in \(dayWord(clock.day(of: weighIn), today: clock.day(for: now), clock: clock)), \(Fmt.clock(weighIn.weighedAt, clock))"
    }

    /// The small line for VoiceOver, with the number the grey digits show: "Last weigh-in 88.35 kilograms, yesterday at
    /// 07:42"; on a day already weighed in, "Last weigh-in today at 07:06".
    static func spokenLastLine(_ weighIn: WeighIn?, unit: WeightUnit, now: Date, clock: DayClock, locale: Locale = .current) -> String {
        guard let weighIn else { return noWeighIns }
        let day = clock.day(of: weighIn)
        let today = clock.day(for: now)
        let time = Fmt.clock(weighIn.weighedAt, clock)
        if day == today { return "Last weigh-in today at \(time)" }
        return "Last weigh-in \(WeightFormat.spoken(weighIn.kg, unit: unit, locale: locale)), \(dayWord(day, today: today, clock: clock)) at \(time)"
    }

    /// "today", "yesterday", "Tuesday" this past week, then "14 Oct", and "14 Oct 2025" from another year.
    static func dayWord(_ day: DayKey, today: DayKey, clock: DayClock) -> String {
        let gap = day.distance(to: today)
        switch gap {
        case 0: return "today"
        case 1: return "yesterday"
        case 2..<7: return Fmt.weekday(day)
        default:
            return Fmt.shortDate(clock.noon(of: day), year: day.ymd.year != today.ymd.year, timeZone: clock.calendar.timeZone)
        }
    }

    /// A row in All weigh-ins: "Today", "Yesterday", "Tue 20 Oct", and "Mon 3 Mar 2025" from another year.
    static func listDay(_ day: DayKey, today: DayKey) -> String {
        switch day.distance(to: today) {
        case 0: return "Today"
        case 1: return "Yesterday"
        default:
            let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            let (year, month, dayOfMonth) = day.ymd
            let base = "\(weekdays[day.mondayIndex]) \(dayOfMonth) \(months[max(0, min(11, month - 1))])"
            return year == today.ymd.year ? base : "\(base) \(year)"
        }
    }

    /// The result of an import: "Added 214 weigh-ins, read in kg." with what was already in Taken and what could not
    /// be read after it.
    static func imported(added: Int, already: Int, unreadable: Int, unit: WeightUnit) -> String {
        var parts: [String] = []
        if added > 0 {
            parts.append("Added \(added) \(added == 1 ? "weigh-in" : "weigh-ins"), read in \(unit.symbol).")
            if already > 0 { parts.append("\(already) \(already == 1 ? "was" : "were") already in Taken.") }
        } else {
            parts.append("Nothing new: \(already == 1 ? "that weigh-in is" : "those \(already) weigh-ins are") already in Taken.")
        }
        if unreadable > 0 { parts.append("\(unreadable) \(unreadable == 1 ? "row" : "rows") could not be read.") }
        return parts.joined(separator: " ")
    }

    /// The chart's first sentence for VoiceOver: "Trend 88.1 kilograms."
    static func spokenTrend(_ trendKg: Double?, unit: WeightUnit, locale: Locale = .current) -> String {
        guard let trendKg else { return "\(noWeighIns)." }
        return "Trend \(WeightFormat.trend(trendKg, unit: unit, locale: locale)) \(unit.spoken)."
    }

    /// The chart for VoiceOver, with the selected range's change: "Trend 88.1 kilograms. Down 1.2 kilograms over 30 days."
    /// The goal's clauses (`WeightGoalCopy`) go in between when there is a goal.
    static func chartSummary(trendKg: Double?, change: String?, unit: WeightUnit, locale: Locale = .current) -> String {
        [spokenTrend(trendKg, unit: unit, locale: locale), change.map { "\($0)." }].compactMap { $0 }.joined(separator: " ")
    }

    /// Every fixed line, for the copy rules test.
    static var all: [String] {
        [tab, noWeighIns, weighIn, save, trend, trendCaption, trendStarts, showTrend, edit, delete, editWeighIn, ticks,
         emptyRange, allWeighIns, more, hideTab, hidden,
         weighedIn, deleted, updated, offer, addTab, notNow, profileSection, profileSwitch, profileFootnote, exportCSV,
         importCSV, editTitle, weightField, when, deleteWeighIn, couldNotSave, notFound, couldNotOpen, typeHint, anotherHint,
         lockedHint, todaysWeighIn,
         imported(added: 214, already: 3, unreadable: 2, unit: .kg), imported(added: 0, already: 5, unreadable: 0, unit: .lb)]
            + WeightUnit.allCases.map(\.menuTitle) + WeightRange.allCases.map(\.spoken)
            + WeightUnit.allCases.flatMap { [fieldLabel($0), rangeHint($0), spokenRangeHint($0)] }
    }
}

// MARK: - Demo

/// `-demo` screens for the Weight tab (CI screenshots only; REDESIGN.md, "Weight tab page: entry first"): screen one as
/// it opens (`weight`), typing (`weight-entry`, `weight-entry-range`), never weighed in (`weight-empty`), weighed in today
/// (`weight-weighed`), locked (`weight-locked`), in pounds (`weight-lb`); screen two (`weight-first`, `weight-trend`);
/// All weigh-ins (`weight-list`); Profile at the Weight switch and the CSV rows (`weight-settings`, `weight-data`); the
/// goal's (`weight-goal`, `weight-goal-saved`, `weight-goal-moment`, `weight-goal-reached`, `weight-goal-reached-moment`,
/// `weight-goal-sheet`, `weight-goal-low`); and `today-weight-offer`.
enum WeightDemo {
    static let pageScreens = ["weight", "weight-entry", "weight-entry-range", "weight-empty", "weight-first", "weight-weighed",
                              "weight-trend", "weight-locked", "weight-lb", "weight-list", "weight-settings", "weight-data"]
    static let goalScreens = ["weight-goal", "weight-goal-saved", "weight-goal-moment", "weight-goal-reached",
                              "weight-goal-reached-moment", "weight-goal-sheet", "weight-goal-low"]

    /// The screens that open on the Weight tab.
    static func opensOnWeight(_ screen: String?) -> Bool {
        guard let screen else { return false }
        return pageScreens.contains(screen) || goalScreens.contains(screen)
    }

    /// The goal screens: Tom-like history from 97.8 kg, the goal 87.0 and 180 cm (`DemoData.goalWeighIns`).
    static func hasGoal(_ screen: String?) -> Bool { screen.map(goalScreens.contains) ?? false }

    /// The goal's history six weeks on, down to about 86.8 and holding.
    static func goalReached(_ screen: String?) -> Bool {
        screen == "weight-goal-reached" || screen == "weight-goal-reached-moment"
    }

    /// The Goal sheet opens over the tab.
    static func opensGoalSheet(_ screen: String?) -> Bool { screen == "weight-goal-sheet" || screen == "weight-goal-low" }

    /// What the goal field holds on `weight-goal-low`.
    static func typedGoal(_ screen: String?) -> String? { screen == "weight-goal-low" ? "55.0" : nil }

    /// What the entry screens type; the page takes focus 450 ms after it appears.
    static func draft(_ screen: String?) -> String? {
        switch screen {
        case "weight-entry": return "88.1"
        case "weight-entry-range": return "883"
        default: return nil
        }
    }

    /// The screens shown scrolled to screen two, 450 ms after the page appears.
    static func opensOnTrend(_ screen: String?) -> Bool {
        ["weight-first", "weight-trend", "weight-goal", "weight-goal-reached"].contains(screen ?? "")
    }

    /// The history includes a weigh-in today; elsewhere it ends yesterday, so the line reads "yesterday".
    static func includesToday(_ screen: String?) -> Bool {
        ["weight-weighed", "weight-list", "weight-settings", "weight-data"].contains(screen ?? "")
    }

    /// Pounds (`weight-lb`); every other capture is in kilograms, so they read the same everywhere.
    static func unit(_ screen: String?) -> WeightUnit { screen == "weight-lb" ? .lb : .kg }

    /// The tab is on for every Weight screen and off everywhere else, so the other captures still show the default app.
    static func showsTab(_ screen: String?) -> Bool { opensOnWeight(screen) }

    /// Weigh-ins everywhere the tab is on but `weight-empty`.
    static func hasWeighIns(_ screen: String?) -> Bool { opensOnWeight(screen) && screen != "weight-empty" }

    /// A weekly shot in the stack, for the chart's dose ticks and the offer's medicine.
    static func addsWeeklyShot(_ screen: String?) -> Bool { hasWeighIns(screen) || screen == "today-weight-offer" }

    /// Today with everything taken, as the offer needs.
    static func allTaken(_ screen: String?) -> Bool { screen == "today-weight-offer" }
}

#endif
