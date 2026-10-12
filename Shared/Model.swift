import Foundation

/// How often an item is due.
enum Frequency: Hashable, Sendable {
    /// Every day, `times` doses (1...3).
    case daily(times: Int)
    /// Due if never taken, or if the last dose was two or more days ago.
    case alternateDays
    /// Due on the given weekdays (Calendar numbering: 1 = Sunday ... 7 = Saturday).
    case weekdays(Set<Int>)

    static let onceDaily = Frequency.daily(times: 1)

    /// Doses due on a due day.
    var dosesPerDay: Int {
        if case .daily(let times) = self { return min(max(times, 1), 3) }
        return 1
    }
}

extension Frequency: Codable {
    private enum CodingKeys: String, CodingKey { case kind, times, days }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "daily"
        switch kind {
        case "alt":
            self = .alternateDays
        case "weekdays":
            let days = try container.decodeIfPresent([Int].self, forKey: .days) ?? []
            self = .weekdays(Set(days.filter { (1...7).contains($0) }))
        default:
            let times = try container.decodeIfPresent(Int.self, forKey: .times) ?? 1
            self = .daily(times: min(max(times, 1), 3))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .daily(let times):
            try container.encode("daily", forKey: .kind)
            try container.encode(times, forKey: .times)
        case .alternateDays:
            try container.encode("alt", forKey: .kind)
        case .weekdays(let days):
            try container.encode("weekdays", forKey: .kind)
            try container.encode(days.sorted(), forKey: .days)
        }
    }
}

/// One thing in the stack.
struct Item: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var code: String
    var frequency: Frequency
    var createdAt: Date
    var archived: Bool
    var archivedAt: Date?
    var sortIndex: Int

    init(id: UUID = UUID(), name: String, code: String, frequency: Frequency, createdAt: Date,
         archived: Bool = false, archivedAt: Date? = nil, sortIndex: Int) {
        self.id = id
        self.name = name
        self.code = code
        self.frequency = frequency
        self.createdAt = createdAt
        self.archived = archived
        self.archivedAt = archivedAt
        self.sortIndex = sortIndex
    }
}

/// One logged dose. The only source of truth for "taken".
struct Dose: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var itemId: UUID
    var takenAt: Date

    init(id: UUID = UUID(), itemId: UUID, takenAt: Date) {
        self.id = id
        self.itemId = itemId
        self.takenAt = takenAt
    }
}

struct StackSettings: Codable, Hashable, Sendable {
    /// Hour (0...23) the day rolls over. A dose before it counts for the previous day.
    var dayStartHour: Int = 4
    var reminderEnabled: Bool = false
    /// Minutes after midnight for the nudge. Default 21:00.
    var reminderMinutes: Int = 21 * 60
    var hapticsEnabled: Bool = true

    init(dayStartHour: Int = 4, reminderEnabled: Bool = false, reminderMinutes: Int = 21 * 60, hapticsEnabled: Bool = true) {
        self.dayStartHour = dayStartHour
        self.reminderEnabled = reminderEnabled
        self.reminderMinutes = reminderMinutes
        self.hapticsEnabled = hapticsEnabled
    }

    private enum CodingKeys: String, CodingKey { case dayStartHour, reminderEnabled, reminderMinutes, hapticsEnabled }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dayStartHour = min(max(try c.decodeIfPresent(Int.self, forKey: .dayStartHour) ?? 4, 0), 23)
        reminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? false
        reminderMinutes = min(max(try c.decodeIfPresent(Int.self, forKey: .reminderMinutes) ?? 21 * 60, 0), 24 * 60 - 1)
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
    }
}

/// Everything Taken knows. Stored as one JSON file in the App Group container.
struct StackState: Codable, Hashable, Sendable {
    var schemaVersion: Int = 1
    var items: [Item] = []
    var doses: [Dose] = []
    var settings = StackSettings()

    init(items: [Item] = [], doses: [Dose] = [], settings: StackSettings = StackSettings()) {
        self.items = items
        self.doses = doses
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, items, doses, settings }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
        doses = try c.decodeIfPresent([Dose].self, forKey: .doses) ?? []
        settings = try c.decodeIfPresent(StackSettings.self, forKey: .settings) ?? StackSettings()
    }
}

/// What the Add sheet hands over.
struct ItemDraft: Hashable, Sendable {
    var name: String
    var code: String?
    var frequency: Frequency

    init(name: String, code: String? = nil, frequency: Frequency = .onceDaily) {
        self.name = name
        self.code = code
        self.frequency = frequency
    }
}
