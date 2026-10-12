import SwiftUI

enum FrequencyChoice: String, CaseIterable, Identifiable, Sendable {
    case daily, twice, thrice, alternate, days

    var id: String { rawValue }

    var label: String {
        switch self {
        case .daily: return "DAILY"
        case .twice: return "2X DAILY"
        case .thrice: return "3X DAILY"
        case .alternate: return "ALT DAYS"
        case .days: return "DAYS"
        }
    }

    var shortLabel: String {
        switch self {
        case .daily: return "DAILY"
        case .twice: return "2X"
        case .thrice: return "3X"
        case .alternate: return "ALT"
        case .days: return "DAYS"
        }
    }

    func frequency(weekdays: Set<Int>) -> Frequency {
        switch self {
        case .daily: return .daily(times: 1)
        case .twice: return .daily(times: 2)
        case .thrice: return .daily(times: 3)
        case .alternate: return .alternateDays
        case .days: return .weekdays(weekdays)
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

/// No typing needed: tap chips, pick a frequency, ADD.
struct AddSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var selected: [String] = []
    @State private var choice: FrequencyChoice = .daily
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

    private var count: Int {
        selected.count + (showCustom && !customTrimmed.isEmpty ? 1 : 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "ADD TO STACK", subtitle: "TAP WHAT YOU TAKE") { dismiss() }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(index: "01", title: "PICK", trailing: String(format: "%02d SELECTED", count),
                                  trailingColor: count > 0 ? Palette.signal : Palette.fgSubtle)
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(Catalog.presets) { preset in
                            chip(preset)
                        }
                        customChip
                    }
                    if showCustom {
                        customField
                            .padding(.top, 14)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    SectionHeader(index: "02", title: "FREQUENCY", trailing: count > 1 ? "APPLIES TO ALL" : nil)
                    FrequencyPicker(choice: $choice, includeDays: false)
                    Text("Change any item later in settings.")
                        .font(.sans(13))
                        .foregroundStyle(Palette.fgFaint)
                        .padding(.top, 10)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            VStack(spacing: 0) {
                Rectangle().fill(Palette.line).frame(height: 1)
                PrimaryButton(title: count > 0 ? "ADD (\(count))" : "ADD", enabled: count > 0) {
                    add()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 8)
            }
            .background(Palette.bg)
        }
        .background(Palette.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Palette.bg)
        .animation(.snappy(duration: 0.22), value: showCustom)
        .onAppear {
            if selected.isEmpty && !model.demoPreselect.isEmpty { selected = model.demoPreselect }
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
                    Rectangle().fill(Palette.signal).frame(width: 6, height: 6)
                        .shadow(color: Palette.signal.opacity(0.7), radius: 3)
                }
                Text(preset.name.uppercased())
                    .font(.monoFixed(12, .monoMedium))
                    .tracking(12 * 0.08)
            }
            .foregroundStyle(owned ? Palette.fgFaint : (isOn ? Palette.signal : Palette.fg))
            .padding(.horizontal, 13)
            .frame(height: 44)
            .background(isOn ? Palette.signalWash : Palette.bgRaised, in: RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(isOn ? Palette.signalEdge : Palette.line, lineWidth: 1)
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
                .foregroundStyle(showCustom ? Palette.signal : Palette.fgMuted)
                .padding(.horizontal, 13)
                .frame(height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(showCustom ? Palette.signalEdge : Palette.lineDash,
                                      style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Custom item")
    }

    private var customField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NAME").hud(10.5, Palette.fgSubtle)
            TextField("", text: $customName, prompt: Text("e.g. Lion's Mane").foregroundStyle(Palette.fgFaint))
                .font(.sans(17))
                .foregroundStyle(Palette.fg)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($customFocused)
                .padding(.horizontal, 14)
                .frame(height: 50)
                .background(Palette.bgRaised, in: RoundedRectangle(cornerRadius: 3))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(customFocused ? Palette.signalEdge : Palette.line, lineWidth: 1)
                )
            if !customTrimmed.isEmpty {
                Text("CODE \(Catalog.code(for: customTrimmed))").hud(10.5, Palette.fgFaint)
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
        let frequency = choice.frequency(weekdays: [])
        var drafts = selected.map { name in
            ItemDraft(name: name, code: Catalog.presets.first { $0.name == name }?.code, frequency: frequency)
        }
        if showCustom && !customTrimmed.isEmpty {
            drafts.append(ItemDraft(name: customTrimmed, code: nil, frequency: frequency))
        }
        guard !drafts.isEmpty else { return }
        model.addItems(drafts)
        dismiss()
    }
}

/// Compact segmented control in mono caps.
struct FrequencyPicker: View {
    @Environment(AppModel.self) private var model
    @Binding var choice: FrequencyChoice
    var includeDays: Bool

    init(choice: Binding<FrequencyChoice>, includeDays: Bool) {
        self._choice = choice
        self.includeDays = includeDays
    }

    private var options: [FrequencyChoice] {
        includeDays ? FrequencyChoice.allCases : [.daily, .twice, .thrice, .alternate]
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element) { index, option in
                if index > 0 {
                    Rectangle().fill(Palette.line).frame(width: 1)
                }
                Button {
                    if choice != option { Haptics.selection(model.hapticsOn) }
                    choice = option
                } label: {
                    Text(includeDays ? option.shortLabel : option.label)
                        .font(.monoFixed(11, choice == option ? .monoSemibold : .monoMedium))
                        .tracking(11 * 0.08)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(choice == option ? Palette.buttonText : Palette.fgMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(choice == option ? Palette.button : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(choice == option ? .isSelected : [])
            }
        }
        .background(Palette.bgRaised)
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.line, lineWidth: 1))
    }
}

/// Weekday toggles, Monday first.
struct WeekdayPicker: View {
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
                        .font(.monoFixed(12, .monoSemibold))
                        .foregroundStyle(on ? Palette.buttonText : Palette.fgMuted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(on ? Palette.button : Palette.bgRaised, in: RoundedRectangle(cornerRadius: 3))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.line, lineWidth: 1))
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
