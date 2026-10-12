import SwiftUI

/// "[02] STACK - - - - - - - - 05 DUE"
struct SectionHeader: View {
    let index: String
    let title: String
    var trailing: String? = nil
    var trailingColor: Color = Palette.fgSubtle

    var body: some View {
        HStack(spacing: 10) {
            Text("[\(index)]").hud(11, Palette.fgFaint, tracking: 0.06)
            Text(title).hud(11, Palette.fgMuted, tracking: 0.16)
            DashedRule()
                .frame(maxWidth: .infinity)
            if let trailing {
                Text(trailing).hud(11, trailingColor, tracking: 0.12)
            }
        }
        .padding(.top, 26)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Small square status lamp, lit = signal.
struct Lamp: View {
    var on: Bool
    var size: CGFloat = 6

    var body: some View {
        Rectangle()
            .fill(on ? Palette.signal : Palette.fgFaint)
            .frame(width: size, height: size)
            .shadow(color: on ? Palette.signal.opacity(0.7) : .clear, radius: on ? 4 : 0)
            .accessibilityHidden(true)
    }
}

/// Solid light button, the badline primary.
struct PrimaryButton: View {
    let title: String
    var lamp: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if lamp {
                    Rectangle().fill(Palette.signal).frame(width: 7, height: 7)
                }
                Text(title)
                    .font(.monoFixed(14, .monoSemibold))
                    .tracking(14 * 0.12)
            }
            .foregroundStyle(Palette.buttonText)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Palette.button.opacity(enabled ? 1 : 0.28), in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
    }
}

/// Outline button for secondary actions.
struct OutlineButton: View {
    let title: String
    var color: Color = Palette.fg
    var height: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.monoFixed(12, .monoSemibold))
                .tracking(12 * 0.12)
                .foregroundStyle(color)
                .padding(.horizontal, 14)
                .frame(height: height)
                .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(color.opacity(0.45), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// Row press: a flat inset highlight, no scaling.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Palette.bgInset : Color.clear)
    }
}

/// Title bar for sheets.
struct SheetHeader: View {
    let title: String
    var subtitle: String? = nil
    var subtitleColor: Color = Palette.fgSubtle
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.monoFixed(16, .monoSemibold))
                    .tracking(16 * 0.14)
                    .foregroundStyle(Palette.fg)
                if let subtitle {
                    Text(subtitle).hud(11, subtitleColor)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.fgMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.line).frame(height: 1)
        }
    }
}

/// The code tag box: "VD3".
struct CodeTag: View {
    let code: String
    var lit: Bool = false
    var dim: Bool = false

    var body: some View {
        Text(code)
            .font(.monoFixed(12, .monoSemibold))
            .tracking(12 * 0.08)
            .foregroundStyle(lit ? Palette.signal : (dim ? Palette.fgFaint : Palette.fgMuted))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 46, height: 28)
            .background(Palette.bgInset, in: RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(lit ? Palette.signalEdge : Palette.line, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

/// A panel: raised surface, hairline border, and a second offset outline behind it (the badline stack).
struct Panel<Content: View>: View {
    var stacked: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(Palette.bgRaised, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line, lineWidth: 1))
            .background(alignment: .topLeading) {
                if stacked {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Palette.line, lineWidth: 1)
                        .offset(x: 5, y: 5)
                }
            }
            .padding(.trailing, stacked ? 5 : 0)
            .padding(.bottom, stacked ? 5 : 0)
    }
}
