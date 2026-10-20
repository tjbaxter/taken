import AppIntents
import Foundation
import WidgetKit

// The agent read surface (REDESIGN.md, SPEC 3.7): the to-dos as Shortcuts actions that hand values on, so a shortcut the
// person builds can pass them to "Ask Claude", "Ask ChatGPT" or Apple's "Use Model", and add to the list from them. It
// is how Things ("Find Items", "Get Item") and Streaks open their data to other apps: everything runs on the iPhone.
// Taken has no server, no key and no account, and sends nothing itself; what a shortcut sends, and to whom, is up to
// the person who builds it. App target only, so adding a to-do can reschedule its due-time notification
// (`TodoNotificationScheduler`). The selection, the gate and the copy are pure, so the tests never touch the App Group.

// MARK: - Values Shortcuts sees

/// Personal or Work, as Shortcuts shows it. Its own enum, one case for each `TodoArea`, so the file format's type stays
/// a plain Codable enum in the widget extension.
enum TodoListOption: String, AppEnum, CaseIterable {
    case personal
    case work

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "List" }
    static var caseDisplayRepresentations: [TodoListOption: DisplayRepresentation] {
        [
            .personal: DisplayRepresentation(title: "Personal", image: .init(systemName: "person")),
            .work: DisplayRepresentation(title: "Work", image: .init(systemName: "briefcase")),
        ]
    }

    init(_ area: TodoArea) {
        self = TodoListOption(rawValue: area.rawValue) ?? .personal
    }

    var area: TodoArea { TodoArea(stored: rawValue) }
}

/// Which to-dos "Get to-dos" hands on.
enum TodoShowOption: String, AppEnum, CaseIterable {
    /// Both lists' open to-dos (or one list's), in the order the list shows them.
    case open
    /// Done on the day being lived (the day-start hour decides it, as it does in the app), newest first.
    case doneToday
    /// Everything Taken keeps: the open ones, then the done ones, newest first (done to-dos are kept 30 days).
    case all

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "To-dos to get" }
    static var caseDisplayRepresentations: [TodoShowOption: DisplayRepresentation] {
        [
            .open: DisplayRepresentation(title: "Open to-dos"),
            .doneToday: DisplayRepresentation(title: "Done today"),
            .all: DisplayRepresentation(title: "All to-dos", subtitle: "Open, then done in the last 30 days"),
        ]
    }
}

/// One to-do as Shortcuts sees it. Each property is something a shortcut can read on its own ("Get Title from To-do"),
/// and what "Use Model" gets when it is handed a to-do.
struct TodoEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "To-do" }
    static var defaultQuery: TodoEntityQuery { TodoEntityQuery() }

    let id: UUID

    @Property(title: "Title")
    var title: String

    /// The moment it is due: its time, or for a day alone the end of that day, as the list orders it.
    @Property(title: "Due")
    var due: Date?

    @Property(title: "Is done")
    var isDone: Bool

    @Property(title: "Done at")
    var completedAt: Date?

    @Property(title: "List")
    var list: TodoListOption

    /// "Tomorrow 09:00": the due label the list shows, under the title in Shortcuts.
    let dueLabel: String?

    init(id: UUID, title: String, due: Date?, isDone: Bool, completedAt: Date?, list: TodoListOption, dueLabel: String?) {
        self.id = id
        self.dueLabel = dueLabel
        self.title = title
        self.due = due
        self.isDone = isDone
        self.completedAt = completedAt
        self.list = list
    }

    init(_ task: TodoTask, now: Date, clock: DayClock) {
        self.init(id: task.id, title: task.title, due: TodoOrdering.sortDate(task, clock: clock), isDone: task.isDone,
                  completedAt: task.completedAt, list: TodoListOption(task.area),
                  dueLabel: TodoText.dueLabel(task, now: now, clock: clock))
    }

    var displayRepresentation: DisplayRepresentation {
        guard let dueLabel else { return DisplayRepresentation(title: "\(title)") }
        return DisplayRepresentation(title: "\(title)", subtitle: "\(dueLabel)")
    }
}

/// Every to-do Taken keeps, for Shortcuts' pickers and the Find action it builds from an enumerable query. The list is
/// short (done ones go after 30 days), which is what Apple says an enumerable query is for.
struct TodoEntityQuery: EnumerableEntityQuery {
    init() {}

    func allEntities() async throws -> [TodoEntity] {
        TodoAgent.live(.all)
    }

    func entities(for identifiers: [UUID]) async throws -> [TodoEntity] {
        let wanted = Set(identifiers)
        return TodoAgent.live(.all).filter { wanted.contains($0.id) }
    }

    func suggestedEntities() async throws -> [TodoEntity] {
        TodoAgent.live(.open)
    }
}

// MARK: - Actions

/// "Get to-dos": the open ones, the ones done today, or all, from one list or both. Reading needs no Taken Pro.
struct GetTodosIntent: AppIntent {
    static var title: LocalizedStringResource { "Get to-dos" }
    static var description: IntentDescription { IntentDescription("Your to-dos from Taken, for use in other shortcuts.") }
    /// Siri reads the list aloud, from both lists and up to 30 days of done ones, so a locked iPhone asks for Face ID or
    /// the passcode first (Apple, IntentAuthenticationPolicy). The Lock Screen widget still shows the list in view.
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Show", default: .open)
    var show: TodoShowOption

    @Parameter(title: "List", description: "Personal or Work. Leave it empty for both.")
    var list: TodoListOption?

    static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$show)") {
            \.$list
        }
    }

    init() {}

    init(show: TodoShowOption, list: TodoListOption? = nil) {
        self.show = show
        self.list = list
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[TodoEntity]> & ProvidesDialog {
        Self.answer(todos: TodoStore.shared.load(), show: show, area: list?.area, now: Date(), clock: TodoAgent.liveClock())
    }

    /// The to-dos as the value, and a short line for Siri: how many, and the first three.
    static func answer(todos: TodoState, show: TodoShowOption, area: TodoArea?, now: Date, clock: DayClock)
        -> some IntentResult & ReturnsValue<[TodoEntity]> & ProvidesDialog {
        let tasks = TodoAgent.tasks(in: todos, show: show, area: area, now: now, clock: clock)
        let text = TodoAgentCopy.summary(tasks.map(\.title), show: show, list: area)
        return .result(value: tasks.map { TodoEntity($0, now: now, clock: clock) }, dialog: "\(text)")
    }
}

/// "Add to-do": one to-do from a shortcut (a title "Use Model" wrote, say), on the list asked for or the one last in
/// view. Gated exactly like a typed note: the first note needs no Taken Pro, after it adding does.
struct AddTodoIntent: AppIntent {
    static var title: LocalizedStringResource { "Add to-do" }
    static var description: IntentDescription {
        IntentDescription("Adds a to-do to Taken, on the list you choose or the one last open.")
    }
    /// A write, and its answer reads the to-do back: the owner unlocks first, as for Get to-dos.
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Title", requestValueDialog: "What needs doing?")
    var title: String

    @Parameter(title: "Due")
    var due: Date?

    @Parameter(title: "List", description: "Personal or Work. Leave it empty for the list last open in Taken.")
    var list: TodoListOption?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$title) to Taken") {
            \.$due
            \.$list
        }
    }

    init() {}

    init(title: String, due: Date? = nil, list: TodoListOption? = nil) {
        self.title = title
        self.due = due
        self.list = list
    }

    func perform() async throws -> some IntentResult & ReturnsValue<TodoEntity> & ProvidesDialog {
        let now = Date()
        let added: (task: TodoTask, state: TodoState)
        do {
            added = try await TodoAgent.add(title: title, due: due, area: list?.area, store: .shared,
                                            ledgerStore: .shared, now: now)
        } catch TodoAgentError.needsTitle {
            throw $title.needsValueError("\(TodoAgentCopy.askTitle)")
        } catch let error as TodoAgentError {
            // Locked: nothing was written. A thrown error stops the shortcut, so nothing after it acts on a to-do that
            // is not there, and Siri or Shortcuts shows the line.
            throw error
        } catch {
            throw TodoAgentError.couldNotSave
        }
        // As a change made in the app does: the Lock Screen list redraws, and a due time gets its notification.
        await MainActor.run { WidgetCenter.shared.reloadTimelines(ofKind: TodoCaptureRoute.widgetKind) }
        await TodoNotificationScheduler.shared.reschedule(added.state.tasks)
        let clock = TodoAgent.liveClock()
        let text = TodoAgentCopy.added(added.task, now: now, clock: clock)
        return .result(value: TodoEntity(added.task, now: now, clock: clock), dialog: "\(text)")
    }
}

/// Why "Add to-do" wrote nothing. Shortcuts and Siri show the line (Apple, AppIntentError: an error that conforms to
/// CustomLocalizedStringResourceConvertible is shown with its own description).
enum TodoAgentError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case needsTitle
    case needsPro
    case couldNotSave

    var message: String {
        switch self {
        case .needsTitle: return TodoAgentCopy.askTitle
        case .needsPro: return TodoAgentCopy.needsPro
        case .couldNotSave: return TodoAgentCopy.couldNotSave
        }
    }

    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

// MARK: - The rules, pure

enum TodoAgent {
    /// The list's clock: the day rolls over at the hour the wake-up time sets, as it does in the app and the widget.
    static func liveClock() -> DayClock {
        DayClock(dayStartHour: TakenStore.shared.load().settings.dayStartHour)
    }

    /// Both lists, from the App Group, as entities.
    static func live(_ show: TodoShowOption) -> [TodoEntity] {
        let now = Date()
        let clock = liveClock()
        return tasks(in: TodoStore.shared.load(), show: show, area: nil, now: now, clock: clock)
            .map { TodoEntity($0, now: now, clock: clock) }
    }

    /// What "Get to-dos" returns. A list given keeps to that list; none means both, never mixed into one order of
    /// their own: open ones come in the order the app shows them.
    static func tasks(in state: TodoState, show: TodoShowOption, area: TodoArea?, now: Date, clock: DayClock) -> [TodoTask] {
        let open = area.map { state.openTasks(in: $0, clock: clock) } ?? state.openTasks(clock: clock)
        switch show {
        case .open:
            return open
        case .doneToday:
            let today = clock.day(for: now)
            return area.map { state.doneTasks(on: today, in: $0, clock: clock) } ?? state.doneTasks(on: today, clock: clock)
        case .all:
            let done = state.tasks.filter { $0.isDone && (area == nil || $0.area == area) }
                .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            return open + done
        }
    }

    /// Adds one to-do: cleaned like every title (short lines, never paragraphs), a due date saved as a moment, on the
    /// list asked for or the one last in view. Throws `needsTitle` when nothing is left of the title and `needsPro` when
    /// adding is locked; either way nothing is written.
    static func add(title: String, due: Date?, area: TodoArea?, store: TodoStore, ledgerStore: ProLedgerStore,
                    now: Date, recheck: (@MainActor @Sendable () async -> Void)? = nil) async throws
        -> (task: TodoTask, state: TodoState) {
        guard let clean = TodoText.clean(title) else { throw TodoAgentError.needsTitle }
        guard await TodoGate.mayAdd(todos: store.load(), now: now, ledgerStore: ledgerStore, recheck: recheck) else {
            throw TodoAgentError.needsPro
        }
        let draft = TodoDraft(title: clean, due: due.map { TodoDue.time($0) })
        let result = try store.update { state in state.add([draft], area: area ?? state.lastArea, at: now) }
        guard let task = result.value.first else { throw TodoAgentError.couldNotSave }
        return (task, result.state)
    }
}

extension TodoGate {
    /// What Shortcuts and Siri read: the ledger the app wrote, read as `ProGate.access(ledger:state:now:)` reads it for
    /// doses, with the first voice note standing in for the first dose.
    static func access(ledger: ProLedger?, todos: TodoState, now: Date) -> ProAccess {
        access(firstNoteAt: todos.firstNoteAt, status: ledger?.status, settled: true,
               legacyLog: ledger?.legacyLog ?? true, now: now)
    }

    /// Whether a shortcut may add a to-do now. As `ProGate.mayLog` does for a dose, a plan set to renew whose cache ran
    /// out is checked with the App Store before the answer is no (`ProRecheck`, which the app sets at launch; `recheck`
    /// stands in for it in tests).
    static func mayAdd(todos: TodoState, now: Date, ledgerStore: ProLedgerStore = .shared,
                       recheck: (@MainActor @Sendable () async -> Void)? = nil) async -> Bool {
        let ledger = ledgerStore.load()
        if access(ledger: ledger, todos: todos, now: now).allowsLogging { return true }
        guard ledger?.status?.lapsedRenewal(at: now) == true else { return false }
        let handler: (@MainActor @Sendable () async -> Void)?
        if let recheck {
            handler = recheck
        } else {
            handler = await ProRecheck.handler
        }
        guard let handler else { return false }
        await handler()
        return access(ledger: ledgerStore.load(), todos: todos, now: now).allowsLogging
    }
}

// MARK: - Copy

/// What Siri says and Shortcuts shows. The same rules as every line in Taken: no dashes, no "!", never "free".
enum TodoAgentCopy {
    static let needsPro = "To-dos need Taken Pro. Open Taken to continue."
    static let couldNotSave = "Taken could not save that. Open the app and try again."
    static let askTitle = "What needs doing?"
    /// How many titles "Get to-dos" reads out.
    static let titlesRead = 3

    /// "3 open to-dos: Call the dentist, Buy milk and Book the car in.", "5 open Work to-dos: A, B, C and 2 more.",
    /// "No to-dos done today."
    static func summary(_ titles: [String], show: TodoShowOption, list: TodoArea?) -> String {
        let noun = titles.count == 1 ? "to-do" : "to-dos"
        let named = list.map { "\($0.title) \(noun)" } ?? noun
        let phrase: String
        switch show {
        case .open: phrase = "open \(named)"
        case .doneToday: phrase = "\(named) done today"
        case .all: phrase = named
        }
        guard !titles.isEmpty else { return "No \(phrase)." }
        let read = Array(titles.prefix(titlesRead))
        let more = titles.count - read.count
        let names = more > 0 ? read.joined(separator: ", ") + " and \(more) more" : Fmt.list(read)
        return sentence("\(titles.count) \(phrase): \(names)")
    }

    /// "Added to Work: Send the deck, due tomorrow at 9:00 AM."
    static func added(_ task: TodoTask, now: Date, clock: DayClock) -> String {
        let due = TodoText.spokenDue(task, now: now, clock: clock).map { ", \($0)" } ?? ""
        return sentence("Added to \(task.area.title): \(task.title)\(due)")
    }

    static let all: [String] = [needsPro, couldNotSave, askTitle]

    /// A full stop, unless the last title already ended the sentence.
    private static func sentence(_ text: String) -> String {
        guard let last = text.last, !".?".contains(last) else { return text }
        return text + "."
    }
}
