import SwiftUI

/// Profile > Look: the four looks side by side, one tap each. Every swatch is a live miniature of Today drawn in that
/// look's own tokens (canvas, glyph, progress bar, a taken and a pending row); the chosen one is ringed in the current
/// look's signal.
struct LookPicker: View {
    let selection: ThemeID
    let onSelect: (ThemeID) -> Void

    init(selection: ThemeID, onSelect: @escaping (ThemeID) -> Void) {
        self.selection = selection
        self.onSelect = onSelect
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Theme.all, id: \.id) { look in
                let chosen = look.id == selection
                Button {
                    onSelect(look.id)
                } label: {
                    LookSwatch(look: look, chosen: chosen)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("\(look.id.title) look")
                .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
                .accessibilityHint(chosen ? "" : "Applies this look to Taken, its widgets and its icon.")
            }
        }
        .padding(.vertical, 10)
    }
}

/// One look in miniature.
private struct LookSwatch: View {
    /// The look in use, for the ring and the name under the swatch.
    @Environment(\.theme) private var current
    let look: Theme
    let chosen: Bool

    init(look: Theme, chosen: Bool) {
        self.look = look
        self.chosen = chosen
    }

    var body: some View {
        VStack(spacing: 8) {
            preview
            Text(look.id.title)
                .font(.sans(13, chosen ? .sansSemibold : .sansMedium, relativeTo: .footnote))
                .foregroundStyle(chosen ? current.fg : current.fgSubtle)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: 7) {
            CapsuleGlyph()
                .frame(width: 14, height: 14)
            Spacer(minLength: 0)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(look.bgInset)
                    Capsule().fill(look.signal).frame(width: geo.size.width * 0.66)
                }
            }
            .frame(height: 4)
            miniRow(taken: true)
            miniRow(taken: false)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 92)
        .background(look.bg, in: shape)
        .overlay(shape.strokeBorder(look.lineStrong, lineWidth: 1))
        // Everything above draws in the swatch's look; the ring below is the current look's.
        .environment(\.theme, look)
        .overlay {
            if chosen {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(current.signal, lineWidth: 2)
                    .padding(-3)
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.22), value: chosen)
        .accessibilityHidden(true)
    }

    private func miniRow(taken: Bool) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(look.fgSubtle)
                .frame(width: 22, height: 3)
            Spacer(minLength: 0)
            Circle()
                .fill(taken ? look.signal : Color.clear)
                .overlay(Circle().strokeBorder(taken ? Color.clear : look.lineStrong, lineWidth: 1))
                .frame(width: 8, height: 8)
        }
    }
}
