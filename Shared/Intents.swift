import AppIntents
import Foundation

// Compiled into the app and the widget extension. Widget buttons and the Control Center control
// run these in the extension process; Siri and Shortcuts run them in the app.

struct TakeAllIntent: AppIntent {
    static var title: LocalizedStringResource { "Take all" }
    static var description: IntentDescription { IntentDescription("Log every pending dose in your stack, right now.") }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date()
        let store = TakenStore.shared
        // Logging needs Taken Pro (PRO.md). Without it nothing is written; the tap is kept and Taken offers it
        // with the paywall when it next opens.
        guard ProGate.access(ledger: ProLedgerStore.shared.load(), state: store.load(), now: now).allowsLogging else {
            ProLedgerStore.shared.recordPending(.takeAll, at: now)
            await Sync.reloadSurfaces()
            return .result(dialog: "\(ProCopy.lockedDialog)")
        }
        do {
            let result = try store.update { state -> [Dose] in
                let clock = DayClock(dayStartHour: state.settings.dayStartHour)
                return state.takeAllPending(now: now, clock: clock)
            }
            await Sync.afterWrite(result.state)
            let names = result.value.compactMap { dose in result.state.item(dose.itemId)?.name }
            if names.isEmpty {
                return .result(dialog: "\(SiriAnswers.nothingPending(state: result.state, now: now))")
            }
            return .result(dialog: "Logged \(names.count): \(names.joined(separator: ", ")).")
        } catch {
            return .result(dialog: "Taken could not save that. Open the app and try again.")
        }
    }
}

struct CheckStackIntent: AppIntent {
    static var title: LocalizedStringResource { "Did I take it?" }
    static var description: IntentDescription { IntentDescription("Answers from your log: what is taken today, and when.") }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = TakenStore.shared.load()
        return .result(dialog: "\(SiriAnswers.status(state: state, now: Date()))")
    }
}

struct LogItemIntent: AppIntent {
    static var title: LocalizedStringResource { "Log item" }
    static var description: IntentDescription { IntentDescription("Log one dose of an item in your stack.") }

    @Parameter(title: "Item")
    var item: StackItemEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$item)")
    }

    init() {}

    init(item: StackItemEntity) {
        self.item = item
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date()
        let itemID = item.id
        guard ProGate.access(ledger: ProLedgerStore.shared.load(), state: TakenStore.shared.load(), now: now).allowsLogging else {
            ProLedgerStore.shared.recordPending(.log(itemID), at: now)
            await Sync.reloadSurfaces()
            return .result(dialog: "\(ProCopy.lockedDialog)")
        }
        do {
            let result = try TakenStore.shared.update { state in
                state.logActiveDose(itemId: itemID, at: now)
            }
            guard let dose = result.value, let logged = result.state.item(dose.itemId) else {
                if let archived = result.state.item(itemID), archived.archived {
                    return .result(dialog: "\(archived.name) is archived in Taken. Unarchive it in Settings to log it.")
                }
                return .result(dialog: "That item is no longer in your stack.")
            }
            await Sync.afterWrite(result.state)
            return .result(dialog: "Logged \(logged.name) at \(Fmt.spoken(dose.takenAt)).")
        } catch {
            return .result(dialog: "Taken could not save that. Open the app and try again.")
        }
    }
}

/// Widget row tap. Logs only while a dose is still pending and the item was not logged in the last hour,
/// so a stale widget or a second tap can never double log.
struct LogNextDoseIntent: AppIntent {
    static var title: LocalizedStringResource { "Log next dose" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Item ID")
    var itemID: String

    init() {}

    init(itemID: UUID) {
        self.itemID = itemID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: itemID) else { return .result() }
        let now = Date()
        // A widget drawn before Pro ran out: log nothing and redraw it read-only, where a tap opens the paywall.
        guard ProGate.access(ledger: ProLedgerStore.shared.load(), state: TakenStore.shared.load(), now: now).allowsLogging else {
            await Sync.reloadSurfaces()
            return .result()
        }
        if let result = try? TakenStore.shared.update({ state in
            state.logNextDoseIfPending(itemId: id, now: now, clock: DayClock(dayStartHour: state.settings.dayStartHour))
        }) {
            await Sync.afterWrite(result.state)
        }
        return .result()
    }
}

// MARK: - Entity

struct StackItemEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Stack item" }
    static var defaultQuery: StackItemQuery { StackItemQuery() }

    let id: UUID
    let name: String
    let code: String

    init(id: UUID, name: String, code: String) {
        self.id = id
        self.name = name
        self.code = code
    }

    init(_ item: Item) {
        self.init(id: item.id, name: item.name, code: item.code)
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(code)")
    }
}

struct StackItemQuery: EntityStringQuery {
    init() {}

    private func current() -> [StackItemEntity] {
        TakenStore.shared.load().orderedItems.filter { !$0.archived }.map(StackItemEntity.init)
    }

    func entities(for identifiers: [UUID]) async throws -> [StackItemEntity] {
        let wanted = Set(identifiers)
        return TakenStore.shared.load().items.filter { wanted.contains($0.id) }.map(StackItemEntity.init)
    }

    func entities(matching string: String) async throws -> [StackItemEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return current() }
        return current().filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.code.localizedCaseInsensitiveContains(query)
        }
    }

    func suggestedEntities() async throws -> [StackItemEntity] {
        current()
    }
}

// MARK: - Siri answers

enum SiriAnswers {
    /// "Yes. Vitamin D3 at 7:42 AM, Fish Oil at 7:42 AM. Finasteride is not due today."
    /// "Not yet: Fish Oil is pending."
    static func status(state: StackState, now: Date, timeZone: TimeZone = .current) -> String {
        let clock = DayClock(dayStartHour: state.settings.dayStartHour, timeZone: timeZone)
        let today = StackEngine(state: state, clock: clock).todaySummary(now: now)
        guard !today.isEmpty else { return "Your stack is empty. Open Taken to add what you take." }

        let taken = today.items.filter { !$0.doses.isEmpty }.map { row -> String in
            let times = row.doses.map { Fmt.spoken($0.takenAt) }
            return "\(row.item.name) at \(Fmt.list(times))"
        }
        let pending = today.items.filter { $0.isPending }.map { row -> String in
            row.dosesPerDay > 1 && !row.doses.isEmpty
                ? "\(row.item.name) (\(row.doses.count) of \(row.dosesPerDay))"
                : row.item.name
        }
        let notDue = today.items.filter { !$0.isDue && $0.doses.isEmpty }.map { $0.item.name }

        var sentences: [String] = []
        if pending.isEmpty {
            sentences.append(taken.isEmpty ? "Nothing is due today." : "Yes. \(taken.joined(separator: ", ")).")
        } else {
            sentences.append("Not yet: \(Fmt.list(pending)) \(pending.count == 1 ? "is" : "are") pending.")
            if !taken.isEmpty { sentences.append("\(taken.joined(separator: ", ")).") }
        }
        if !notDue.isEmpty {
            sentences.append("\(Fmt.list(notDue)) \(notDue.count == 1 ? "is" : "are") not due today.")
        }
        return sentences.joined(separator: " ")
    }

    /// Why TAKE ALL logged nothing.
    static func nothingPending(state: StackState, now: Date, timeZone: TimeZone = .current) -> String {
        let clock = DayClock(dayStartHour: state.settings.dayStartHour, timeZone: timeZone)
        let today = StackEngine(state: state, clock: clock).todaySummary(now: now)
        if today.isEmpty { return "Your stack is empty. Open Taken to add what you take." }
        if today.allTaken { return "Nothing pending. All taken today." }
        // Still pending, but logged within the last hour: TAKE ALL never logs a next dose on top of it.
        let recent = today.pendingItems.map { $0.item.name }
        if !recent.isEmpty {
            return "Nothing logged. \(Fmt.list(recent)) \(recent.count == 1 ? "was" : "were") logged in the last hour. To log another dose now, tap it in Taken."
        }
        return "Nothing pending right now."
    }
}
