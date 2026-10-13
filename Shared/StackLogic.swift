import Foundation

enum DayStatus: Sendable, Equatable {
    case future
    case nothingDue
    case complete
    case partial
    case missed
}

/// One item on one logical day.
struct ItemDay: Identifiable, Sendable {
    let item: Item
    let day: DayKey
    /// The item's frequency on this day. A later change in settings never rewrites it.
    let frequency: Frequency
    let isDue: Bool
    /// False when the item was not in the stack this day: added later, or archived then
    /// (shown only so it can be backfilled).
    let isActive: Bool
    /// True when the item sat archived on this day, rather than not being added yet.
    let isPaused: Bool
    let doses: [Dose]

    var id: UUID { item.id }
    var dosesPerDay: Int { frequency.dosesPerDay }
    var dueCount: Int { isDue && isActive ? dosesPerDay : 0 }
    var takenCount: Int { doses.count }
    var takenDueCount: Int { min(doses.count, dueCount) }
    var pendingCount: Int { max(0, dueCount - doses.count) }
    var isPending: Bool { pendingCount > 0 }
    /// Nothing more to take today.
    var isDone: Bool { isDue ? doses.count >= dosesPerDay : !doses.isEmpty }
    var lastDose: Dose? { doses.last }
}

/// Everything about one logical day.
struct DaySummary: Sendable {
    let day: DayKey
    let items: [ItemDay]

    var due: [ItemDay] { items.filter { $0.isDue } }
    var notDue: [ItemDay] { items.filter { !$0.isDue } }
    var dueDoses: Int { items.reduce(0) { $0 + $1.dueCount } }
    var takenDueDoses: Int { items.reduce(0) { $0 + $1.takenDueCount } }
    var pendingDoses: Int { max(0, dueDoses - takenDueDoses) }
    var pendingItems: [ItemDay] { items.filter { $0.isPending } }
    var allTaken: Bool { dueDoses > 0 && takenDueDoses >= dueDoses }
    var isEmpty: Bool { items.isEmpty }
    var allDoses: [Dose] { items.flatMap { $0.doses }.sorted { $0.takenAt < $1.takenAt } }
    var lastDose: Dose? { allDoses.last }

    var status: DayStatus {
        if dueDoses == 0 { return .nothingDue }
        if takenDueDoses >= dueDoses { return .complete }
        if takenDueDoses > 0 { return .partial }
        return .missed
    }
}

struct HistoryCell: Identifiable, Sendable {
    let day: DayKey
    let status: DayStatus
    let isToday: Bool
    var id: Int { day.ordinal }
}

struct Adherence: Sendable, Equatable {
    let taken: Int
    let due: Int

    /// Whole percent, rounded down so 100% only ever means perfect. Nil when nothing was due.
    var percent: Int? {
        guard due > 0 else { return nil }
        return Int((Double(taken) * 100 / Double(due)).rounded(.down))
    }
}

/// Read-only view over a StackState for one day-start setting. Everything is computed from doses.
struct StackEngine: Sendable {
    /// TAKE ALL, a widget row, the Control Center control, Siri and the nudge skip an item logged this
    /// recently, so a second tap seconds later never logs a 2x or 3x item's next dose on top of the first.
    /// A tap on the row in the app is deliberate and never held back.
    static let repeatGuard: TimeInterval = 60 * 60

    let state: StackState
    let clock: DayClock
    let orderedItems: [Item]

    private let doseDays: [UUID: [DayKey: [Dose]]]
    private let sortedDoseDays: [UUID: [DayKey]]
    private let latestDoseAt: [UUID: Date]
    private let activeFrom: [UUID: DayKey]
    private let archivedFrom: [UUID: DayKey]
    private let frequencyEras: [UUID: [DayEra]]
    private let pausedDays: [UUID: [DayRange]]

    init(state: StackState, clock: DayClock) {
        self.state = state
        self.clock = clock
        self.orderedItems = state.orderedItems

        var grouped: [UUID: [Dose]] = [:]
        for dose in state.doses { grouped[dose.itemId, default: []].append(dose) }

        var fixedClocks: [Int: DayClock] = [:]
        var byDay: [UUID: [DayKey: [Dose]]] = [:]
        var days: [UUID: [DayKey]] = [:]
        var latest: [UUID: Date] = [:]
        for (itemId, list) in grouped {
            let sorted = list.sorted(by: { $0.takenAt < $1.takenAt })
            var map: [DayKey: [Dose]] = [:]
            for dose in sorted {
                let day: DayKey
                if let offset = dose.utcOffset, offset != clock.utcOffset(at: dose.takenAt) {
                    // Logged in another time zone: it keeps the day that was being lived there.
                    let logged = fixedClocks[offset] ?? clock.fixed(utcOffset: offset)
                    fixedClocks[offset] = logged
                    day = logged.day(for: dose.takenAt)
                } else {
                    day = clock.day(for: dose.takenAt)
                }
                map[day, default: []].append(dose)
            }
            byDay[itemId] = map
            days[itemId] = map.keys.sorted()
            latest[itemId] = sorted.last?.takenAt
        }
        self.doseDays = byDay
        self.sortedDoseDays = days
        self.latestDoseAt = latest

        var from: [UUID: DayKey] = [:]
        var archived: [UUID: DayKey] = [:]
        var eras: [UUID: [DayEra]] = [:]
        var paused: [UUID: [DayRange]] = [:]
        for item in state.items {
            var start = clock.day(for: item.createdAt)
            if let first = days[item.id]?.first, first < start { start = first }
            from[item.id] = start
            if item.archived {
                archived[item.id] = item.archivedAt.map { clock.day(for: $0) } ?? start
            }
            if let past = item.pastFrequencies, !past.isEmpty {
                eras[item.id] = past.sorted(by: { $0.until < $1.until }).map {
                    DayEra(until: clock.day(for: $0.until), frequency: $0.frequency)
                }
            }
            if let pauses = item.pauses, !pauses.isEmpty {
                paused[item.id] = pauses.map { DayRange(from: clock.day(for: $0.from), until: clock.day(for: $0.until)) }
            }
        }
        self.activeFrom = from
        self.archivedFrom = archived
        self.frequencyEras = eras
        self.pausedDays = paused
    }

    // MARK: Days

    func today(now: Date) -> DayKey { clock.day(for: now) }

    /// True if the item was part of the stack on that day: added on or before it, and not archived then.
    func isActive(_ item: Item, on day: DayKey) -> Bool {
        guard let start = activeFrom[item.id], day >= start else { return false }
        if let end = archivedFrom[item.id], day >= end { return false }
        if let ranges = pausedDays[item.id], ranges.contains(where: { $0.contains(day) }) {
            // A dose logged for an archived day proves it was taken, as a backfill before the add does.
            return !doses(of: item.id, on: day).isEmpty
        }
        return true
    }

    /// True if the item sat archived on that day.
    func isPaused(_ item: Item, on day: DayKey) -> Bool {
        if let end = archivedFrom[item.id], day >= end { return true }
        return pausedDays[item.id]?.contains(where: { $0.contains(day) }) ?? false
    }

    /// The frequency in force on a day, so changing it in settings never rewrites earlier days.
    func frequency(of item: Item, on day: DayKey) -> Frequency {
        if let era = frequencyEras[item.id]?.first(where: { day < $0.until }) { return era.frequency }
        return item.frequency
    }

    func doses(of itemId: UUID, on day: DayKey) -> [Dose] {
        doseDays[itemId]?[day] ?? []
    }

    /// The last day with a dose strictly before `day`.
    func lastDoseDay(of itemId: UUID, before day: DayKey) -> DayKey? {
        guard let days = sortedDoseDays[itemId], !days.isEmpty else { return nil }
        var lo = 0
        var hi = days.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if days[mid] < day { lo = mid + 1 } else { hi = mid }
        }
        return lo > 0 ? days[lo - 1] : nil
    }

    func isDue(_ item: Item, on day: DayKey) -> Bool {
        switch frequency(of: item, on: day) {
        case .daily:
            return true
        case .weekdays(let set):
            return set.contains(day.weekday)
        case .alternateDays:
            guard let last = lastDoseDay(of: item.id, before: day) else { return true }
            return last.distance(to: day) >= 2
        }
    }

    func itemDay(_ item: Item, on day: DayKey) -> ItemDay {
        ItemDay(item: item, day: day, frequency: frequency(of: item, on: day), isDue: isDue(item, on: day),
                isActive: isActive(item, on: day), isPaused: isPaused(item, on: day),
                doses: doses(of: item.id, on: day))
    }

    // MARK: Quick logging

    /// When the item was last logged, on any day.
    func latestDose(of itemId: UUID) -> Date? {
        latestDoseAt[itemId]
    }

    /// True when TAKE ALL, a widget row, the control, Siri or the nudge may log this row now: a dose is
    /// still pending, and the item was not logged within the repeat guard.
    func canQuickLog(_ row: ItemDay, now: Date) -> Bool {
        guard row.isPending else { return false }
        guard let last = latestDoseAt[row.item.id] else { return true }
        return now.timeIntervalSince(last) >= Self.repeatGuard
    }

    /// The rows TAKE ALL logs right now.
    func quickLogRows(_ summary: DaySummary, now: Date) -> [ItemDay] {
        summary.items.filter { canQuickLog($0, now: now) }
    }

    /// When a pending row held back by the repeat guard can be quick logged again (nil when it is not held back).
    func quickLogResumes(_ row: ItemDay, now: Date) -> Date? {
        guard row.isPending, let last = latestDoseAt[row.item.id] else { return nil }
        let resumes = last.addingTimeInterval(Self.repeatGuard)
        return resumes > now ? resumes : nil
    }

    /// A day as history sees it: only items that were in the stack that day.
    func summary(for day: DayKey) -> DaySummary {
        DaySummary(day: day, items: orderedItems.filter { isActive($0, on: day) }.map { itemDay($0, on: day) })
    }

    /// TODAY: every item that is not archived, in the user's order.
    func todaySummary(now: Date) -> DaySummary {
        let day = clock.day(for: now)
        return DaySummary(day: day, items: orderedItems.filter { !$0.archived }.map { itemDay($0, on: day) })
    }

    /// The day sheet: items in the stack that day plus current items, so a missed day can be backfilled.
    func sheetSummary(for day: DayKey) -> DaySummary {
        let items = orderedItems.filter { isActive($0, on: day) || !$0.archived }
        return DaySummary(day: day, items: items.map { itemDay($0, on: day) })
    }

    /// The next day after `day` on which the item is due, assuming nothing else gets logged.
    func nextDueDay(for item: Item, after day: DayKey) -> DayKey? {
        switch item.frequency {
        case .daily:
            return day.adding(1)
        case .weekdays(let set):
            guard !set.isEmpty else { return nil }
            for offset in 1...7 {
                let candidate = day.adding(offset)
                if set.contains(candidate.weekday) { return candidate }
            }
            return nil
        case .alternateDays:
            guard let last = lastDoseDay(of: item.id, before: day.adding(1)) else { return day.adding(1) }
            let candidate = last.adding(2)
            return candidate > day ? candidate : day.adding(1)
        }
    }

    // MARK: Stats

    /// Consecutive complete days ending today (today counts once complete; days with nothing due are skipped).
    func streak(today: DayKey) -> Int {
        guard let earliest = activeFrom.values.min() else { return 0 }
        var count = summary(for: today).status == .complete ? 1 : 0
        var day = today.adding(-1)
        while day >= earliest {
            switch summary(for: day).status {
            case .complete:
                count += 1
            case .nothingDue, .future:
                break
            case .partial, .missed:
                return count
            }
            day = day.adding(-1)
        }
        return count
    }

    /// Due doses taken over the last `days` days. Today only counts what is already taken,
    /// so the number never drops just because the day is not over.
    func adherence(today: DayKey, days: Int = 30) -> Adherence {
        var taken = 0
        var due = 0
        for offset in 0..<max(days, 1) {
            let summary = summary(for: today.adding(-offset))
            taken += summary.takenDueDoses
            due += offset == 0 ? summary.takenDueDoses : summary.dueDoses
        }
        return Adherence(taken: taken, due: due)
    }

    /// Rows of 7 days (Monday first), oldest week first, the last row holding today.
    func history(today: DayKey, weeks: Int = 5) -> [[HistoryCell]] {
        let thisMonday = today.adding(-today.mondayIndex)
        let start = thisMonday.adding(-7 * (max(weeks, 1) - 1))
        return (0..<max(weeks, 1)).map { week in
            (0..<7).map { offset in
                let day = start.adding(week * 7 + offset)
                if day > today { return HistoryCell(day: day, status: .future, isToday: false) }
                return HistoryCell(day: day, status: summary(for: day).status, isToday: day == today)
            }
        }
    }
}

/// A frequency era resolved to days: days before `until` used `frequency`.
private struct DayEra: Sendable {
    let until: DayKey
    let frequency: Frequency
}

/// Archived days, from `from` up to, not including, `until`.
private struct DayRange: Sendable {
    let from: DayKey
    let until: DayKey

    func contains(_ day: DayKey) -> Bool { day >= from && day < until }
}

// MARK: - Mutations (pure; TakenStore runs them inside a coordinated write)

extension StackState {
    var orderedItems: [Item] {
        items.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            return lhs.createdAt < rhs.createdAt
        }
    }

    func item(_ id: UUID) -> Item? { items.first { $0.id == id } }

    @discardableResult
    mutating func addItems(_ drafts: [ItemDraft], now: Date) -> [Item] {
        var next = (items.map(\.sortIndex).max() ?? -1) + 1
        var added: [Item] = []
        for draft in drafts {
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let code = Catalog.sanitizeCode(draft.code ?? "")
            let item = Item(name: name, code: code.isEmpty ? Catalog.code(for: name) : code,
                            frequency: draft.frequency, createdAt: now, sortIndex: next)
            next += 1
            items.append(item)
            added.append(item)
        }
        return added
    }

    /// Replace name, code and frequency of an item. A new frequency applies from the day of `now` on;
    /// earlier days keep the frequency they had.
    mutating func updateItem(id: UUID, name: String, code: String, frequency: Frequency, now: Date) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { items[index].name = trimmed }
        let cleanCode = Catalog.sanitizeCode(code)
        items[index].code = cleanCode.isEmpty ? Catalog.code(for: items[index].name) : cleanCode
        if items[index].frequency != frequency {
            let era = FrequencyEra(until: now, frequency: items[index].frequency)
            items[index].pastFrequencies = (items[index].pastFrequencies ?? []) + [era]
            items[index].frequency = frequency
        }
    }

    mutating func setArchived(id: UUID, archived: Bool, now: Date) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].archived != archived else { return }
        if archived {
            items[index].archived = true
            items[index].archivedAt = now
            return
        }
        // The archived stretch stays out of history, so unarchiving never turns it into missed days.
        if let from = items[index].archivedAt {
            items[index].pauses = (items[index].pauses ?? []) + [Pause(from: from, until: max(from, now))]
        }
        items[index].archived = false
        items[index].archivedAt = nil
        items[index].sortIndex = (items.map(\.sortIndex).max() ?? 0) + 1
    }

    /// Delete an item and its log entries, so they never count in stats again.
    mutating func deleteItem(id: UUID) {
        items.removeAll { $0.id == id }
        doses.removeAll { $0.itemId == id }
    }

    /// Reorder the active (not archived) items the way SwiftUI's onMove describes it.
    mutating func moveActiveItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        let active = orderedItems.filter { !$0.archived }
        let moving = source.compactMap { $0 < active.count ? active[$0] : nil }
        var remaining: [Item] = []
        for (index, item) in active.enumerated() where !source.contains(index) { remaining.append(item) }
        let shift = source.filter { $0 < destination }.count
        let insertAt = min(max(destination - shift, 0), remaining.count)
        remaining.insert(contentsOf: moving, at: insertAt)
        let archivedItems = orderedItems.filter { $0.archived }
        for (position, item) in (remaining + archivedItems).enumerated() {
            if let index = items.firstIndex(where: { $0.id == item.id }) { items[index].sortIndex = position }
        }
    }

    /// Log one dose. `timeZone` is where it was taken, so the dose keeps its day after the phone changes zone.
    @discardableResult
    mutating func logDose(itemId: UUID, at date: Date, timeZone: TimeZone = .current) -> Dose? {
        guard items.contains(where: { $0.id == itemId }) else { return nil }
        let dose = Dose(itemId: itemId, takenAt: date, utcOffset: timeZone.secondsFromGMT(for: date))
        doses.append(dose)
        return dose
    }

    /// Siri and Shortcuts: log one dose, but never to an archived item, which the app no longer shows.
    @discardableResult
    mutating func logActiveDose(itemId: UUID, at date: Date, timeZone: TimeZone = .current) -> Dose? {
        guard let item = item(itemId), !item.archived else { return nil }
        return logDose(itemId: itemId, at: date, timeZone: timeZone)
    }

    /// Widget row tap: log only while a dose is still pending today and the item was not logged in the
    /// last hour, so a stale widget or a second tap never double logs.
    @discardableResult
    mutating func logNextDoseIfPending(itemId: UUID, now: Date, clock: DayClock) -> Dose? {
        guard let item = item(itemId), !item.archived else { return nil }
        let engine = StackEngine(state: self, clock: clock)
        let today = engine.itemDay(item, on: clock.day(for: now))
        guard engine.canQuickLog(today, now: now) else { return nil }
        return logDose(itemId: itemId, at: now, timeZone: clock.calendar.timeZone)
    }

    /// TAKE ALL: one dose for every item that still has a pending due dose today, skipping any item logged
    /// in the last hour, so a repeated tap never logs a 2x item's next dose. Nothing else is touched.
    @discardableResult
    mutating func takeAllPending(now: Date, clock: DayClock) -> [Dose] {
        let engine = StackEngine(state: self, clock: clock)
        var logged: [Dose] = []
        for row in engine.quickLogRows(engine.todaySummary(now: now), now: now) {
            if let dose = logDose(itemId: row.item.id, at: now, timeZone: clock.calendar.timeZone) { logged.append(dose) }
        }
        return logged
    }

    mutating func removeDoses(_ ids: Set<UUID>) {
        doses.removeAll { ids.contains($0.id) }
    }

    /// Remove the latest dose of an item on a given logical day.
    @discardableResult
    mutating func undoLastDose(itemId: UUID, on day: DayKey, clock: DayClock) -> Dose? {
        let candidates = doses.filter { $0.itemId == itemId && clock.day(of: $0) == day }
        guard let last = candidates.max(by: { $0.takenAt < $1.takenAt }) else { return nil }
        doses.removeAll { $0.id == last.id }
        return last
    }

    mutating func setDoseTime(doseId: UUID, to date: Date, timeZone: TimeZone = .current) {
        guard let index = doses.firstIndex(where: { $0.id == doseId }) else { return }
        doses[index].takenAt = date
        doses[index].utcOffset = timeZone.secondsFromGMT(for: date)
    }

    /// Undo: put a dose back exactly as it was, whether it was removed or had its time changed.
    mutating func restore(_ dose: Dose) {
        guard items.contains(where: { $0.id == dose.itemId }) else { return }
        if let index = doses.firstIndex(where: { $0.id == dose.id }) {
            doses[index] = dose
        } else {
            doses.append(dose)
        }
    }

    mutating func eraseAll() {
        self = StackState()
    }
}

// MARK: - CSV export

enum CSVExport {
    static let header = "date,time,item,code"

    /// One row per dose, oldest first, in local wall-clock time.
    static func make(state: StackState, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let items = Dictionary(state.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var lines = [header]
        for dose in state.doses.sorted(by: { $0.takenAt < $1.takenAt }) {
            guard let item = items[dose.itemId] else { continue }
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: dose.takenAt)
            let date = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
            lines.append([date, time, escape(item.name), escape(item.code)].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
