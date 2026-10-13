import SwiftUI

/// A section title over a card: "Stack", "Not today". Geist, sentence case, nothing else.
struct SectionHeader: View {
    @Environment(\.theme) private var theme
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.sans(15, .sansSemibold, relativeTo: .subheadline))
                .foregroundStyle(theme.fgMuted)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.sans(14, .sans, relativeTo: .footnote))
                    .foregroundStyle(theme.fgSubtle)
            }
        }
        .padding(.top, 22)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A raised surface with a hairline edge and the look's soft corners: the list cards on Today, History and the sheets.
struct Card<Content: View>: View {
    @Environment(\.theme) private var theme
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
        content
            .background(theme.bgRaised, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(theme.line, lineWidth: 1))
    }
}

/// A hairline between rows in a card.
struct RowDivider: View {
    @Environment(\.theme) private var theme
    var inset: CGFloat

    init(inset: CGFloat = 16) {
        self.inset = inset
    }

    var body: some View {
        Rectangle()
            .fill(theme.line)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// The solid button: light on the dark looks, ink on Blush.
struct PrimaryButton: View {
    @Environment(\.theme) private var theme
    let title: String
    /// Locked mode: a small lock, because the tap opens Taken Pro.
    var locked: Bool = false
    var enabled: Bool = true
    /// A count shown after the title in Geist Mono: "Take all 2".
    var count: Int?
    let action: () -> Void

    init(title: String, locked: Bool = false, enabled: Bool = true, count: Int? = nil, action: @escaping () -> Void) {
        self.title = title
        self.locked = locked
        self.enabled = enabled
        self.count = count
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(title)
                    .font(.sans(17, .sansSemibold, relativeTo: .body))
                if let count {
                    Text("\(count)")
                        .font(.mono(16, .monoMedium, relativeTo: .body))
                        .opacity(0.7)
                }
            }
            .foregroundStyle(theme.buttonText)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .background(theme.button.opacity(enabled ? 1 : 0.28),
                        in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
    }
}

/// An outline button for secondary and destructive actions.
struct OutlineButton: View {
    @Environment(\.theme) private var theme
    let title: String
    var color: Color?
    var height: CGFloat = 48
    let action: () -> Void

    init(title: String, color: Color? = nil, height: CGFloat = 48, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.height = height
        self.action = action
    }

    var body: some View {
        let color = self.color ?? theme.fg
        Button(action: action) {
            Text(title)
                .font(.sans(16, .sansSemibold, relativeTo: .body))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .frame(minHeight: height)
                .overlay(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                    .strokeBorder(color.opacity(0.45), lineWidth: 1))
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

/// Title bar for sheets: a title, an optional line under it, and Close.
struct SheetHeader: View {
    @Environment(\.theme) private var theme
    let title: String
    var subtitle: String?
    var subtitleColor: Color?
    let onClose: () -> Void

    init(title: String, subtitle: String? = nil, subtitleColor: Color? = nil, onClose: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.subtitleColor = subtitleColor
        self.onClose = onClose
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.sans(22, .sansSemibold, relativeTo: .title2))
                    .foregroundStyle(theme.fg)
                if let subtitle {
                    Text(subtitle)
                        .font(.sans(15, .sans, relativeTo: .subheadline))
                        .foregroundStyle(subtitleColor ?? theme.fgSubtle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.fgMuted)
                    .frame(width: 32, height: 32)
                    .background(theme.bgInset, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.leading, 20)
        .padding(.trailing, 10)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
}

/// A time setting in Geist Mono with a chevron. A tap opens a wheel in a small sheet, so every time on screen stays in
/// one type system.
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
                    .font(.mono(16, .monoMedium, relativeTo: .body))
                    .foregroundStyle(theme.fg)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.fgSubtle)
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(Fmt.minutes(minutes))")
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
                .padding(.top, 4)
            PrimaryButton(title: "Set \(Fmt.minutes(picked))") {
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
