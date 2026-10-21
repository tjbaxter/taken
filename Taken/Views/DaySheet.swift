import SwiftUI

/// One day from History: what was taken and when. The backfill path for a forgotten day.
struct DaySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.paywallAnchor) private var paywallAnchor
    @Environment(\.theme) private var theme

    let day: DayKey

    /// Set on appear: now for today, an hour after the wake-up time for an earlier day.
    @State private var logMinutes: Int = 0
    @State private var removing: Dose?

    init(day: DayKey) {
        self.day = day
    }

    var body: some View {
        let summary = model.sheetSummary(for: day)
        let future = isFuture
        VStack(spacing: 0) {
            SheetHeader(title: Fmt.longDay(day), subtitle: Fmt.daySheetStatus(summary, isToday: isLive),
                        subtitleColor: summary.allTaken && summary.openCount == 0 ? theme.signalInk : theme.fgSubtle) {
                dismiss()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    logTimeRow(isFuture: future)
                        .padding(.top, 12)
                    SectionHeader("Items", trailing: summary.items.isEmpty ? nil : "Tap a time to remove it")
                    if summary.items.isEmpty {
                        Text("Nothing in your stack yet")
                            .font(.sans(16, .sans, relativeTo: .body))
                            .foregroundStyle(theme.fgSubtle)
                    } else {
                        Card {
                            VStack(spacing: 0) {
                                ForEach(Array(summary.items.enumerated()), id: \.element.id) { index, row in
                                    if index > 0 { RowDivider() }
                                    DayItemRow(row: row, day: day, clock: model.clock, isToday: isLive,
                                               logLabel: Fmt.minutes(logMinutes), canLog: !future,
                                               onLog: { backfill(row.item) },
                                               onRemove: { removing = $0 })
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
        .onAppear {
            logMinutes = isToday ? model.clock.minutesOfDay(model.now) : model.settings.backfillMinutes
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

    /// Today, or a day still to come: what is not taken yet reads as pending, never missed.
    private var isLive: Bool { Self.isLive(day, today: model.today.day) }

    /// A day sheet for a day after today opens only from a weekly row whose early dose counts for its next due day
    /// ("Open Thursday", SPEC 3.3). Nothing on it can have been missed yet, so it reads like today.
    nonisolated static func isLive(_ day: DayKey, today: DayKey) -> Bool { day >= today }

    /// Backfill logs a dose, so in locked mode it opens the paywall over this sheet; the log stays readable.
    private func backfill(_ item: Item) {
        let minutes = logMinutes
        let day = self.day
        model.requirePro(paywallAnchor) { [weak model = model] in
            model?.logDose(item, on: day, minutes: minutes)
        }
    }

    /// The chosen time on this day has not come yet, so it cannot be logged.
    private var isFuture: Bool {
        model.clock.date(on: day, hour: logMinutes / 60, minute: logMinutes % 60) > model.now
    }

    private var removalTitle: String {
        guard let removing else { return "Remove dose?" }
        let name = model.state.item(removing.itemId)?.name ?? "this item"
        return "Remove the \(Fmt.doseClock(removing, viewing: day, model.clock)) dose of \(name)?"
    }

    private func logTimeRow(isFuture: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Log at")
                    .font(.sans(17, .sans, relativeTo: .body))
                    .foregroundStyle(theme.fg)
                Text(isFuture ? "That time is still to come. Pick an earlier one."
                              : (isToday ? "Defaults to now." : "An hour after you wake up. Change it if you remember."))
                    .font(.sans(14, .sans, relativeTo: .footnote))
                    .foregroundStyle(isFuture ? theme.fg : theme.fgSubtle)
            }
            Spacer()
            MonoTimeButton(title: "Log at", minutes: logMinutes) { minutes in
                logMinutes = minutes
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
    }
}

private struct DayItemRow: View {
    @Environment(\.theme) private var theme
    let row: ItemDay
    /// The sheet's day: a dose logged on another day (a weekly dose that counts for it) shows that day, "Fri 08:12".
    let day: DayKey
    let clock: DayClock
    let isToday: Bool
    let logLabel: String
    let canLog: Bool
    let onLog: () -> Void
    let onRemove: (Dose) -> Void

    init(row: ItemDay, day: DayKey, clock: DayClock, isToday: Bool, logLabel: String, canLog: Bool,
         onLog: @escaping () -> Void, onRemove: @escaping (Dose) -> Void) {
        self.row = row
        self.day = day
        self.clock = clock
        self.isToday = isToday
        self.logLabel = logLabel
        self.canLog = canLog
        self.onLog = onLog
        self.onRemove = onRemove
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.item.name)
                    .font(.sans(16, .sansMedium, relativeTo: .body))
                    .foregroundStyle(theme.fg)
                    .lineLimit(1)
                Text(Fmt.dayItemStatus(row, isToday: isToday))
                    .font(.sans(14, .sans, relativeTo: .footnote))
                    .foregroundStyle(row.isDue && row.isDone ? theme.signalInk : theme.fgSubtle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .layoutPriority(0)
            Spacer(minLength: 8)
            actions
                .layoutPriority(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: 64)
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
                    Text(Fmt.doseClock(dose, viewing: day, clock))
                        .font(.monoFixed(14, .monoMedium))
                        .foregroundStyle(theme.signalInk)
                        .fixedSize()
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(theme.fgSubtle)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(theme.signalWash, in: Capsule())
                .overlay(Capsule().strokeBorder(theme.signalEdge, lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Taken \(Fmt.spokenDose(dose, viewing: day, clock)). Remove.")
        }
        if showsLog {
            Button(action: onLog) {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text(logLabel)
                        .font(.monoFixed(14, .monoMedium))
                }
                .foregroundStyle(theme.fg)
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(height: 32)
                .overlay(Capsule().strokeBorder(theme.lineStrong, lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .disabled(!canLog)
            .opacity(canLog ? 1 : 0.4)
            .accessibilityLabel("Log \(row.item.name) at \(logLabel)")
        }
    }
}

/// Set time: correct when the last dose was really taken, or log one at the right time.
struct SetTimeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.paywallAnchor) private var paywallAnchor
    @Environment(\.theme) private var theme

    let item: Item
    @State private var time = Date()

    init(item: Item) {
        self.item = item
    }

    /// The dose this corrects: the item's latest logged today, whichever day it counts for.
    private var lastDose: Dose? {
        model.setTimeDose(for: item)
    }

    /// The wheel's time on today's logical day has not come yet (an hour before the day start means
    /// tomorrow morning), so it is never used in place of the time that was picked.
    private var isFuture: Bool {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        return model.clock.date(on: model.today.day, hour: c.hour ?? 0, minute: c.minute ?? 0) > model.now
    }

    private var buttonTitle: String {
        if isFuture { return "That time is still to come" }
        return lastDose == nil ? "Log at \(timeLabel)" : "Set to \(timeLabel)"
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: item.name,
                        subtitle: lastDose == nil ? "Log a dose at the time you took it." : "Correct the last dose.") {
                dismiss()
            }
            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "en_GB"))
                .environment(\.colorScheme, theme.scheme)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            PrimaryButton(title: buttonTitle, enabled: !isFuture) {
                let c = Calendar.current.dateComponents([.hour, .minute], from: time)
                let item = self.item
                let dismiss = self.dismiss
                model.requirePro(paywallAnchor) { [weak model = model] in
                    model?.setTime(item, hour: c.hour ?? 0, minute: c.minute ?? 0)
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            Spacer(minLength: 0)
        }
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.height(430)])
        .presentationBackground(theme.bg)
        .onAppear {
            time = lastDose?.takenAt ?? model.now
        }
    }

    private var timeLabel: String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
