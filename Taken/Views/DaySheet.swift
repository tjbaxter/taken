import SwiftUI

/// One day from the log: what was taken and when. The backfill path for a forgotten day.
struct DaySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let day: DayKey

    @State private var logMinutes: Int = 9 * 60
    @State private var removing: Dose?

    init(day: DayKey) {
        self.day = day
    }

    var body: some View {
        let summary = model.sheetSummary(for: day)
        VStack(spacing: 0) {
            SheetHeader(title: Fmt.dayHeader(day), subtitle: statusLine(summary),
                        subtitleColor: summary.allTaken ? Palette.signal : Palette.fgSubtle) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(index: "01", title: "LOG AT", trailing: isToday ? "TODAY" : nil)
                    logTimeRow
                    SectionHeader(index: "02", title: "ITEMS", trailing: "\(summary.items.count)")
                    if summary.items.isEmpty {
                        Text("NOTHING IN YOUR STACK").hud(11, Palette.fgFaint)
                    } else {
                        Panel {
                            VStack(spacing: 0) {
                                ForEach(Array(summary.items.enumerated()), id: \.element.id) { index, row in
                                    if index > 0 { DashedRule().padding(.horizontal, 14) }
                                    DayItemRow(row: row, clock: model.clock, logLabel: Fmt.minutes(logMinutes),
                                               onLog: { model.logDose(row.item, on: day, minutes: logMinutes) },
                                               onRemove: { removing = $0 })
                                }
                            }
                        }
                    }
                    Text("Tap a time to remove that dose.")
                        .font(.sans(13))
                        .foregroundStyle(Palette.fgFaint)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .background(Palette.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(Palette.bg)
        .onAppear {
            if isToday {
                logMinutes = model.clock.minutesOfDay(model.now)
            }
        }
        .confirmationDialog(
            removalTitle,
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible,
            presenting: removing
        ) { dose in
            Button("Remove dose", role: .destructive) {
                model.removeDose(dose)
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
        }
    }

    private var isToday: Bool { day == model.today.day }

    private var removalTitle: String {
        guard let removing else { return "Remove dose?" }
        let name = model.state.item(removing.itemId)?.name ?? "this item"
        return "Remove the \(Fmt.clock(removing.takenAt, model.clock)) dose of \(name)?"
    }

    private var logTimeRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEW ENTRIES").hud(12, Palette.fg)
                Text(isToday ? "Defaults to now." : "Defaults to 09:00. Change it if you remember.")
                    .font(.sans(13))
                    .foregroundStyle(Palette.fgSubtle)
            }
            Spacer()
            DatePicker("", selection: logTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "en_GB"))
                .tint(Palette.signal)
        }
        .padding(14)
        .background(Palette.bgRaised, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line, lineWidth: 1))
    }

    private var logTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: logMinutes / 60, minute: logMinutes % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                logMinutes = (c.hour ?? 9) * 60 + (c.minute ?? 0)
            }
        )
    }

    private func statusLine(_ summary: DaySummary) -> String {
        switch summary.status {
        case .nothingDue: return summary.allDoses.isEmpty ? "NOTHING DUE" : "\(summary.allDoses.count) LOGGED \u{00B7} NOTHING DUE"
        case .complete: return "ALL TAKEN \u{00B7} \(summary.takenDueDoses)/\(summary.dueDoses)"
        case .partial: return "\(summary.takenDueDoses)/\(summary.dueDoses) TAKEN \u{00B7} \(summary.pendingDoses) MISSING"
        case .missed: return isToday ? "\(summary.dueDoses) PENDING" : "NOTHING LOGGED \u{00B7} 0/\(summary.dueDoses)"
        case .future: return ""
        }
    }
}

private struct DayItemRow: View {
    let row: ItemDay
    let clock: DayClock
    let logLabel: String
    let onLog: () -> Void
    let onRemove: (Dose) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            CodeTag(code: row.item.code, lit: row.isDue && row.isDone, dim: !row.isDue && row.doses.isEmpty)
            VStack(alignment: .leading, spacing: 5) {
                Text(row.item.name)
                    .font(.sans(16, .sansMedium))
                    .foregroundStyle(Palette.fg)
                    .lineLimit(1)
                Text(subtitle).hud(10, subtitleColor, tracking: 0.12)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(row.doses) { dose in
                    Button {
                        onRemove(dose)
                    } label: {
                        HStack(spacing: 6) {
                            Text(Fmt.clock(dose.takenAt, clock))
                                .font(.monoFixed(13, .monoMedium))
                                .foregroundStyle(Palette.signal)
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Palette.fgSubtle)
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 32)
                        .background(Palette.signalWash, in: RoundedRectangle(cornerRadius: 3))
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.signalEdge, lineWidth: 1))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Taken at \(Fmt.spoken(dose.takenAt)). Remove.")
                }
                if row.isPending || row.doses.isEmpty {
                    Button(action: onLog) {
                        Text("+ LOG \(logLabel)")
                            .font(.monoFixed(11, .monoSemibold))
                            .tracking(11 * 0.1)
                            .foregroundStyle(Palette.fg)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.lineStrong, lineWidth: 1))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("Log \(row.item.name) at \(logLabel)")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 70)
    }

    private var subtitle: String {
        if !row.isActive && row.doses.isEmpty { return "\(Fmt.frequency(row.item.frequency)) \u{00B7} ADDED LATER" }
        if !row.isDue { return "\(Fmt.frequency(row.item.frequency)) \u{00B7} NOT DUE" }
        if row.isDone { return "\(Fmt.frequency(row.item.frequency)) \u{00B7} TAKEN" }
        if row.doses.isEmpty { return "\(Fmt.frequency(row.item.frequency)) \u{00B7} MISSED" }
        return "\(Fmt.frequency(row.item.frequency)) \u{00B7} \(row.takenCount)/\(row.dosesPerDay)"
    }

    private var subtitleColor: Color {
        if row.isDue && row.isDone { return Palette.signal }
        return Palette.fgSubtle
    }
}

/// Set time: correct when the last dose was really taken, or log one at the right time.
struct SetTimeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let item: Item
    @State private var time = Date()

    init(item: Item) {
        self.item = item
    }

    private var lastDose: Dose? {
        model.today.items.first { $0.id == item.id }?.lastDose
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "SET TIME \u{00B7} \(item.code)",
                        subtitle: lastDose == nil ? "LOG A DOSE AT THE TIME YOU TOOK IT" : "CORRECT THE LAST DOSE") {
                dismiss()
            }
            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "en_GB"))
                .environment(\.colorScheme, .dark)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
            PrimaryButton(title: lastDose == nil ? "LOG AT \(timeLabel)" : "SET TO \(timeLabel)") {
                let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                model.setTime(item, hour: c.hour ?? 0, minute: c.minute ?? 0)
                dismiss()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .background(Palette.bg.ignoresSafeArea())
        .presentationDetents([.height(430)])
        .presentationBackground(Palette.bg)
        .onAppear {
            time = lastDose?.takenAt ?? model.now
        }
    }

    private var timeLabel: String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
