import SwiftUI

/// Design check for the widgets, rendered in the app with demo data (`-demo -screen widgets`).
/// Not reachable from the UI; CI captures it so the widget look can be reviewed without a Home Screen.
struct WidgetGallery: View {
    @Environment(AppModel.self) private var model

    init() {}

    var body: some View {
        let now = model.now
        let partial = WidgetSnapshot(state: model.state, now: now)
        let done = WidgetSnapshot(state: DemoData.state(now: now, allTaken: true), now: now)
        let empty = WidgetSnapshot(state: StackState(), now: now)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(index: "W1", title: "HOME SCREEN", trailing: "SMALL \u{00B7} MEDIUM")
                HStack(spacing: 22) {
                    tile(width: 170, height: 170) { SmallStackView(snapshot: partial) }
                    tile(width: 170, height: 170) { SmallStackView(snapshot: done) }
                }
                tile(width: 364, height: 170) { MediumStackView(snapshot: partial) }
                    .padding(.top, 22)
                tile(width: 364, height: 170) { MediumStackView(snapshot: done) }
                    .padding(.top, 22)
                HStack(spacing: 22) {
                    tile(width: 170, height: 170) { SmallStackView(snapshot: empty) }
                }
                .padding(.top, 22)

                SectionHeader(index: "W2", title: "LOCK SCREEN", trailing: "ACCESSORY")
                HStack(spacing: 18) {
                    accessory(width: 76, height: 76) { CircularStackView(snapshot: partial) }
                    accessory(width: 76, height: 76) { CircularStackView(snapshot: done) }
                    accessory(width: 172, height: 76) { RectangularStackView(snapshot: partial) }
                }
                HStack(spacing: 18) {
                    accessory(width: 172, height: 76) { RectangularStackView(snapshot: done) }
                    accessory(width: 172, height: 26) { InlineStackView(snapshot: partial) }
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Palette.bgInset.ignoresSafeArea())
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
            .frame(width: width, height: height)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
