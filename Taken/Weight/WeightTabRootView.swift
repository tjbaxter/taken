import SwiftUI

#if DEBUG || TAKEN_INTERNAL
/// The Weight tab (SPEC 3.12; REDESIGN.md, "Weight tab page: entry first, 2026-10-22"): one ScrollView with two screens.
/// Screen one (`WeightEntryPage`) is the big number, the small line under it and a chevron; screen two (`WeightTrendPage`)
/// is the trend, how close it is to the goal, the chart card and All weigh-ins, one scroll down. The page height is
/// measured once (status bar to tab bar, keyboard ignored) and frozen while typing, so the number never moves; the Weigh
/// in bar rides on the decimal pad. Off until the person turns it on in Profile or from Today's one-time offer. Weight
/// never shows on Today (apart from the offer), in the widgets, the control, Siri, the nudge, the streak or History.
/// Compiled only into Debug and the owner's internal builds until 1.2: this type's name is the marker
/// scripts/check-app-store-build.sh looks for, so an App Store build is proven not to contain the tab.
struct WeightTabRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    /// The status bar's bottom and the tab bar's top, in global points, measured with the keyboard ignored.
    @State private var pageTop: CGFloat = 0
    @State private var tabBarTop: CGFloat = 0
    /// The scroll view's frame and the insets it reports, keyboard ignored.
    @State private var scrollFrame = WeightScrollFrame()
    /// Status bar to tab bar, frozen while typing.
    @State private var pageHeight: CGFloat = 0
    /// The floating tab bar and the home indicator below it: screen one runs on under them, empty, so screen two starts
    /// fully below the fold and nothing of it shows through the bar.
    @State private var belowFold: CGFloat = 0
    /// Screen one's height: where the snap's fold is.
    @State private var fold: CGFloat = 0
    @State private var blockMid: CGFloat = 0
    @State private var blockMidBefore: CGFloat = 0
    @State private var lineBottom: CGFloat = 0
    @State private var buttonTop: CGFloat = 0
    /// The range hint is announced once per typing session.
    @State private var rangeAnnounced = false

    init() {}

    var body: some View {
        let weight = model.weight
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    WeightEntryPage(focused: $focused, hasTrend: !weight.isEmpty, blockMid: $blockMid,
                                    lineBottom: $lineBottom, save: save, showTrend: { showTrend(proxy) })
                        .frame(minHeight: pageHeight, alignment: .top)
                        .padding(.bottom, weight.isEmpty ? 0 : belowFold)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.onChange(of: geometry.size.height, initial: true) { _, height in fold = height }
                            }
                        }
                        .id(WeightAnchor.entry)
                    if !weight.isEmpty {
                        WeightTrendPage(pageTop: pageTop, tabBarTop: tabBarTop)
                            .frame(minHeight: pageHeight, alignment: .top)
                            .id(WeightAnchor.trend)
                    }
                }
                .padding(.horizontal, 20)
                // Shown once measured, so there is no first-frame jump.
                .opacity(pageHeight > 0 ? 1 : 0)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.immediately)
            .scrollTargetBehavior(WeightFoldSnap(fold: fold, enabled: !focused))
            .background(theme.bg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focused {
                    PrimaryButton(title: WeightCopy.weighIn, enabled: kilograms != nil) { save() }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 12)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.onChange(of: geometry.frame(in: .global).minY, initial: true) { _, top in
                                    buttonTop = top + 8
                                }
                            }
                        }
                        .transition(.opacity)
                } else {
                    // The dock sits on the bottom safe area, so its bottom is the top of the tab bar.
                    WeightToastDock()
                        .background {
                            GeometryReader { geometry in
                                Color.clear.onChange(of: geometry.frame(in: .global).maxY, initial: true) { _, bottom in
                                    tabBarTop = bottom
                                    measure()
                                }
                            }
                        }
                }
            }
            .background {
                // The scroll view's frame and its reported insets, keyboard ignored (see `measure`).
                GeometryReader { geometry in
                    let frame = geometry.frame(in: .global)
                    Color.clear.onChange(of: WeightScrollFrame(minY: frame.minY, maxY: frame.maxY,
                                                               insetTop: geometry.safeAreaInsets.top,
                                                               insetBottom: geometry.safeAreaInsets.bottom),
                                         initial: true) { _, measured in
                        scrollFrame = measured
                        measure()
                    }
                }
                .ignoresSafeArea(.keyboard)
            }
            .onChange(of: focused) { _, now in
                model.weight.entryFocused = now
                if now {
                    blockMidBefore = blockMid
                    keepLineClear(proxy)
                } else {
                    model.weight.draft = ""
                    rangeAnnounced = false
                }
                record()
            }
            .task { await applyDemo(proxy) }
        }
        .onChange(of: model.weight.draft) { _, typed in
            let unit = model.weight.unit
            let clean = WeightFormat.sanitize(typed, locale: locale, maxDecimals: unit.decimals)
            if clean != typed { model.weight.draft = clean }
            if focused, !rangeAnnounced, WeightEntry.showsRangeHint(clean, unit: unit, locale: locale) {
                rangeAnnounced = true
                if !model.isDemo { UIAccessibility.post(notification: .announcement, argument: WeightCopy.spokenRangeHint(unit)) }
            }
        }
        .onChange(of: model.weightFigure.kind) { _, _ in record() }
        .onChange(of: model.weightLine(locale: locale).kind) { _, _ in record() }
        .onChange(of: model.weight.onTrend) { _, _ in record() }
        .onAppear { model.weight.refresh() }
        .onDisappear {
            focused = false
            model.weight.endVisit()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                focused = false
                model.weight.endVisit()
            }
        }
    }

    private var kilograms: Double? {
        WeightFormat.kilograms(model.weight.draft, unit: model.weight.unit, locale: locale)
    }

    /// The page height and the room under the tab bar, measured while not typing. The scroll view's frame stops at the
    /// safe area while it reports the full insets (CI measured 62 to 769 with insets 62 and 83 on a 393 x 852 iPhone), so
    /// the status bar's bottom is the frame's top unless the frame starts at the screen's top, and the screen's bottom is
    /// the frame's bottom plus the bottom inset when the frame stops at the tab bar. The tab bar's top comes from the toast
    /// dock, which sits on the bottom safe area.
    private func measure() {
        guard !focused, tabBarTop > 0 else { return }
        let frame = scrollFrame
        let top = frame.minY > 1 ? frame.minY : frame.minY + frame.insetTop
        let bottom = abs(frame.maxY - tabBarTop) < 2 ? frame.maxY + frame.insetBottom : max(frame.maxY, tabBarTop)
        guard top > 0, tabBarTop > top else { return }
        pageTop = top
        let height = tabBarTop - top
        if abs(height - pageHeight) > 0.5 { pageHeight = height }
        let under = max(0, bottom - tabBarTop)
        if abs(under - belowFold) > 0.5 { belowFold = under }
    }

    /// Weigh in: read the number, close the keypad, then save, so the digits stay as today's without a flash.
    private func save() {
        guard let kg = kilograms else { return }
        focused = false
        model.saveWeighIn(kg: kg)
    }

    private func showTrend(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.35)) {
            proxy.scrollTo(WeightAnchor.trend, anchor: .top)
        }
    }

    /// On small phones or with large text: 0.35 s after focus, if the small line comes within 16 of the Weigh in bar,
    /// the page scrolls up just enough. Under -demo the fit is written for CI afterwards.
    private func keepLineClear(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard focused else { return }
            if buttonTop > 0, lineBottom > buttonTop - 16 {
                withAnimation(.snappy(duration: 0.25)) {
                    proxy.scrollTo(WeightAnchor.block, anchor: .bottom)
                }
            }
            guard model.isDemo else { return }
            try? await Task.sleep(for: .milliseconds(600))
            DemoProbe.recordWeightEntryFit(lineBottom: lineBottom, buttonTop: buttonTop, shift: blockMid - blockMidBefore)
        }
    }

    /// `-demo`: the entry screens take focus, and the trend screens scroll to screen two, 450 ms after appearing.
    private func applyDemo(_ proxy: ScrollViewProxy) async {
        guard model.isDemo else { return }
        let screen = model.launchScreen
        guard WeightDemo.draft(screen) != nil || WeightDemo.opensOnTrend(screen) else { return }
        try? await Task.sleep(for: .milliseconds(450))
        if WeightDemo.draft(screen) != nil { focused = true }
        if WeightDemo.opensOnTrend(screen) { proxy.scrollTo(WeightAnchor.trend, anchor: .top) }
    }

    private func record() {
        guard model.isDemo else { return }
        DemoProbe.record(model)
    }
}

/// The scroll view's global frame and the safe-area insets its background reports.
struct WeightScrollFrame: Equatable {
    var minY: CGFloat = 0
    var maxY: CGFloat = 0
    var insetTop: CGFloat = 0
    var insetBottom: CGFloat = 0
}

/// Screen two: "Trend" and its value, how close it is to the goal (the slot), the chart card with its ranges, the change
/// line and weekly dose ticks, and All weigh-ins. With one weigh-in day: the single dot and "Your trend starts here.".
struct WeightTrendPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    /// The status bar's bottom and the tab bar's top: screen two at the top, and the fit probe.
    let pageTop: CGFloat
    let tabBarTop: CGFloat

    init(pageTop: CGFloat, tabBarTop: CGFloat) {
        self.pageTop = pageTop
        self.tabBarTop = tabBarTop
    }

    var body: some View {
        let weight = model.weight
        let unit = weight.unit
        let picture = model.weightPicture(range: weight.range)
        let firstDay = picture.trend.count <= 1
        VStack(alignment: .leading, spacing: 0) {
            headline(weight, picture: picture, unit: unit)
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    if !firstDay {
                        WeightRangePicker(selection: weight.range) { range in
                            model.setWeightRange(range)
                        }
                        if let change = picture.change {
                            changeLine(change, unit: unit)
                        }
                    }
                    WeightChart(picture: picture, unit: unit, range: weight.range, clock: model.clock, today: model.today.day,
                                goalKg: weight.goal?.kg)
                    if firstDay {
                        Text(WeightCopy.trendStarts)
                            .font(.sans(15, .sans, relativeTo: .subheadline))
                            .foregroundStyle(theme.fgSubtle)
                    } else if !picture.window.ticks.isEmpty {
                        Text(WeightCopy.ticks)
                            .font(.sans(13, .sans, relativeTo: .footnote))
                            .foregroundStyle(theme.fgSubtle)
                    }
                }
                .padding(16)
            }
            .background {
                if model.isDemo {
                    GeometryReader { geometry in
                        Color.clear.onChange(of: geometry.frame(in: .global).maxY, initial: true) { _, bottom in
                            guard tabBarTop > 0 else { return }
                            DemoProbe.recordWeightFit(chartBottom: bottom, visibleBottom: tabBarTop)
                        }
                    }
                }
            }
            .padding(.top, 16)
            allWeighInsRow(count: weight.state.weighIns.count)
                .padding(.top, 16)
        }
        .padding(.top, 20)
        .padding(.bottom, 28)
        .background {
            GeometryReader { geometry in
                Color.clear.onChange(of: geometry.frame(in: .global).minY, initial: true) { _, top in
                    let atTop = pageTop > 0 && abs(top - pageTop) <= 1
                    if model.weight.onTrend != atTop { model.weight.onTrend = atTop }
                }
            }
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
    }

    /// "Trend", the trend in Geist Mono 34, and the slot: "smooths daily swings", or how close it is to the goal. One
    /// VoiceOver heading.
    private func headline(_ weight: WeightModel, picture: WeightPicture, unit: WeightUnit) -> some View {
        let trendKg = picture.trend.last?.kg
        return VStack(alignment: .leading, spacing: 2) {
            Text(WeightCopy.trend)
                .font(.sans(14, .sansMedium, relativeTo: .footnote))
                .foregroundStyle(theme.fgSubtle)
            if let trendKg {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(WeightFormat.trend(trendKg, unit: unit))
                        .font(.mono(34, .monoMedium, relativeTo: .largeTitle))
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(weight, picture: picture, trendKg: trendKg, unit: unit))
        .accessibilityAddTraits(.isHeader)
    }

    private func slot(_ weight: WeightModel, picture: WeightPicture, unit: WeightUnit) -> Text {
        if let goal = weight.goal, let readout = picture.readout {
            return WeightEntryPage.lineText(WeightGoalCopy.slot(readout, goalKg: goal.kg, unit: unit, locale: locale),
                                            numbers: theme.fg, words: theme.fgMuted, wordsFace: .sans)
        }
        return Text(WeightCopy.trendCaption)
            .font(.sans(15, .sans, relativeTo: .subheadline))
            .foregroundStyle(theme.fgSubtle)
    }

    /// "Trend 88.1 kilograms. 1.1 kilograms to your goal, 87.0."
    private func spoken(_ weight: WeightModel, picture: WeightPicture, trendKg: Double?, unit: WeightUnit) -> String {
        let trend = WeightCopy.spokenTrend(trendKg, unit: unit)
        guard let goal = weight.goal, let readout = picture.readout else {
            return "\(trend.hasSuffix(".") ? String(trend.dropLast()) : trend), \(WeightCopy.trendCaption)"
        }
        return "\(trend) \(WeightGoalCopy.spokenSlot(readout, goalKg: goal.kg, unit: unit))."
    }

    /// "−1.2 kg over 30 days", "−9.7 kg since 4 Mar", "No change over 7 days": one neutral colour, no arrow.
    private func changeLine(_ change: (kg: Double, span: WeightChangeLine.Span), unit: WeightUnit) -> some View {
        let today = model.today.day
        return WeightEntryPage.lineText(WeightGoalCopy.changeLine(change.kg, span: change.span, unit: unit, today: today),
                                        numbers: theme.fg, words: theme.fgMuted, wordsFace: .sans)
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
