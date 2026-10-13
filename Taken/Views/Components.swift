import SwiftUI

/// "[02] STACK - - - - - - - - 05 DUE"
struct SectionHeader: View {
    @Environment(\.theme) private var theme
    let index: String
    let title: String
    var trailing: String? = nil
    var trailingColor: Color? = nil

    init(index: String, title: String, trailing: String? = nil, trailingColor: Color? = nil) {
        self.index = index
        self.title = title
        self.trailing = trailing
        self.trailingColor = trailingColor
    }

    var body: some View {
        HStack(spacing: 10) {
            Text("[\(index)]").hud(11, theme.fgFaint, tracking: 0.06)
            Text(title).hud(11, theme.fgMuted, tracking: 0.16)
            DashedRule()
                .frame(maxWidth: .infinity)
            if let trailing {
                Text(trailing).hud(11, trailingColor ?? theme.fgSubtle, tracking: 0.12)
            }
        }
        .padding(.top, 26)
        .padding(.bottom, 12)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Small status lamp, lit = signal. Square in the HUD looks, round in Blush.
struct Lamp: View {
    @Environment(\.theme) private var theme
    var on: Bool
    var size: CGFloat = 6

    init(on: Bool, size: CGFloat = 6) {
        self.on = on
        self.size = size
    }

    var body: some View {
        LampShape(roundness: theme.radius.lampRoundness)
            .fill(on ? theme.signal : theme.fgFaint)
            .frame(width: size, height: size)
            .shadow(color: on ? theme.glow(0.7) : .clear, radius: on ? 4 : 0)
            .accessibilityHidden(true)
    }
}

/// Solid button, the badline primary: light on the dark looks, ink on Blush.
struct PrimaryButton: View {
    @Environment(\.theme) private var theme
    let title: String
    var lamp: Bool = false
    /// Locked mode: a small lock where the lamp sits, because the tap opens Taken Pro.
    var locked: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    init(title: String, lamp: Bool = false, locked: Bool = false, enabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.lamp = lamp
        self.locked = locked
        self.enabled = enabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                } else if lamp {
                    LampShape(roundness: theme.radius.lampRoundness).fill(theme.signal).frame(width: 7, height: 7)
                }
                Text(title)
                    .font(.monoFixed(14, .monoSemibold))
                    .tracking(14 * 0.12)
            }
            .foregroundStyle(theme.buttonText)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(theme.button.opacity(enabled ? 1 : 0.28), in: RoundedRectangle(cornerRadius: theme.radius.panel))
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
    }
}

/// Outline button for secondary actions.
struct OutlineButton: View {
    @Environment(\.theme) private var theme
    let title: String
    var color: Color? = nil
    var height: CGFloat = 44
    let action: () -> Void

    init(title: String, color: Color? = nil, height: CGFloat = 44, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.height = height
        self.action = action
    }

    var body: some View {
        let color = self.color ?? theme.fg
        Button(action: action) {
            Text(title)
                .font(.monoFixed(12, .monoSemibold))
                .tracking(12 * 0.12)
                .foregroundStyle(color)
                .padding(.horizontal, 14)
                .frame(height: height)
                .overlay(RoundedRectangle(cornerRadius: theme.radius.control).strokeBorder(color.opacity(0.45), lineWidth: 1))
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
        RowPressLabel(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct RowPressLabel: View {
    @Environment(\.theme) private var theme
    let label: ButtonStyleConfiguration.Label
    let isPressed: Bool

    init(label: ButtonStyleConfiguration.Label, isPressed: Bool) {
        self.label = label
        self.isPressed = isPressed
    }

    var body: some View {
        label.background(isPressed ? theme.bgInset : Color.clear)
    }
}

/// Title bar for sheets.
struct SheetHeader: View {
    @Environment(\.theme) private var theme
    let title: String
    var subtitle: String? = nil
    var subtitleColor: Color? = nil
    let onClose: () -> Void

    init(title: String, subtitle: String? = nil, subtitleColor: Color? = nil, onClose: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.subtitleColor = subtitleColor
        self.onClose = onClose
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.monoFixed(16, .monoSemibold))
                    .tracking(16 * 0.14)
                    .foregroundStyle(theme.fg)
                if let subtitle {
                    Text(subtitle).hud(11, subtitleColor ?? theme.fgSubtle)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.fgMuted)
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
            Rectangle().fill(theme.line).frame(height: 1)
        }
    }
}

/// The code tag box: "VD3".
struct CodeTag: View {
    @Environment(\.theme) private var theme
    let code: String
    var lit: Bool = false
    var dim: Bool = false

    init(code: String, lit: Bool = false, dim: Bool = false) {
        self.code = code
        self.lit = lit
        self.dim = dim
    }

    var body: some View {
        Text(code)
            .font(.monoFixed(12, .monoSemibold))
            .tracking(12 * 0.08)
            .foregroundStyle(lit ? theme.signalInk : (dim ? theme.fgFaint : theme.fgMuted))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 46, height: 28)
            .background(theme.bgInset, in: RoundedRectangle(cornerRadius: theme.radius.control))
            .overlay(
                RoundedRectangle(cornerRadius: theme.radius.control)
                    .strokeBorder(lit ? theme.signalEdge : theme.line, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

/// A panel: raised surface, hairline border, and a second offset outline behind it (the badline stack).
struct Panel<Content: View>: View {
    @Environment(\.theme) private var theme
    var stacked: Bool = true
    var content: Content

    init(stacked: Bool = true, @ViewBuilder content: () -> Content) {
        self.stacked = stacked
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius.panel)
        content
            .background(theme.bgRaised, in: shape)
            .overlay(shape.strokeBorder(theme.line, lineWidth: 1))
            .background(alignment: .topLeading) {
                if stacked {
                    shape
                        .strokeBorder(theme.line, lineWidth: 1)
                        .offset(x: 5, y: 5)
                }
            }
            // The offset outline's 5 pt is reserved either way, so stacked and flat panels share one width.
            .padding(.trailing, 5)
            .padding(.bottom, stacked ? 5 : 0)
    }
}

/// A time setting in Geist Mono with a chevron, like the day-start control. A tap opens a wheel in a small
/// sheet, so every time on screen stays in one type system.
struct MonoTimeButton: View {
    @Environment(\.theme) private var theme
    let title: String
    let minutes: Int
    let onSet: (Int) -> Void

    @State private var editing = false

    init(title: String, minutes: Int, onSet: @escaping (Int) -> Void) {
        self.title = title
        self.minutes = minutes
        self.onSet = onSet
    }

    var body: some View {
        Button {
            editing = true
        } label: {
            HStack(spacing: 8) {
                Text(Fmt.minutes(minutes))
                    .font(.monoFixed(15, .monoMedium))
                    .foregroundStyle(theme.fg)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.fgSubtle)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title.capitalized), \(Fmt.minutes(minutes))")
        .accessibilityHint("Double tap to change.")
        .sheet(isPresented: $editing) {
            TimeWheelSheet(title: title, minutes: minutes, onSet: onSet)
                .environment(\.theme, theme)
        }
    }
}

/// One time of day on a wheel, in a small sheet.
struct TimeWheelSheet: View {
    @Environment(\.theme) private var theme
    let title: String
    let minutes: Int
    let onSet: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var time = Date()

    init(title: String, minutes: Int, onSet: @escaping (Int) -> Void) {
        self.title = title
        self.minutes = minutes
        self.onSet = onSet
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: title) { dismiss() }
            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "en_GB"))
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            PrimaryButton(title: "SET \(Fmt.minutes(picked))") {
                onSet(picked)
                dismiss()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.height(400)])
        .presentationBackground(theme.bg)
        .preferredColorScheme(theme.scheme)
        .onAppear {
            time = Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        }
    }

    private var picked: Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}
