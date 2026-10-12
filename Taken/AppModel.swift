import SwiftUI
import Observation
import AppIntents

enum SheetRoute: Identifiable, Hashable {
    case add
    case settings
    case day(DayKey)
    case setTime(UUID)
    case editItem(UUID)

    var id: String {
        switch self {
        case .add: return "add"
        case .settings: return "settings"
        case .day(let day): return "day-\(day.ordinal)"
        case .setTime(let id): return "time-\(id.uuidString)"
        case .editItem(let id): return "edit-\(id.uuidString)"
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let doseIDs: Set<UUID>
}

/// The app's single source of UI state. Reads and writes go through TakenStore.
@MainActor
@Observable
final class AppModel {
    let store: TakenStore
    let isDemo: Bool
    let launchScreen: String?
    private let clockNow: @Sendable () -> Date

    private(set) var state: StackState
    private(set) var now: Date
    private(set) var engine: StackEngine
    private(set) var today: DaySummary
    private(set) var history: [[HistoryCell]] = []
    private(set) var streak: Int = 0
    private(set) var adherence = Adherence(taken: 0, due: 0)

    var sheet: SheetRoute?
    var toast: Toast?
    var expandedItemID: UUID?
    /// Section the TODAY scroll view should jump to (screenshots, deep links).
    var scrollTarget: String?
    /// Chips pre-selected in the Add sheet for the `-demo -screen add` screenshot.
    let demoPreselect: [String]
    /// Increments each time the day locks in (ALL TAKEN) from a tap, to run the lock-in animation once.
    private(set) var lockInCount = 0
    private(set) var notificationsDenied = false

    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var darwinObserver: DarwinObserver?

    init(store: TakenStore, isDemo: Bool, launchScreen: String?, clockNow: @escaping @Sendable () -> Date) {
        self.store = store
        self.isDemo = isDemo
        self.launchScreen = launchScreen
        self.clockNow = clockNow
        self.demoPreselect = isDemo && launchScreen == "add" ? ["Vitamin D3", "Fish Oil", "Finasteride"] : []
        let state = store.load()
        let now = clockNow()
        let engine = StackEngine(state: state, clock: DayClock(dayStartHour: state.settings.dayStartHour))
        self.state = state
        self.now = now
        self.engine = engine
        self.today = engine.todaySummary(now: now)
        recomputeStats()
        if !isDemo {
            startTicker()
            darwinObserver = DarwinObserver { [weak self] in
                guard let model = self else { return }
                Task { @MainActor in model.reload() }
            }
        }
    }

    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> AppModel {
        var screen: String?
        if let index = arguments.firstIndex(of: "-screen"), index + 1 < arguments.count {
            screen = arguments[index + 1]
        }
        guard arguments.contains("-demo") else {
            return AppModel(store: .shared, isDemo: false, launchScreen: nil, clockNow: { Date() })
        }
        let demoNow = DemoData.referenceNow()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("taken-demo-\(UUID().uuidString).json")
        let store = TakenStore(fileURL: url, postsChangeNotifications: false)
        let seeded = screen == "add" || screen == "empty"
            ? StackState(settings: StackSettings(reminderEnabled: true))
            : DemoData.state(now: demoNow, allTaken: screen == "today-done")
        try? store.replace(with: seeded)
        return AppModel(store: store, isDemo: true, launchScreen: screen, clockNow: { demoNow })
    }

    // MARK: Derived

    var clock: DayClock { engine.clock }
    var settings: StackSettings { state.settings }
    var hapticsOn: Bool { state.settings.hapticsEnabled }
    var activeItems: [Item] { engine.orderedItems.filter { !$0.archived } }
    var archivedItems: [Item] { engine.orderedItems.filter { $0.archived } }
    var hasStack: Bool { !activeItems.isEmpty }

    func nextLabel(for row: ItemDay) -> String {
        Fmt.next(engine.nextDueDay(for: row.item, after: today.day), today: today.day)
    }

    func sheetSummary(for day: DayKey) -> DaySummary { engine.sheetSummary(for: day) }

    func csv() -> String { CSVExport.make(state: state) }

    // MARK: Lifecycle

    private func startTicker() {
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                self?.tick()
            }
        }
    }

    private func tick() {
        let fresh = clockNow()
        let dayChanged = clock.day(for: fresh) != today.day
        now = fresh
        today = engine.todaySummary(now: fresh)
        if dayChanged { recomputeStats() }
    }

    func reload() {
        let fresh = store.load()
        if fresh != state {
            apply(fresh)
        } else {
            tick()
        }
    }

    func didBecomeActive() {
        reload()
        guard !isDemo else { return }
        let snapshot = state
        Task {
            await Reminders.reschedule(state: snapshot, now: Date())
            let denied = await Reminders.isDenied()
            self.notificationsDenied = denied && snapshot.settings.reminderEnabled
        }
    }

    func applyLaunchScreen() async {
        guard let launchScreen else { return }
        try? await Task.sleep(for: .milliseconds(450))
        switch launchScreen {
        case "add": sheet = .add
        case "settings": sheet = .settings
        case "day": sheet = .day(DemoData.sheetDay(now: now))
        case "log": scrollTarget = "log"
        default: break
        }
    }

    func handle(url: URL) {
        guard url.scheme == "taken" else { return }
        sheet = nil
        reload()
    }

    private func apply(_ fresh: StackState) {
        state = fresh
        now = clockNow()
        engine = StackEngine(state: fresh, clock: DayClock(dayStartHour: fresh.settings.dayStartHour))
        today = engine.todaySummary(now: now)
        recomputeStats()
    }

    private func recomputeStats() {
        history = engine.history(today: today.day)
        streak = engine.streak(today: today.day)
        adherence = engine.adherence(today: today.day)
    }

    /// Every write goes through here: coordinated store write, then widgets, controls, nudges.
    @discardableResult
    private func write<T>(_ body: (inout StackState) throws -> T) -> T? {
        do {
            let result = try store.update(body)
            apply(result.state)
            if !isDemo {
                let snapshot = result.state
                Task { await Sync.afterWrite(snapshot) }
            }
            return result.value
        } catch {
            show(Toast(message: "COULD NOT SAVE. TRY AGAIN", doseIDs: []))
            return nil
        }
    }

    // MARK: Taking

    /// Tap on a row: pending logs a dose, taken shows the detail. Never un-takes.
    func tap(_ row: ItemDay) {
        if row.isPending || (!row.isDue && row.doses.isEmpty) {
            log(row.item)
        } else {
            Haptics.soft(hapticsOn)
            withAnimation(.snappy(duration: 0.22)) {
                expandedItemID = expandedItemID == row.id ? nil : row.id
            }
        }
    }

    func log(_ item: Item) {
        let at = clockNow()
        let wasLocked = today.allTaken
        guard let dose = write({ $0.logDose(itemId: item.id, at: at) }) ?? nil else { return }
        afterTake(wasLocked: wasLocked)
        show(Toast(message: "\(item.code) TAKEN \(Fmt.clock(at, clock))", doseIDs: [dose.id]))
    }

    func takeAll() {
        let at = clockNow()
        let wasLocked = today.allTaken
        let clock = self.clock
        guard let logged = write({ $0.takeAllPending(now: at, clock: clock) }), !logged.isEmpty else { return }
        afterTake(wasLocked: wasLocked)
        show(Toast(message: "\(logged.count) TAKEN \(Fmt.clock(at, clock))", doseIDs: Set(logged.map(\.id))))
    }

    private func afterTake(wasLocked: Bool) {
        if !wasLocked && today.allTaken {
            Haptics.success(hapticsOn)
            lockInCount += 1
        } else {
            Haptics.impact(hapticsOn)
        }
    }

    func undo(_ toast: Toast) {
        guard !toast.doseIDs.isEmpty else { return }
        write { $0.removeDoses(toast.doseIDs) }
        Haptics.soft(hapticsOn)
        dismissToast()
    }

    func undoLastDose(_ item: Item) {
        let day = today.day
        let clock = self.clock
        let removed = write({ $0.undoLastDose(itemId: item.id, on: day, clock: clock) }) ?? nil
        if removed != nil {
            Haptics.soft(hapticsOn)
            show(Toast(message: "\(item.code) LAST DOSE REMOVED", doseIDs: []))
        }
    }

    /// Set time: corrects today's latest dose, or logs one at that time if none yet.
    func setTime(_ item: Item, hour: Int, minute: Int) {
        let clock = self.clock
        var date = clock.date(on: today.day, hour: hour, minute: minute)
        if date > clockNow() { date = clockNow() }
        let existing = today.items.first { $0.id == item.id }?.lastDose
        let wasLocked = today.allTaken
        let at = date
        if let existing {
            write { $0.setDoseTime(doseId: existing.id, to: at) }
            Haptics.impact(hapticsOn)
            show(Toast(message: "\(item.code) SET TO \(Fmt.clock(at, clock))", doseIDs: []))
        } else if let dose = write({ $0.logDose(itemId: item.id, at: at) }) ?? nil {
            afterTake(wasLocked: wasLocked)
            show(Toast(message: "\(item.code) TAKEN \(Fmt.clock(at, clock))", doseIDs: [dose.id]))
        }
    }

    // MARK: Backfill (day sheet)

    func logDose(_ item: Item, on day: DayKey, minutes: Int) {
        var date = clock.date(on: day, hour: minutes / 60, minute: minutes % 60)
        if date > clockNow() { date = clockNow() }
        let at = date
        let logged = write({ $0.logDose(itemId: item.id, at: at) }) ?? nil
        if logged != nil {
            Haptics.impact(hapticsOn)
        }
    }

    func removeDose(_ dose: Dose) {
        write { $0.removeDoses([dose.id]) }
        Haptics.soft(hapticsOn)
    }

    // MARK: Stack editing

    func addItems(_ drafts: [ItemDraft]) {
        let at = clockNow()
        guard let added = write({ $0.addItems(drafts, now: at) }), !added.isEmpty else { return }
        Haptics.impact(hapticsOn)
        show(Toast(message: added.count == 1 ? "\(added[0].code) ADDED" : "\(added.count) ADDED TO STACK", doseIDs: []))
        refreshShortcuts()
    }

    func updateItem(id: UUID, name: String, code: String, frequency: Frequency, archived: Bool) {
        let at = clockNow()
        write { state in
            state.updateItem(id: id, name: name, code: code, frequency: frequency)
            state.setArchived(id: id, archived: archived, now: at)
        }
        refreshShortcuts()
    }

    func deleteItem(id: UUID) {
        write { $0.deleteItem(id: id) }
        if expandedItemID == id { expandedItemID = nil }
        refreshShortcuts()
    }

    func moveItems(from source: IndexSet, to destination: Int) {
        write { $0.moveActiveItems(fromOffsets: source, toOffset: destination) }
    }

    private func refreshShortcuts() {
        guard !isDemo else { return }
        TakenShortcuts.updateAppShortcutParameters()
    }

    // MARK: Settings

    func setReminderEnabled(_ enabled: Bool) async {
        if enabled && !isDemo {
            let granted = await Reminders.requestPermission()
            notificationsDenied = !granted
            guard granted else { return }
        }
        if !enabled { notificationsDenied = false }
        write { $0.settings.reminderEnabled = enabled }
    }

    func setReminderMinutes(_ minutes: Int) {
        write { $0.settings.reminderMinutes = min(max(minutes, 0), 24 * 60 - 1) }
    }

    func setDayStartHour(_ hour: Int) {
        write { $0.settings.dayStartHour = min(max(hour, 0), 23) }
    }

    func setHaptics(_ enabled: Bool) {
        write { $0.settings.hapticsEnabled = enabled }
        Haptics.selection(enabled)
    }

    func eraseAll() {
        write { $0.eraseAll() }
        expandedItemID = nil
        refreshShortcuts()
    }

    // MARK: Toast

    func show(_ toast: Toast) {
        toastTask?.cancel()
        withAnimation(.snappy(duration: 0.2)) { self.toast = toast }
        let id = toast.id
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, self.toast?.id == id else { return }
            withAnimation(.snappy(duration: 0.2)) { self.toast = nil }
        }
    }

    func dismissToast() {
        toastTask?.cancel()
        withAnimation(.snappy(duration: 0.2)) { toast = nil }
    }
}

@MainActor
enum Haptics {
    static func impact(_ enabled: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func soft(_ enabled: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func success(_ enabled: Bool) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func selection(_ enabled: Bool) {
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
