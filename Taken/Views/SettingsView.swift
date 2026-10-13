import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var editMode: EditMode = .inactive
    @State private var pendingDelete: Item?
    @State private var confirmErase = false
    @State private var showAdd = false

    init() {}

    var body: some View {
        NavigationStack {
            List {
                stackSection
                reminderSection
                dayStartSection
                hapticsSection
                dataSection
                aboutSection
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
            .environment(\.editMode, $editMode)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SETTINGS")
                        .font(.monoFixed(14, .monoSemibold))
                        .tracking(14 * 0.2)
                        .foregroundStyle(Palette.fg)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("DONE")
                            .font(.monoFixed(13, .monoSemibold))
                            .tracking(13 * 0.12)
                            .foregroundStyle(Palette.fg)
                    }
                }
            }
            .toolbarBackground(Palette.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                ItemEditorView(itemID: id, isSheet: false)
            }
            .sheet(isPresented: $showAdd) {
                AddSheet()
                    .environment(model)
                    .preferredColorScheme(.dark)
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
        .tint(Palette.signal)
        .presentationBackground(Palette.bg)
        .presentationDetents([.large])
    }

    // MARK: Sections

    private var stackSection: some View {
        Section {
            if model.activeItems.isEmpty {
                Text("NOTHING IN YOUR STACK").hud(11, Palette.fgFaint)
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
                showAdd = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                    Text("ADD").hud(12, Palette.fg, face: .monoSemibold)
                }
                .foregroundStyle(Palette.fg)
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
                            .hudFixed(10.5, editMode.isEditing ? Palette.signal : Palette.fgMuted, tracking: 0.12)
                            .frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var reminderSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { model.settings.reminderEnabled },
                set: { enabled in Task { await model.setReminderEnabled(enabled) } }
            )) {
                Text("NUDGE").hud(12, Palette.fg)
            }
            .settingsRow()

            if model.settings.reminderEnabled {
                HStack {
                    Text("TIME").hud(12, Palette.fg)
                    Spacer()
                    MonoTimeButton(title: "NUDGE TIME", minutes: model.settings.reminderMinutes) { minutes in
                        model.setReminderMinutes(minutes)
                    }
                }
                .settingsRow()
            }

            Text("If anything is still pending at this time, nudge me.")
                .font(.sans(14))
                .foregroundStyle(Palette.fgSubtle)
                .settingsRow()

            if model.notificationsDenied {
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                } label: {
                    Text("NOTIFICATIONS ARE OFF FOR TAKEN. OPEN SETTINGS")
                        .hud(10.5, Palette.signal, tracking: 0.1)
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
                Text("DAY STARTS AT").hud(12, Palette.fg)
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
                            .foregroundStyle(Palette.fg)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.fgSubtle)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Day starts at \(Fmt.hour(model.settings.dayStartHour))")
            }
            .settingsRow()

            Text("A dose before this time counts for the day before, so a late night stays on the right day.")
                .font(.sans(14))
                .foregroundStyle(Palette.fgSubtle)
                .settingsRow()
        } header: {
            SettingsHeader(index: "03", title: "DAY") { EmptyView() }
        }
    }

    private var hapticsSection: some View {
        Section {
            Toggle(isOn: Binding(get: { model.settings.hapticsEnabled }, set: { model.setHaptics($0) })) {
                Text("HAPTICS").hud(12, Palette.fg)
            }
            .settingsRow()
        } header: {
            SettingsHeader(index: "04", title: "FEEL") { EmptyView() }
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
                    .hud(12, Palette.danger)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .settingsRow()
        } header: {
            SettingsHeader(index: "05", title: "DATA") { EmptyView() }
        }
    }

    private var aboutSection: some View {
        Section {
            Text("Everything stays on this iPhone. No accounts. No ads. No tracking.")
                .font(.sans(15))
                .foregroundStyle(Palette.fgMuted)
                .padding(.vertical, 6)
                .settingsRow()
            HStack {
                Text("VERSION").hud(12, Palette.fg)
                Spacer()
                Text("\(AppInfo.version) (\(AppInfo.build))").hud(12, Palette.fgSubtle, tracking: 0.08)
            }
            .frame(minHeight: 44)
            .settingsRow()
            Link(destination: URL(string: "https://tjbaxter.github.io/taken/privacy.html")!) {
                SettingsLinkRow(title: "PRIVACY POLICY", symbol: "arrow.up.right")
            }
            .settingsRow()
            Link(destination: URL(string: "https://tjbaxter.github.io/taken/")!) {
                SettingsLinkRow(title: "SUPPORT", symbol: "arrow.up.right")
            }
            .settingsRow()
        } header: {
            SettingsHeader(index: "06", title: "ABOUT") { EmptyView() }
        } footer: {
            Text("TAKEN \(AppInfo.versionLine)")
                .hudFixed(9.5, Palette.fgFaint)
                .padding(.top, 18)
                .padding(.bottom, 30)
        }
    }

}

private struct SettingsHeader<Trailing: View>: View {
    let index: String
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            Text("[\(index)]").hudFixed(11, Palette.fgFaint, tracking: 0.06)
            Text(title).hudFixed(11, Palette.fgMuted, tracking: 0.16)
            DashedRule().frame(maxWidth: .infinity)
            trailing
        }
        .padding(.top, 22)
        .padding(.bottom, 8)
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.bg)
        .listRowInsets(EdgeInsets())
    }
}

private struct StackSettingsRow: View {
    let item: Item
    let archived: Bool

    var body: some View {
        HStack(spacing: 12) {
            CodeTag(code: item.code, dim: archived)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.sans(16, .sansMedium))
                    .foregroundStyle(archived ? Palette.fgSubtle : Palette.fg)
                    .lineLimit(1)
                Text(archived ? "ARCHIVED" : Fmt.frequency(item.frequency))
                    .hud(10, Palette.fgSubtle, tracking: 0.12)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct SettingsLinkRow: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack {
            Text(title).hud(12, Palette.fg)
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.fgSubtle)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

private extension View {
    func settingsRow() -> some View {
        self
            .listRowBackground(Palette.bg)
            .listRowSeparatorTint(Palette.line)
            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
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
                        Text("ARCHIVED").hud(12, Palette.fg)
                        Text("Hidden from today. History stays.")
                            .font(.sans(13))
                            .foregroundStyle(Palette.fgSubtle)
                    }
                }
                .tint(Palette.signal)
                .padding(.vertical, 4)

                OutlineButton(title: "DELETE ITEM", color: Palette.danger, height: 48) {
                    confirmDelete = true
                }
                .padding(.top, 30)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("EDIT \u{00B7} \(code.isEmpty ? "ITEM" : code)")
                    .font(.monoFixed(14, .monoSemibold))
                    .tracking(14 * 0.16)
                    .foregroundStyle(Palette.fg)
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
                            .foregroundStyle(Palette.fg)
                    }
                }
            }
        }
        .toolbarBackground(Palette.bg, for: .navigationBar)
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
        TextField("", text: text, prompt: Text(prompt).foregroundStyle(Palette.fgFaint))
            .font(mono ? .monoFixed(17, .monoMedium) : .sans(17))
            .foregroundStyle(Palette.fg)
            .textInputAutocapitalization(mono ? .characters : .words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(Palette.bgRaised, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.line, lineWidth: 1))
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
