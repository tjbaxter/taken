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
        let future = isFuture
        VStack(spacing: 0) {
            SheetHeader(title: Fmt.dayHeader(day), subtitle: Fmt.daySheetStatus(summary, isToday: isToday),
                        subtitleColor: summary.allTaken ? Palette.signal : Palette.fgSubtle) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(index: "01", title: "LOG AT", trailing: isToday ? "TODAY" : nil)
                    logTimeRow(isFuture: future)
                    SectionHeader(index: "02", title: "ITEMS", trailing: "\(summary.items.count)")
                    if summary.items.isEmpty {
                        Text("NOTHING IN YOUR STACK").hud(11, Palette.fgSubtle)
                    } else {
                        Panel {
                            VStack(spacing: 0) {
                                ForEach(Array(summary.items.enumerated()), id: \.element.id) { index, row in
                                    if index > 0 { DashedRule().padding(.horizontal, 14) }
                                    DayItemRow(row: row, clock: model.clock, isToday: isToday,
                                               logLabel: Fmt.minutes(logMinutes), canLog: !future,
                                               onLog: { model.logDose(row.item, on: day, minutes: logMinutes) },
                                               onRemove: { removing = $0 })
                                }
                            }
                        }
                    }
                    Text("Tap a time to remove that dose.")
                        .font(.sans(13))
                        .foregroundStyle(Palette.fgSubtle)
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

    /// The chosen time on this day has not come yet, so it cannot be logged.
    private var isFuture: Bool {
        model.clock.date(on: day, hour: logMinutes / 60, minute: logMinutes % 60) > model.now
    }

    private var removalTitle: String {
        guard let removing else { return "Remove dose?" }
        let name = model.state.item(removing.itemId)?.name ?? "this item"
        return "Remove the \(Fmt.clock(removing.takenAt, model.clock)) dose of \(name)?"
    }

    private func logTimeRow(isFuture: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEW ENTRIES").hud(12, Palette.fg)
                Text(isFuture ? "That time is still to come. Pick an earlier one."
                              : (isToday ? "Defaults to now." : "Defaults to 09:00. Change it if you remember."))
                    .font(.sans(13))
                    .foregroundStyle(isFuture ? Palette.fg : Palette.fgSubtle)
            }
            Spacer()
            MonoTimeButton(title: "LOG AT", minutes: logMinutes) { minutes in
                logMinutes = minutes
            }
        }
        .padding(14)
        .background(Palette.bgRaised, in: RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line, lineWidth: 1))
    }
}

private struct DayItemRow: View {
    let row: ItemDay
    let clock: DayClock
    let isToday: Bool
    let logLabel: String
    let canLog: Bool
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
                Text(Fmt.dayItemStatus(row, isToday: isToday)).hud(10, subtitleColor, tracking: 0.12)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .layoutPriority(0)
            Spacer(minLength: 8)
            actions
                .layoutPriority(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 70)
    }

    private var showsLog: Bool { row.isPending || row.doses.isEmpty }

    @ViewBuilder
    private var actions: some View {
        if row.doses.count + (showsLog ? 1 : 0) <= 2 {
            HStack(spacing: 6) { actionItems }
        } else {
            VStack(alignment: .trailing, spacing: 6) { actionItems }
        }
    }

    @ViewBuilder
    private var actionItems: some View {
        ForEach(row.doses) { dose in
            Button {
                onRemove(dose)
            } label: {
                HStack(spacing: 6) {
                    Text(Fmt.clock(dose.takenAt, clock))
                        .font(.monoFixed(13, .monoMedium))
                        .foregroundStyle(Palette.signal)
                        .fixedSize()
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
        if showsLog {
            Button(action: onLog) {
                Text("+ LOG \(logLabel)")
                    .font(.monoFixed(11, .monoSemibold))
                    .tracking(11 * 0.1)
                    .foregroundStyle(Palette.fg)
                    .fixedSize()
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.lineStrong, lineWidth: 1))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .disabled(!canLog)
            .opacity(canLog ? 1 : 0.4)
            .accessibilityLabel("Log \(row.item.name) at \(logLabel)")
        }
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

    /// The wheel's time on today's logical day has not come yet (an hour before the day start means
    /// tomorrow morning), so it is never used in place of the time that was picked.
    private var isFuture: Bool {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        return model.clock.date(on: model.today.day, hour: c.hour ?? 0, minute: c.minute ?? 0) > model.now
    }

    private var buttonTitle: String {
        if isFuture { return "IN THE FUTURE" }
        return lastDose == nil ? "LOG AT \(timeLabel)" : "SET TO \(timeLabel)"
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
            PrimaryButton(title: buttonTitle, enabled: !isFuture) {
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
