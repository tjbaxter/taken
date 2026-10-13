import Foundation

// Voice to-dos (REDESIGN.md, SPEC 3.10). The data and the pure rules: what is open, what was done today, in what
// order, and how a task reads. Compiled into the app and the widget extension; the speech and the model that turn a
// voice note into these live in Taken/Todo.

/// When a to-do is due.
enum TodoDue: Hashable, Sendable {
    /// A clock time was said ("by 4 pm"): the moment it is due.
    case time(Date)
    /// Only a day was said ("on Friday"): that calendar date, which stays the same date wherever the iPhone goes.
    case day(DayKey)
}

/// One thing to do, from a voice note.
struct TodoTask: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    /// Short and imperative: "Call the dentist".
    var title: String
    var due: TodoDue?
    var createdAt: Date
    var completedAt: Date?
    /// The voice note it came from. Tasks from one note share it.
    var noteId: UUID
    /// Where it came in its note, so a ramble keeps the order it was said in.
    var order: Int

    init(id: UUID = UUID(), title: String, due: TodoDue? = nil, createdAt: Date, completedAt: Date? = nil,
         noteId: UUID, order: Int = 0) {
        self.id = id
        self.title = title
        self.due = due
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.noteId = noteId
        self.order = order
    }

    var isDone: Bool { completedAt != nil }

    /// A clock time was said.
    var hasTime: Bool { dueTime != nil }

    /// The moment it is due, when a clock time was said.
    var dueTime: Date? {
        if case .time(let date) = due { return date }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, dueAt, dueDay, createdAt, completedAt, noteId, order
        /// Builds before 1.1 shipped stored every due date as a moment, a day alone at noon.
        case dueDate, hasTime
    }

    /// Every field but the title has a default, so a file from an earlier or later version always loads.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        if let day = (try? c.decodeIfPresent(String.self, forKey: .dueDay)).flatMap({ DayKey(iso: $0) }) {
            due = .day(day)
        } else if let at = try? c.decodeIfPresent(Date.self, forKey: .dueAt) {
            due = .time(at)
        } else if let legacy = try? c.decodeIfPresent(Date.self, forKey: .dueDate) {
            let timed = (try? c.decodeIfPresent(Bool.self, forKey: .hasTime)) ?? false
            due = timed ? .time(legacy) : .day(DayKey(calendarDateOf: legacy, in: .current))
        } else {
            due = nil
        }
        createdAt = (try? c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? .distantPast
        completedAt = try? c.decodeIfPresent(Date.self, forKey: .completedAt)
        noteId = (try? c.decodeIfPresent(UUID.self, forKey: .noteId)) ?? id
        order = (try? c.decodeIfPresent(Int.self, forKey: .order)) ?? 0
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        switch due {
        case .time(let date): try c.encode(date, forKey: .dueAt)
        case .day(let day): try c.encode(day.iso, forKey: .dueDay)
        case nil: break
        }
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(completedAt, forKey: .completedAt)
        try c.encode(noteId, forKey: .noteId)
        try c.encode(order, forKey: .order)
    }
}

/// A task as a voice note produced it, before it is saved.
struct TodoDraft: Hashable, Sendable {
    var title: String
    var due: TodoDue?

    init(title: String, due: TodoDue? = nil) {
        self.title = title
        self.due = due
    }
}

/// Everything the To-do tab keeps: one JSON file next to the log in the App Group (`todos.json`).
struct TodoState: Codable, Hashable, Sendable {
    var schemaVersion: Int = 1
    var tasks: [TodoTask] = []
    /// The first voice note ever saved. That one needs no Taken Pro; after it the mic does. Erasing keeps it.
    var firstNoteAt: Date?

    /// Done tasks are kept this long (for "Done today" and an undo), then dropped.
    static let doneRetention: TimeInterval = 30 * 24 * 60 * 60

    init(tasks: [TodoTask] = [], firstNoteAt: Date? = nil) {
        self.tasks = tasks
        self.firstNoteAt = firstNoteAt
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, tasks, firstNoteAt }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = (try? c.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? 1
        // One unreadable task never costs the others.
        let lossy = (try? c.decodeIfPresent([LossyTask].self, forKey: .tasks)) ?? []
        tasks = lossy.compactMap(\.task).filter { !$0.title.isEmpty }
        firstNoteAt = try? c.decodeIfPresent(Date.self, forKey: .firstNoteAt)
    }

    private struct LossyTask: Decodable {
        let task: TodoTask?

        init(from decoder: any Decoder) throws {
            task = try? TodoTask(from: decoder)
        }
    }

    // MARK: Reading

    func task(_ id: UUID) -> TodoTask? { tasks.first { $0.id == id } }

    /// Every open task, whenever it was said: yesterday's stay until they are done. Due first, soonest first; then
    /// the newest note first, each note in the order it was said.
    func openTasks(clock: DayClock) -> [TodoTask] {
        TodoOrdering.sorted(tasks.filter { !$0.isDone }, clock: clock)
    }

    /// Tasks done on the day being lived (the day-start hour decides it, as it does for doses), newest first.
    func doneTasks(on day: DayKey, clock: DayClock) -> [TodoTask] {
        tasks.filter { task in
            guard let done = task.completedAt else { return false }
            return clock.day(for: done) == day
        }
        .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    // MARK: Changing

    /// Adds a note's tasks in the order they were said. Returns what was added.
    @discardableResult
    mutating func add(_ drafts: [TodoDraft], noteId: UUID = UUID(), at now: Date) -> [TodoTask] {
        let added = drafts.enumerated().map { index, draft in
            TodoTask(title: draft.title, due: draft.due, createdAt: now, noteId: noteId, order: index)
        }
        tasks.append(contentsOf: added)
        if !added.isEmpty && firstNoteAt == nil { firstNoteAt = now }
        prune(now: now)
        return added
    }

    /// A voice note is saved whole the moment its words are known (so nothing said is lost if iOS ends Taken while the
    /// model is still sorting), then replaced here by the tasks the model made of it. Returns the note's tasks as they
    /// now stand: the sorted ones; the whole note when the drafts are just that; nothing when the note was deleted or
    /// erased meanwhile; and the note as it is when someone already changed it.
    @discardableResult
    mutating func replaceNote(_ placeholder: UUID, with drafts: [TodoDraft], at now: Date) -> [TodoTask] {
        guard let index = tasks.firstIndex(where: { $0.id == placeholder }) else { return [] }
        let whole = tasks[index]
        guard !whole.isDone, whole.due == nil else { return [whole] }
        if drafts.count == 1, drafts[0].title == whole.title, drafts[0].due == nil { return [whole] }
        guard !drafts.isEmpty else { return [whole] }
        tasks.remove(at: index)
        let added = drafts.enumerated().map { offset, draft in
            TodoTask(title: draft.title, due: draft.due, createdAt: whole.createdAt, noteId: whole.noteId, order: offset)
        }
        tasks.append(contentsOf: added)
        prune(now: now)
        return added
    }

    /// Marks a task done. Done twice keeps the first time.
    mutating func complete(_ id: UUID, at now: Date) {
        guard let index = tasks.firstIndex(where: { $0.id == id }), tasks[index].completedAt == nil else { return }
        tasks[index].completedAt = now
        prune(now: now)
    }

    /// Back to open (a tap on a done task's check).
    mutating func reopen(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].completedAt = nil
    }

    /// Edits the words or when it is due. An empty title keeps the old one.
    mutating func update(_ id: UUID, title: String, due: TodoDue?) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        if let trimmed = TodoText.clean(title) { tasks[index].title = trimmed }
        tasks[index].due = due
    }

    @discardableResult
    mutating func delete(_ id: UUID) -> TodoTask? {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return nil }
        return tasks.remove(at: index)
    }

    /// Puts a deleted task back where it was (UNDO).
    mutating func restore(_ task: TodoTask) {
        guard !tasks.contains(where: { $0.id == task.id }) else { return }
        tasks.append(task)
    }

    /// Erase all data: the tasks go, the first free note stays used.
    mutating func eraseAll() {
        tasks = []
    }

    /// Drops tasks done more than `doneRetention` ago.
    mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.doneRetention)
        tasks.removeAll { task in
            guard let done = task.completedAt else { return false }
            return done < cutoff
        }
    }
}

/// Voice to-dos and Taken Pro (REDESIGN.md): the first voice note needs no Pro, so people feel it; after it the mic
/// needs Pro. The same gate as logging (`ProGate`), with "has logged" meaning "has saved a voice note".
enum TodoGate {
    static func access(firstNoteAt: Date?, status: ProStatus?, settled: Bool, legacyLog: Bool, now: Date) -> ProAccess {
        ProGate.access(status: status, settled: settled, legacyLog: legacyLog, hasLogged: firstNoteAt != nil, now: now)
    }
}

/// The order of the open list.
enum TodoOrdering {
    /// Due first, soonest first (a task with a clock time before a day-only one on the same day, which counts as due by
    /// the end of that day). Then tasks with no due date: the newest note first, each in the order it was said.
    static func sorted(_ tasks: [TodoTask], clock: DayClock) -> [TodoTask] {
        tasks.sorted { a, b in
            switch (sortDate(a, clock: clock), sortDate(b, clock: clock)) {
            case let (x?, y?):
                if x != y { return x < y }
                return tieBreak(a, b)
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                return tieBreak(a, b)
            }
        }
    }

    /// The moment a task is due by: its time, or the end of its day where the iPhone is now.
    static func sortDate(_ task: TodoTask, clock: DayClock) -> Date? {
        switch task.due {
        case .time(let date):
            return date
        case .day(let day):
            let (year, month, dayOfMonth) = day.adding(1).ymd
            let next = clock.calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))
            return next.map { $0.addingTimeInterval(-1) }
        case nil:
            return nil
        }
    }

    private static func tieBreak(_ a: TodoTask, _ b: TodoTask) -> Bool {
        if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
        if a.noteId != b.noteId { return a.noteId.uuidString < b.noteId.uuidString }
        if a.order != b.order { return a.order < b.order }
        return a.id.uuidString < b.id.uuidString
    }
}

/// How a task reads: due labels, spoken labels, cleaned titles.
enum TodoText {
    private static let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static let maxTitleLength = 120

    /// "16:00" today, "Today", "Tomorrow 09:00", "Thu", "14 Oct 16:00", "Yesterday". Days are the days being lived
    /// (the day-start hour), the same as everywhere else in Taken.
    static func dueLabel(_ task: TodoTask, now: Date, clock: DayClock) -> String? {
        guard let parts = dueParts(task, now: now, clock: clock) else { return nil }
        return [parts.day, parts.time].compactMap { $0 }.joined(separator: " ")
    }

    /// The day word and the clock time of a due label, apart, so the time can be set in mono: ("Tomorrow", "09:00").
    static func dueParts(_ task: TodoTask, now: Date, clock: DayClock) -> (day: String?, time: String?)? {
        guard let due = task.due else { return nil }
        let today = clock.day(for: now)
        let day: DayKey
        let time: String?
        switch due {
        case .time(let date):
            day = clock.day(for: date)
            time = clockTime(date, clock: clock)
        case .day(let date):
            day = date
            time = nil
        }
        let gap = today.distance(to: day)
        let dayWord: String?
        switch gap {
        case 0: dayWord = time == nil ? "Today" : nil
        case 1: dayWord = "Tomorrow"
        case -1: dayWord = "Yesterday"
        case 2..<7: dayWord = weekdays[day.mondayIndex]
        default:
            let (_, month, dayOfMonth) = day.ymd
            dayWord = "\(dayOfMonth) \(months[max(0, min(11, month - 1))])"
        }
        return (dayWord, time)
    }

    /// Past its time (or its day) and still open.
    static func isOverdue(_ task: TodoTask, now: Date, clock: DayClock) -> Bool {
        guard !task.isDone, let due = task.due else { return false }
        switch due {
        case .time(let date): return date < now
        case .day(let day): return day < clock.day(for: now)
        }
    }

    /// "due tomorrow at 9:00 AM", for VoiceOver.
    static func spokenDue(_ task: TodoTask, now: Date, clock: DayClock) -> String? {
        guard let label = dueLabel(task, now: now, clock: clock) else { return nil }
        if let due = task.dueTime {
            let spokenTime = due.formatted(date: .omitted, time: .shortened)
            let words = label.split(separator: " ").dropLast().joined(separator: " ")
            return words.isEmpty ? "due at \(spokenTime)" : "due \(words.lowercased()) at \(spokenTime)"
        }
        return "due \(label.lowercased())"
    }

    /// "07:42"
    static func clockTime(_ date: Date, clock: DayClock) -> String {
        let hm = clock.hourMinute(of: date)
        return String(format: "%02d:%02d", hm.hour, hm.minute)
    }

    /// The calendar date of a moment in the clock's zone (midnight to midnight), as a DayKey.
    static func calendarDay(_ date: Date, clock: DayClock) -> DayKey {
        DayKey(calendarDateOf: date, in: clock.calendar.timeZone)
    }

    /// A title as the list shows it: trimmed, one space between words, no list marker or end punctuation, a capital
    /// first letter, at most `maxTitleLength` characters. Nil when nothing is left.
    static func clean(_ raw: String) -> String? {
        var text = raw.replacingOccurrences(of: "\n", with: " ")
        text = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        // List markers the model or a typed note may add: "- ", "* ", "1. ", "2) ".
        while let first = text.first, "-*\u{2022}".contains(first) {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        if let marker = text.range(of: #"^\d{1,2}[.)]\s+"#, options: .regularExpression) {
            text.removeSubrange(marker)
        }
        let wrappers = CharacterSet(charactersIn: "\"'\u{201C}\u{201D}\u{2018}\u{2019}")
        text = text.trimmingCharacters(in: wrappers.union(.whitespaces))
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:").union(.whitespaces))
        guard !text.isEmpty else { return nil }
        if text.count > maxTitleLength {
            let cut = text.prefix(maxTitleLength)
            if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > maxTitleLength / 2 {
                text = String(cut[..<space])
            } else {
                text = String(cut)
            }
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:").union(.whitespaces))
        }
        guard let first = text.first else { return nil }
        return first.uppercased() + text.dropFirst()
    }
}
