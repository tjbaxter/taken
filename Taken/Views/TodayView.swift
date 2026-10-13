import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isDemo && model.launchScreen == "widgets" {
            WidgetGallery()
        } else if model.isDemo && model.launchScreen == "widgets-locked" {
            WidgetGallery(locked: true)
        } else {
            main
        }
    }

    private var main: some View {
        TodayView()
            .paywallHost(.root)
            .sheet(item: sheetBinding, onDismiss: { model.rootSheetDidDismiss() }) { route in
                sheetContent(route)
                    .paywallHost(.sheet)
                    .environment(model)
                    .preferredColorScheme(.dark)
            }
            .task { await model.applyLaunchScreen() }
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
            SettingsView()
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
            .presentationBackground(Palette.bg)
        }
    }
}

/// The single main screen.
struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.hasStack {
                        stackContent
                    } else {
                        EmptyStackView()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .background(Palette.bg.ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) { TopBar() }
            .safeAreaInset(edge: .bottom, spacing: 0) { BottomDock() }
            .onChange(of: model.scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.snappy(duration: 0.3)) { proxy.scrollTo(target, anchor: .top) }
                model.scrollTarget = nil
            }
        }
    }

    @ViewBuilder
    private var stackContent: some View {
        let today = model.today
        SectionHeader(index: "01", title: "STATUS", trailing: today.allTaken ? "LOCKED" : "LIVE",
                      trailingColor: today.allTaken ? Palette.signal : Palette.fgSubtle)
        StatusPanel(summary: today, now: model.now, clock: model.clock, lockInCount: model.lockInCount,
                    streak: model.streak)
        if model.isLocked {
            LockedBar(text: model.lockedBarText) {
                model.presentPaywall(origin: .bar)
            }
            .padding(.top, 12)
            .transition(.opacity)
        }

        SectionHeader(index: "02", title: "STACK", trailing: Fmt.stackProgress(today))
        if today.due.isEmpty {
            Panel {
                Text("NOTHING DUE TODAY")
                    .hud(11, Palette.fgSubtle)
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
        } else {
            Panel {
                rows(today.due, notDue: false)
            }
        }

        if !today.notDue.isEmpty {
            HStack(spacing: 10) {
                Text("NOT DUE").hud(10.5, Palette.fgSubtle)
                DashedRule()
            }
            .padding(.top, 18)
            .padding(.bottom, 10)
            Panel(stacked: false) {
                rows(today.notDue, notDue: true)
            }
        }

        SectionHeader(index: "03", title: "LOG", trailing: "5 WEEKS")
            .id("log")
        HistoryGrid(rows: model.history) { day in
            model.sheet = .day(day)
        }
        StatsRow(streak: model.streak, adherence: model.adherence)
            .padding(.top, 16)

        FooterLine()
            .padding(.top, 26)
    }

    private func rows(_ items: [ItemDay], notDue: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    DashedRule().padding(.horizontal, 14)
                }
                ItemRowView(row: row, now: model.now, clock: model.clock,
                            expanded: model.expandedItemID == row.id,
                            notDueLabel: notDue ? model.nextLabel(for: row) : nil,
                            locked: model.isLocked) {
                    model.tap(row)
                }
                .contextMenu { menu(for: row) }
                .accessibilityActions { voiceOverActions(for: row) }
            }
        }
    }

    /// The context menu's actions for VoiceOver, so undo never depends on reaching the toast in time.
    @ViewBuilder
    private func voiceOverActions(for row: ItemDay) -> some View {
        if !row.doses.isEmpty {
            Button("Undo last dose") { model.undoLastDose(row.item) }
        }
        Button("Set time") { openSetTime(row.item.id) }
        Button("Edit item") { model.sheet = .editItem(row.item.id) }
    }

    @ViewBuilder
    private func menu(for row: ItemDay) -> some View {
        Button {
            model.undoLastDose(row.item)
        } label: {
            Label("Undo last dose", systemImage: "arrow.uturn.backward")
        }
        .disabled(row.doses.isEmpty)
        Button {
            openSetTime(row.item.id)
        } label: {
            Label("Set time\u{2026}", systemImage: "clock")
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

struct TopBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            CapsuleGlyph()
                .frame(width: 20, height: 20)
            Text("TAKEN")
                .font(.monoFixed(15, .monoSemibold))
                .tracking(15 * 0.3)
                .foregroundStyle(Palette.fg)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Text(Fmt.dayHeader(model.today.day))
                .hudFixed(11.5, Palette.fgMuted, tracking: 0.14)
            Button {
                model.sheet = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Palette.fgMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Settings")
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .frame(height: 52)
        .background(Palette.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.line).frame(height: 1)
        }
    }
}

/// TAKE ALL and the undo toast, pinned above the home indicator.
struct BottomDock: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Counts what TAKE ALL logs right now, so the number on the button is the number it takes.
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
                PrimaryButton(title: "TAKE ALL (\(pending))", lamp: true, locked: model.isLocked) {
                    model.requirePro { [weak model = model] in model?.takeAll() }
                }
                .transition(.opacity)
                .accessibilityHint(model.isLocked ? "Opens Taken Pro." : "Marks every pending dose taken now.")
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, visible ? 12 : 0)
        .padding(.bottom, visible ? 6 : 0)
        .frame(maxWidth: .infinity)
        .background {
            if showTakeAll {
                Palette.bg
                    .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .animation(.snappy(duration: 0.22), value: showTakeAll)
        .animation(.snappy(duration: 0.22), value: model.toast)
    }
}

/// Locked mode: the slim bar under the status panel. The log stays readable; a tap opens Taken Pro.
struct LockedBar: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.signal)
                Text(text)
                    .hudFixed(11, Palette.fg, face: .monoSemibold, tracking: 0.14)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 8)
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.fgMuted)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Palette.signalWash.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.signalEdge, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("Logging needs Taken Pro. \(text.capitalized).")
        .accessibilityHint("Opens Taken Pro.")
    }
}

struct ToastView: View {
    let toast: Toast
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Palette.signal).frame(width: 6, height: 6)
            Text(toast.message)
                .hudFixed(12, Palette.fg, tracking: 0.1)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 8)
            if toast.undo != nil {
                Button(action: onUndo) {
                    Text("\u{00B7} UNDO")
                        .font(.monoFixed(12, .monoSemibold))
                        .tracking(12 * 0.12)
                        .foregroundStyle(Palette.signal)
                        .frame(minWidth: 64, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Undo")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .frame(minHeight: 48)
        .background(Palette.bgRaised, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.lineStrong, lineWidth: 1))
    }
}

/// First run: no onboarding, just the way in.
struct EmptyStackView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(index: "01", title: "STATUS", trailing: "EMPTY")
            VStack(spacing: 26) {
                CapsuleGlyph(fill: Palette.fgFaint, stroke: Palette.fgSubtle)
                    .frame(width: 72, height: 72)
                    .padding(.top, 12)
                Text("NOTHING IN YOUR STACK")
                    .hud(13, Palette.fgMuted, tracking: 0.16)
                PrimaryButton(title: "ADD TO STACK", lamp: true, locked: model.isLocked) {
                    model.requirePro { [weak model = model] in model?.sheet = .add }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(Palette.bgRaised.opacity(0.6))
            .overlay {
                CornerBrackets(length: 14)
                    .stroke(Palette.fgSubtle, style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
                    .padding(0.75)
            }
            FooterLine()
                .padding(.top, 26)
        }
    }
}

struct FooterLine: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LOCAL ONLY \u{00B7} NO ACCOUNTS \u{00B7} NO ADS \u{00B7} NO TRACKING")
                .hudFixed(9.5, Palette.fgFaint, tracking: 0.14)
            Text("TAKEN \(AppInfo.versionLine)")
                .hudFixed(9.5, Palette.fgFaint, tracking: 0.14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var versionLine: String { "V\(version) (\(build))" }
}
