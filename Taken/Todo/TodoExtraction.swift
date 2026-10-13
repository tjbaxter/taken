import Foundation

// Turning a voice note's words into to-dos. The model does the language (Apple Foundation Models on the iPhone, iOS 26
// with Apple Intelligence); code owns the dates and the titles that get saved: every model answer goes through
// `TodoValidation`, which is unit tested with canned answers because the model itself cannot run in CI.

/// What the model needs to resolve "by 4" and "tomorrow": the moment, the time zone and the day-start hour.
struct TodoContext: Sendable {
    var now: Date
    var timeZone: TimeZone
    /// The hour the day rolls over (from the wake-up time): before it, "today" is still the day before.
    var dayStartHour: Int

    init(now: Date, timeZone: TimeZone = .current, dayStartHour: Int) {
        self.now = now
        self.timeZone = timeZone
        self.dayStartHour = min(max(dayStartHour, 0), 23)
    }

    var clock: DayClock { DayClock(dayStartHour: dayStartHour, timeZone: timeZone) }
}

/// One task as the model wrote it, before validation. The shape of the guided generation (`GeneratedTodo`), and
/// decodable from JSON for canned answers.
struct RawTodo: Codable, Hashable, Sendable {
    var title: String
    var dueISO8601: String?
    var hasTime: Bool

    init(title: String, dueISO8601: String? = nil, hasTime: Bool = false) {
        self.title = title
        self.dueISO8601 = dueISO8601
        self.hasTime = hasTime
    }

    private enum CodingKeys: String, CodingKey { case title, dueISO8601, due, hasTime }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        dueISO8601 = (try? c.decodeIfPresent(String.self, forKey: .dueISO8601)) ?? (try? c.decodeIfPresent(String.self, forKey: .due))
        hasTime = (try? c.decodeIfPresent(Bool.self, forKey: .hasTime)) ?? false
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(dueISO8601, forKey: .dueISO8601)
        try c.encode(hasTime, forKey: .hasTime)
    }
}

/// How a voice note became tasks.
enum TodoSorting: Equatable, Sendable {
    /// The on-device model sorted it.
    case model
    /// Saved as one task: automatic sorting needs Apple Intelligence (an older iPhone, or it is off).
    case needsAppleIntelligence
    /// Saved as one task: the model was there but could not sort this note.
    case couldNotSort
}

struct TodoExtraction: Sendable {
    var drafts: [TodoDraft]
    var sorting: TodoSorting
}

/// Turns a transcript into tasks.
protocol TaskExtractor: Sendable {
    /// Loads what the next `extract` needs while the person is still talking.
    func prepare() async
    func extract(transcript: String, context: TodoContext) async -> TodoExtraction
}

/// No model: the whole note is one task, editable. Never loses a word.
struct FallbackExtractor: TaskExtractor {
    var sorting: TodoSorting = .needsAppleIntelligence

    init(sorting: TodoSorting = .needsAppleIntelligence) {
        self.sorting = sorting
    }

    func prepare() async {}

    func extract(transcript: String, context: TodoContext) async -> TodoExtraction {
        TodoExtraction(drafts: TodoValidation.wholeNote(transcript), sorting: sorting)
    }
}

/// The extractor for this iPhone: the on-device model where it can run, otherwise the fallback.
enum TodoExtractors {
    @MainActor
    static func best() -> any TaskExtractor {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), FoundationModelsExtractor.isAvailable {
            return FoundationModelsExtractor()
        }
        #endif
        return FallbackExtractor()
    }

    /// Whether automatic sorting can run here (for the one-line note when it cannot).
    @MainActor
    static var modelAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return FoundationModelsExtractor.isAvailable }
        #endif
        return false
    }
}

// MARK: - Prompt

enum TodoPrompt {
    /// The session's instructions: the rules, short (the on-device model has a small context).
    static let instructions = """
        You turn a spoken voice note into a to-do list.
        - Make one task for each separate thing the speaker needs to do. Split lists like "X, Y and Z" into separate tasks.
        - Each title is short and starts with a verb, in the speaker's own words and language, at most 8 words. Drop filler such as "I need to", "um" or "also".
        - Never add a task that was not said. Leave out chat that is not a task.
        - dueISO8601: only when the speaker gave a day or a clock time for that task. Write local time like 2026-10-13T16:00:00, or only the date like 2026-10-14 when no clock time was said. "By 4" or "at 4 pm" means 16:00. Otherwise leave it empty.
        - A day or time said once for a list ("today by 4 I need to do X, Y and Z") applies to every task in that list.
        - hasTime is true only when a clock time was said.
        """

    private static let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    private static let months = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
                                 "October", "November", "December"]

    /// The request: now, the time zone, the day the speaker is living (the day-start hour), the next seven dates by
    /// name, and the words.
    static func prompt(transcript: String, context: TodoContext) -> String {
        let clock = context.clock
        let now = context.now
        let calendarToday = TodoText.calendarDay(now, clock: clock)
        let today = clock.day(for: now)
        let time = TodoText.clockTime(now, clock: clock)
        var lines = ["Now: \(long(calendarToday)), \(time), time zone \(context.timeZone.identifier)."]
        if today != calendarToday {
            lines.append("The speaker's day starts at \(String(format: "%02d:00", context.dayStartHour)), so their today is still \(long(today)).")
        }
        lines.append("Today is \(long(today)) (\(iso(today))). Tomorrow is \(long(today.adding(1))) (\(iso(today.adding(1)))).")
        let week = (2...7).map { offset -> String in
            let day = today.adding(offset)
            return "\(weekdays[day.mondayIndex]) \(iso(day))"
        }
        lines.append("Next days: \(week.joined(separator: ", ")).")
        lines.append("Voice note: \"\(transcript.trimmingCharacters(in: .whitespacesAndNewlines))\"")
        return lines.joined(separator: "\n")
    }

    /// "Tuesday 13 October 2026"
    static func long(_ day: DayKey) -> String {
        let (year, month, dayOfMonth) = day.ymd
        return "\(weekdays[day.mondayIndex]) \(dayOfMonth) \(months[max(0, min(11, month - 1))]) \(year)"
    }

    /// "2026-10-13"
    static func iso(_ day: DayKey) -> String {
        let (year, month, dayOfMonth) = day.ymd
        return String(format: "%04d-%02d-%02d", year, month, dayOfMonth)
    }
}

// MARK: - Validation (code owns what is saved)

enum TodoValidation {
    /// At most this many tasks from one note.
    static let maxTasks = 20
    /// A transcript saved as one task keeps at most this many characters.
    static let maxNoteLength = 400
    /// Due dates further ahead than this are a mistake (a wrong year), so they are dropped.
    static let maxAhead: TimeInterval = 366 * 24 * 60 * 60
    /// A due time may be in the past by up to a day (said late: "I had to call her by 4"), never more.
    static let maxBehind: TimeInterval = 24 * 60 * 60

    /// The model's tasks as they are saved: titles cleaned, due dates parsed and checked, duplicates and empties
    /// dropped, at most `maxTasks`. With nothing left from a note that had words, the note is one task.
    static func validate(_ raw: [RawTodo], transcript: String, context: TodoContext) -> [TodoDraft] {
        var drafts: [TodoDraft] = []
        var seen = Set<String>()
        for item in raw {
            guard let title = TodoText.clean(item.title) else { continue }
            let due = item.dueISO8601.flatMap { parseDue($0, hasTime: item.hasTime, context: context) }
            let key = title.lowercased() + "|" + (due.map { String($0.date.timeIntervalSince1970) } ?? "")
            guard seen.insert(key).inserted else { continue }
            drafts.append(TodoDraft(title: title, dueDate: due?.date, hasTime: due?.hasTime ?? false))
            if drafts.count == maxTasks { break }
        }
        return drafts.isEmpty ? wholeNote(transcript) : drafts
    }

    /// The whole note as one task (no model, or nothing the model found). Empty words make no task.
    static func wholeNote(_ transcript: String) -> [TodoDraft] {
        guard let title = TodoText.cleanKeepingLength(transcript, limit: maxNoteLength) else { return [] }
        return [TodoDraft(title: title)]
    }

    /// A due date the model wrote, as a moment: "2026-10-13T16:00:00" (local), with seconds or not, with a "Z" or
    /// "+01:00" offset or not, or a date alone ("2026-10-14", kept at noon that day). Nil for anything else, for a
    /// day or time that does not exist, more than a day in the past, or more than a year ahead.
    static func parseDue(_ text: String, hasTime: Bool, context: TodoContext) -> (date: Date, hasTime: Bool)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let parts = DueParts(trimmed) else { return nil }
        guard (1...12).contains(parts.month), (1...31).contains(parts.day), (2000...2200).contains(parts.year) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = parts.offsetSeconds.flatMap { TimeZone(secondsFromGMT: $0) } ?? context.timeZone
        // A time is kept only when the model says one was said and wrote one; midnight with no time said is a date.
        let timed = hasTime && parts.hour != nil
        let hour = timed ? (parts.hour ?? 12) : 12
        let minute = timed ? (parts.minute ?? 0) : 0
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        let components = DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: hour, minute: minute)
        guard let date = calendar.date(from: components) else { return nil }
        // The calendar rolls 31 February into March: a day that does not exist is not a due date.
        let check = calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == parts.year, check.month == parts.month, check.day == parts.day else { return nil }
        let now = context.now
        if timed {
            guard date >= now.addingTimeInterval(-maxBehind), date <= now.addingTimeInterval(maxAhead) else { return nil }
            return (date, true)
        }
        // A date alone: yesterday at the earliest (said late at night), a year ahead at the latest. Kept at noon in the
        // speaker's own zone.
        var local = Calendar(identifier: .gregorian)
        local.timeZone = context.timeZone
        guard let noon = local.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 12))
        else { return nil }
        let today = TodoText.calendarDay(now, clock: context.clock)
        let day = DayKey(year: parts.year, month: parts.month, day: parts.day)
        guard today.distance(to: day) >= -1, noon <= now.addingTimeInterval(maxAhead) else { return nil }
        return (noon, false)
    }

    /// Canned or stored answers in the guided generation's shape: `{"tasks": [{"title": ..., "dueISO8601": ...,
    /// "hasTime": ...}]}` or a bare array of tasks. Nil when it is not that.
    static func decode(json: String) -> [RawTodo]? {
        let data = Data(json.utf8)
        struct List: Decodable { var tasks: [RawTodo]? }
        if let list = try? JSONDecoder().decode(List.self, from: data), let tasks = list.tasks { return tasks }
        return try? JSONDecoder().decode([RawTodo].self, from: data)
    }

    /// The pieces of "YYYY-MM-DD[THH:MM[:SS[.fff]]][Z|±HH:MM]".
    private struct DueParts {
        var year: Int
        var month: Int
        var day: Int
        var hour: Int?
        var minute: Int?
        var offsetSeconds: Int?

        init?(_ text: String) {
            let pattern = #"^(\d{4})-(\d{1,2})-(\d{1,2})(?:[T ](\d{1,2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?)?\s*(Z|[+-]\d{2}:?\d{2})?$"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
            func group(_ index: Int) -> String? {
                let range = match.range(at: index)
                guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
                return String(text[swiftRange])
            }
            guard let year = group(1).flatMap(Int.init), let month = group(2).flatMap(Int.init),
                  let day = group(3).flatMap(Int.init) else { return nil }
            self.year = year
            self.month = month
            self.day = day
            hour = group(4).flatMap(Int.init)
            minute = group(5).flatMap(Int.init)
            if let zone = group(7) {
                if zone == "Z" {
                    offsetSeconds = 0
                } else {
                    let sign = zone.hasPrefix("-") ? -1 : 1
                    let digits = zone.dropFirst().replacingOccurrences(of: ":", with: "")
                    guard digits.count == 4, let hh = Int(digits.prefix(2)), let mm = Int(digits.suffix(2)),
                          hh <= 14, mm < 60 else { return nil }
                    offsetSeconds = sign * (hh * 3600 + mm * 60)
                }
            }
        }
    }
}

extension TodoText {
    /// Like `clean`, with a longer limit: a whole voice note saved as one task.
    static func cleanKeepingLength(_ raw: String, limit: Int) -> String? {
        var text = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:").union(.whitespaces))
        guard !text.isEmpty else { return nil }
        if text.count > limit { text = String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) }
        guard let first = text.first else { return nil }
        return first.uppercased() + text.dropFirst()
    }
}
