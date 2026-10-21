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

/// A frequency an item had before it was changed. Days before the day of `until` keep `frequency`,
/// so a settings change never rewrites the past.
struct FrequencyEra: Codable, Hashable, Sendable {
    /// The moment the item moved off `frequency`.
    var until: Date
    var frequency: Frequency

    init(until: Date, frequency: Frequency) {
        self.until = until
        self.frequency = frequency
    }
}

/// A stretch an item spent archived: from the day of `from` up to, not including, the day of `until`.
struct Pause: Codable, Hashable, Sendable {
    var from: Date
    var until: Date

    init(from: Date, until: Date) {
        self.from = from
        self.until = until
    }
}

/// One thing in the stack.
struct Item: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var code: String
    /// The frequency from the last change on. Earlier days use `pastFrequencies`.
    var frequency: Frequency
    var createdAt: Date
    var archived: Bool
    var archivedAt: Date?
    var sortIndex: Int
    /// Frequencies before each change, oldest first. Nil in files written before it existed.
    var pastFrequencies: [FrequencyEra]?
    /// Archived stretches that have ended, oldest first. Nil in files written before it existed.
    var pauses: [Pause]?

    init(id: UUID = UUID(), name: String, code: String, frequency: Frequency, createdAt: Date,
         archived: Bool = false, archivedAt: Date? = nil, sortIndex: Int,
         pastFrequencies: [FrequencyEra]? = nil, pauses: [Pause]? = nil) {
        self.id = id
        self.name = name
        self.code = code
        self.frequency = frequency
        self.createdAt = createdAt
        self.archived = archived
        self.archivedAt = archivedAt
        self.sortIndex = sortIndex
        self.pastFrequencies = pastFrequencies
        self.pauses = pauses
    }
}

/// One logged dose. The only source of truth for "taken".
struct Dose: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var itemId: UUID
    var takenAt: Date
    /// Seconds east of UTC where the dose was logged, so it keeps the day it was taken on after the
    /// phone changes time zone. Nil in files written before it existed: those read in the current zone.
    var utcOffset: Int?

    init(id: UUID = UUID(), itemId: UUID, takenAt: Date, utcOffset: Int? = nil) {
        self.id = id
        self.itemId = itemId
        self.takenAt = takenAt
        self.utcOffset = utcOffset
    }
}

struct StackSettings: Codable, Hashable, Sendable {
    /// When the person wakes up, in minutes after midnight (Profile > Wake-up time). Default 07:00. The day rolls over
    /// from it (`dayStartHour`), so nobody ever sets or sees the rollover itself.
    var wakeMinutes: Int = StackSettings.defaultWakeMinutes
    var reminderEnabled: Bool = false
    /// The nudge time the person chose, in minutes after midnight. Nil until they choose one: the nudge then comes 13
    /// hours after the wake-up time (`reminderMinutes`).
    var chosenReminderMinutes: Int?
    var hapticsEnabled: Bool = true
    /// The look (Profile > Look). The app, the widgets, the Control Center control and the app icon follow it, so it
    /// lives here in the App Group store with everything else. Files from before 1.1 have none: Signal.
    var theme: ThemeID = .signal
    /// Today's one-time rows (SPEC 3.1, the 1.1 retention build), each answered once and never shown again. Kept in this
    /// file with the rest of the settings, and kept by Erase all data like the look, so a row once answered never comes
    /// back. The evening nudge offer was answered (Turn on or Not now).
    var nudgeOfferDone: Bool = false
    /// The day (DayKey ordinal) the widget invite first showed, under the first All taken: it shows on that day only.
    var widgetInviteDay: Int?
    /// The widget invite was tapped or closed.
    var widgetInviteDone: Bool = false

    static let defaultWakeMinutes = 7 * 60
    /// The day rolls over this long before the wake-up time, so a late night stays on the day being lived.
    static let rolloverLead = 4 * 60
    /// The latest the day may roll over: a wake-up time in the afternoon still starts its day by noon.
    static let latestRolloverHour = 12
    /// The nudge, unless the person chose a time: this long after waking up.
    static let nudgeAfterWake = 13 * 60
    /// A missed day's backfill time: this long after waking up.
    static let backfillAfterWake = 60

    init(wakeMinutes: Int = StackSettings.defaultWakeMinutes, reminderEnabled: Bool = false,
         reminderMinutes: Int? = nil, hapticsEnabled: Bool = true, theme: ThemeID = .signal) {
        self.wakeMinutes = Self.clampMinutes(wakeMinutes)
        self.reminderEnabled = reminderEnabled
        self.chosenReminderMinutes = reminderMinutes.map(Self.clampMinutes)
        self.hapticsEnabled = hapticsEnabled
        self.theme = theme
    }

    /// Settings as 1.0 and the first 1.1 builds described them, with a day-start hour: the wake-up time is that hour
    /// plus 4, so the day rolls over exactly where it did and nobody's history moves.
    init(dayStartHour: Int, reminderEnabled: Bool = false, reminderMinutes: Int = 21 * 60, hapticsEnabled: Bool = true,
         theme: ThemeID = .signal) {
        self.init(wakeMinutes: Self.wakeMinutes(forDayStartHour: dayStartHour), reminderEnabled: reminderEnabled,
                  reminderMinutes: reminderMinutes, hapticsEnabled: hapticsEnabled, theme: theme)
    }

    /// The hour the day rolls over (0...12): the wake-up time minus 4 hours, never before midnight or after noon.
    /// Wake 08:00 rolls over at 04:00, 05:00 at 01:00, 14:00 at 10:00, 02:00 at 00:00.
    var dayStartHour: Int { Self.dayStartHour(forWake: wakeMinutes) }

    /// Minutes after midnight for the nudge: the one chosen, or 13 hours after waking up.
    var reminderMinutes: Int {
        get { chosenReminderMinutes ?? (wakeMinutes + Self.nudgeAfterWake) % (24 * 60) }
        set { chosenReminderMinutes = Self.clampMinutes(newValue) }
    }

    /// Where the day sheet starts a backfill on a past day: an hour after waking up.
    var backfillMinutes: Int { (wakeMinutes + Self.backfillAfterWake) % (24 * 60) }

    static func dayStartHour(forWake minutes: Int) -> Int {
        let rollover = clampMinutes(minutes) - rolloverLead
        guard rollover > 0 else { return 0 }
        return min(rollover / 60, latestRolloverHour)
    }

    static func wakeMinutes(forDayStartHour hour: Int) -> Int {
        (min(max(hour, 0), 23) * 60 + rolloverLead) % (24 * 60)
    }

    static func clampMinutes(_ minutes: Int) -> Int { min(max(minutes, 0), 24 * 60 - 1) }

    private enum CodingKeys: String, CodingKey {
        case wakeMinutes, dayStartHour, reminderEnabled, reminderMinutes, hapticsEnabled, theme
        case nudgeOfferDone, widgetInviteDay, widgetInviteDone
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let wake = try? c.decodeIfPresent(Int.self, forKey: .wakeMinutes) {
            wakeMinutes = Self.clampMinutes(wake)
        } else if let hour = try? c.decodeIfPresent(Int.self, forKey: .dayStartHour) {
            // A file from before the wake-up time: the same rollover, as a wake-up time.
            wakeMinutes = Self.wakeMinutes(forDayStartHour: hour)
        } else {
            wakeMinutes = Self.defaultWakeMinutes
        }
        reminderEnabled = try c.decodeIfPresent(Bool.self, forKey: .reminderEnabled) ?? false
        chosenReminderMinutes = (try? c.decodeIfPresent(Int.self, forKey: .reminderMinutes)).map(Self.clampMinutes)
        hapticsEnabled = try c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        // A look this version does not know (or a malformed one) reads as Signal and never costs the rest of the file.
        theme = (try? c.decodeIfPresent(ThemeID.self, forKey: .theme)) ?? .signal
        nudgeOfferDone = (try? c.decodeIfPresent(Bool.self, forKey: .nudgeOfferDone)) ?? false
        widgetInviteDay = try? c.decodeIfPresent(Int.self, forKey: .widgetInviteDay)
        widgetInviteDone = (try? c.decodeIfPresent(Bool.self, forKey: .widgetInviteDone)) ?? false
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(wakeMinutes, forKey: .wakeMinutes)
        // Written too, so an earlier build reading this file rolls the day over at the same hour.
        try c.encode(dayStartHour, forKey: .dayStartHour)
        try c.encode(reminderEnabled, forKey: .reminderEnabled)
        try c.encodeIfPresent(chosenReminderMinutes, forKey: .reminderMinutes)
        try c.encode(hapticsEnabled, forKey: .hapticsEnabled)
        try c.encode(theme, forKey: .theme)
        // Written only once set, so a file that never showed a one-time row looks as it did.
        if nudgeOfferDone { try c.encode(true, forKey: .nudgeOfferDone) }
        try c.encodeIfPresent(widgetInviteDay, forKey: .widgetInviteDay)
        if widgetInviteDone { try c.encode(true, forKey: .widgetInviteDone) }
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
