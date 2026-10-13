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

/// What UNDO on a toast puts back.
enum UndoStep: Equatable, Sendable {
    /// Remove doses that were just logged.
    case remove(Set<UUID>)
    /// Put doses back exactly as they were: a removed dose, or a dose before its time was changed.
    case restore([Dose])
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    var undo: UndoStep? = nil
}

/// The app's single source of UI state. Reads and writes go through TakenStore.
@MainActor
@Observable
final class AppModel {
    let store: TakenStore
    let pro: ProStore
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
    /// The Taken Pro sheet, and which presentation level shows it.
    var paywall: PaywallRequest?
    /// Chips pre-selected in the Add sheet for the `-demo -screen add` screenshot.
    let demoPreselect: [String]
    /// Increments each time the day locks in (ALL TAKEN) from a tap, to run the lock-in animation once.
    private(set) var lockInCount = 0
    private(set) var notificationsDenied = false

    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var darwinObserver: DarwinObserver?
    @ObservationIgnored private var introTask: Task<Void, Never>?
    @ObservationIgnored private var introWaitsForSheet = false
    /// What the paywall was opened for, run once Pro is on and the sheet has closed.
    @ObservationIgnored private var afterPaywall: (@MainActor () -> Void)?

    init(store: TakenStore, pro: ProStore? = nil, isDemo: Bool, launchScreen: String?,
         clockNow: @escaping @Sendable () -> Date) {
        self.store = store
        self.isDemo = isDemo
        self.launchScreen = launchScreen
        self.clockNow = clockNow
        self.demoPreselect = isDemo && launchScreen == "add" ? ["Vitamin D3", "Fish Oil", "Finasteride"] : []
        let state = store.load()
        let now = clockNow()
        let engine = StackEngine(state: state, clock: DayClock(dayStartHour: state.settings.dayStartHour))
        self.pro = pro ?? ProStore(ledger: .shared, hasLogged: !state.doses.isEmpty)
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
            NudgeRoute.shared.attach { [weak self] day in
                self?.openDay(fromNudge: day)
            }
            self.pro.onChange = { [weak self] in self?.proDidChange() }
            self.pro.start()
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
        // Store screenshots show Taken with Pro; -screen paywall and -screen locked show it without.
        let pro = ProStore(demoLocked: screen == "paywall" || screen == "locked", now: demoNow)
        return AppModel(store: store, pro: pro, isDemo: true, launchScreen: screen, clockNow: { demoNow })
    }

    // MARK: Derived

    var clock: DayClock { engine.clock }
    var settings: StackSettings { state.settings }
    var hapticsOn: Bool { state.settings.hapticsEnabled }
    var activeItems: [Item] { engine.orderedItems.filter { !$0.archived } }
    var archivedItems: [Item] { engine.orderedItems.filter { $0.archived } }
    var hasStack: Bool { !activeItems.isEmpty }

    /// Items TAKE ALL logs right now: pending, and not logged in the last hour (StackEngine.repeatGuard).
    var takeAllCount: Int { engine.quickLogRows(today, now: now).count }

    /// Whether a dose may be logged right now (PRO.md).
    var access: ProAccess {
        ProGate.access(status: pro.status, settled: pro.settled, legacyLog: pro.legacyLog,
                       hasLogged: !state.doses.isEmpty, now: now)
    }

    /// Locked mode: the log stays readable, logging opens the paywall.
    var isLocked: Bool { access == .locked }

    /// "START 7 DAYS ON US" or "PRO ENDED · TAP TO CONTINUE".
    var lockedBarText: String {
        ProCopy.lockedBar(eligible: pro.introEligible, intro: pro.offers[.yearly]?.intro)
    }

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
        // Always rebuild: the time zone or the day may have changed while the app was away.
        apply(store.load())
        guard !isDemo else { return }
        let snapshot = state
        Task {
            // Renewals, refunds and purchases made elsewhere land here (PRO.md: refresh on foreground).
            await pro.refresh()
            await Reminders.reschedule(state: snapshot, now: Date())
            let denied = await Reminders.isDenied()
            self.notificationsDenied = denied && snapshot.settings.reminderEnabled
        }
        consumePendingLog()
        // A first dose logged from a widget, or an app closed before the sheet came up, still gets its one paywall.
        if !state.doses.isEmpty && !pro.introShown { scheduleIntro() }
    }

    func applyLaunchScreen() async {
        guard let launchScreen else { return }
        try? await Task.sleep(for: .milliseconds(450))
        switch launchScreen {
        case "add": sheet = .add
        case "settings": sheet = .settings
        case "day": sheet = .day(DemoData.sheetDay(now: now))
        case "log": scrollTarget = "log"
        case "paywall": presentPaywall(origin: .intro)
        default: break
        }
    }

    func handle(url: URL) {
        guard url.scheme == "taken" else { return }
        reload()
        guard let route = ProRoute(url: url) else {
            sheet = nil
            return
        }
        // taken://pro from a locked widget: the tap it was, run once Pro is on.
        let requestedAt = clockNow()
        var pending: (@MainActor () -> Void)?
        if let action = route.then {
            pending = { [weak self] in self?.applyPending(PendingLog(action: action, at: requestedAt)) }
        }
        Task { [weak self, pending] in
            guard let self else { return }
            // A renewal may have arrived since the widget last drew.
            await self.pro.refresh()
            if self.access.allowsLogging {
                pending?()
            } else {
                self.presentPaywall(origin: .link, pending: pending)
            }
        }
    }

    /// A tapped nudge opens on the day it was for: today's on TODAY, an earlier day's on that day's sheet.
    func openDay(fromNudge day: DayKey) {
        reload()
        sheet = day == today.day ? nil : .day(day)
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
            let hadLogged = !state.doses.isEmpty
            let result = try store.update(body)
            apply(result.state)
            if !isDemo {
                let snapshot = result.state
                Task { await Sync.afterWrite(snapshot) }
            }
            // The first dose ever: the moment Taken makes sense. The paywall follows it once (PRO.md).
            if !hadLogged && !result.state.doses.isEmpty { scheduleIntro() }
            return result.value
        } catch {
            show(Toast(message: "COULD NOT SAVE. TRY AGAIN"))
            return nil
        }
    }

    // MARK: Taken Pro

    /// Runs `action` while logging is open; otherwise opens the paywall and runs it once Pro is on.
    func requirePro(_ anchor: PaywallAnchor = .root, _ action: @escaping @MainActor () -> Void) {
        switch access {
        case .pro, .firstSession, .pending:
            action()
        case .locked:
            presentPaywall(anchor: anchor, origin: .action, pending: action)
        case .checking:
            Task { [weak self] in
                guard let self else { return }
                await self.pro.settle()
                self.requirePro(anchor, action)
            }
        }
    }

    func presentPaywall(anchor: PaywallAnchor = .root, origin: PaywallOrigin, pending: (@MainActor () -> Void)? = nil) {
        guard paywall == nil else { return }
        // Any paywall counts as the one after the first dose, so it never comes up on its own a second time. Plans
        // looked at from Settings before anything was logged do not: the first dose still brings it up once.
        if origin != .settings || !state.doses.isEmpty { pro.markIntroShown() }
        Task { await pro.loadOffers() }
        let request = PaywallRequest(anchor: anchor, origin: origin, pending: pending)
        if anchor == .root && sheet != nil {
            // A sheet is up on TODAY: it closes first, then the paywall slides up.
            sheet = nil
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard let self, self.paywall == nil else { return }
                self.paywall = request
            }
        } else {
            paywall = request
        }
    }

    func closePaywall() {
        paywall = nil
    }

    /// Pro just came on in the paywall: what opened it runs once the sheet has gone.
    func paywallUnlocked() {
        if let pending = paywall?.pending { afterPaywall = pending }
    }

    /// The paywall sheet finished closing.
    func paywallDidDismiss() {
        let action = afterPaywall
        afterPaywall = nil
        guard let action, access.allowsLogging else { return }
        action()
    }

    /// About 1.5 s after the first dose the paywall slides up, once.
    private func scheduleIntro(after delay: Duration = .milliseconds(1500)) {
        guard !isDemo, !pro.introShown, introTask == nil else { return }
        introTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self else { return }
            await self.pro.settle()
            self.introTask = nil
            self.showIntroIfDue()
        }
    }

    private func showIntroIfDue() {
        guard !pro.introShown, paywall == nil, access == .locked else { return }
        guard sheet == nil else {
            // Never over a sheet in use: it waits for the sheet to close.
            introWaitsForSheet = true
            return
        }
        presentPaywall(origin: .intro)
    }

    /// A sheet on TODAY finished closing.
    func rootSheetDidDismiss() {
        guard introWaitsForSheet else { return }
        introWaitsForSheet = false
        scheduleIntro(after: .milliseconds(500))
    }

    /// A log a widget, the control, Siri or a nudge could not make while locked, offered now Taken is open.
    private func consumePendingLog() {
        guard let pending = pro.takePendingLog(maxAge: 10 * 60, now: clockNow()) else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.pro.refresh()
            self.requirePro { [weak self] in self?.applyPending(pending) }
        }
    }

    /// Logs what was asked for, at the time it was asked for.
    private func applyPending(_ pending: PendingLog) {
        switch pending.action {
        case .takeAll:
            takeAll(at: pending.at)
        case .log(let id):
            logIfPending(itemID: id, at: pending.at)
        }
    }

    private func proDidChange() {
        guard !isDemo else { return }
        let snapshot = state
        // Widgets, the control and the nudges follow Pro.
        Task { await Sync.afterWrite(snapshot) }
    }

    // MARK: Taking

    /// Tap on a row: pending logs a dose, taken shows the detail. Never un-takes.
    func tap(_ row: ItemDay) {
        if row.isPending || (!row.isDue && row.doses.isEmpty) {
            let item = row.item
            requirePro { [weak self] in self?.log(item) }
        } else {
            Haptics.soft(hapticsOn)
            withAnimation(.snappy(duration: 0.22)) {
                expandedItemID = expandedItemID == row.id ? nil : row.id
            }
        }
    }

    func log(_ item: Item, at time: Date? = nil) {
        let at = time ?? clockNow()
        let wasLocked = today.allTaken
        let zone = clock.calendar.timeZone
        guard let dose = write({ $0.logDose(itemId: item.id, at: at, timeZone: zone) }) ?? nil else { return }
        afterTake(wasLocked: wasLocked)
        show(Toast(message: "\(item.code) TAKEN \(Fmt.clock(at, clock))", undo: .remove([dose.id])))
        announce("\(item.name) taken at \(Fmt.spoken(at)).")
    }

    /// A widget row asked for this item: logs only while a dose is still pending, never twice in the hour.
    private func logIfPending(itemID: UUID, at: Date) {
        let wasLocked = today.allTaken
        let clock = self.clock
        guard let dose = write({ $0.logNextDoseIfPending(itemId: itemID, now: at, clock: clock) }) ?? nil,
              let item = state.item(dose.itemId) else { return }
        afterTake(wasLocked: wasLocked)
        show(Toast(message: "\(item.code) TAKEN \(Fmt.clock(at, clock))", undo: .remove([dose.id])))
        announce("\(item.name) taken at \(Fmt.spoken(at)).")
    }

    func takeAll(at time: Date? = nil) {
        let at = time ?? clockNow()
        let wasLocked = today.allTaken
        let clock = self.clock
        guard let logged = write({ $0.takeAllPending(now: at, clock: clock) }), !logged.isEmpty else { return }
        afterTake(wasLocked: wasLocked)
        show(Toast(message: "\(logged.count) TAKEN \(Fmt.clock(at, clock))", undo: .remove(Set(logged.map(\.id)))))
        announce("\(logged.count) taken at \(Fmt.spoken(at)).")
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
        guard let step = toast.undo else { return }
        switch step {
        case .remove(let ids):
            write { $0.removeDoses(ids) }
        case .restore(let doses):
            write { state in
                for dose in doses { state.restore(dose) }
            }
        }
        Haptics.soft(hapticsOn)
        dismissToast()
        announce("Undone.")
    }

    /// Removes today's latest dose of an item. The toast's UNDO puts it back with its original time.
    func undoLastDose(_ item: Item) {
        let day = today.day
        let clock = self.clock
        guard let removed = write({ $0.undoLastDose(itemId: item.id, on: day, clock: clock) }) ?? nil else { return }
        Haptics.soft(hapticsOn)
        show(Toast(message: "\(item.code) LAST DOSE REMOVED", undo: .restore([removed])))
        announce("\(item.name), last dose removed.")
    }

    /// The moment a wall-clock time means on a logical day, and whether it is still to come.
    func moment(on day: DayKey, minutes: Int) -> (date: Date, isFuture: Bool) {
        let date = clock.date(on: day, hour: minutes / 60, minute: minutes % 60)
        return (date, date > clockNow())
    }

    /// Set time: corrects today's latest dose, or logs one at that time if none yet. A time still to come
    /// is never used (the sheet disables it), and the toast's UNDO restores the time it replaced.
    func setTime(_ item: Item, hour: Int, minute: Int) {
        let clock = self.clock
        let (at, isFuture) = moment(on: today.day, minutes: hour * 60 + minute)
        guard !isFuture else { return }
        let zone = clock.calendar.timeZone
        let existing = today.items.first { $0.id == item.id }?.lastDose
        let wasLocked = today.allTaken
        if let existing {
            write { $0.setDoseTime(doseId: existing.id, to: at, timeZone: zone) }
            Haptics.impact(hapticsOn)
            show(Toast(message: "\(item.code) SET TO \(Fmt.clock(at, clock))", undo: .restore([existing])))
            announce("\(item.name) set to \(Fmt.spoken(at)).")
        } else if let dose = write({ $0.logDose(itemId: item.id, at: at, timeZone: zone) }) ?? nil {
            afterTake(wasLocked: wasLocked)
            show(Toast(message: "\(item.code) TAKEN \(Fmt.clock(at, clock))", undo: .remove([dose.id])))
            announce("\(item.name) taken at \(Fmt.spoken(at)).")
        }
    }

    // MARK: Backfill (day sheet)

    /// Logs a dose at a time on a day. A time still to come is never used (the sheet disables it).
    func logDose(_ item: Item, on day: DayKey, minutes: Int) {
        let (at, isFuture) = moment(on: day, minutes: minutes)
        guard !isFuture else { return }
        let zone = clock.calendar.timeZone
        let logged = write({ $0.logDose(itemId: item.id, at: at, timeZone: zone) }) ?? nil
        guard logged != nil else { return }
        Haptics.impact(hapticsOn)
        announce("\(item.name) logged at \(Fmt.spoken(at)).")
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
        show(Toast(message: added.count == 1 ? "\(added[0].code) ADDED" : "\(added.count) ADDED TO STACK"))
        refreshShortcuts()
    }

    func updateItem(id: UUID, name: String, code: String, frequency: Frequency, archived: Bool) {
        let at = clockNow()
        write { state in
            state.updateItem(id: id, name: name, code: code, frequency: frequency, now: at)
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
        // With VoiceOver the toast stays until it is dismissed, so UNDO is still there after a swipe to it.
        guard !UIAccessibility.isVoiceOverRunning else { return }
        let id = toast.id
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled, let self, self.toast?.id == id else { return }
            withAnimation(.snappy(duration: 0.2)) { self.toast = nil }
        }
    }

    /// Spoken confirmation for VoiceOver.
    private func announce(_ text: String) {
        guard !isDemo else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
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
