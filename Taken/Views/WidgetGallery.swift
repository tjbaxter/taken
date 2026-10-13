import SwiftUI

/// Design check for the widgets, rendered in the app with demo data (`-demo -screen widgets`, `-screen widgets-locked`
/// for the read-only states without Taken Pro, `-screen widgets-standby` for the small widget with its canvas removed,
/// `-screen widgets-todo` for voice to-dos' Lock Screen widget and the Control Center controls), in the look chosen with
/// `-theme`. Not reachable from the UI; CI captures it so the widget look can be reviewed without a Home Screen.
struct WidgetGallery: View {
    enum Mode {
        case home
        case locked
        /// StandBy and CarPlay: the system removes the canvas and draws the small widget on black.
        case standBy
        /// Voice to-dos: the Lock Screen mic, list and count, and the New voice to-do control.
        case todo

        /// The gallery a `-screen` names, or nil for an app screen.
        init?(screen: String?) {
            switch screen {
            case "widgets": self = .home
            case "widgets-locked": self = .locked
            case "widgets-standby": self = .standBy
            case "widgets-todo": self = .todo
            default: return nil
            }
        }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let mode: Mode

    init(mode: Mode = .home) {
        self.mode = mode
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch mode {
                case .home: states
                case .locked: lockedStates
                case .standBy: standByStates
                case .todo: todoStates
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(theme.bgInset.ignoresSafeArea())
    }

    /// A state of the demo stack in the look being reviewed.
    private func demo(allTaken: Bool) -> StackState {
        var state = DemoData.state(now: model.now, allTaken: allTaken)
        state.settings.theme = theme.id
        return state
    }

    @ViewBuilder
    private var states: some View {
        let now = model.now
        let partial = WidgetSnapshot(state: model.state, now: now)
        let done = WidgetSnapshot(state: demo(allTaken: true), now: now)
        let empty = WidgetSnapshot(state: StackState(), now: now)
        SectionHeader("Home Screen", trailing: "Small and medium")
        HStack(spacing: 22) {
            tile(width: 170, height: 170) { SmallStackView(snapshot: partial) }
            tile(width: 170, height: 170) { SmallStackView(snapshot: done) }
        }
        tile(width: 364, height: 170) { MediumStackView(snapshot: partial) }
            .padding(.top, 18)

        SectionHeader("Lock Screen", trailing: "Accessory")
        HStack(spacing: 14) {
            accessory(width: 76, height: 76) { CircularStackView(snapshot: partial) }
            accessory(width: 76, height: 76) { CircularStackView(snapshot: done) }
            accessory(width: 172, height: 76) { RectangularStackView(snapshot: partial) }
        }
        HStack(spacing: 14) {
            accessory(width: 172, height: 76) { RectangularStackView(snapshot: done) }
            accessory(width: 180, height: 26) { InlineStackView(snapshot: partial) }
        }
        .padding(.top, 14)

        SectionHeader("More states")
        tile(width: 364, height: 170) { MediumStackView(snapshot: done) }
        HStack(spacing: 22) {
            tile(width: 170, height: 170) { SmallStackView(snapshot: empty) }
        }
        .padding(.top, 18)
    }

    /// Without Taken Pro: the stack read-only, a small PRO glyph, and every tap opening the paywall.
    @ViewBuilder
    private var lockedStates: some View {
        let now = model.now
        let partial = WidgetSnapshot(state: model.state, now: now, locked: true)
        let done = WidgetSnapshot(state: demo(allTaken: true), now: now, locked: true)
        SectionHeader("Home Screen", trailing: "Without Pro")
        HStack(spacing: 22) {
            tile(width: 170, height: 170) { SmallStackView(snapshot: partial) }
            tile(width: 170, height: 170) { SmallStackView(snapshot: done) }
        }
        tile(width: 364, height: 170) { MediumStackView(snapshot: partial) }
            .padding(.top, 18)

        SectionHeader("Lock Screen", trailing: "Without Pro")
        HStack(spacing: 14) {
            accessory(width: 76, height: 76) { CircularStackView(snapshot: partial) }
            accessory(width: 172, height: 76) { RectangularStackView(snapshot: partial) }
        }
        HStack(spacing: 14) {
            accessory(width: 220, height: 26) { InlineStackView(snapshot: partial) }
        }
        .padding(.top, 14)

        SectionHeader("Taps")
        Text("Every tap on a locked widget opens Taken Pro. A row tapped on the medium widget is logged once Pro is on. The Control Center control shows a lock and logs nothing; Taken offers that Take all when it opens.")
            .font(.sans(14))
            .foregroundStyle(theme.fgSubtle)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The small widget where StandBy and CarPlay remove its canvas: on black, in the look the widget switches to there
    /// (`Theme.withoutBackground`, which is the look itself for the dark ones).
    @ViewBuilder
    private var standByStates: some View {
        let now = model.now
        let partial = WidgetSnapshot(state: model.state, now: now)
        let done = WidgetSnapshot(state: demo(allTaken: true), now: now)
        let lockedPartial = WidgetSnapshot(state: model.state, now: now, locked: true)
        let lockedDone = WidgetSnapshot(state: demo(allTaken: true), now: now, locked: true)
        SectionHeader("StandBy", trailing: "No background")
        HStack(spacing: 22) {
            standByTile { SmallStackView(snapshot: partial) }
            standByTile { SmallStackView(snapshot: done) }
        }
        SectionHeader("StandBy", trailing: "Without Pro")
        HStack(spacing: 22) {
            standByTile { SmallStackView(snapshot: lockedPartial) }
            standByTile { SmallStackView(snapshot: lockedDone) }
        }
        SectionHeader("Why")
        Text("StandBy and CarPlay draw the small widget on black without its canvas. A light look keeps its signal there and switches its text to the dark canvas roles, so it stays readable.")
            .font(.sans(14))
            .foregroundStyle(theme.fgSubtle)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Voice to-dos away from the app: the Lock Screen widget in its three sizes (the mic opens Taken listening, the list
    /// opens the To-do tab), and the Control Center controls, drawn as Control Center draws them in the look's tint.
    @ViewBuilder
    private var todoStates: some View {
        let open = TodoEntry(date: model.now, state: TodoModel.shared.state, clock: model.clock)
        let empty = TodoEntry(date: model.now, open: [], openCount: 0)
        SectionHeader("Lock Screen", trailing: "Voice to-do")
        HStack(spacing: 14) {
            accessory(width: 76, height: 76) { TodoCircularView() }
            accessory(width: 172, height: 76) { TodoRectangularView(entry: open) }
        }
        HStack(spacing: 14) {
            accessory(width: 172, height: 76) { TodoRectangularView(entry: empty) }
            accessory(width: 150, height: 26) { TodoInlineView(entry: open) }
        }
        .padding(.top, 14)

        SectionHeader("Control Center", trailing: "Controls")
        HStack(spacing: 22) {
            control(symbol: "mic.fill", title: "New voice to-do")
            control(symbol: "pill.fill", title: "Take all")
        }
        Text("The mic, the list, the control, the Action button, Siri and the app icon's quick action all open Taken on the To-do tab. The mic, the control and Siri start listening.")
            .font(.sans(14))
            .foregroundStyle(theme.fgSubtle)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 18)
    }

    /// A Control Center button: the system draws the glyph in the control's tint (the look's signal) on a dark plate.
    private func control(symbol: String, title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(theme.signal)
                .frame(width: 72, height: 72)
                .background(theme.lockScreenPlate, in: Circle())
            Text(title)
                .font(.sans(12, .sansMedium))
                .foregroundStyle(theme.fgMuted)
        }
    }

    private func standByTile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .environment(\.theme, theme.withoutBackground)
            .padding(16)
            .frame(width: 170, height: 170)
            .background(Theme.removedBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// A Home Screen widget: the look's canvas, as `containerBackground` draws it.
    private func tile<Content: View>(width: CGFloat, height: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(width: width, height: height)
            .background(theme.bg, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
    }

    /// A Lock Screen accessory: the system draws these in white over the wallpaper in every look.
    private func accessory<Content: View>(width: CGFloat, height: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .foregroundStyle(theme.lockScreenInk)
            // The Lock Screen draws gauges in its own white too, never in the app's tint.
            .tint(theme.lockScreenInk)
            .padding(.horizontal, 6)
            .frame(width: width, height: height)
            .background(theme.lockScreenPlate, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
