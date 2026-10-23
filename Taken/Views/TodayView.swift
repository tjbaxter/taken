import SwiftUI

/// The three tabs (REDESIGN.md): Today (the stack), To-do (voice to-dos) and History (the calendar and stats), in the
/// system tab bar, which is Liquid Glass on iOS 26, and the optional Weight tab last when it is switched on (SPEC
/// 3.12). Every sheet and the Taken Pro paywall are presented from here, above
/// the tabs, so Siri, the Action button, the control, the Lock Screen, links, notifications and the quick action can
/// close whatever is open and bring the To-do tab to the front.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    /// A light look fades in from the launch screen's dark canvas instead of cutting to it.
    @State private var veiled: Bool

    init(veiled: Bool = false) {
        _veiled = State(initialValue: veiled)
    }

    var body: some View {
        Group {
            if model.isDemo, let gallery = WidgetGallery.Mode(screen: model.launchScreen) {
                WidgetGallery(mode: gallery)
            } else {
                main
            }
        }
        .overlay {
            if veiled {
                Theme.launchCanvas
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .task {
            guard veiled else { return }
            withAnimation(.easeOut(duration: 0.4)) { veiled = false }
        }
    }

    private var main: some View {
        TabView(selection: tabBinding) {
            TodayView()
                .tabItem { Label("Today", systemImage: "pills") }
                .tag(AppTab.today)
            TodoRootView()
                .tabItem { Label("To-do", systemImage: "checklist") }
                .tag(AppTab.todo)
            HistoryScreen()
                .tabItem { Label("History", systemImage: "calendar") }
                .tag(AppTab.history)
            // The optional Weight tab, last, behind the person's own switch (SPEC 3.12). A plain `if` is Apple DTS's
            // advice for a tab shown by a user setting, and the only way on iOS 17 (`Tab` and `hidden(_:)` are iOS 18).
            if model.weight.showsTab {
                WeightTabRootView()
                    .tabItem { Label(WeightCopy.tab, systemImage: WeightCopy.symbol) }
                    .tag(AppTab.weight)
            }
        }
        .opensTodoTab { model.openTodoTab() }
        .paywallHost(.root)
        #if DEBUG
        // `-demo -type ax3`: CI's large-text capture of the Weight tab.
        .modifier(DemoTypeSize(enabled: model.isDemo))
        #endif
        .sheet(item: sheetBinding, onDismiss: { model.rootSheetDidDismiss() }) { route in
            sheetContent(route)
                .paywallHost(.sheet)
                .environment(model)
                .environment(\.theme, model.theme)
                .preferredColorScheme(model.theme.scheme)
        }
        .task { await model.applyLaunchScreen() }
        // CI reads what is in front (`-demo` only), so a link check fails when the link lands on the wrong screen.
        .onAppear { DemoProbe.record(model) }
        .onChange(of: model.tab) { _, _ in DemoProbe.record(model) }
        .onChange(of: model.sheet) { _, _ in DemoProbe.record(model) }
        .onChange(of: model.paywall?.id) { _, _ in DemoProbe.record(model) }
        .onChange(of: model.trialAsk) { _, _ in DemoProbe.record(model) }
        .onChange(of: TodoModel.shared.phase) { _, phase in
            DemoProbe.record(model)
            // A trial ask that waited for the voice note comes once it is done.
            if phase == .idle { model.captureDidSettle() }
        }
    }

    private var tabBinding: Binding<AppTab> {
        Binding(get: { model.tab }, set: { model.tab = $0 })
    }

    private var sheetBinding: Binding<SheetRoute?> {
        Binding(get: { model.sheet }, set: { model.sheet = $0 })
    }

    @ViewBuilder
    private func sheetContent(_ route: SheetRoute) -> some View {
        switch route {
        case .add:
            AddSheet()
        case .settings:
            ProfileView()
        case .day(let day):
            DaySheet(day: day)
        case .setTime(let id):
            if let item = model.state.item(id) {
                SetTimeSheet(item: item)
            }
        case .editItem(let id):
            NavigationStack {
                ItemEditorView(itemID: id, isSheet: true)
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(theme.bg)
        case .todoEdit(let id):
            if let task = TodoModel.shared.state.task(id) {
                TodoEditSheet(task: task, clock: TodoModel.shared.clock) { title, due in
                    TodoModel.shared.edit(id, title: title, due: due)
                } onDelete: {
                    TodoModel.shared.delete(task)
                }
            }
        case .todoType:
            TodoTypeSheet { text in
                TodoModel.shared.submitTyped(text, app: model)
            }
        case .widgetHelp:
            WidgetHelpSheet()
        case .weighIns:
            WeighInList()
        case .weightGoal:
            WeightGoalSheet()
        }
    }
}

/// Today: a large title with the date, one calm progress line, then the stack with a "+" beside its title. Items not
/// due today sit in a quiet Not today group with the day they are next due.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                TabHeader(title: "Today", subtitle: Fmt.longDay(model.today.day))
                if model.hasStack {
                    stackContent
                } else {
                    EmptyStackView()
                        .padding(.top, 28)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .background(theme.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { BottomDock() }
    }

    @ViewBuilder
    private var stackContent: some View {
        let today = model.today
        ProgressSummary(summary: today, clock: model.clock, lockInCount: model.lockInCount, streak: model.streak)
            .padding(.top, 18)
        if model.isLocked {
            LockedBar(text: model.lockedBarText) {
                model.presentPaywall(origin: .bar)
            }
            .padding(.top, 16)
            .transition(.opacity)
        } else if let prompt = model.todayPrompt {
            // One quiet row at most, never in the way of a ring: the nudge offered once, yesterday's repair, or the
            // widget invite under the first All taken.
            TodayPromptRow(prompt: prompt)
                .padding(.top, 16)
                .transition(.opacity)
        }

        HStack(alignment: .center, spacing: 8) {
            Text("Stack")
                .font(.sans(20, .sansSemibold, relativeTo: .title3))
                .foregroundStyle(theme.fg)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            AddToStackButton()
        }
        .padding(.top, 20)
        .padding(.bottom, 6)

        if today.due.isEmpty {
            Card {
                Text("Nothing due today")
                    .font(.sans(16, .sans, relativeTo: .body))
                    .foregroundStyle(theme.fgMuted)
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
        } else {
            Card { rows(today.due, notDue: false) }
        }

        if !today.notDue.isEmpty {
            SectionHeader("Not today")
            Card { rows(today.notDue, notDue: true) }
        }
    }

    private func rows(_ items: [ItemDay], notDue: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { RowDivider() }
                // Not today: a weekly item shows the week today is in (its due day, or the next one an early dose
                // counts for), with the line that goes with it.
                let shown = notDue ? model.notTodayRow(entry) : (row: entry, note: "")
                let row = shown.row
                ItemRowView(row: row, now: model.now, clock: model.clock,
                            expanded: model.expandedItemID == row.id,
                            nextLabel: notDue ? model.nextLabel(for: entry) : nil,
                            note: notDue ? shown.note : nil,
                            locked: model.isLocked,
                            onTake: { model.tap(row) },
                            onOpen: { model.sheet = .editItem(row.item.id) })
                    .contextMenu { menu(for: row) }
                    .accessibilityActions { voiceOverActions(for: row) }
            }
        }
    }

    /// The context menu's actions for VoiceOver, so undo never depends on reaching the toast in time.
    @ViewBuilder
    private func voiceOverActions(for row: ItemDay) -> some View {
        if !row.doses.isEmpty {
            Button("Undo last dose") { model.undoLastDose(row) }
        }
        if model.offersSetTime(row) {
            Button("Set time") { openSetTime(row.item.id) }
        } else {
            Button("Open \(Fmt.weekday(row.day))") { model.sheet = .day(row.day) }
        }
    }

    @ViewBuilder
    private func menu(for row: ItemDay) -> some View {
        Button {
            model.undoLastDose(row)
        } label: {
            Label("Undo last dose", systemImage: "arrow.uturn.backward")
        }
        .disabled(row.doses.isEmpty)
        // Set time corrects a dose logged today. A weekly row whose dose was logged on another day, or whose week is
        // open, opens its due day's sheet instead, where a dose can be logged at any time or removed.
        if model.offersSetTime(row) {
            Button {
                openSetTime(row.item.id)
            } label: {
                Label("Set time\u{2026}", systemImage: "clock")
            }
        } else {
            Button {
                model.sheet = .day(row.day)
            } label: {
                Label("Open \(Fmt.weekday(row.day))", systemImage: "calendar")
            }
        }
        Button {
            model.sheet = .editItem(row.item.id)
        } label: {
            Label("Edit item", systemImage: "slider.horizontal.3")
        }
    }

    /// Set time logs or moves a dose, so in locked mode it opens the paywall instead.
    private func openSetTime(_ id: UUID) {
        model.requirePro { [weak model = model] in model?.sheet = .setTime(id) }
    }
}

/// The clear "+" beside the stack's title: opens Add.
struct AddToStackButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    init() {}

    var body: some View {
        Button {
            // Adding needs no Pro until the first dose; after it, without Pro, the paywall comes first.
            model.requirePro { [weak model = model] in model?.sheet = .add }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.signalInk)
                .frame(width: 36, height: 36)
                .background(theme.signalWash, in: Circle())
                .overlay(Circle().strokeBorder(theme.signalEdge, lineWidth: 1))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Add to stack")
    }
}

/// Take all and the undo toast, pinned above the tab bar.
struct BottomDock: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    init() {}

    var body: some View {
        // Counts what Take all logs right now, so the number on the button is the number it takes.
        let pending = model.takeAllCount
        let showTakeAll = pending >= 2
        let visible = showTakeAll || model.toast != nil
        VStack(spacing: 10) {
            if let toast = model.toast {
                ToastView(toast: toast) { model.undo(toast) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAction(named: "Dismiss") { model.dismissToast() }
            }
            if showTakeAll {
                PrimaryButton(title: "Take all", locked: model.isLocked, count: pending) {
                    model.requirePro { [weak model = model] in model?.takeAll() }
                }
                .transition(.opacity)
                .accessibilityLabel("Take all, \(pending)")
                .accessibilityHint(model.isLocked ? "Opens Taken Pro." : "Marks every pending dose taken now.")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, visible ? 10 : 0)
        .padding(.bottom, visible ? 8 : 0)
        .frame(maxWidth: .infinity)
        .background {
            if showTakeAll {
                theme.bg.opacity(0.94)
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .animation(.snappy(duration: 0.22), value: showTakeAll)
        .animation(.snappy(duration: 0.22), value: model.toast)
    }
}

/// Locked mode: a slim bar under the progress line. The log stays readable; a tap opens Taken Pro.
struct LockedBar: View {
    @Environment(\.theme) private var theme
    let text: String
    let action: () -> Void

    init(text: String, action: @escaping () -> Void) {
        self.text = text
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.signalInk)
                Text(text)
                    .font(.sans(15, .sansMedium, relativeTo: .subheadline))
                    .foregroundStyle(theme.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.fgSubtle)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(theme.signalWash, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                .strokeBorder(theme.signalEdge, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Logging needs Taken Pro. \(text).")
        .accessibilityHint("Opens Taken Pro.")
    }
}

struct ToastView: View {
    @Environment(\.theme) private var theme
    let toast: Toast
    let onUndo: () -> Void

    init(toast: Toast, onUndo: @escaping () -> Void) {
        self.toast = toast
        self.onUndo = onUndo
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(toast.message)
                .font(.sans(15, .sans, relativeTo: .subheadline))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let time = toast.time {
                Text(time)
                    .font(.mono(15, .monoMedium, relativeTo: .subheadline))
                    .fixedSize()
            }
            Spacer(minLength: 8)
            if toast.undo != nil {
                Button(action: onUndo) {
                    Text("Undo")
                        .font(.sans(15, .sansSemibold, relativeTo: .subheadline))
                        .foregroundStyle(theme.signalInk)
                        .frame(minWidth: 64, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Undo")
            }
        }
        .foregroundStyle(theme.fg)
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .frame(minHeight: 50)
        .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
            .strokeBorder(theme.lineStrong, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// First run: no onboarding, just the way in.
struct EmptyStackView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    init() {}

    var body: some View {
        VStack(spacing: 18) {
            CapsuleGlyph(fill: theme.signal, stroke: theme.fgSubtle)
                .frame(width: 64, height: 64)
                .padding(.top, 8)
            VStack(spacing: 6) {
                Text("Nothing in your stack yet")
                    .font(.sans(20, .sansSemibold, relativeTo: .title3))
                    .foregroundStyle(theme.fg)
                Text("Tap what you take. It takes a few seconds.")
                    .font(.sans(15, .sans, relativeTo: .subheadline))
                    .foregroundStyle(theme.fgSubtle)
                    .multilineTextAlignment(.center)
            }
            PrimaryButton(title: "Add to stack", locked: model.isLocked) {
                model.requirePro { [weak model = model] in model?.sheet = .add }
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}
