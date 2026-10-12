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
    let isDue: Bool
    /// False when the item was added after this day (shown only so it can be backfilled).
    let isActive: Bool
    let doses: [Dose]

    var id: UUID { item.id }
    var dosesPerDay: Int { item.frequency.dosesPerDay }
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
    let state: StackState
    let clock: DayClock
    let orderedItems: [Item]

    private let doseDays: [UUID: [DayKey: [Dose]]]
    private let sortedDoseDays: [UUID: [DayKey]]
    private let activeFrom: [UUID: DayKey]
    private let archivedFrom: [UUID: DayKey]

    init(state: StackState, clock: DayClock) {
        self.state = state
        self.clock = clock
        self.orderedItems = state.orderedItems

        var grouped: [UUID: [Dose]] = [:]
        for dose in state.doses { grouped[dose.itemId, default: []].append(dose) }

        var byDay: [UUID: [DayKey: [Dose]]] = [:]
        var days: [UUID: [DayKey]] = [:]
        for (itemId, list) in grouped {
            var map: [DayKey: [Dose]] = [:]
            for dose in list.sorted(by: { $0.takenAt < $1.takenAt }) {
                map[clock.day(for: dose.takenAt), default: []].append(dose)
            }
            byDay[itemId] = map
            days[itemId] = map.keys.sorted()
        }
        self.doseDays = byDay
        self.sortedDoseDays = days

        var from: [UUID: DayKey] = [:]
        var archived: [UUID: DayKey] = [:]
        for item in state.items {
            var start = clock.day(for: item.createdAt)
            if let first = days[item.id]?.first, first < start { start = first }
            from[item.id] = start
            if item.archived {
                archived[item.id] = item.archivedAt.map { clock.day(for: $0) } ?? start
            }
        }
        self.activeFrom = from
        self.archivedFrom = archived
    }

    // MARK: Days

    func today(now: Date) -> DayKey { clock.day(for: now) }

    /// True if the item was part of the stack on that day (added on or before it, not archived yet).
    func isActive(_ item: Item, on day: DayKey) -> Bool {
        guard let start = activeFrom[item.id], day >= start else { return false }
        if let end = archivedFrom[item.id], day >= end { return false }
        return true
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
        switch item.frequency {
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
        ItemDay(item: item, day: day, isDue: isDue(item, on: day), isActive: isActive(item, on: day),
                doses: doses(of: item.id, on: day))
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

    /// Replace name, code and frequency of an item.
    mutating func updateItem(id: UUID, name: String, code: String, frequency: Frequency) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { items[index].name = trimmed }
        let cleanCode = Catalog.sanitizeCode(code)
        items[index].code = cleanCode.isEmpty ? Catalog.code(for: items[index].name) : cleanCode
        items[index].frequency = frequency
    }

    mutating func setArchived(id: UUID, archived: Bool, now: Date) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].archived != archived else { return }
        items[index].archived = archived
        items[index].archivedAt = archived ? now : nil
        if !archived { items[index].sortIndex = (items.map(\.sortIndex).max() ?? 0) + 1 }
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

    @discardableResult
    mutating func logDose(itemId: UUID, at date: Date) -> Dose? {
        guard items.contains(where: { $0.id == itemId }) else { return nil }
        let dose = Dose(itemId: itemId, takenAt: date)
        doses.append(dose)
        return dose
    }

    /// Widget tap: log only while something is still pending today, so a stale widget never double logs.
    @discardableResult
    mutating func logNextDoseIfPending(itemId: UUID, now: Date, clock: DayClock) -> Dose? {
        guard let item = item(itemId), !item.archived else { return nil }
        let engine = StackEngine(state: self, clock: clock)
        let today = engine.itemDay(item, on: clock.day(for: now))
        guard today.isPending else { return nil }
        return logDose(itemId: itemId, at: now)
    }

    /// TAKE ALL: one dose for every item that still has a pending due dose today. Nothing else is touched.
    @discardableResult
    mutating func takeAllPending(now: Date, clock: DayClock) -> [Dose] {
        let engine = StackEngine(state: self, clock: clock)
        var logged: [Dose] = []
        for row in engine.todaySummary(now: now).items where row.isPending {
            if let dose = logDose(itemId: row.item.id, at: now) { logged.append(dose) }
        }
        return logged
    }

    mutating func removeDoses(_ ids: Set<UUID>) {
        doses.removeAll { ids.contains($0.id) }
    }

    /// Remove the latest dose of an item on a given logical day.
    @discardableResult
    mutating func undoLastDose(itemId: UUID, on day: DayKey, clock: DayClock) -> Dose? {
        let candidates = doses.filter { $0.itemId == itemId && clock.day(for: $0.takenAt) == day }
        guard let last = candidates.max(by: { $0.takenAt < $1.takenAt }) else { return nil }
        doses.removeAll { $0.id == last.id }
        return last
    }

    mutating func setDoseTime(doseId: UUID, to date: Date) {
        guard let index = doses.firstIndex(where: { $0.id == doseId }) else { return }
        doses[index].takenAt = date
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
