import SwiftUI

/// Design check for the widgets, rendered in the app with demo data (`-demo -screen widgets`, and
/// `-screen widgets-locked` for the read-only states without Taken Pro), in the look chosen with `-theme`. Not
/// reachable from the UI; CI captures it so the widget look can be reviewed without a Home Screen.
struct WidgetGallery: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let locked: Bool

    init(locked: Bool = false) {
        self.locked = locked
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if locked {
                    lockedStates
                } else {
                    states
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
        SectionHeader(index: "W1", title: "HOME SCREEN", trailing: "SMALL \u{00B7} MEDIUM")
        HStack(spacing: 22) {
            tile(width: 170, height: 170) { SmallStackView(snapshot: partial) }
            tile(width: 170, height: 170) { SmallStackView(snapshot: done) }
        }
        tile(width: 364, height: 170) { MediumStackView(snapshot: partial) }
            .padding(.top, 18)

        SectionHeader(index: "W2", title: "LOCK SCREEN", trailing: "ACCESSORY")
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

        SectionHeader(index: "W3", title: "MORE STATES")
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
        SectionHeader(index: "W1", title: "HOME SCREEN", trailing: "NO PRO", trailingColor: theme.signalInk)
        HStack(spacing: 22) {
            tile(width: 170, height: 170) { SmallStackView(snapshot: partial) }
            tile(width: 170, height: 170) { SmallStackView(snapshot: done) }
        }
        tile(width: 364, height: 170) { MediumStackView(snapshot: partial) }
            .padding(.top, 18)

        SectionHeader(index: "W2", title: "LOCK SCREEN", trailing: "NO PRO", trailingColor: theme.signalInk)
        HStack(spacing: 14) {
            accessory(width: 76, height: 76) { CircularStackView(snapshot: partial) }
            accessory(width: 172, height: 76) { RectangularStackView(snapshot: partial) }
        }
        HStack(spacing: 14) {
            accessory(width: 220, height: 26) { InlineStackView(snapshot: partial) }
        }
        .padding(.top, 14)

        SectionHeader(index: "W3", title: "TAPS")
        Text("Every tap on a locked widget opens Taken Pro. A row tapped on the medium widget is logged once Pro is on. The Control Center control shows a lock and logs nothing; Taken offers that TAKE ALL when it opens.")
            .font(.sans(14))
            .foregroundStyle(theme.fgSubtle)
            .fixedSize(horizontal: false, vertical: true)
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
