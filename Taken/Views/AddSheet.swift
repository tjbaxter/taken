import SwiftUI

/// How often an item is taken, as the Add sheet and the item sheet offer it.
enum FrequencyChoice: String, CaseIterable, Identifiable, Sendable {
    case daily, alternate, twice, thrice, days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "Daily"
        case .alternate: return "Every other day"
        case .twice: return "2x daily"
        case .thrice: return "3x daily"
        case .days: return "Days"
        }
    }

    /// Monday to Friday until other days are picked.
    static let defaultDays: Set<Int> = [2, 3, 4, 5, 6]

    /// The frequency to save. Days with none picked is every day, so an item is never added that is never due.
    func frequency(weekdays: Set<Int>) -> Frequency {
        switch self {
        case .daily: return .daily(times: 1)
        case .twice: return .daily(times: 2)
        case .thrice: return .daily(times: 3)
        case .alternate: return .alternateDays
        case .days: return weekdays.isEmpty ? .daily(times: 1) : .weekdays(weekdays)
        }
    }

    init(_ frequency: Frequency) {
        switch frequency {
        case .daily(let times):
            self = times >= 3 ? .thrice : (times == 2 ? .twice : .daily)
        case .alternateDays:
            self = .alternate
        case .weekdays:
            self = .days
        }
    }
}

/// What the Add sheet hands to the stack: every picked chip and the typed name, each with its own frequency.
enum AddPlan {
    /// The key a typed name's frequency is kept under.
    static let customKey = "\u{0}custom"

    static func drafts(selected: [String], custom: String?, choices: [String: FrequencyChoice],
                       days: [String: Set<Int>]) -> [ItemDraft] {
        func frequency(_ key: String) -> Frequency {
            (choices[key] ?? .daily).frequency(weekdays: days[key] ?? FrequencyChoice.defaultDays)
        }
        var drafts = selected.map { name in
            ItemDraft(name: name, code: Catalog.presets.first { $0.name == name }?.code, frequency: frequency(name))
        }
        if let custom = custom?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            drafts.append(ItemDraft(name: custom, code: nil, frequency: frequency(customKey)))
        }
        return drafts
    }
}

/// No typing needed: tap chips, set how often each is taken, add.
struct AddSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.paywallAnchor) private var paywallAnchor
    @Environment(\.theme) private var theme

    @State private var selected: [String] = []
    @State private var choices: [String: FrequencyChoice] = [:]
    @State private var days: [String: Set<Int>] = [:]
    @State private var showCustom = false
    @State private var customName = ""
    @FocusState private var customFocused: Bool

    init() {}

    private var inStack: Set<String> {
        Set(model.activeItems.map { $0.name.lowercased() })
    }

    private var customTrimmed: String {
        customName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One pick: the key its frequency is kept under, and its name.
    private struct Pick: Identifiable {
        let key: String
        let name: String
        var id: String { key }
    }

    /// Every pick in the order it was made, the typed name last.
    private var picked: [Pick] {
        var list = selected.map { Pick(key: $0, name: $0) }
        if showCustom && !customTrimmed.isEmpty { list.append(Pick(key: AddPlan.customKey, name: customTrimmed)) }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Add to stack", subtitle: "Tap what you take.") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(Catalog.presets) { preset in
                            chip(preset)
                        }
                        customChip
                    }
                    .padding(.top, 12)
                    if showCustom {
                        customField
                            .padding(.top, 14)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    if !picked.isEmpty {
                        SectionHeader("How often")
                        Card {
                            VStack(spacing: 0) {
                                ForEach(Array(picked.enumerated()), id: \.element.id) { index, pick in
                                    if index > 0 { RowDivider() }
                                    frequencyRow(key: pick.key, name: pick.name)
                                }
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            VStack(spacing: 0) {
                Rectangle().fill(theme.line).frame(height: 1)
                PrimaryButton(title: picked.isEmpty ? "Add" : "Add \(picked.count)", enabled: !picked.isEmpty) {
                    add()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .background(theme.bg)
        }
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(theme.bg)
        .animation(.snappy(duration: 0.22), value: showCustom)
        .animation(.snappy(duration: 0.22), value: picked.count)
        .onAppear {
            if selected.isEmpty && !model.demoPreselect.isEmpty {
                selected = model.demoPreselect
                choices = model.demoChoices
            }
        }
    }

    private func chip(_ preset: Preset) -> some View {
        let isOn = selected.contains(preset.name)
        let owned = inStack.contains(preset.name.lowercased())
        return Button {
            toggle(preset.name)
        } label: {
            HStack(spacing: 7) {
                if owned {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                } else if isOn {
                    LampShape(roundness: theme.radius.lampRoundness).fill(theme.signal).frame(width: 6, height: 6)
                        .shadow(color: theme.glow(0.7), radius: 3)
                }
                Text(preset.name.uppercased())
                    .font(.monoFixed(12, .monoMedium))
                    .tracking(12 * 0.08)
            }
            .foregroundStyle(owned ? theme.fgFaint : (isOn ? theme.signalInk : theme.fg))
            .padding(.horizontal, 13)
            .frame(height: 44)
            .background(isOn ? theme.signalWash : theme.bgRaised, in: RoundedRectangle(cornerRadius: theme.radius.control))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius.control)
                    .strokeBorder(isOn ? theme.signalEdge : theme.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(owned)
        .accessibilityLabel(preset.name)
        .accessibilityValue(owned ? "In your stack" : (isOn ? "Selected" : "Not selected"))
    }

    private var customChip: some View {
        Button {
            Haptics.selection(model.hapticsOn)
            showCustom.toggle()
            customFocused = showCustom
        } label: {
            Text(showCustom ? "\u{2212} CUSTOM" : "+ CUSTOM")
                .font(.monoFixed(12, .monoMedium))
                .tracking(12 * 0.08)
                .foregroundStyle(showCustom ? theme.signalInk : theme.fgMuted)
                .padding(.horizontal, 13)
                .frame(height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.radius.control)
                        .strokeBorder(showCustom ? theme.signalEdge : theme.lineStrong, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Custom item")
    }

    private var customField: some View {
        TextField("", text: $customName, prompt: Text("Name, like Lion's Mane").foregroundStyle(theme.fgFaint))
            .font(.sans(17, .sans, relativeTo: .body))
            .foregroundStyle(theme.fg)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($customFocused)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: theme.radius.card / 2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius.card / 2, style: .continuous)
                    .strokeBorder(customFocused ? theme.signalEdge : theme.line, lineWidth: 1)
            )
            .accessibilityLabel("Custom item name")
    }

    /// One picked item and how often it is taken. Days shows the weekdays under it.
    private func frequencyRow(key: String, name: String) -> some View {
        let choice = choices[key] ?? .daily
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(name)
                    .font(.sans(16, .sansMedium, relativeTo: .body))
                    .foregroundStyle(theme.fg)
                    .lineLimit(1)
                Spacer(minLength: 8)
                FrequencyMenu(choice: Binding(get: { choices[key] ?? .daily }, set: { choices[key] = $0 }))
                    .accessibilityLabel("\(name), how often")
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .frame(minHeight: 52)
            if choice == .days {
                WeekdayPicker(selection: Binding(get: { days[key] ?? FrequencyChoice.defaultDays },
                                                 set: { days[key] = $0 }))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }

    private func toggle(_ name: String) {
        Haptics.selection(model.hapticsOn)
        if let index = selected.firstIndex(of: name) {
            selected.remove(at: index)
        } else {
            selected.append(name)
        }
    }

    private func add() {
        let drafts = AddPlan.drafts(selected: selected, custom: showCustom ? customName : nil, choices: choices,
                                    days: days)
        guard !drafts.isEmpty else { return }
        let dismiss = self.dismiss
        // Adding needs no Pro until the first dose; in locked mode it opens the paywall over this sheet.
        model.requirePro(paywallAnchor) { [weak model = model] in
            model?.addItems(drafts)
            dismiss()
        }
    }
}

/// How often, as a compact menu: the choice in the look's readable signal with a chevron.
struct FrequencyMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Binding var choice: FrequencyChoice

    init(choice: Binding<FrequencyChoice>) {
        self._choice = choice
    }

    var body: some View {
        Menu {
            Picker("How often", selection: Binding(get: { choice }, set: { newValue in
                if newValue != choice { Haptics.selection(model.hapticsOn) }
                choice = newValue
            })) {
                ForEach(FrequencyChoice.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(choice.title)
                    .font(.sans(15, .sansMedium, relativeTo: .subheadline))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(theme.signalInk)
            .padding(.horizontal, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityValue(choice.title)
    }
}

/// Weekday toggles, Monday first.
struct WeekdayPicker: View {
    @Environment(\.theme) private var theme
    @Binding var selection: Set<Int>

    private let order = [2, 3, 4, 5, 6, 7, 1]

    init(selection: Binding<Set<Int>>) {
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(order.enumerated()), id: \.element) { index, weekday in
                let on = selection.contains(weekday)
                Button {
                    if on { selection.remove(weekday) } else { selection.insert(weekday) }
                } label: {
                    Text(Fmt.weekdayLetters[index])
                        .font(.sans(14, .sansSemibold, relativeTo: .subheadline))
                        .foregroundStyle(on ? theme.buttonText : theme.fgMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(on ? theme.button : theme.bgInset,
                                    in: RoundedRectangle(cornerRadius: theme.radius.card / 2, style: .continuous))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][index])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
