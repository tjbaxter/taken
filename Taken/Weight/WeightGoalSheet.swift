import SwiftUI

/// Set Goal or Change Goal, from the Weight tab's More menu and nowhere else (REDESIGN.md, "Goal and moments"): the goal
/// in a field like the big number's, the start (the first weigh-in day unless the trend has already been at the goal,
/// movable here), the height (asked only here, to keep goals at or above BMI 18.5), two footnotes and Save. No target date,
/// rate, plan, forecast or start-weight field. A goal below the floor shows one line in the look's muted ink, never red,
/// and no number. Logging a weigh-in does not change at all.
struct WeightGoalSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.theme) private var theme

    @State private var text = ""
    @FocusState private var focused: Bool
    /// The start the person picked in the Start row; until then the start follows the rules as the goal is typed.
    @State private var pickedDay: DayKey?
    @State private var startPicked = false
    /// The height in this sheet: the stored one, or what the wheel set. Kept only on Save.
    @State private var heightCm: Double?
    @State private var editingHeight = false
    @State private var loaded = false
    /// The content's own height: the sheet is as tall as what it holds.
    @State private var contentHeight: CGFloat = 520

    init() {}

    var body: some View {
        let weight = model.weight
        let unit = weight.unit
        let trend = WeightTrend.trend(weight.state.weighIns, clock: model.clock)
        let goalKg = typedKilograms(unit: unit)
        let start = startPoint(trend: trend, goalKg: goalKg)
        let blocked = goalKg.flatMap { kg in
            start.map { WeightGoals.floorBlocks(goalKg: kg, startKg: $0.kg, heightCm: heightCm ?? 0) }
        } ?? false
        let canSave = goalKg != nil && heightCm != nil && start != nil && !blocked
        VStack(spacing: 0) {
            SheetHeader(title: WeightGoalCopy.title) { dismiss() }
            field(unit: unit, placeholder: trend.last.map { WeightFormat.trend($0.kg, unit: unit, locale: locale) } ?? "")
            VStack(spacing: 0) {
                startRow(start: start, trend: trend, unit: unit)
                RowDivider()
                heightRow
            }
            .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                .strokeBorder(theme.line, lineWidth: 1))
            .padding(.horizontal, 20)
            .padding(.top, 12)
            VStack(alignment: .leading, spacing: 6) {
                footnote(WeightGoalCopy.footnote)
                footnote(WeightGoalCopy.heightFootnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 10)
            if blocked {
                Text(WeightGoalCopy.tooLow)
                    .font(.sans(15, .sans, relativeTo: .subheadline))
                    .foregroundStyle(theme.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
            }
            PrimaryButton(title: WeightGoalCopy.save, enabled: canSave) {
                guard let goalKg, let start else { return }
                save(goalKg: goalKg, startDay: start.day)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { contentHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, height in contentHeight = height }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(theme.bg)
        .onChange(of: text) { _, typed in
            let clean = WeightFormat.sanitize(typed, locale: locale, maxDecimals: 1)
            if clean != typed { text = clean }
        }
        .onAppear(perform: load)
        .task {
            // Focus once the sheet is up: a field inserted with the sheet takes focus after one main-actor hop.
            try? await Task.sleep(for: .milliseconds(80))
            focused = true
        }
        .sheet(isPresented: $editingHeight) {
            HeightWheelSheet(unit: HeightUnit.preferred(for: locale), centimetres: heightCm) { picked in
                heightCm = picked
            }
            .environment(\.theme, theme)
        }
    }

    // MARK: Pieces

    /// The goal's field: Geist Mono 44 in a raised box whose border lights while focused, the unit beside it,
    /// the decimal pad, one decimal at most. The placeholder is the current trend.
    private func field(unit: WeightUnit, placeholder: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(theme.fgFaint))
                .font(.mono(44, .monoMedium, relativeTo: .largeTitle))
                .foregroundStyle(theme.fg)
                .keyboardType(.decimalPad)
                .focused($focused)
                .lineLimit(1)
                .accessibilityLabel("Goal in \(unit.spoken)")
            Text(unit.symbol)
                .font(.sans(22, .sansMedium, relativeTo: .title2))
                .foregroundStyle(theme.fgMuted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
            .strokeBorder(focused ? theme.signalEdge : theme.line, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    /// "Start", the trend that day ("97.8 kg"), and a compact date picker limited to the weigh-in days.
    @ViewBuilder
    private func startRow(start: WeightPoint?, trend: [WeightPoint], unit: WeightUnit) -> some View {
        let clock = model.clock
        HStack(spacing: 10) {
            Text(WeightGoalCopy.start)
                .font(.sans(15, .sans, relativeTo: .subheadline))
                .foregroundStyle(theme.fgMuted)
            if let start {
                Text(WeightFormat.withUnit(start.kg, unit: unit, locale: locale))
                    .font(.mono(15, .monoMedium, relativeTo: .subheadline))
                    .foregroundStyle(theme.fg)
            }
            Spacer(minLength: 8)
            if let start, let first = trend.first, let last = trend.last {
                DatePicker(WeightGoalCopy.start,
                           selection: Binding(get: { clock.noon(of: start.day) },
                                              set: { date in
                                                  pickedDay = clock.day(for: date)
                                                  startPicked = true
                                              }),
                           in: clock.noon(of: first.day)...clock.noon(of: last.day),
                           displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .environment(\.locale, Locale(identifier: "en_GB"))
                    .tint(theme.signal)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    /// "Height" and Set, or the height with the wheel's chevrons once it is chosen.
    private var heightRow: some View {
        let unit = HeightUnit.preferred(for: locale)
        return HStack(spacing: 10) {
            Text(WeightGoalCopy.height)
                .font(.sans(15, .sans, relativeTo: .subheadline))
                .foregroundStyle(theme.fgMuted)
            Spacer(minLength: 8)
            Button {
                editingHeight = true
            } label: {
                if let heightCm {
                    HStack(spacing: 8) {
                        Text(unit.text(heightCm))
                            .font(.mono(15, .monoMedium, relativeTo: .subheadline))
                            .foregroundStyle(theme.fg)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.fgSubtle)
                    }
                    .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                    .contentShape(Rectangle())
                } else {
                    Text(WeightGoalCopy.setButton)
                        .font(.sans(15, .sansSemibold, relativeTo: .subheadline))
                        .foregroundStyle(theme.signalInk)
                        .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(WeightGoalCopy.height), \(heightCm.map(unit.spoken) ?? "not set")")
            .accessibilityHint("Double tap to choose.")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.sans(13, .sans, relativeTo: .footnote))
            .foregroundStyle(theme.fgSubtle)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Rules

    /// The typed goal in kilograms, inside the unit's bounds. A value left as the stored goal shows keeps its exact value.
    private func typedKilograms(unit: WeightUnit) -> Double? {
        guard let kg = WeightFormat.kilograms(text, unit: unit, locale: locale) else { return nil }
        if let existing = model.weight.goal, sameValue(kg, existing.kg, unit: unit) { return existing.kg }
        return kg
    }

    private func sameValue(_ a: Double, _ b: Double, unit: WeightUnit) -> Bool {
        WeightGoalCopy.goal(a, unit: unit, locale: locale) == WeightGoalCopy.goal(b, unit: unit, locale: locale)
    }

    /// The start (`WeightGoals.sheetStartDay`), clamped to the weigh-ins, and the trend that day.
    private func startPoint(trend: [WeightPoint], goalKg: Double?) -> WeightPoint? {
        guard let last = trend.last,
              let day = WeightGoals.sheetStartDay(existing: model.weight.goal, typedKg: goalKg, pickedDay: pickedDay,
                                                  trend: trend) else { return nil }
        return WeightGoals.start(of: WeightGoal(kg: goalKg ?? last.kg, startDay: day), trend: trend)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let weight = model.weight
        heightCm = weight.state.heightCm
        if let goal = weight.goal {
            text = WeightGoalCopy.goal(goal.kg, unit: weight.unit, locale: locale)
            startPicked = goal.startPicked
            if goal.startPicked { pickedDay = goal.startDay }
        }
        if let typed = weight.demoTypedGoal { text = typed }
    }

    private func save(goalKg: Double, startDay: DayKey) {
        model.saveWeightGoal(kg: goalKg, startDay: startDay, startPicked: startPicked, heightCm: heightCm)
        dismiss()
    }
}

/// The height on a wheel in a small sheet, built like TimeWheelSheet: centimetres (100 to 230), or feet (3 to 7) and
/// inches (0 to 11). It starts at the stored height, else 170 cm or 5 ft 7 in, and nothing is kept until Set.
struct HeightWheelSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    let unit: HeightUnit
    let onSet: (Double) -> Void

    @State private var centimetres: Int
    @State private var feet: Int
    @State private var inches: Int

    init(unit: HeightUnit, centimetres: Double?, onSet: @escaping (Double) -> Void) {
        self.unit = unit
        self.onSet = onSet
        let start = centimetres ?? HeightUnit.defaultCentimetres
        let clampedCm = min(max(Int(start.rounded()), HeightUnit.centimetreRange.lowerBound), HeightUnit.centimetreRange.upperBound)
        let imperial = centimetres.map(HeightUnit.feetInches(centimetres:)) ?? HeightUnit.defaultFeetInches
        _centimetres = State(initialValue: clampedCm)
        _feet = State(initialValue: min(max(imperial.feet, HeightUnit.feetRange.lowerBound), HeightUnit.feetRange.upperBound))
        _inches = State(initialValue: min(max(imperial.inches, 0), 11))
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: WeightGoalCopy.height) { dismiss() }
            HStack(spacing: 0) {
                switch unit {
                case .centimetres:
                    Picker(WeightGoalCopy.height, selection: $centimetres) {
                        ForEach(Array(HeightUnit.centimetreRange), id: \.self) { value in
                            Text("\(value) cm").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                case .feetInches:
                    Picker("Feet", selection: $feet) {
                        ForEach(Array(HeightUnit.feetRange), id: \.self) { value in
                            Text("\(value) ft").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    Picker("Inches", selection: $inches) {
                        ForEach(Array(HeightUnit.inchRange), id: \.self) { value in
                            Text("\(value) in").tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 4)
            PrimaryButton(title: WeightGoalCopy.setHeight(picked, unit: unit)) {
                onSet(picked)
                dismiss()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.height(400)])
        .presentationBackground(theme.bg)
        .preferredColorScheme(theme.scheme)
    }

    private var picked: Double {
        switch unit {
        case .centimetres: return Double(centimetres)
        case .feetInches: return HeightUnit.centimetres(feet: feet, inches: inches)
        }
    }
}
