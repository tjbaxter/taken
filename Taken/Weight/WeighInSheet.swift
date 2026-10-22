import SwiftUI

#if DEBUG || TAKEN_INTERNAL
/// Log weigh-in (SPEC 3.12): one field, already focused on the decimal pad, the unit beside it, the time as plain text,
/// and Save. Three taps and the digits from the Weight tab. The last weigh-in shows in grey as the placeholder, there to
/// see but never saved by accident: Save stays off until what is typed reads as a number in this locale (88,35 in de_DE)
/// between 20 and 350 kg (44 and 770 lb). No date, photo, note, goal or unit question here (Tom's rule: never a choice
/// on the capture path); a past weigh-in or a wrong number is fixed in All weigh-ins.
struct WeighInSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.theme) private var theme

    @State private var text = ""
    @FocusState private var focused: Bool
    /// The content's own height: the sheet is as tall as what it holds.
    @State private var contentHeight: CGFloat = 300

    init() {}

    var body: some View {
        let unit = model.weight.unit
        let kg = WeightFormat.kilograms(text, unit: unit, locale: locale)
        VStack(spacing: 0) {
            SheetHeader(title: WeightCopy.logWeighIn) { dismiss() }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                TextField("", text: $text, prompt: Text(placeholder(unit)).foregroundStyle(theme.fgFaint))
                    .font(.mono(44, .monoMedium, relativeTo: .largeTitle))
                    .foregroundStyle(theme.fg)
                    .keyboardType(.decimalPad)
                    .focused($focused)
                    .submitLabel(.done)
                    .lineLimit(1)
                    .accessibilityLabel("Weight in \(unit.spoken)")
                Text(unit.symbol)
                    .font(.sans(22, .sansMedium, relativeTo: .title2))
                    .foregroundStyle(theme.fgMuted)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
                .strokeBorder(focused ? theme.signalEdge : theme.line, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            Text(WeightCopy.now)
                .font(.sans(15, .sans, relativeTo: .subheadline))
                .foregroundStyle(theme.fgSubtle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .accessibilityLabel("Logged now")
            PrimaryButton(title: WeightCopy.save, enabled: kg != nil) {
                save(kg)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { contentHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, height in contentHeight = height }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(theme.bg)
        .onChange(of: text) { _, typed in
            let clean = WeightFormat.sanitize(typed, locale: locale)
            if clean != typed { text = clean }
        }
        .task {
            // Focus once the sheet is up: a field inserted with the sheet takes focus after one main-actor hop.
            try? await Task.sleep(for: .milliseconds(80))
            focused = true
        }
    }

    /// The last weigh-in, in grey, in the unit in use; "0.0" before there is one.
    private func placeholder(_ unit: WeightUnit) -> String {
        WeightFormat.value(model.weight.state.last?.kg ?? 0, unit: unit, locale: locale)
    }

    private func save(_ kg: Double?) {
        guard let kg else { return }
        model.saveWeighIn(kg: kg)
        dismiss()
    }
}
#endif
