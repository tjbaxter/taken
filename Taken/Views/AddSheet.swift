import SwiftUI
import Accessibility

/// How often an item is taken, as the Add sheet and the item sheet offer it.
enum FrequencyChoice: String, CaseIterable, Identifiable, Sendable {
    case daily, alternate, weekly, twice, thrice, days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "Daily"
        case .alternate: return "Every other day"
        case .weekly: return "Weekly"
        case .twice: return "2x daily"
        case .thrice: return "3x daily"
        case .days: return "Days"
        }
    }

    /// Monday to Friday until other days are picked.
    static let defaultDays: Set<Int> = [2, 3, 4, 5, 6]

    /// The frequency to save. Days with none picked is every day, so an item is never added that is never due. Weekly
    /// is the one weekday `weekday` (Calendar numbering, 1 is Sunday), saved as a one-day Days set, so the file format
    /// does not change and an older build reads it as that day.
    func frequency(weekdays: Set<Int>, weekday: Int) -> Frequency {
        switch self {
        case .daily: return .daily(times: 1)
        case .twice: return .daily(times: 2)
        case .thrice: return .daily(times: 3)
        case .alternate: return .alternateDays
        case .weekly: return .weekdays([min(max(weekday, 1), 7)])
        case .days: return weekdays.isEmpty ? .daily(times: 1) : .weekdays(weekdays)
        }
    }

    init(_ frequency: Frequency) {
        switch frequency {
        case .daily(let times):
            self = times >= 3 ? .thrice : (times == 2 ? .twice : .daily)
        case .alternateDays:
            self = .alternate
        case .weekdays(let days):
            self = days.count == 1 ? .weekly : .days
        }
    }
}

/// What the Add sheet hands to the stack: every picked chip and every other name, each with its own frequency.
enum AddPlan {
    /// How often a pick starts: Weekly for a weekly catalog entry (Semaglutide, Tirzepatide, or a brand of either),
    /// else Daily. Either can be changed in its row, so oral semaglutide is one tap from Daily.
    static func defaultChoice(for name: String) -> FrequencyChoice {
        Catalog.entry(matching: name)?.weekly == true ? .weekly : .daily
    }

    /// `extras` are picks that are not chips: a suggestion, the typed text as a row, or text left in the field. Choices
    /// and days are kept under each pick's name; a weekly pick's day is in `weekly`, else `weekday`, the weekday of the
    /// day being lived. A name picked twice, in any case, is added once.
    static func drafts(selected: [String], extras: [String], choices: [String: FrequencyChoice],
                       days: [String: Set<Int>], weekly: [String: Int] = [:], weekday: Int) -> [ItemDraft] {
        var seen = Set<String>()
        var drafts: [ItemDraft] = []
        for key in selected + extras {
            let name = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(Catalog.lookupKey(name)).inserted else { continue }
            let choice = choices[key] ?? defaultChoice(for: name)
            let frequency = choice.frequency(weekdays: days[key] ?? FrequencyChoice.defaultDays,
                                             weekday: weekly[key] ?? weekday)
            drafts.append(ItemDraft(name: name, code: Catalog.entry(matching: name)?.code, frequency: frequency))
        }
        return drafts
    }
}

/// The Add sheet's words, in one place so the copy tests cover every one.
enum AddCopy {
    static let title = "Add to stack"
    static let subtitle = "Tap what you take."
    static let howOften = "How often"
    static let add = "Add"
    static let customChip = "Custom item"
    static let fieldPrompt = "Search or type a name"
    static let fieldLabel = "Name"
    static let clear = "Clear"
    static let inStack = "In your stack"
    static let selectedValue = "Selected"
    static let notSelectedValue = "Not selected"

    /// The last row: what was typed, added as it is.
    static func literal(_ text: String) -> String {
        "Add \u{201C}\(text)\u{201D}"
    }

    /// What VoiceOver hears once typing pauses.
    static func suggestions(_ count: Int) -> String {
        switch count {
        case 0: return "No suggestions"
        case 1: return "1 suggestion"
        default: return "\(count) suggestions"
        }
    }

    static var all: [String] {
        [title, subtitle, howOften, add, customChip, fieldPrompt, fieldLabel, clear, inStack, selectedValue,
         notSelectedValue, "+ " + literal("Lion's Mane"), suggestions(0), suggestions(1), suggestions(4)]
            + FrequencyChoice.allCases.map(\.title)
    }
}

/// No typing needed: tap chips, set how often each is taken, add. + CUSTOM opens type mode: the field pinned under the
/// header, where nothing can cover it (Apple Health, Medisafe and MyTherapy put the name field at the top with matches
/// under it), suggestions under the field, and the Add bar out of the way until the keyboard goes (Baymard: nothing
/// sticky between a field and the keyboard).
struct AddSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.paywallAnchor) private var paywallAnchor
    @Environment(\.theme) private var theme

    @State private var selected: [String] = []
    /// Picks that are not chips (a suggestion, or the typed text as a row): selected chips just before + CUSTOM.
    @State private var extras: [String] = []
    @State private var choices: [String: FrequencyChoice] = [:]
    @State private var days: [String: Set<Int>] = [:]
    @State private var weekly: [String: Int] = [:]
    /// Type mode: the field is pinned under the header.
    @State private var typing = false
    @State private var query = ""
    @State private var announcement: Task<Void, Never>?
    @FocusState private var customFocused: Bool
    @ScaledMetric(relativeTo: .body) private var fieldHeight: CGFloat = 50
    @ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = 48

    init() {}

    /// The stack's names as `Catalog.lookupKey` folds them.
    private var owned: Set<String> {
        Set(model.activeItems.map { Catalog.lookupKey($0.name) })
    }

    private var typed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The weekday of the day being lived: where a Weekly pick starts.
    private var weekday: Int { model.today.day.weekday }

    /// Text left in the field once the keyboard is down counts as a pick, as it always has.
    private var fieldPick: [String] {
        guard typing, !customFocused, !typed.isEmpty, !isPicked(typed) else { return [] }
        return [typed]
    }

    /// Every pick in the order it was made: chips, then other names, then text left in the field.
    private var picked: [String] { selected + extras + fieldPick }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: AddCopy.title, subtitle: AddCopy.subtitle) { dismiss() }
            GeometryReader { stage in
                VStack(spacing: 0) {
                    if typing {
                        typeArea(height: stage.size.height)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            FlowLayout(spacing: 8, lineSpacing: 8) {
                                ForEach(Catalog.presets) { preset in
                                    chip(preset)
                                }
                                ForEach(extras, id: \.self) { name in
                                    extraChip(name)
                                }
                                customChip
                            }
                            .padding(.top, 12)
                            if !picked.isEmpty {
                                SectionHeader(AddCopy.howOften)
                                Card {
                                    VStack(spacing: 0) {
                                        ForEach(Array(picked.enumerated()), id: \.element) { index, name in
                                            if index > 0 { RowDivider() }
                                            frequencyRow(name)
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
                }
                .frame(width: stage.size.width, height: stage.size.height, alignment: .top)
            }
            .clipped()
            if !customFocused {
                VStack(spacing: 0) {
                    Rectangle().fill(theme.line).frame(height: 1)
                    PrimaryButton(title: picked.isEmpty ? AddCopy.add : "\(AddCopy.add) \(picked.count)",
                                  enabled: !picked.isEmpty) {
                        add()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .background(theme.bg)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(theme.bg)
        // Deliberate, not per keystroke: entering and leaving type mode, the keyboard, and a pick landing.
        .animation(.snappy(duration: 0.28), value: typing)
        .animation(.snappy(duration: 0.22), value: customFocused)
        .animation(.snappy(duration: 0.22), value: picked.count)
        .onChange(of: customFocused) { _, focused in
            // Losing focus with nothing typed leaves type mode; with text, the field keeps it as a pick.
            if !focused && typing && typed.isEmpty { typing = false }
        }
        .onChange(of: query) { _, _ in
            announceSuggestions()
        }
        .onAppear {
            if selected.isEmpty && !model.demoPreselect.isEmpty {
                selected = model.demoPreselect
                choices = model.demoChoices
            }
            if query.isEmpty && !model.demoQuery.isEmpty {
                typing = true
                query = model.demoQuery
            }
        }
    }

    // MARK: Type mode

    /// The pinned field and, while it has focus and text, the suggestions: as many rows as fit above the chips.
    private func typeArea(height: CGFloat) -> some View {
        let capacity = Self.rowCapacity(available: height - 8 - fieldHeight - 8 - 8, rowHeight: rowHeight)
        let rows = customFocused ? suggestionRows(capacity: capacity) : []
        return VStack(spacing: 8) {
            customField
            if !rows.isEmpty {
                Card {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { RowDivider() }
                            suggestionRow(row)
                        }
                    }
                }
            }
        }
    }

    /// Suggestion rows that fit in `available` points under the field without pushing it off screen, however large the
    /// text or small the iPhone (an iPhone SE with the keyboard up fits about four). Rows after the first have a 1 pt
    /// divider above them.
    nonisolated static func rowCapacity(available: CGFloat, rowHeight: CGFloat) -> Int {
        guard available > 0, rowHeight > 0 else { return 0 }
        return Int(((available + 1) / (rowHeight + 1)).rounded(.down))
    }

    private func suggestionRows(capacity: Int) -> [SuggestRow] {
        guard !typed.isEmpty else { return [] }
        return Suggest.rows(Suggest.rank(query, owned: owned), literal: Suggest.literal(for: query), owned: owned,
                            capacity: capacity)
    }

    private var customField: some View {
        HStack(spacing: 4) {
            TextField("", text: $query, prompt: Text(AddCopy.fieldPrompt).foregroundStyle(theme.fgFaint))
                .font(.sans(17, .sans, relativeTo: .body))
                .foregroundStyle(theme.fg)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($customFocused)
                .onSubmit(submit)
                .accessibilityLabel(AddCopy.fieldLabel)
            if !query.isEmpty {
                Button {
                    query = ""
                    if !customFocused { typing = false }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(theme.fgFaint)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(AddCopy.clear)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 3)
        .frame(height: fieldHeight)
        .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: theme.radius.card / 2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.radius.card / 2, style: .continuous)
                .strokeBorder(customFocused ? theme.signalEdge : theme.line, lineWidth: 1)
        )
        .onAppear {
            // The field is inserted by the tap, so defaultFocus would not fire; one main-actor hop lets it join the
            // hierarchy first, and the keyboard rises while it slides in.
            Task { @MainActor in customFocused = true }
        }
    }

    @ViewBuilder
    private func suggestionRow(_ row: SuggestRow) -> some View {
        switch row {
        case .match(let suggestion):
            matchRow(suggestion)
        case .literal(let text, let owned):
            literalRow(text, owned: owned)
        }
    }

    private func matchRow(_ suggestion: Suggestion) -> some View {
        let name = suggestion.entry.name
        return Button {
            pick(name)
        } label: {
            HStack(spacing: 6) {
                nameText(suggestion)
                    .lineLimit(1)
                    .layoutPriority(1)
                if let alias = suggestion.alias {
                    Text("\u{00B7} \(alias)")
                        .font(.sans(15, .sans, relativeTo: .subheadline))
                        .foregroundStyle(theme.fgFaint)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if suggestion.owned { ownedCheck }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .disabled(suggestion.owned)
        .accessibilityLabel(suggestion.alias.map { "\(name), \($0)" } ?? name)
        .accessibilityValue(suggestion.owned ? AddCopy.inStack : "")
    }

    /// What was typed in fgMuted and the completion in fg semibold, so the rest of the word is what stands out.
    private func nameText(_ suggestion: Suggestion) -> Text {
        let name = suggestion.entry.name
        guard !suggestion.owned else {
            return Text(name).font(.sans(17, .sans, relativeTo: .body)).foregroundStyle(theme.fgFaint)
        }
        let segments = suggestion.alias == nil && suggestion.tier < 3
            ? Suggest.segments(of: name, typed: query)
            : [Suggest.Segment(text: name, typed: false)]
        var text = AttributedString()
        for segment in segments {
            var part = AttributedString(segment.text)
            let color: Color = segment.typed ? theme.fgMuted : theme.fg
            let font: Font = segment.typed ? .sans(17, .sans, relativeTo: .body) : .sans(17, .sansSemibold, relativeTo: .body)
            part[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = color
            part[AttributeScopes.SwiftUIAttributes.FontAttribute.self] = font
            text += part
        }
        return Text(text)
    }

    private func literalRow(_ text: String, owned: Bool) -> some View {
        Button {
            pick(text)
        } label: {
            HStack(spacing: 6) {
                Text("+ " + AddCopy.literal(text))
                    .font(.sans(17, .sansMedium, relativeTo: .body))
                    .foregroundStyle(owned ? theme.fgFaint : theme.signalInk)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if owned { ownedCheck }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .disabled(owned)
        .accessibilityLabel(AddCopy.literal(text))
        .accessibilityValue(owned ? AddCopy.inStack : "")
    }

    private var ownedCheck: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(theme.fgFaint)
    }

    /// Return picks the first row that can be picked; with nothing to pick, type mode ends.
    private func submit() {
        let rows = Suggest.rows(Suggest.rank(query, owned: owned), literal: Suggest.literal(for: query), owned: owned,
                                capacity: .max)
        if let first = Suggest.firstPick(rows) {
            pick(first.name)
        } else {
            leaveTypeMode()
        }
    }

    /// A pick from the suggestions: a chip lights up in the grid, any other name becomes a selected chip just before
    /// + CUSTOM, and its How often row fades in. The field closes back into + CUSTOM.
    private func pick(_ name: String) {
        Haptics.selection(model.hapticsOn)
        if !isPicked(name) {
            if let entry = Catalog.entry(named: name), entry.isChip {
                selected.append(entry.name)
            } else {
                extras.append(name)
            }
        }
        leaveTypeMode()
    }

    private func leaveTypeMode() {
        query = ""
        customFocused = false
        typing = false
    }

    private func isPicked(_ name: String) -> Bool {
        let key = Catalog.lookupKey(name)
        return (selected + extras).contains { Catalog.lookupKey($0) == key }
    }

    private func announceSuggestions() {
        announcement?.cancel()
        guard customFocused, !typed.isEmpty, UIAccessibility.isVoiceOverRunning else { return }
        let text = AddCopy.suggestions(Suggest.rank(query, owned: owned).count)
        // Once typing pauses, not on every letter.
        announcement = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            AccessibilityNotification.Announcement(text).post()
        }
    }

    // MARK: Chips

    private func chipLabel(_ name: String, isOn: Bool, owned: Bool) -> some View {
        HStack(spacing: 7) {
            if owned {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
            } else if isOn {
                LampShape(roundness: theme.radius.lampRoundness).fill(theme.signal).frame(width: 6, height: 6)
                    .shadow(color: theme.glow(0.7), radius: 3)
            }
            Text(name.uppercased())
                .font(.monoFixed(12, .monoMedium))
                .tracking(12 * 0.08)
                .lineLimit(1)
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

    private func chip(_ preset: Preset) -> some View {
        let isOn = selected.contains(preset.name)
        let inStack = owned.contains(Catalog.lookupKey(preset.name))
        return Button {
            toggle(preset.name)
        } label: {
            chipLabel(preset.name, isOn: isOn, owned: inStack)
        }
        .buttonStyle(PressStyle())
        .disabled(inStack)
        .accessibilityLabel(preset.name)
        .accessibilityValue(inStack ? AddCopy.inStack : (isOn ? AddCopy.selectedValue : AddCopy.notSelectedValue))
    }

    /// A picked name that is not a chip. A tap takes it off again.
    private func extraChip(_ name: String) -> some View {
        Button {
            Haptics.selection(model.hapticsOn)
            extras.removeAll { $0 == name }
        } label: {
            chipLabel(name, isOn: true, owned: false)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(name)
        .accessibilityValue(AddCopy.selectedValue)
    }

    /// Opens type mode, and shows itself selected while the field is open; a second tap closes it and drops the text.
    private var customChip: some View {
        Button {
            Haptics.selection(model.hapticsOn)
            if typing { leaveTypeMode() } else { typing = true }
        } label: {
            Text(typing ? "\u{2212} CUSTOM" : "+ CUSTOM")
                .font(.monoFixed(12, .monoMedium))
                .tracking(12 * 0.08)
                .foregroundStyle(typing ? theme.signalInk : theme.fgMuted)
                .padding(.horizontal, 13)
                .frame(height: 44)
                .background(typing ? theme.signalWash : Color.clear,
                            in: RoundedRectangle(cornerRadius: theme.radius.control))
                .overlay(
                    RoundedRectangle(cornerRadius: theme.radius.control)
                        .strokeBorder(typing ? theme.signalEdge : theme.lineStrong, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(AddCopy.customChip)
        .accessibilityValue(typing ? AddCopy.selectedValue : AddCopy.notSelectedValue)
    }

    // MARK: How often

    private func frequencyChoice(for name: String) -> FrequencyChoice {
        choices[name] ?? AddPlan.defaultChoice(for: name)
    }

    /// One picked item and how often it is taken. Days shows the weekdays under it; Weekly shows them to pick its one
    /// day, starting on today's.
    private func frequencyRow(_ name: String) -> some View {
        let choice = frequencyChoice(for: name)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(name)
                    .font(.sans(16, .sansMedium, relativeTo: .body))
                    .foregroundStyle(theme.fg)
                    .lineLimit(1)
                Spacer(minLength: 8)
                FrequencyMenu(choice: Binding(get: { frequencyChoice(for: name) }, set: { choices[name] = $0 }))
                    .accessibilityLabel("\(name), \(AddCopy.howOften.lowercased())")
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
            .frame(minHeight: 52)
            if choice == .days {
                WeekdayPicker(selection: Binding(get: { days[name] ?? FrequencyChoice.defaultDays },
                                                 set: { days[name] = $0 }))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else if choice == .weekly {
                WeekdayPicker(selection: Binding(get: { [weekly[name] ?? weekday] },
                                                 set: { weekly[name] = $0.first }),
                              single: true)
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
        let drafts = AddPlan.drafts(selected: selected, extras: extras + fieldPick, choices: choices, days: days,
                                    weekly: weekly, weekday: weekday)
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
            Picker(AddCopy.howOften, selection: Binding(get: { choice }, set: { newValue in
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

/// Weekday toggles, Monday first. `single` (Weekly): a tap selects only that day.
struct WeekdayPicker: View {
    @Environment(\.theme) private var theme
    @Binding var selection: Set<Int>
    let single: Bool

    private let order = [2, 3, 4, 5, 6, 7, 1]

    init(selection: Binding<Set<Int>>, single: Bool = false) {
        self._selection = selection
        self.single = single
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(order.enumerated()), id: \.element) { index, weekday in
                let on = selection.contains(weekday)
                Button {
                    if single {
                        selection = [weekday]
                    } else if on {
                        selection.remove(weekday)
                    } else {
                        selection.insert(weekday)
                    }
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

/// Wrapping layout for chips. A chip wider than a line (a long typed name) is offered the line's width, so it
/// truncates instead of running off the sheet.
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
            let size = subview.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
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
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
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
