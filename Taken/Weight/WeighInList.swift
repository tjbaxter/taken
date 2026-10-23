import SwiftUI

/// All weigh-ins (SPEC 3.12): every weigh-in, newest first, with its day, time and weight. A tap opens it to change the
/// weight, the day or the time (Taken Pro after the first weigh-in, as backdating a dose needs it); a swipe deletes it,
/// always, with UNDO. Hiding the tab never deletes anything here; only Erase all data does.
struct WeighInList: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.paywallAnchor) private var paywallAnchor
    @Environment(\.theme) private var theme
    @State private var path: [UUID] = []

    init() {}

    var body: some View {
        let weight = model.weight
        let rows = weight.state.newestFirst
        NavigationStack(path: $path) {
            List {
                if rows.isEmpty {
                    Text(WeightCopy.noWeighIns)
                        .font(.sans(16, .sans, relativeTo: .body))
                        .foregroundStyle(theme.fgSubtle)
                        .listRowBackground(theme.bgRaised)
                }
                ForEach(rows) { weighIn in
                    Button {
                        edit(weighIn.id)
                    } label: {
                        WeighInRow(weighIn: weighIn, unit: weight.unit, clock: model.clock, today: model.today.day)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(theme.bgRaised)
                    .listRowSeparatorTint(theme.line)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            model.deleteWeighIn(weighIn.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .accessibilityAction(named: "Delete") { model.deleteWeighIn(weighIn.id) }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.bg.ignoresSafeArea())
            .environment(\.defaultMinListRowHeight, 52)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(WeightCopy.allWeighIns)
                        .font(.sans(17, .sansSemibold, relativeTo: .body))
                        .foregroundStyle(theme.fg)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.sans(17, .sansSemibold, relativeTo: .body))
                            .foregroundStyle(theme.signalInk)
                    }
                }
            }
            .toolbarBackground(theme.bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                WeighInEditor(id: id)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { WeightToastDock() }
        }
        .tint(theme.signalInk)
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
        .onAppear {
            // Edit… on today's number: the editor is already open, and Back leads to the list.
            guard let id = model.weight.editOnOpen else { return }
            model.weight.editOnOpen = nil
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { path = [id] }
        }
    }

    /// Changing a weigh-in follows the weigh-in rule: without Pro after the first one, the paywall comes over this sheet.
    private func edit(_ id: UUID) {
        let path = $path
        model.requireWeightPro(paywallAnchor) { path.wrappedValue.append(id) }
    }
}

/// "Tue 20 Oct" over "07:42", and "88.35 kg" on the right, in Geist Mono.
private struct WeighInRow: View {
    @Environment(\.theme) private var theme
    let weighIn: WeighIn
    let unit: WeightUnit
    let clock: DayClock
    let today: DayKey

    init(weighIn: WeighIn, unit: WeightUnit, clock: DayClock, today: DayKey) {
        self.weighIn = weighIn
        self.unit = unit
        self.clock = clock
        self.today = today
    }

    var body: some View {
        let day = clock.day(of: weighIn)
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(WeightCopy.listDay(day, today: today))
                    .font(.sans(17, .sans, relativeTo: .body))
                    .foregroundStyle(theme.fg)
                Text(Fmt.clock(weighIn.weighedAt, clock))
                    .font(.mono(14, .monoMedium, relativeTo: .footnote))
                    .foregroundStyle(theme.fgSubtle)
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(WeightFormat.value(weighIn.kg, unit: unit))
                    .font(.mono(17, .monoMedium, relativeTo: .body))
                    .foregroundStyle(theme.fg)
                Text(unit.symbol)
                    .font(.sans(14, .sans, relativeTo: .footnote))
                    .foregroundStyle(theme.fgMuted)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.fgFaint)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Fmt.longDay(day)) at \(Fmt.spoken(weighIn.weighedAt)), \(WeightFormat.spoken(weighIn.kg, unit: unit))")
        .accessibilityHint("Double tap to change it.")
    }
}

/// One weigh-in: its weight, day and time, or Delete. Save is on once something changed and the weight reads in this
/// locale within the bounds; a moment still to come cannot be picked.
struct WeighInEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.theme) private var theme
    let id: UUID

    @State private var text = ""
    @State private var date = Date()
    @State private var loaded = false

    init(id: UUID) {
        self.id = id
    }

    var body: some View {
        let unit = model.weight.unit
        let kg = WeightFormat.kilograms(text, unit: unit, locale: locale)
        Form {
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    TextField("", text: $text, prompt: Text(WeightFormat.value(0, unit: unit, locale: locale))
                        .foregroundStyle(theme.fgFaint))
                        .font(.mono(22, .monoMedium, relativeTo: .title2))
                        .foregroundStyle(theme.fg)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Weight in \(unit.spoken)")
                    Text(unit.symbol)
                        .font(.sans(17, .sans, relativeTo: .body))
                        .foregroundStyle(theme.fgMuted)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
            } header: {
                sectionTitle(WeightCopy.weightField)
            }
            .listRowBackground(theme.bgRaised)

            Section {
                DatePicker(WeightCopy.when, selection: $date, in: ...max(Date(), date), displayedComponents: [.date, .hourAndMinute])
                    .font(.sans(17, .sans, relativeTo: .body))
                    .foregroundStyle(theme.fg)
                    .environment(\.locale, Locale(identifier: "en_GB"))
            } header: {
                sectionTitle(WeightCopy.when)
            }
            .listRowBackground(theme.bgRaised)

            Section {
                Button(role: .destructive) {
                    model.deleteWeighIn(id)
                    dismiss()
                } label: {
                    Text(WeightCopy.deleteWeighIn)
                        .font(.sans(17, .sans, relativeTo: .body))
                        .foregroundStyle(theme.danger)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }
            .listRowBackground(theme.bgRaised)
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(theme.bg.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(WeightCopy.editTitle)
                    .font(.sans(17, .sansSemibold, relativeTo: .body))
                    .foregroundStyle(theme.fg)
                    .accessibilityAddTraits(.isHeader)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    save(kg)
                } label: {
                    Text(WeightCopy.save)
                        .font(.sans(17, .sansSemibold, relativeTo: .body))
                        .foregroundStyle(theme.signalInk)
                }
                .disabled(kg == nil || !changed(kg))
            }
        }
        .toolbarBackground(theme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onChange(of: text) { _, typed in
            let clean = WeightFormat.sanitize(typed, locale: locale)
            if clean != typed { text = clean }
        }
        .onAppear(perform: load)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.sans(14, .sansSemibold, relativeTo: .footnote))
            .foregroundStyle(theme.fgSubtle)
            .textCase(nil)
    }

    private func load() {
        guard !loaded, let weighIn = model.weight.state.weighIn(id) else { return }
        loaded = true
        text = WeightFormat.value(weighIn.kg, unit: model.weight.unit, locale: locale)
        date = weighIn.weighedAt
    }

    /// Something to save: a weight that differs from the stored one as shown, or another minute.
    private func changed(_ kg: Double?) -> Bool {
        guard let kg, let weighIn = model.weight.state.weighIn(id) else { return false }
        let unit = model.weight.unit
        let weightChanged = WeightFormat.value(kg, unit: unit) != WeightFormat.value(weighIn.kg, unit: unit)
        return weightChanged || WeightImport.minute(date) != WeightImport.minute(weighIn.weighedAt)
    }

    private func save(_ kg: Double?) {
        guard let kg, let weighIn = model.weight.state.weighIn(id) else { return }
        let unit = model.weight.unit
        // A weight left as it was keeps its exact value (a pound figure round-trips through kilograms).
        let kept = WeightFormat.value(kg, unit: unit) == WeightFormat.value(weighIn.kg, unit: unit) ? weighIn.kg : kg
        let moment = WeightImport.minute(date) == WeightImport.minute(weighIn.weighedAt) ? weighIn.weighedAt : date
        model.updateWeighIn(id, kg: kept, at: moment)
        dismiss()
    }
}
