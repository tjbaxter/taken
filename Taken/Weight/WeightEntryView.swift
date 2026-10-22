import Accessibility
import Combine
import SwiftUI

#if DEBUG || TAKEN_INTERNAL
/// Screen one of the Weight tab (REDESIGN.md, "Weight tab page: entry first, 2026-10-22"): More and the avatar top right,
/// one big number in the middle (the last weigh-in in grey with an amber caret, or today's in the look's ink), one small
/// line under it, and a small chevron at the bottom. Nothing else. A tap on the number brings up the decimal pad and the
/// Weigh in bar; the number never moves. Screen two (the trend, the goal and the chart) is one scroll down.
struct WeightEntryPage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.locale) private var locale
    let focused: FocusState<Bool>.Binding
    /// There is a screen two to show (a weigh-in exists).
    let hasTrend: Bool
    @Binding var blockMid: CGFloat
    @Binding var lineBottom: CGFloat
    let save: () -> Void
    let showTrend: () -> Void

    /// The caret pulses three times on appear and whenever the number turns grey or empty again (after Undo).
    @State private var pulse = 0

    init(focused: FocusState<Bool>.Binding, hasTrend: Bool, blockMid: Binding<CGFloat>, lineBottom: Binding<CGFloat>,
         save: @escaping () -> Void, showTrend: @escaping () -> Void) {
        self.focused = focused
        self.hasTrend = hasTrend
        _blockMid = blockMid
        _lineBottom = lineBottom
        self.save = save
        self.showTrend = showTrend
    }

    var body: some View {
        let weight = model.weight
        let isFocused = focused.wrappedValue
        let figure = WeightEntry.figure(last: weight.state.last, today: model.today.day, clock: model.clock,
                                        draft: weight.draft, focused: isFocused)
        let resting = figure == .empty || isGhost(figure)
        VStack(spacing: 0) {
            topBar
            // Two spacers above and three below: the block's centre sits 40% of the way down the free space.
            Spacer(minLength: 16)
            Spacer(minLength: 0)
            block(figure)
            Spacer(minLength: 16)
            Spacer(minLength: 0)
            Spacer(minLength: 0)
            chevron(visible: hasTrend && !isFocused)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            // A tap anywhere outside the number closes the keypad without saving.
            if focused.wrappedValue { focused.wrappedValue = false }
        }
        .onAppear { pulse += 1 }
        .onChange(of: resting && !isFocused) { _, grey in
            if grey { pulse += 1 }
        }
        .onChange(of: weight.entryRequested) { _, wanted in
            guard wanted else { return }
            weight.entryRequested = false
            focused.wrappedValue = true
        }
    }

    private func isGhost(_ figure: WeightFigure) -> Bool {
        if case .ghost = figure { return true }
        return false
    }

    /// Today's latest weigh-in, if there is one: the long-press menu and the field's actions act on it.
    private var todaysWeighIn: WeighIn? {
        guard let last = model.weight.state.last, model.clock.day(of: last) == model.today.day else { return nil }
        return last
    }

    private var locked: Bool { model.weightAccess == .locked }

    // MARK: Top bar

    /// More and the avatar exactly where TabHeader puts them on the other tabs, and an invisible "Weight" heading.
    private var topBar: some View {
        HStack(alignment: .top, spacing: 12) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityLabel(WeightCopy.tab)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            WeightMoreMenu()
                .padding(.trailing, -8)
            ProfileButton()
        }
        .padding(.top, 10)
    }

    // MARK: The block

    private func block(_ figure: WeightFigure) -> some View {
        VStack(spacing: 12) {
            figureLine(figure)
            smallLine
                .background {
                    GeometryReader { proxy in
                        Color.clear.onChange(of: proxy.frame(in: .global).maxY, initial: true) { _, bottom in
                            lineBottom = bottom
                        }
                    }
                }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, minHeight: 160)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !focused.wrappedValue else { return }
            model.requireWeightPro { [weak weight = model.weight] in weight?.entryRequested = true }
        }
        .contextMenu {
            if !focused.wrappedValue, let today = todaysWeighIn {
                Button(WeightCopy.edit) { model.editWeighIn(today.id) }
                Button(WeightCopy.delete, role: .destructive) { model.deleteWeighIn(today.id) }
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.onChange(of: proxy.frame(in: .global).midY, initial: true) { _, mid in blockMid = mid }
            }
        }
        .id(WeightAnchor.block)
    }

    /// The digits (Geist Mono Regular 72, the separator pulled in), the caret or the lock, and the unit, with the real
    /// field over them, invisible.
    private func figureLine(_ figure: WeightFigure) -> some View {
        let weight = model.weight
        let unit = weight.unit
        let isFocused = focused.wrappedValue
        let ghost = weight.state.last.map { WeightFormat.value($0.kg, unit: unit, locale: locale) } ?? ""
        let shown = shownText(figure, unit: unit)
        let grey = figure == .empty || isGhost(figure)
        let color = grey ? theme.fgSubtle : theme.fg
        let caret = !locked && (isFocused || grey)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.signalInk)
                    // Centred on the digits' cap height, as the caret is.
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 25.55 }
                    .padding(.trailing, -2)
            }
            ZStack(alignment: .leading) {
                Self.figureText(WeightEntry.sizing(ghost: ghost, draft: weight.draft), color: .clear)
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                Self.figureText(shown, color: color)
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(isFocused ? .identity : .numericText())
                HStack(spacing: 0) {
                    Self.figureText(isFocused ? weight.draft : "", color: .clear)
                        .lineLimit(1)
                        .fixedSize()
                        .hidden()
                    if caret {
                        WeightCaret(blinking: isFocused, pulse: pulse)
                            .id(isFocused ? weight.draft : "resting")
                    }
                }
            }
            Text(unit.symbol)
                .font(.sans(22, .sansMedium, relativeTo: .title2))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .foregroundStyle(grey ? theme.fgSubtle : theme.fgMuted)
        }
        .accessibilityHidden(true)
        .overlay { field(figure) }
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
    }

    /// The real field: clear, not hit-testable (the block's tap focuses it), so VoiceOver still finds it.
    private func field(_ figure: WeightFigure) -> some View {
        let weight = model.weight
        let unit = weight.unit
        let isFocused = focused.wrappedValue
        let today = todaysWeighIn
        let label = today == nil ? WeightCopy.fieldLabel(unit) : WeightCopy.todaysWeighIn
        let value: String
        if isFocused || today == nil {
            value = weight.draft
        } else {
            value = today.map { WeightFormat.spoken($0.kg, unit: unit, locale: locale) } ?? ""
        }
        let hint = locked ? WeightCopy.lockedHint : (today == nil ? WeightCopy.typeHint : WeightCopy.anotherHint)
        return TextField("", text: Binding(get: { model.weight.draft }, set: { model.weight.draft = $0 }))
            .keyboardType(.decimalPad)
            .focused(focused)
            .onSubmit(save)
            .autocorrectionDisabled()
            .font(.monoFixed(72, .mono))
            .foregroundStyle(.clear)
            .tint(.clear)
            .allowsHitTesting(false)
            .accessibilityLabel(label)
            .accessibilityValue(value)
            .accessibilityHint(hint)
            .accessibilityAction(.escape) { focused.wrappedValue = false }
            .accessibilityActions {
                if !isFocused, let today {
                    if !locked {
                        Button(WeightCopy.editWeighIn) { model.editWeighIn(today.id) }
                    }
                    Button(WeightCopy.deleteWeighIn) { model.deleteWeighIn(today.id) }
                }
            }
    }

    /// Every string in the digits box: Geist Mono Regular 72 at a fixed size, with the last whole digit and the
    /// separator kerned in by 11, so the point does not leave a gap either side.
    static func figureText(_ text: String, color: Color) -> Text {
        var out = AttributedString()
        let characters = Array(text)
        let separator = characters.firstIndex { !$0.isNumber }
        for (index, character) in characters.enumerated() {
            var run = AttributedString(String(character))
            let font: Font = .monoFixed(72, .mono)
            run.font = font
            run.foregroundColor = color
            if let separator, index == separator - 1 || index == separator {
                run[AttributeScopes.SwiftUIAttributes.KerningAttribute.self] = -11
            }
            out += run
        }
        return Text(out)
    }

    /// The digits the big number shows: none, the last weigh-in, today's, or the draft.
    private func shownText(_ figure: WeightFigure, unit: WeightUnit) -> String {
        switch figure {
        case .empty: return ""
        case .ghost(let kg), .today(let kg): return WeightFormat.value(kg, unit: unit, locale: locale)
        case .typing(let text): return text
        }
    }

    // MARK: The small line

    private var smallLine: some View {
        let weight = model.weight
        let unit = weight.unit
        let readout = weight.goal != nil && weight.justSaved != nil ? model.weightPicture(range: weight.range).readout : nil
        let line = WeightEntry.line(focused: focused.wrappedValue, draft: weight.draft, unit: unit, locale: locale,
                                    hasGoal: weight.goal != nil, justSaved: weight.justSaved != nil,
                                    justReached: weight.justReached, readout: readout)
        return ZStack {
            lineContent(line, unit: unit)
                .id(line.kind)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.2), value: line.kind)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(line, unit: unit))
    }

    @ViewBuilder
    private func lineContent(_ line: WeightLine, unit: WeightUnit) -> some View {
        let weight = model.weight
        switch line {
        case .range:
            plain(WeightCopy.rangeHint(unit))
        case .last:
            plain(WeightCopy.lastLine(weight.state.last, now: model.now, clock: model.clock))
        case .closing(let readout):
            if let goal = weight.goal, let parts = WeightGoalCopy.visit(readout, goalKg: goal.kg, unit: unit, locale: locale) {
                Self.lineText(parts, numbers: theme.fg, words: theme.fgMuted, wordsFace: .sans)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        case .moment(let moment):
            if let goal = weight.goal {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    WeightLitPoint(springs: !weight.momentPlayed, bead: false)
                        // The dot's centre 5 above the first line's baseline.
                        .alignmentGuide(.firstTextBaseline) { d in d.height / 2 + 5 }
                        .onAppear { weight.momentPlayed = true }
                    Self.lineText(WeightGoalCopy.moment(moment, goalKg: goal.kg, unit: unit, locale: locale),
                                  numbers: theme.signalInk, words: theme.signalInk, wordsFace: .sansMedium)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                }
            }
        }
    }

    private func plain(_ text: String) -> some View {
        Text(text)
            .font(.sans(15, .sans, relativeTo: .subheadline))
            .foregroundStyle(theme.fgSubtle)
            .multilineTextAlignment(.center)
            .lineLimit(3)
    }

    private func spoken(_ line: WeightLine, unit: WeightUnit) -> String {
        let weight = model.weight
        switch line {
        case .range:
            return WeightCopy.spokenRangeHint(unit)
        case .last:
            return WeightCopy.spokenLastLine(weight.state.last, unit: unit, now: model.now, clock: model.clock, locale: locale)
        case .closing(let readout):
            guard let goal = weight.goal else { return "" }
            return WeightGoalCopy.spokenVisit(readout, goalKg: goal.kg, unit: unit, locale: locale) ?? ""
        case .moment(let moment):
            guard let goal = weight.goal else { return "" }
            return WeightGoalCopy.spokenMoment(moment, goalKg: goal.kg, unit: unit, locale: locale)
        }
    }

    /// Numbers with their units in Geist Mono Medium 15; words in Geist 15.
    static func lineText(_ parts: [WeightGoalCopy.Part], numbers: Color, words: Color, wordsFace: Face) -> Text {
        var line = AttributedString()
        for part in parts {
            var run = AttributedString(part.text)
            let font: Font = part.isNumber ? .mono(15, .monoMedium, relativeTo: .subheadline)
                : .sans(15, wordsFace, relativeTo: .subheadline)
            let color: Color = part.isNumber ? numbers : words
            run.font = font
            run.foregroundColor = color
            line += run
        }
        return Text(line)
    }

    // MARK: The chevron

    /// "Show trend": always laid out, so the block never moves when it comes or goes.
    private func chevron(visible: Bool) -> some View {
        Button(action: showTrend) {
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.fgSubtle)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .accessibilityHidden(!visible)
        .accessibilityLabel(WeightCopy.showTrend)
        .padding(.bottom, 8)
    }
}

/// The drawn caret: 3 by 59 in the look's signal colour, its centre on the box's edge. At rest it pulses three times and
/// then holds; while typing it blinks, half a second on and off, and restarts with each key so it stays solid while keys
/// are pressed. It holds still under Reduce Motion or Prefer Non-Blinking Cursor (iOS 18).
struct WeightCaret: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let blinking: Bool
    let pulse: Int
    @State private var nonBlinking = false

    var body: some View {
        Capsule()
            .fill(theme.signal)
            .frame(width: 3, height: 59)
            .offset(x: -1.5)
            .modifier(CaretMotion(blinking: blinking, pulse: pulse, still: reduceMotion || nonBlinking))
            .modifier(NonBlinkingObserver(nonBlinking: $nonBlinking))
            .accessibilityHidden(true)
    }
}

private struct CaretMotion: ViewModifier {
    let blinking: Bool
    let pulse: Int
    let still: Bool

    func body(content: Content) -> some View {
        if still {
            content
        } else if blinking {
            content.phaseAnimator([1.0, 0.0]) { view, phase in
                view.opacity(phase)
            } animation: { _ in
                .easeInOut(duration: 0.1).delay(0.4)
            }
        } else {
            // Three pulses then steady: about 3.6 s, under WCAG 2.2.2's 5 s.
            content.phaseAnimator([1.0, 0.3, 1.0, 0.3, 1.0, 0.3], trigger: pulse) { view, phase in
                view.opacity(phase)
            } animation: { _ in
                .easeInOut(duration: 0.6)
            }
        }
    }
}

/// iOS 18's Prefer Non-Blinking Cursor, "relevant for apps that draw custom insertion indicators".
private struct NonBlinkingObserver: ViewModifier {
    @Binding var nonBlinking: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onAppear { nonBlinking = AccessibilitySettings.prefersNonBlinkingTextInsertionIndicator }
                .onReceive(NotificationCenter.default.publisher(
                    for: AccessibilitySettings.prefersNonBlinkingTextInsertionIndicatorDidChangeNotification)) { _ in
                    nonBlinking = AccessibilitySettings.prefersNonBlinkingTextInsertionIndicator
                }
        } else {
            content
        }
    }
}

/// Snaps a scroll that would stop between the number and the top of the trend to whichever is nearer, so a flick goes
/// all the way; below the fold, scrolling is free; off while typing.
struct WeightFoldSnap: ScrollTargetBehavior {
    var fold: CGFloat
    var enabled: Bool

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard enabled else { return }
        target.rect.origin.y = WeightFold.snap(target.rect.minY, fold: fold)
    }
}

/// `-demo -type ax3`: the whole app at accessibility size 3, for CI's large-text capture.
struct DemoTypeSize: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        let arguments = ProcessInfo.processInfo.arguments
        if enabled, let index = arguments.firstIndex(of: "-type"), index + 1 < arguments.count, arguments[index + 1] == "ax3" {
            content.dynamicTypeSize(.accessibility3)
        } else {
            content
        }
    }
}
#endif
