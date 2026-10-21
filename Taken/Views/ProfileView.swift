import PhotosUI
import StoreKit
import SwiftUI
import UniformTypeIdentifiers

/// Profile (REDESIGN.md): the avatar on every tab opens it. A name and a photo, both optional and kept on this iPhone,
/// the streak, then every setting: Stack, Look, Reminder, Wake-up time, Haptics, Taken Pro, Data and About.
struct ProfileView: View {
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
    @State private var name = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var pickingPhoto = false
    @State private var loadingPhoto = false
    #if DEBUG || TAKEN_INTERNAL
    @State private var showVoiceLog = false
    #endif

    init() {}

    /// The Look row, which `-demo -screen look` scrolls to.
    static let lookAnchor = "look"

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    header
                    stackSection
                    lookSection
                    reminderSection
                    wakeSection
                    hapticsSection
                    proSection
                    dataSection
                    #if DEBUG || TAKEN_INTERNAL
                    if InternalBuild.unlocksPro { internalSection }
                    #endif
                    aboutSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(theme.bg)
                .environment(\.editMode, $editMode)
                .photosPicker(isPresented: $pickingPhoto, selection: $photoItem, matching: .images)
                .task {
                    // `-demo -screen look`: the Look section in view, for the screenshots.
                    guard model.isDemo && model.launchScreen == "look" else { return }
                    try? await Task.sleep(for: .milliseconds(500))
                    proxy.scrollTo(Self.lookAnchor, anchor: .center)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Profile")
                        .font(.sans(17, .sansSemibold, relativeTo: .body))
                        .foregroundStyle(theme.fg)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        saveName()
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.sans(17, .sansSemibold, relativeTo: .body))
                            .foregroundStyle(theme.signalInk)
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
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                loadPhoto(item)
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
                Button("Erase all data", role: .destructive) {
                    model.eraseAll()
                    // The field forgets the name too, so closing Profile never writes it back.
                    name = ""
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(Self.eraseMessage)
            }
        }
        .onAppear { name = model.profile.name }
        .onDisappear { saveName() }
        // Links, menus and dialogs take the readable signal; the toggles below take the lit one.
        .tint(theme.signalInk)
        .presentationBackground(theme.bg)
        .presentationDetents([.large])
    }

    /// What Erase all data takes, said before it does.
    static let eraseMessage = "This removes your stack, every logged dose, all your to-dos and your profile from this iPhone. It cannot be undone."

    // MARK: Profile

    private var header: some View {
        Section {
            VStack(spacing: 14) {
                // A plain button opens Apple's photo picker (`.photosPicker` on the list), so the label stays main-actor code.
                Button {
                    pickingPhoto = true
                } label: {
                    photoBadge
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(model.profilePhoto == nil ? "Add a profile photo" : "Change your profile photo")
                TextField("", text: $name, prompt: Text("Your name").foregroundStyle(theme.fgFaint))
                    .font(.sans(22, .sansSemibold, relativeTo: .title2))
                    .foregroundStyle(theme.fg)
                    .multilineTextAlignment(.center)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(saveName)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Your name")
                Text(streakLine)
                    .font(.sans(15, .sans, relativeTo: .subheadline))
                    .foregroundStyle(theme.fgSubtle)
                    .multilineTextAlignment(.center)
                if model.profilePhoto != nil {
                    Button("Remove photo") { model.removeProfilePhoto() }
                        .font(.sans(15, .sansMedium, relativeTo: .subheadline))
                        .foregroundStyle(theme.fgMuted)
                        .frame(minHeight: 44)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    /// The avatar with a camera badge: a tap opens Apple's photo picker.
    private var photoBadge: some View {
        ZStack(alignment: .bottomTrailing) {
            ProfileAvatar(size: 92)
            Image(systemName: loadingPhoto ? "ellipsis" : "camera.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.buttonText)
                .frame(width: 30, height: 30)
                .background(theme.button, in: Circle())
                .overlay(Circle().strokeBorder(theme.bg, lineWidth: 2))
        }
        .frame(minWidth: 44, minHeight: 44)
    }

    /// "14-day streak · 97% over 30 days"
    private var streakLine: String {
        let percent = model.adherence.percent
        if model.state.doses.isEmpty { return "Your streak starts with your first dose." }
        let streak = model.streak == 1 ? "1-day streak" : "\(model.streak)-day streak"
        guard let percent else { return streak }
        return "\(streak) \u{00B7} \(percent)% over 30 days"
    }

    private func saveName() {
        let clean = Profile.clean(name)
        guard clean != model.profile.name else { return }
        model.setProfileName(clean)
    }

    private func loadPhoto(_ item: PhotosPickerItem) {
        loadingPhoto = true
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await model.setProfilePhoto(data)
            }
            loadingPhoto = false
            photoItem = nil
        }
    }

    // MARK: Stack

    private var stackSection: some View {
        Section {
            if model.activeItems.isEmpty {
                Text("Nothing in your stack yet")
                    .font(.sans(16, .sans, relativeTo: .body))
                    .foregroundStyle(theme.fgSubtle)
                    .profileRow()
            }
            ForEach(model.activeItems) { item in
                NavigationLink(value: item.id) {
                    StackRow(item: item, archived: false)
                }
                .profileRow()
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
                Label {
                    Text("Add to stack")
                        .font(.sans(17, .sansMedium, relativeTo: .body))
                } icon: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(theme.signalInk)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .profileRow()

            ForEach(model.archivedItems) { item in
                NavigationLink(value: item.id) {
                    StackRow(item: item, archived: true)
                }
                .profileRow()
            }
        } header: {
            HStack {
                ProfileSectionTitle("Stack")
                Spacer()
                if model.activeItems.count > 1 {
                    Button(editMode.isEditing ? "Done" : "Reorder") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                    .font(.sans(14, .sansMedium, relativeTo: .footnote))
                    .foregroundStyle(theme.signalInk)
                    .textCase(nil)
                    .frame(minHeight: 32)
                }
            }
        }
    }

    // MARK: Look

    /// Four looks, one tap each. The swatches are live miniatures drawn in each look's own tokens; the app, the
    /// widgets, the Control Center control and the app icon follow the one chosen.
    private var lookSection: some View {
        Section {
            LookPicker(selection: model.theme.id) { look in
                model.setLook(look)
            }
            .profileRow()
            .id(Self.lookAnchor)
        } header: {
            HStack {
                ProfileSectionTitle("Look")
                Spacer()
                Text(model.theme.id.title)
                    .font(.sans(14, .sansMedium, relativeTo: .footnote))
                    .foregroundStyle(theme.signalInk)
                    .textCase(nil)
            }
        } footer: {
            ProfileFootnote("The widgets and the app icon follow it.")
        }
    }

    // MARK: Reminder

    private var reminderSection: some View {
        Section {
            // Without Pro a tap on the toggle opens the paywall, and the nudge (with iOS's permission prompt) comes on
            // once Pro does. Turning it off always works.
            Toggle(isOn: Binding(
                get: { model.settings.reminderEnabled },
                set: { enabled in model.setReminder(enabled, anchor: paywallAnchor) }
            )) {
                ProfileRowTitle("Nudge")
            }
            .tint(theme.signal)
            .profileRow()

            if model.settings.reminderEnabled {
                HStack {
                    ProfileRowTitle("Time")
                    Spacer()
                    MonoTimeButton(title: "Nudge time", minutes: model.settings.reminderMinutes) { minutes in
                        model.setReminderMinutes(minutes)
                    }
                }
                .profileRow()
            }

            if model.isLocked {
                // No nudge is scheduled without Pro: say so here, where it is set, and let the line open the plans.
                Button {
                    model.presentPaywall(anchor: paywallAnchor, origin: .settings)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text(ProCopy.nudgeLocked)
                            .font(.sans(15, .sansMedium, relativeTo: .subheadline))
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.fgSubtle)
                    }
                    .foregroundStyle(theme.signalInk)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .profileRow()
                .accessibilityLabel("The nudge needs Taken Pro")
                .accessibilityHint("Opens Taken Pro.")
            }

            if model.notificationsDenied {
                Button {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                } label: {
                    Text("Notifications are off for Taken. Open Settings")
                        .font(.sans(15, .sansMedium, relativeTo: .subheadline))
                        .foregroundStyle(theme.signalInk)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .profileRow()
            }
        } header: {
            ProfileSectionTitle("Reminder")
        } footer: {
            ProfileFootnote("If anything is still pending at this time, Taken nudges you.")
        }
    }

    // MARK: Wake-up time

    private var wakeSection: some View {
        Section {
            HStack {
                ProfileRowTitle("Wake-up time")
                Spacer()
                MonoTimeButton(title: "Wake-up time", minutes: model.settings.wakeMinutes) { minutes in
                    model.setWakeMinutes(minutes)
                }
            }
            .profileRow()
        } header: {
            ProfileSectionTitle("Your day")
        } footer: {
            ProfileFootnote("Doses count for the day you wake up into.")
        }
    }

    // MARK: Haptics

    private var hapticsSection: some View {
        Section {
            Toggle(isOn: Binding(get: { model.settings.hapticsEnabled }, set: { model.setHaptics($0) })) {
                ProfileRowTitle("Haptics")
            }
            .tint(theme.signal)
            .profileRow()
        } header: {
            ProfileSectionTitle("Feel")
        }
    }

    // MARK: Taken Pro

    private var proActive: Bool { model.pro.isActive(at: model.now) }

    private var proStatusLine: String {
        if model.pro.status == nil && !model.pro.settled { return "Checking" }
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
                Circle()
                    .fill(proActive ? theme.signal : theme.fgFaint)
                    .frame(width: 8, height: 8)
                Text(proStatusLine)
                    .font(.sans(16, .sansMedium, relativeTo: .body))
                    .foregroundStyle(proActive ? theme.signalInk : theme.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(minHeight: 44)
            .profileRow()
            .accessibilityElement(children: .combine)

            if renewsNextToProForGood {
                Text(ProCopy.renewingNextToProForGood)
                    .font(.sans(15, .sans, relativeTo: .subheadline))
                    .foregroundStyle(theme.fgMuted)
                    .profileRow()
            }

            if !proActive {
                Button {
                    model.presentPaywall(anchor: paywallAnchor, origin: .settings)
                } label: {
                    ProfileLinkRow(title: "See plans", symbol: "chevron.right")
                }
                .profileRow()
            }

            Button {
                restore()
            } label: {
                ProfileLinkRow(title: restoring ? "Restoring" : "Restore purchases", symbol: "arrow.clockwise")
            }
            .disabled(restoring)
            .profileRow()

            Button {
                redeeming = true
            } label: {
                ProfileLinkRow(title: "Redeem code", symbol: "ticket")
            }
            .profileRow()

            if showsManage {
                Button {
                    managing = true
                } label: {
                    ProfileLinkRow(title: "Manage subscription", symbol: "arrow.up.right")
                }
                .profileRow()
            }

            Link(destination: ProCopy.termsOfUseURL) {
                ProfileLinkRow(title: "Terms of Use", symbol: "arrow.up.right")
            }
            .profileRow()
            Link(destination: ProCopy.privacyURL) {
                ProfileLinkRow(title: "Privacy Policy", symbol: "arrow.up.right")
            }
            .profileRow()

            if let proNote {
                Text(proNote)
                    .font(.sans(15, .sans, relativeTo: .subheadline))
                    .foregroundStyle(theme.fgSubtle)
                    .profileRow()
            }
        } header: {
            ProfileSectionTitle("Taken Pro")
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

    // MARK: Data and About

    private var dataSection: some View {
        Section {
            ShareLink(item: CSVFile(text: model.csv()), preview: SharePreview("taken-log.csv")) {
                ProfileLinkRow(title: "Export CSV", symbol: "square.and.arrow.up")
            }
            .profileRow()

            Button {
                confirmErase = true
            } label: {
                Text("Erase all data")
                    .font(.sans(17, .sans, relativeTo: .body))
                    .foregroundStyle(theme.danger)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .profileRow()
        } header: {
            ProfileSectionTitle("Data")
        }
    }

    #if DEBUG || TAKEN_INTERNAL
    /// The owner's internal builds only (the TakenInternalPro marker): the voice note log, also at taken://todo-log.
    private var internalSection: some View {
        Section {
            Button {
                showVoiceLog = true
            } label: {
                ProfileLinkRow(title: VoiceNoteLogCopy.title, symbol: "waveform")
            }
            .buttonStyle(.plain)
            .profileRow()
        } header: {
            ProfileSectionTitle(VoiceNoteLogCopy.section)
        }
        .sheet(isPresented: $showVoiceLog) {
            VoiceNoteLogView()
                .environment(\.theme, model.theme)
        }
    }
    #endif

    private var aboutSection: some View {
        Section {
            Text("Everything stays on this iPhone. No accounts. No ads. No tracking.")
                .font(.sans(16, .sans, relativeTo: .body))
                .foregroundStyle(theme.fgMuted)
                .padding(.vertical, 6)
                .profileRow()
            HStack {
                ProfileRowTitle("Version")
                Spacer()
                Text("\(AppInfo.version) (\(AppInfo.build))")
                    .font(.mono(15, .monoMedium, relativeTo: .body))
                    .foregroundStyle(theme.fgSubtle)
            }
            .frame(minHeight: 44)
            .profileRow()
            Link(destination: URL(string: "https://tjbaxter.github.io/taken/")!) {
                ProfileLinkRow(title: "Support", symbol: "arrow.up.right")
            }
            .profileRow()
        } header: {
            ProfileSectionTitle("About")
        }
    }
}

/// A section's title in Profile: Geist, sentence case.
private struct ProfileSectionTitle: View {
    @Environment(\.theme) private var theme
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.sans(14, .sansSemibold, relativeTo: .footnote))
            .foregroundStyle(theme.fgSubtle)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The line under a section.
private struct ProfileFootnote: View {
    @Environment(\.theme) private var theme
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.sans(14, .sans, relativeTo: .footnote))
            .foregroundStyle(theme.fgSubtle)
            .textCase(nil)
    }
}

private struct ProfileRowTitle: View {
    @Environment(\.theme) private var theme
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.sans(17, .sans, relativeTo: .body))
            .foregroundStyle(theme.fg)
    }
}

private struct StackRow: View {
    @Environment(\.theme) private var theme
    let item: Item
    let archived: Bool

    init(item: Item, archived: Bool) {
        self.item = item
        self.archived = archived
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.name)
                .font(.sans(17, .sansMedium, relativeTo: .body))
                .foregroundStyle(archived ? theme.fgSubtle : theme.fg)
                .lineLimit(1)
            Text(archived ? "Archived" : Fmt.frequency(item.frequency))
                .font(.sans(14, .sans, relativeTo: .footnote))
                .foregroundStyle(theme.fgSubtle)
        }
        .padding(.vertical, 4)
    }
}

private struct ProfileLinkRow: View {
    @Environment(\.theme) private var theme
    let title: String
    let symbol: String

    init(title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.sans(17, .sans, relativeTo: .body))
                .foregroundStyle(theme.fg)
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.fgSubtle)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// A Profile row on the look's raised surface, with its hairline separators.
private struct ProfileRowStyle: ViewModifier {
    @Environment(\.theme) private var theme

    init() {}

    func body(content: Content) -> some View {
        content
            .listRowBackground(theme.bgRaised)
            .listRowSeparatorTint(theme.line)
    }
}

private extension View {
    func profileRow() -> some View {
        modifier(ProfileRowStyle())
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

/// The item sheet: tap an item's name on Today (or its row in Profile) to rename it, change how often it is taken,
/// archive it or delete it. No trip to settings.
struct ItemEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    let itemID: UUID
    let isSheet: Bool

    @State private var name = ""
    @State private var choice: FrequencyChoice = .daily
    @State private var weekdays: Set<Int> = FrequencyChoice.defaultDays
    /// Weekly's one day (Calendar numbering): the item's own, else the day being lived.
    @State private var weekday = 2
    @State private var archived = false
    @State private var loaded = false
    @State private var deleted = false
    @State private var confirmDelete = false

    init(itemID: UUID, isSheet: Bool) {
        self.itemID = itemID
        self.isSheet = isSheet
    }

    var body: some View {
        List {
            Section {
                TextField("", text: $name, prompt: Text("Name").foregroundStyle(theme.fgFaint))
                    .font(.sans(17, .sans, relativeTo: .body))
                    .foregroundStyle(theme.fg)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Name")
                    .listRowBackground(theme.bgRaised)
            } header: {
                editorTitle("Name")
            }

            Section {
                HStack {
                    Text("How often")
                        .font(.sans(17, .sans, relativeTo: .body))
                        .foregroundStyle(theme.fg)
                    Spacer()
                    FrequencyMenu(choice: $choice)
                }
                .listRowBackground(theme.bgRaised)
                if choice == .days {
                    WeekdayPicker(selection: $weekdays)
                        .padding(.vertical, 6)
                        .listRowBackground(theme.bgRaised)
                } else if choice == .weekly {
                    WeekdayPicker(selection: Binding(get: { [weekday] }, set: { if let day = $0.first { weekday = day } }),
                                  single: true)
                        .padding(.vertical, 6)
                        .listRowBackground(theme.bgRaised)
                }
            } header: {
                editorTitle("Schedule")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("A change applies from today. Earlier days keep the schedule they had.")
                    // Weekly: one fixed line, never a countdown or a window (App Review Guideline 1.4.1). Taken only
                    // records doses; what to do about a missed one is for the leaflet and the pharmacist.
                    if choice == .weekly {
                        Text(Fmt.missedDoseNote)
                    }
                }
                .font(.sans(14, .sans, relativeTo: .footnote))
                .foregroundStyle(theme.fgSubtle)
            }

            Section {
                Toggle(isOn: $archived) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Archive")
                            .font(.sans(17, .sans, relativeTo: .body))
                            .foregroundStyle(theme.fg)
                        Text("Hidden from Today. History stays.")
                            .font(.sans(14, .sans, relativeTo: .footnote))
                            .foregroundStyle(theme.fgSubtle)
                    }
                }
                .tint(theme.signal)
                .listRowBackground(theme.bgRaised)

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Text("Delete item")
                        .font(.sans(17, .sans, relativeTo: .body))
                        .foregroundStyle(theme.danger)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .listRowBackground(theme.bgRaised)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(name.isEmpty ? "Item" : name)
                    .font(.sans(17, .sansSemibold, relativeTo: .body))
                    .foregroundStyle(theme.fg)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
            }
            if isSheet {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.sans(17, .sansSemibold, relativeTo: .body))
                            .foregroundStyle(theme.signalInk)
                    }
                }
            }
        }
        .toolbarBackground(theme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(theme.signalInk)
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

    private func editorTitle(_ title: String) -> some View {
        Text(title)
            .font(.sans(14, .sansSemibold, relativeTo: .footnote))
            .foregroundStyle(theme.fgSubtle)
            .textCase(nil)
    }

    private func load() {
        guard !loaded, let item = model.state.item(itemID) else { return }
        loaded = true
        name = item.name
        choice = FrequencyChoice(item.frequency)
        weekday = model.today.day.weekday
        if case .weekdays(let days) = item.frequency, !days.isEmpty {
            weekdays = days
            if days.count == 1, let day = days.first { weekday = day }
        }
        archived = item.archived
    }

    private func save() {
        guard loaded, !deleted, let item = model.state.item(itemID) else { return }
        let frequency = choice.frequency(weekdays: weekdays, weekday: weekday)
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = cleanName.isEmpty ? item.name : cleanName
        // The short code on the widgets and the nudge follows a new name.
        let code = newName == item.name ? item.code : Catalog.code(for: newName)
        let changed = newName != item.name || frequency != item.frequency || archived != item.archived
        guard changed else { return }
        model.updateItem(id: itemID, name: newName, code: code, frequency: frequency, archived: archived)
    }
}
