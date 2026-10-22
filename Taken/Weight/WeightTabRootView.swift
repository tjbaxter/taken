import SwiftUI

#if DEBUG || TAKEN_INTERNAL
/// The Weight tab (SPEC 3.12; REDESIGN.md, "Weight tab, 2026-10-22" and "Goal and moments"): the last weigh-in under the
/// title, the trend as the headline with one slot line under it (the caption, how close the trend is to the goal, or for
/// one visit the sentence for a point just lit) and Log weigh-in, then the chart card with its ranges, the change line for
/// the range and weekly dose ticks, then All weigh-ins. Off until the person turns it on in Profile or from Today's
/// one-time offer; its More menu sets kilograms or pounds, sets, changes or clears the optional goal, and hides the tab,
/// with UNDO. Weight never shows on Today (apart from the offer), in the widgets, the control, Siri, the nudge, the streak
/// or History. Compiled only into Debug and the owner's internal builds until 1.2: this type's name is the marker
/// scripts/check-app-store-build.sh looks for, so an App Store build is proven not to contain the tab.
struct WeightTabRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    /// `-demo` only: where the chart card ends and where the tab bar begins, for the fit probe.
    @State private var chartBottom: CGFloat = 0
    @State private var visibleBottom: CGFloat = 0

    init() {}

    var body: some View {
        let weight = model.weight
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TabHeader(title: WeightCopy.tab,
                          subtitle: WeightCopy.lastLine(weight.state.last, unit: weight.unit, now: model.now,
                                                        clock: model.clock)) {
                    WeightMoreMenu()
                }
                if weight.isEmpty {
                    emptyCard
                        .padding(.top, 22)
                } else {
                    content(weight)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background {
            if model.isDemo {
                // The top of the tab bar: the scroll view's visible bottom less its bottom safe-area inset.
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { visibleBottom = proxy.frame(in: .global).maxY - proxy.safeAreaInsets.bottom }
                        .onChange(of: proxy.size) { _, _ in
                            visibleBottom = proxy.frame(in: .global).maxY - proxy.safeAreaInsets.bottom
                        }
                }
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { WeightToastDock() }
        .onAppear { weight.refresh() }
        // The sentence for a point just lit lasts one visit.
        .onDisappear { weight.justReached = nil }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { weight.justReached = nil }
        }
        .onChange(of: chartBottom) { _, _ in recordFit() }
        .onChange(of: visibleBottom) { _, _ in recordFit() }
    }

    private var locked: Bool { model.weightAccess == .locked }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
    }

    private func recordFit() {
        guard model.isDemo, chartBottom > 0, visibleBottom > 0 else { return }
        DemoProbe.recordWeightFit(chartBottom: chartBottom, visibleBottom: visibleBottom)
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ weight: WeightModel) -> some View {
        let unit = weight.unit
        let picture = model.weightPicture(range: weight.range)
        headlineCard(weight, picture: picture, unit: unit)
            .padding(.top, 22)
        Card {
            VStack(alignment: .leading, spacing: 14) {
                WeightRangePicker(selection: weight.range) { range in
                    model.setWeightRange(range)
                }
                if let change = picture.change {
                    changeLine(change, unit: unit)
                }
                WeightChart(picture: picture, unit: unit, range: weight.range, clock: model.clock, today: model.today.day,
                            goalKg: weight.goal?.kg, justReached: weight.justReached)
                if !picture.window.ticks.isEmpty {
                    Text(WeightCopy.ticks)
                        .font(.sans(13, .sans, relativeTo: .footnote))
                        .foregroundStyle(theme.fgSubtle)
                }
            }
            .padding(16)
        }
        .background {
            if model.isDemo {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { chartBottom = proxy.frame(in: .global).maxY }
                        .onChange(of: proxy.size) { _, _ in chartBottom = proxy.frame(in: .global).maxY }
                }
            }
        }
        .padding(.top, 16)
        allWeighInsRow(count: weight.state.weighIns.count)
            .padding(.top, 16)
    }

    /// One column: "Trend", the trend in Geist Mono, the slot, and the one big button. The slot is always there, so the
    /// card never changes height. One neutral colour: nothing turns red or green.
    private func headlineCard(_ weight: WeightModel, picture: WeightPicture, unit: WeightUnit) -> some View {
        let trendKg = picture.trend.last?.kg
        return Card {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(WeightCopy.trend)
                        .font(.sans(14, .sansMedium, relativeTo: .footnote))
                        .foregroundStyle(theme.fgSubtle)
                    if let trendKg {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(WeightFormat.trend(trendKg, unit: unit))
                                .font(.mono(40, .monoMedium, relativeTo: .largeTitle))
                                .foregroundStyle(theme.fg)
                                .contentTransition(.numericText())
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(unit.symbol)
                                .font(.sans(18, .sansMedium, relativeTo: .title3))
                                .foregroundStyle(theme.fgMuted)
                        }
                    }
                    slot(weight, picture: picture, unit: unit)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(headlineSpoken(weight, picture: picture, trendKg: trendKg, unit: unit))
                PrimaryButton(title: WeightCopy.logWeighIn, locked: locked) {
                    model.openWeighIn()
                }
                .accessibilityHint(locked ? "Opens Taken Pro." : "Opens a field for today's weight.")
            }
            .padding(16)
        }
    }

    /// The caption, the closing-in line, or for one visit the sentence for a point just lit.
    private func slot(_ weight: WeightModel, picture: WeightPicture, unit: WeightUnit) -> Text {
        if let goal = weight.goal, let moment = weight.justReached {
            return lineText(WeightGoalCopy.moment(moment, goalKg: goal.kg, unit: unit), words: theme.fg)
        }
        if let goal = weight.goal, let readout = picture.readout {
            return lineText(WeightGoalCopy.slot(readout, goalKg: goal.kg, unit: unit), words: theme.fgMuted)
        }
        return Text(WeightCopy.trendCaption)
            .font(.sans(15, .sans, relativeTo: .subheadline))
            .foregroundStyle(theme.fgSubtle)
    }

    /// Numbers with their units in Geist Mono Medium 15 and the look's ink; words in Geist 15.
    private func lineText(_ parts: [WeightGoalCopy.Part], words: Color) -> Text {
        var line = AttributedString()
        for part in parts {
            var run = AttributedString(part.text)
            let font: Font = part.isNumber ? .mono(15, .monoMedium, relativeTo: .subheadline)
                : .sans(15, .sans, relativeTo: .subheadline)
            let color: Color = part.isNumber ? theme.fg : words
            run.font = font
            run.foregroundColor = color
            line += run
        }
        return Text(line)
    }

    /// "Trend 88.1 kilograms. 1.1 kilograms to your goal, 87.0."
    private func headlineSpoken(_ weight: WeightModel, picture: WeightPicture, trendKg: Double?, unit: WeightUnit) -> String {
        let trend = WeightCopy.spokenTrend(trendKg, unit: unit)
        guard let goal = weight.goal else {
            return "\(trend.hasSuffix(".") ? String(trend.dropLast()) : trend), \(WeightCopy.trendCaption)"
        }
        if let moment = weight.justReached {
            return "\(trend) \(WeightGoalCopy.spokenMoment(moment, goalKg: goal.kg, unit: unit))"
        }
        guard let readout = picture.readout else { return trend }
        return "\(trend) \(WeightGoalCopy.spokenSlot(readout, goalKg: goal.kg, unit: unit))."
    }

    /// "−1.2 kg over 30 days", "−9.7 kg since 4 Mar", "No change over 7 days": one neutral colour, no arrow.
    private func changeLine(_ change: (kg: Double, span: WeightChangeLine.Span), unit: WeightUnit) -> some View {
        let today = model.today.day
        return lineText(WeightGoalCopy.changeLine(change.kg, span: change.span, unit: unit, today: today), words: theme.fgMuted)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .contentTransition(.numericText())
            .accessibilityLabel(WeightGoalCopy.spokenChange(change.kg, span: change.span, unit: unit, today: today))
    }

    private func allWeighInsRow(count: Int) -> some View {
        Button {
            model.sheet = .weighIns
        } label: {
            HStack(spacing: 10) {
                Text(WeightCopy.allWeighIns)
                    .font(.sans(17, .sans, relativeTo: .body))
                    .foregroundStyle(theme.fg)
                Spacer(minLength: 8)
                Text("\(count)")
                    .font(.mono(15, .monoMedium, relativeTo: .subheadline))
                    .foregroundStyle(theme.fgSubtle)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.fgSubtle)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .background(theme.bgRaised, in: shape)
        .overlay(shape.strokeBorder(theme.line, lineWidth: 1))
        .accessibilityLabel("\(WeightCopy.allWeighIns), \(count)")
        .accessibilityHint("Edit or delete a weigh-in.")
    }

    // MARK: Empty

    /// "Log your first weigh-in. Your trend starts here." with the one button.
    private var emptyCard: some View {
        VStack(spacing: 18) {
            Image(systemName: WeightCopy.symbol)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(theme.signalInk)
                .frame(width: 64, height: 64)
                .background(theme.signalWash, in: Circle())
                .overlay(Circle().strokeBorder(theme.signalEdge, lineWidth: 1))
                .padding(.top, 8)
                .accessibilityHidden(true)
            Text(WeightCopy.empty)
                .font(.sans(17, .sans, relativeTo: .body))
                .foregroundStyle(theme.fgMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: WeightCopy.logWeighIn, locked: locked) {
                model.openWeighIn()
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(theme.bgRaised, in: shape)
        .overlay(shape.strokeBorder(theme.line, lineWidth: 1))
    }
}

/// The More button left of the avatar (HIG pull-down buttons: a More button for items that need no prominent place):
/// Kilograms and Pounds with a check on the one in use, a divider, Set Goal (or Change Goal and Clear Goal), a divider,
/// and Hide Weight Tab, which acts at once with UNDO and asks nothing, because nothing is deleted. Clear Goal does the
/// same.
struct WeightMoreMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    init() {}

    var body: some View {
        let unit = model.weight.unit
        Menu {
            ForEach(WeightUnit.allCases) { option in
                Toggle(isOn: Binding(get: { unit == option }, set: { on in if on { model.setWeightUnit(option) } })) {
                    Text(option.menuTitle)
                }
            }
            Divider()
            // The goal lives here and nowhere else (HIG Menus: an ellipsis when more input follows); dimmed until there
            // is a weigh-in to start from.
            if model.weight.goal == nil {
                Button(WeightGoalCopy.setGoal) {
                    model.openWeightGoal()
                }
                .disabled(model.weight.isEmpty)
            } else {
                Button(WeightGoalCopy.changeGoal) {
                    model.openWeightGoal()
                }
                .disabled(model.weight.isEmpty)
                Button(WeightGoalCopy.clearGoal) {
                    model.clearWeightGoal()
                }
            }
            Divider()
            Button(WeightCopy.hideTab) {
                model.hideWeightTab()
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.fgMuted)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(WeightCopy.more)
    }
}

/// The undo toast above the tab bar on the Weight tab and in All weigh-ins: the same toast Today shows.
struct WeightToastDock: View {
    @Environment(AppModel.self) private var model

    init() {}

    var body: some View {
        VStack(spacing: 0) {
            if let toast = model.toast {
                ToastView(toast: toast) { model.undo(toast) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAction(named: "Dismiss") { model.dismissToast() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, model.toast == nil ? 0 : 10)
        .padding(.bottom, model.toast == nil ? 0 : 8)
        .frame(maxWidth: .infinity)
        .animation(.snappy(duration: 0.22), value: model.toast)
    }
}
#endif
