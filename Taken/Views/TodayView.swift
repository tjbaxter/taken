import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isDemo && model.launchScreen == "widgets" {
            WidgetGallery()
        } else {
            main
        }
    }

    private var main: some View {
        TodayView()
            .sheet(item: sheetBinding) { route in
                sheetContent(route)
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

        SectionHeader(index: "02", title: "STACK", trailing: "\(today.due.count) DUE")
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
                Text("NOT DUE").hud(10.5, Palette.fgFaint)
                DashedRule()
            }
            .padding(.top, 18)
            .padding(.bottom, 10)
            Panel(stacked: false) {
                rows(today.notDue, notDue: true)
            }
            .opacity(0.85)
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
                            notDueLabel: notDue ? model.nextLabel(for: row) : nil) {
                    model.tap(row)
                }
                .contextMenu { menu(for: row) }
            }
        }
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
            model.sheet = .setTime(row.item.id)
        } label: {
            Label("Set time\u{2026}", systemImage: "clock")
        }
        Button {
            model.sheet = .editItem(row.item.id)
        } label: {
            Label("Edit item", systemImage: "slider.horizontal.3")
        }
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
        let pending = model.today.pendingItems.count
        let showTakeAll = pending >= 2
        let visible = showTakeAll || model.toast != nil
        VStack(spacing: 10) {
            if let toast = model.toast {
                ToastView(toast: toast) { model.undo(toast) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if showTakeAll {
                PrimaryButton(title: "TAKE ALL (\(pending))", lamp: true) {
                    model.takeAll()
                }
                .transition(.opacity)
                .accessibilityHint("Marks every pending dose taken now.")
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
            if !toast.doseIDs.isEmpty {
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
                PrimaryButton(title: "ADD TO STACK", lamp: true) {
                    model.sheet = .add
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
