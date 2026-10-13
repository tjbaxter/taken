import SwiftUI

/// Settings > LOOK: the four looks side by side, one tap each. Every swatch is a live miniature of TODAY drawn in that
/// look's own tokens (canvas, glyph, counter, bar); the chosen one sits in the current look's brackets.
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
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

/// One look in miniature.
private struct LookSwatch: View {
    /// The look in use, for the brackets and the name under the swatch.
    @Environment(\.theme) private var current
    let look: Theme
    let chosen: Bool

    init(look: Theme, chosen: Bool) {
        self.look = look
        self.chosen = chosen
    }

    var body: some View {
        VStack(spacing: 10) {
            preview
            HStack(spacing: 5) {
                Lamp(on: chosen, size: 5)
                Text(look.label)
                    .hudFixed(9.5, chosen ? current.fg : current.fgSubtle, face: chosen ? .monoSemibold : .monoMedium,
                              tracking: 0.1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var preview: some View {
        let corner = max(look.radius.panel, 6)
        let shape = RoundedRectangle(cornerRadius: corner)
        return VStack(alignment: .leading, spacing: 0) {
            CapsuleGlyph()
                .frame(width: 15, height: 15)
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("4").foregroundStyle(look.fg)
                Text("/6").foregroundStyle(look.fgSubtle)
            }
            .font(.monoFixed(19, .monoMedium))
            .tracking(-0.6)
            SwatchBar()
                .padding(.top, 7)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 92)
        .background(look.bg, in: shape)
        .overlay(shape.strokeBorder(look.lineStrong, lineWidth: 1))
        // Everything above draws in the swatch's look; the brackets below are the current look's.
        .environment(\.theme, look)
        .overlay {
            if chosen {
                CornerBrackets(length: 9 * current.brackets.scale, radius: current.bracketRadius(corner + 4))
                    .stroke(current.signal, style: current.brackets.style)
                    .shadow(color: current.glow(0.6), radius: 4)
                    .padding(-4)
                    .transition(.opacity.combined(with: .scale(scale: 1.06)))
            }
        }
        .animation(.snappy(duration: 0.22), value: chosen)
        .accessibilityHidden(true)
    }
}

/// Four of six segments lit, in the swatch's look.
private struct SwatchBar: View {
    @Environment(\.theme) private var theme

    init() {}

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: min(theme.radius.segment, 1.5))
        HStack(spacing: 2.5) {
            ForEach(0..<6, id: \.self) { index in
                let on = index < 4
                shape
                    .fill(on ? theme.signal : theme.bgInset)
                    .overlay(shape.strokeBorder(on ? Color.clear : theme.line, lineWidth: 1))
                    .frame(height: 4)
                    .shadow(color: on ? theme.glow(0.5) : .clear, radius: 3)
            }
        }
    }
}
