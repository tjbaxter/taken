import StoreKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.paywallAnchor) private var paywallAnchor
    @Environment(\.theme) private var theme

    @State private var editMode: EditMode = .inactive
    @State private var pendingDelete: Item?
    @State private var confirmErase = false
    @State private var showAdd = false
    @State private var redeeming = false
    @State private var managing = false
    @State private var restoring = false
    @State private var proNote: String?

    init() {}

    /// The LOOK row, which `-demo -screen look` scrolls to.
    static let lookAnchor = "look"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    stackSection
                    reminderSection
                    dayStartSection
                    lookSection
                    hapticsSection
                    proSection
                    dataSection
                    aboutSection
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(theme.bg)
                .environment(\.editMode, $editMode)
                .task {
                    // `-demo -screen look`: the LOOK section in view, for the screenshots.
                    guard model.isDemo && model.launchScreen == "look" else { return }
                    try? await Task.sleep(for: .milliseconds(500))
                    proxy.scrollTo(Self.lookAnchor, anchor: .center)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SETTINGS")
                        .font(.monoFixed(14, .monoSemibold))
                        .tracking(14 * 0.2)
                        .foregroundStyle(theme.fg)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("DONE")
                            .font(.monoFixed(13, .monoSemibold))
                            .tracking(13 * 0.12)
                            .foregroundStyle(theme.fg)
                    }
                }
            }
            .toolbarBackground(theme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                ItemEditorView(itemID: id, isSheet: false)
            }
            .sheet(isPresented: $showAdd) {
                AddSheet()
                    .paywallHost(.nested)
                    .environment(model)
                    .environment(\.theme, model.theme)
                    .preferredColorScheme(model.theme.scheme)
            }
            .offerCodeRedemption(isPresented: $redeeming) { _ in
                Task { await model.pro.refresh() }
            }
            .manageSubscriptionsSheet(isPresented: $managing)
            .onChange(of: managing) { _, open in
                // A plan changed or cancelled in Apple's sheet shows here at once.
                if !open { Task { await model.pro.refresh() } }
            }
            .confirmationDialog(
                "Delete \(pendingDelete?.name ?? "item")?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible,
                presenting: pendingDelete
            ) { item in
                Button("Delete \(item.name)", role: .destructive) {
                    model.deleteItem(id: item.id)
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: { _ in
                Text("Its log entries leave your stats. To keep its history, archive it instead.")
            }
            .confirmationDialog("Erase all data?", isPresented: $confirmErase, titleVisibility: .visible) {
                Button("Erase all data", role: .destructive) { model.eraseAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes your stack and every logged dose from this iPhone. It cannot be undone.")
            }
        }
        // Links, menus and dialogs take the readable signal; the toggles below take the lit one.
        .tint(theme.signalInk)
        .presentationBackground(theme.bg)
        .presentationDetents([.large])
    }

    // MARK: Sections

    private var proActive: Bool { model.pro.isActive(at: model.now) }

    private var proStatusLine: String {
        if model.pro.status == nil && !model.pro.settled { return "CHECKING" }
        return ProCopy.statusLine(model.pro.status, now: model.now)
    }

    /// Manage subscription matters to subscribers, to anyone without Pro (an ended plan restarts there), and to a
    /// lifetime or founding member whose subscription still renews.
    private var showsManage: Bool {
        guard proActive, let status = model.pro.status else { return true }
        switch status.reason {
        case .lifetime, .founding: return status.renewingSubscription
        case .trial, .yearly, .monthly, .none: return true
        }
    }

    /// Pro for good, and a subscription on the same Apple Account still charging for it.
    private var renewsNextToProForGood: Bool {
        guard proActive, let status = model.pro.status else { return false }
        return (status.reason == .lifetime || status.reason == .founding) && status.renewingSubscription
    }

    private var proSection: some View {
        Section {
            HStack(spacing: 10) {
                Lamp(on: proActive)
                Text(proStatusLine)
                    .hud(12, proActive ? theme.signalInk : theme.fg, tracking: 0.1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(minHeight: 44)
            .settingsRow()
            .accessibilityElement(children: .combine)

            if renewsNextToProForGood {
                Text(ProCopy.renewingNextToProForGood)
                    .font(.sans(14))
                    .foregroundStyle(theme.fgMuted)
                    .settingsRow()
            }

            if !proActive {
                Button {
                    model.presentPaywall(anchor: paywallAnchor, origin: .settings)
                } label: {
                    SettingsLinkRow(title: "SEE PLANS", symbol: "arrow.right")
                }
                .settingsRow()
            }

            Button {
                restore()
            } label: {
                SettingsLinkRow(title: restoring ? "RESTORING" : "RESTORE PURCHASES", symbol: "arrow.clockwise")
            }
            .disabled(restoring)
            .settingsRow()

            Button {
                redeeming = true
            } label: {
                SettingsLinkRow(title: "REDEEM CODE", symbol: "ticket")
            }
            .settingsRow()

            if showsManage {
                Button {
                    managing = true
                } label: {
                    SettingsLinkRow(title: "MANAGE SUBSCRIPTION", symbol: "arrow.up.right")
                }
                .settingsRow()
            }

            Link(destination: ProCopy.termsOfUseURL) {
                SettingsLinkRow(title: "TERMS OF USE", symbol: "arrow.up.right")
            }
            .settingsRow()
            Link(destination: ProCopy.privacyURL) {
                SettingsLinkRow(title: "PRIVACY POLICY", symbol: "arrow.up.right")
            }
            .settingsRow()

            if let proNote {
                Text(proNote)
                    .font(.sans(14))
                    .foregroundStyle(theme.fgSubtle)
                    .settingsRow()
            }
        } header: {
            SettingsHeader(index: "06", title: "PRO") { EmptyView() }
        }
    }

    private func restore() {
        restoring = true
        proNote = nil
        Task {
            let outcome = await model.pro.restore()
            restoring = false
            switch outcome {
            case .restored:
                proNote = ProCopy.restored
            case .nothing:
                proNote = ProCopy.nothingToRestore
            case .cancelled:
                proNote = nil
            case .failed(let text):
                proNote = text
            }
        }
    }

    private var stackSection: some View {
        Section {
            if model.activeItems.isEmpty {
                Text("NOTHING IN YOUR STACK").hud(11, theme.fgFaint)
                    .settingsRow()
            }
            ForEach(model.activeItems) { item in
                NavigationLink(value: item.id) {
                    StackSettingsRow(item: item, archived: false)
                }
                .settingsRow()
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        pendingDelete = item
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .onMove { source, destination in
                model.moveItems(from: source, to: destination)
            }
            .deleteDisabled(true)

            Button {
                let show = $showAdd
                model.requirePro(paywallAnchor) { show.wrappedValue = true }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                    Text("ADD").hud(12, theme.fg, face: .monoSemibold)
                }
                .foregroundStyle(theme.fg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .settingsRow()

            ForEach(model.archivedItems) { item in
                NavigationLink(value: item.id) {
                    StackSettingsRow(item: item, archived: true)
                }
                .settingsRow()
            }
        } header: {
            SettingsHeader(index: "01", title: "STACK") {
                if model.activeItems.count > 1 {
                    Button {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    } label: {
                        Text(editMode.isEditing ? "DONE" : "REORDER")
                            .hudFixed(10.5, editMode.isEditing ? theme.signalInk : theme.fgMuted, tracking: 0.12)
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var reminderSection: some View {
        Section {
            // Without Pro a tap on the toggle opens the paywall, and the nudge (with iOS's permission prompt) comes on
            // once Pro does. Turning it off always works.
            Toggle(isOn: Binding(
                get: { model.settings.reminderEnabled },
                set: { enabled in model.setReminder(enabled, anchor: paywallAnchor) }
            )) {
                Text("NUDGE").hud(12, theme.fg)
            }
            .tint(theme.signal)
            .settingsRow()

            if model.settings.reminderEnabled {
                HStack {
                    Text("TIME").hud(12, theme.fg)
                    Spacer()
                    MonoTimeButton(title: "NUDGE TIME", minutes: model.settings.reminderMinutes) { minutes in
                        model.setReminderMinutes(minutes)
                    }
                }
                .settingsRow()
            }

            Text("If anything is still pending at this time, nudge me.")
                .font(.sans(14))
                .foregroundStyle(theme.fgSubtle)
                .settingsRow()

            if model.isLocked {
                // No nudge is scheduled without Pro: say so here, where it is set, and let the line open the plans.
                Button {
                    model.presentPaywall(anchor: paywallAnchor, origin: .settings)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.signalInk)
                        Text(ProCopy.nudgeLocked)
                            .hud(10.5, theme.signalInk, tracking: 0.1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.fgSubtle)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .settingsRow()
                .accessibilityLabel("The nudge needs Taken Pro")
                .accessibilityHint("Opens Taken Pro.")
            }

            if model.notificationsDenied {
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                } label: {
                    Text("NOTIFICATIONS ARE OFF FOR TAKEN. OPEN SETTINGS")
                        .hud(10.5, theme.signalInk, tracking: 0.1)
                        .frame(minHeight: 44)
                }
                .settingsRow()
            }
        } header: {
            SettingsHeader(index: "02", title: "REMINDER") { EmptyView() }
        }
    }

    private var dayStartSection: some View {
        Section {
            HStack {
                Text("DAY STARTS AT").hud(12, theme.fg)
                Spacer()
                Menu {
                    Picker("Day starts at", selection: Binding(get: { model.settings.dayStartHour },
                                                               set: { model.setDayStartHour($0) })) {
                        ForEach(0..<13, id: \.self) { hour in
                            Text(Fmt.hour(hour)).tag(hour)
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(Fmt.hour(model.settings.dayStartHour))
                            .font(.monoFixed(15, .monoMedium))
                            .foregroundStyle(theme.fg)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.fgSubtle)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Day starts at \(Fmt.hour(model.settings.dayStartHour))")
            }
            .settingsRow()

            Text("A dose before this time counts for the day before, so a late night stays on the right day.")
                .font(.sans(14))
                .foregroundStyle(theme.fgSubtle)
                .settingsRow()
        } header: {
            SettingsHeader(index: "03", title: "DAY") { EmptyView() }
        }
    }

    /// Four looks, one tap each. The swatches are live miniatures drawn in each look's own tokens; the app, the
    /// widgets, the Control Center control and the app icon follow the one chosen.
    private var lookSection: some View {
        Section {
            LookPicker(selection: model.theme.id) { look in
                model.setLook(look)
            }
            // The hairline under the swatches runs the full width, like the rows around it.
            .alignmentGuide(.listRowSeparatorLeading) { dimensions in dimensions[.leading] }
            .settingsRow()
            .id(Self.lookAnchor)

            Text("The widgets and the app icon follow it.")
                .font(.sans(14))
                .foregroundStyle(theme.fgSubtle)
                .settingsRow()
        } header: {
            SettingsHeader(index: "04", title: "LOOK") {
                Text(model.theme.label)
                    .hudFixed(10.5, theme.signalInk, tracking: 0.12)
            }
        }
    }

    private var hapticsSection: some View {
        Section {
            Toggle(isOn: Binding(get: { model.settings.hapticsEnabled }, set: { model.setHaptics($0) })) {
                Text("HAPTICS").hud(12, theme.fg)
            }
            .tint(theme.signal)
            .settingsRow()
        } header: {
            SettingsHeader(index: "05", title: "FEEL") { EmptyView() }
        }
    }

    private var dataSection: some View {
        Section {
            ShareLink(item: CSVFile(text: model.csv()), preview: SharePreview("taken-log.csv")) {
                SettingsLinkRow(title: "EXPORT CSV", symbol: "square.and.arrow.up")
            }
            .settingsRow()

            Button {
                confirmErase = true
            } label: {
                Text("ERASE ALL DATA")
                    .hud(12, theme.danger)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .settingsRow()
        } header: {
            SettingsHeader(index: "07", title: "DATA") { EmptyView() }
        }
    }

    private var aboutSection: some View {
        Section {
            Text("Everything stays on this iPhone. No accounts. No ads. No tracking.")
                .font(.sans(15))
                .foregroundStyle(theme.fgMuted)
                .padding(.vertical, 6)
                .settingsRow()
            HStack {
                Text("VERSION").hud(12, theme.fg)
                Spacer()
                Text("\(AppInfo.version) (\(AppInfo.build))").hud(12, theme.fgSubtle, tracking: 0.08)
            }
            .frame(minHeight: 44)
            .settingsRow()
            Link(destination: URL(string: "https://tjbaxter.github.io/taken/")!) {
                SettingsLinkRow(title: "SUPPORT", symbol: "arrow.up.right")
            }
            .settingsRow()
        } header: {
            SettingsHeader(index: "08", title: "ABOUT") { EmptyView() }
        } footer: {
            Text("TAKEN \(AppInfo.versionLine)")
                .hudFixed(9.5, theme.fgFaint)
                .padding(.top, 18)
                .padding(.bottom, 30)
        }
    }

}

private struct SettingsHeader<Trailing: View>: View {
    @Environment(\.theme) private var theme
    let index: String
    let title: String
    var trailing: Trailing

    init(index: String, title: String, @ViewBuilder trailing: () -> Trailing) {
        self.index = index
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("[\(index)]").hudFixed(11, theme.fgFaint, tracking: 0.06)
            Text(title).hudFixed(11, theme.fgMuted, tracking: 0.16)
            DashedRule().frame(maxWidth: .infinity)
            trailing
        }
        .padding(.top, 22)
        .padding(.bottom, 8)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg)
        .listRowInsets(EdgeInsets())
    }
}

private struct StackSettingsRow: View {
    @Environment(\.theme) private var theme
    let item: Item
    let archived: Bool

    init(item: Item, archived: Bool) {
        self.item = item
        self.archived = archived
    }

    var body: some View {
        HStack(spacing: 12) {
            CodeTag(code: item.code, dim: archived)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.sans(16, .sansMedium))
                    .foregroundStyle(archived ? theme.fgSubtle : theme.fg)
                    .lineLimit(1)
                Text(archived ? "ARCHIVED" : Fmt.frequency(item.frequency))
                    .hud(10, theme.fgSubtle, tracking: 0.12)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct SettingsLinkRow: View {
    @Environment(\.theme) private var theme
    let title: String
    let symbol: String

    init(title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        HStack {
            Text(title).hud(12, theme.fg)
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.fgSubtle)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// A Settings row on the look's canvas, with its hairline separators.
private struct SettingsRow: ViewModifier {
    @Environment(\.theme) private var theme

    init() {}

    func body(content: Content) -> some View {
        content
            .listRowBackground(theme.bg)
            .listRowSeparatorTint(theme.line)
            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
    }
}

private extension View {
    func settingsRow() -> some View {
        modifier(SettingsRow())
    }
}

/// The CSV export as a shareable file.
struct CSVFile: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("taken-log.csv")
            try Data(file.text.utf8).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}

/// Edit one item: name, code tag, frequency, archive, delete.
struct ItemEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    let itemID: UUID
    let isSheet: Bool

    @State private var name = ""
    @State private var code = ""
    @State private var choice: FrequencyChoice = .daily
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var archived = false
    @State private var loaded = false
    @State private var deleted = false
    @State private var confirmDelete = false

    init(itemID: UUID, isSheet: Bool) {
        self.itemID = itemID
        self.isSheet = isSheet
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(index: "01", title: "NAME")
                field(text: $name, prompt: "Name", mono: false)
                SectionHeader(index: "02", title: "CODE TAG", trailing: "UP TO 4")
                field(text: $code, prompt: "VD3", mono: true)
                    .onChange(of: code) { _, newValue in
                        let clean = Catalog.sanitizeCode(newValue)
                        if clean != newValue { code = clean }
                    }
                SectionHeader(index: "03", title: "FREQUENCY")
                FrequencyPicker(choice: $choice, includeDays: true)
                if choice == .days {
                    WeekdayPicker(selection: $weekdays)
                        .padding(.top, 12)
                }
                SectionHeader(index: "04", title: "STATUS")
                Toggle(isOn: $archived) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ARCHIVED").hud(12, theme.fg)
                        Text("Hidden from today. History stays.")
                            .font(.sans(13))
                            .foregroundStyle(theme.fgSubtle)
                    }
                }
                .tint(theme.signal)
                .padding(.vertical, 4)

                OutlineButton(title: "DELETE ITEM", color: theme.danger, height: 48) {
                    confirmDelete = true
                }
                .padding(.top, 30)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("EDIT \u{00B7} \(code.isEmpty ? "ITEM" : code)")
                    .font(.monoFixed(14, .monoSemibold))
                    .tracking(14 * 0.16)
                    .foregroundStyle(theme.fg)
            }
            if isSheet {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                        dismiss()
                    } label: {
                        Text("DONE")
                            .font(.monoFixed(13, .monoSemibold))
                            .tracking(13 * 0.12)
                            .foregroundStyle(theme.fg)
                    }
                }
            }
        }
        .toolbarBackground(theme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear(perform: load)
        .onDisappear(perform: save)
        .confirmationDialog("Delete \(name.isEmpty ? "this item" : name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleted = true
                model.deleteItem(id: itemID)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its log entries leave your stats. To keep its history, archive it instead.")
        }
    }

    private func field(text: Binding<String>, prompt: String, mono: Bool) -> some View {
        TextField("", text: text, prompt: Text(prompt).foregroundStyle(theme.fgFaint))
            .font(mono ? .monoFixed(17, .monoMedium) : .sans(17))
            .foregroundStyle(theme.fg)
            .textInputAutocapitalization(mono ? .characters : .words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: theme.radius.control))
            .overlay(RoundedRectangle(cornerRadius: theme.radius.control).strokeBorder(theme.line, lineWidth: 1))
    }

    private func load() {
        guard !loaded, let item = model.state.item(itemID) else { return }
        loaded = true
        name = item.name
        code = item.code
        choice = FrequencyChoice(item.frequency)
        if case .weekdays(let days) = item.frequency, !days.isEmpty { weekdays = days }
        archived = item.archived
    }

    private func save() {
        guard loaded, !deleted, let item = model.state.item(itemID) else { return }
        let frequency = choice.frequency(weekdays: weekdays)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = cleanName != item.name || code != item.code || frequency != item.frequency || archived != item.archived
        guard changed else { return }
        model.updateItem(id: itemID, name: cleanName.isEmpty ? item.name : cleanName, code: code,
                         frequency: frequency, archived: archived)
    }
}
