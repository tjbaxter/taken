import SwiftUI

#if DEBUG || TAKEN_INTERNAL
/// The Weight tab (SPEC 3.12; REDESIGN.md, "Weight tab, 2026-10-22"): the last weigh-in under the title, the trend as the
/// headline with Log weigh-in under it, the chart with its ranges and weekly dose ticks, then All weigh-ins. Off until the
/// person turns it on in Profile or from Today's one-time offer; its More menu sets kilograms or pounds and hides it, with
/// UNDO. Weight never shows on Today (apart from the offer), in the widgets, the control, Siri, the nudge, the streak or
/// History. Compiled only into Debug and the owner's internal builds until 1.2: this type's name is the marker
/// scripts/check-app-store-build.sh looks for, so an App Store build is proven not to contain the tab.
struct WeightTabRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    init() {}

    var body: some View {
        let weight = model.weight
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TabHeader(title: WeightCopy.tab,
                          subtitle: WeightCopy.lastLine(weight.state.last, now: model.now, clock: model.clock)) {
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
        .background(theme.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { WeightToastDock() }
        .onAppear { weight.refresh() }
    }

    private var locked: Bool { model.weightAccess == .locked }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ weight: WeightModel) -> some View {
        let unit = weight.unit
        let picture = model.weightPicture(range: weight.range)
        let summary = WeightCopy.chartSummary(trendKg: picture.trend.last?.kg, changes: picture.changes, unit: unit)
        summaryCard(trendKg: picture.trend.last?.kg, last: weight.state.last, unit: unit)
            .padding(.top, 22)
        Card {
            VStack(alignment: .leading, spacing: 14) {
                WeightRangePicker(selection: weight.range) { range in
                    model.setWeightRange(range)
                }
                WeightChart(window: picture.window, unit: unit, range: weight.range, clock: model.clock,
                            summary: summary)
                    .frame(height: 220)
                if !picture.window.ticks.isEmpty {
                    Text(WeightCopy.ticks)
                        .font(.sans(13, .sans, relativeTo: .footnote))
                        .foregroundStyle(theme.fgSubtle)
                }
                if !picture.changes.isEmpty {
                    RowDivider(inset: 0)
                    changesRow(picture.changes, unit: unit)
                }
            }
            .padding(16)
        }
        .padding(.top, 16)
        allWeighInsRow(count: weight.state.weighIns.count)
            .padding(.top, 16)
    }

    /// The trend as the headline (Geist Mono), "smooths daily swings" under it, the last weigh-in beside it, and the one
    /// big button. One neutral colour: the number never turns red or green.
    private func summaryCard(trendKg: Double?, last: WeighIn?, unit: WeightUnit) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    if let trendKg {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(WeightCopy.trend)
                                .font(.sans(14, .sansMedium, relativeTo: .footnote))
                                .foregroundStyle(theme.fgSubtle)
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
                            Text(WeightCopy.trendCaption)
                                .font(.sans(14, .sans, relativeTo: .footnote))
                                .foregroundStyle(theme.fgSubtle)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Trend \(WeightFormat.trend(trendKg, unit: unit)) \(unit.spoken), smooths daily swings")
                    }
                    Spacer(minLength: 8)
                    if let last {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(WeightCopy.last)
                                .font(.sans(14, .sansMedium, relativeTo: .footnote))
                                .foregroundStyle(theme.fgSubtle)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(WeightFormat.value(last.kg, unit: unit))
                                    .font(.mono(22, .monoMedium, relativeTo: .title3))
                                    .foregroundStyle(theme.fg)
                                    .lineLimit(1)
                                Text(unit.symbol)
                                    .font(.sans(15, .sans, relativeTo: .subheadline))
                                    .foregroundStyle(theme.fgMuted)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Last weigh-in \(WeightFormat.spoken(last.kg, unit: unit))")
                    }
                }
                PrimaryButton(title: WeightCopy.logWeighIn, locked: locked) {
                    model.openWeighIn()
                }
                .accessibilityHint(locked ? "Opens Taken Pro." : "Opens a field for today's weight.")
            }
            .padding(16)
        }
    }

    /// "7 days ↓ 0.4 kg", "30 days ↓ 1.2 kg", "90 days ↓ 3.9 kg": each once that much history exists, an arrow and a
    /// number in one neutral colour.
    private func changesRow(_ changes: [WeightChange], unit: WeightUnit) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(changes, id: \.days) { change in
                VStack(alignment: .leading, spacing: 4) {
                    Text(change.label)
                        .font(.sans(13, .sans, relativeTo: .footnote))
                        .foregroundStyle(theme.fgSubtle)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: change.symbol(unit: unit))
                            .font(.system(size: 11, weight: .semibold))
                        Text(WeightFormat.trend(abs(change.kg), unit: unit))
                            .font(.mono(15, .monoMedium, relativeTo: .subheadline))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(unit.symbol)
                            .font(.sans(13, .sans, relativeTo: .footnote))
                    }
                    .foregroundStyle(theme.fgMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(change.spoken(unit: unit))
            }
        }
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
/// Kilograms and Pounds with a check on the one in use, a divider, and Hide Weight Tab, which acts at once with UNDO and
/// asks nothing, because nothing is deleted.
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
