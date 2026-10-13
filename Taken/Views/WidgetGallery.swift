import SwiftUI

/// Design check for the widgets, rendered in the app with demo data (`-demo -screen widgets`, and
/// `-screen widgets-locked` for the read-only states without Taken Pro). Not reachable from the UI; CI captures it
/// so the widget look can be reviewed without a Home Screen.
struct WidgetGallery: View {
    @Environment(AppModel.self) private var model
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
        .background(Palette.bgInset.ignoresSafeArea())
    }

    @ViewBuilder
    private var states: some View {
        let now = model.now
        let partial = WidgetSnapshot(state: model.state, now: now)
        let done = WidgetSnapshot(state: DemoData.state(now: now, allTaken: true), now: now)
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
        let done = WidgetSnapshot(state: DemoData.state(now: now, allTaken: true), now: now, locked: true)
        SectionHeader(index: "W1", title: "HOME SCREEN", trailing: "NO PRO", trailingColor: Palette.signal)
        HStack(spacing: 22) {
            tile(width: 170, height: 170) { SmallStackView(snapshot: partial) }
            tile(width: 170, height: 170) { SmallStackView(snapshot: done) }
        }
        tile(width: 364, height: 170) { MediumStackView(snapshot: partial) }
            .padding(.top, 18)

        SectionHeader(index: "W2", title: "LOCK SCREEN", trailing: "NO PRO", trailingColor: Palette.signal)
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
            .foregroundStyle(Palette.fgSubtle)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func tile<Content: View>(width: CGFloat, height: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(width: width, height: height)
            .background(Palette.bg, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
    }

    private func accessory<Content: View>(width: CGFloat, height: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(width: width, height: height)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
