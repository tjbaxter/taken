import Observation
import SwiftUI
import UIKit

#if DEBUG || TAKEN_INTERNAL
/// The Weight tab's state (SPEC 3.12): weights.json through `WeightStore`, read and written on the main actor. The app
/// model owns one (`AppModel.weight`); `-demo` gives it a temporary file seeded for the screen. Compiled only into Debug
/// and the owner's internal builds until 1.2.
@MainActor
@Observable
final class WeightModel {
    let store: WeightStore
    let isDemo: Bool
    @ObservationIgnored private let clockNow: @Sendable () -> Date
    private(set) var state: WeightState
    @ObservationIgnored private var observer: DarwinObserver?

    init(store: WeightStore, isDemo: Bool, clockNow: @escaping @Sendable () -> Date) {
        self.store = store
        self.isDemo = isDemo
        self.clockNow = clockNow
        self.state = store.load()
        guard !isDemo else { return }
        observer = DarwinObserver(name: WeightStore.darwinNotificationName) { [weak self] in
            guard let model = self else { return }
            Task { @MainActor in model.refresh() }
        }
    }

    /// `-demo`: a temporary file, the tab on for the Weight screens with a flat-to-gently-falling line of weigh-ins
    /// (`DemoData.weighIns`), in kilograms so every capture reads the same; off and empty for every other screen.
    static func demo(screen: String?, now: Date) -> WeightModel {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("weights-demo-\(UUID().uuidString).json")
        let store = WeightStore(fileURL: url, postsChangeNotifications: false)
        var state = WeightState()
        if WeightDemo.showsTab(screen) {
            state.showsTab = true
            state.unit = .kg
        }
        if WeightDemo.hasWeighIns(screen) {
            state.weighIns = DemoData.weighIns(now: now)
            state.firstWeighInAt = state.weighIns.map(\.weighedAt).min()
        }
        try? store.replace(with: state)
        return WeightModel(store: store, isDemo: true, clockNow: { now })
    }

    // MARK: Reading

    /// The tab is on only once the person turned it on (nil is off).
    var showsTab: Bool { state.showsTab == true }

    var unit: WeightUnit { state.unit ?? WeightUnit.preferred(for: .current) }

    var range: WeightRange { state.range ?? .all }

    var isEmpty: Bool { state.weighIns.isEmpty }

    /// Profile > Data shows the weight CSV rows once the tab is on or there is anything to export.
    var showsDataRows: Bool { showsTab || !isEmpty }

    /// Whether a weigh-in may be logged, edited, backdated or imported now (`WeightGate`): the first one ever needs no Pro.
    func access(status: ProStatus?, settled: Bool, legacyLog: Bool, now: Date) -> ProAccess {
        WeightGate.access(firstWeighInAt: state.firstWeighInAt, status: status, settled: settled, legacyLog: legacyLog,
                          now: now)
    }

    func csv(timeZone: TimeZone = .current) -> String {
        WeightCSV.make(state.weighIns, timeZone: timeZone)
    }

    /// Re-reads the file (on appear, on return to the foreground, after another process wrote it).
    func refresh() {
        let fresh = store.load()
        if fresh != state { state = fresh }
    }

    // MARK: Changing

    /// Every write goes through here: a coordinated read-modify-write of weights.json. Nil when it could not be saved.
    @discardableResult
    func write<T>(_ body: (inout WeightState) throws -> T) -> T? {
        do {
            let result = try store.update(body)
            state = result.state
            return result.value
        } catch {
            return nil
        }
    }

    func setShowsTab(_ on: Bool) {
        write { $0.showsTab = on }
    }

    func setUnit(_ unit: WeightUnit) {
        guard unit != state.unit else { return }
        write { $0.unit = unit }
    }

    func setRange(_ range: WeightRange) {
        write { $0.range = range }
    }

    /// Add tab or Not now on Today's offer: either answer is final, and Add tab turns the tab on.
    func answerOffer(addTab: Bool) {
        write { state in
            state.offerAnswered = true
            if addTab { state.showsTab = true }
        }
    }

    /// Saves a weigh-in now, where the iPhone is.
    func log(kg: Double, timeZone: TimeZone = .current) -> WeighIn? {
        let at = clockNow()
        return write { $0.log(kg: kg, at: at, timeZone: timeZone) }
    }

    /// Returns the weigh-in as it was before, for UNDO.
    func update(_ id: UUID, kg: Double, at date: Date, timeZone: TimeZone = .current) -> WeighIn? {
        write { $0.update(id, kg: kg, at: date, timeZone: timeZone) } ?? nil
    }

    func delete(_ id: UUID) -> WeighIn? {
        write { $0.delete(id) } ?? nil
    }

    func restore(_ weighIn: WeighIn) {
        write { $0.restore(weighIn) }
    }

    /// Weigh-ins read from a CSV (`WeightImport.parse`), merged by the minute. The line Profile shows after it.
    func importCSV(_ text: String, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let now = clockNow()
        switch WeightImport.parse(text, fallbackUnit: unit, locale: locale, timeZone: timeZone, now: now) {
        case .failure:
            return WeightCopy.notFound
        case .success(let parsed):
            guard let merged = write({ $0.merge(parsed.weighIns, at: now) }) else { return WeightCopy.couldNotSave }
            return WeightCopy.imported(added: merged.added, already: merged.already, unreadable: parsed.unreadable,
                                       unit: parsed.unit)
        }
    }

    /// Erase all data: the weigh-ins go; the tab setting, the unit, the offer's answer and the first weigh-in's date stay.
    func eraseAll() {
        write { $0.eraseAll() }
        if !isDemo { store.removeSetAsideCopies() }
    }
}

// MARK: - The app model's weight actions

extension AppModel {
    /// Whether a weigh-in may be logged, edited, backdated or imported right now: Taken Pro, or the first weigh-in ever.
    var weightAccess: ProAccess {
        weight.access(status: pro.status, settled: pro.settled, legacyLog: pro.legacyLog, now: now)
    }

    /// Runs `action` while weigh-ins are open; otherwise opens the paywall (over the level `anchor` names) and runs it
    /// once Pro is on, as `requirePro` does for doses. Weight never opens the paywall on its own.
    func requireWeightPro(_ anchor: PaywallAnchor = .root, _ action: @escaping @MainActor () -> Void) {
        switch weightAccess {
        case .pro, .firstSession, .pending:
            action()
        case .locked:
            presentPaywall(anchor: anchor, origin: .action, pending: action)
        case .checking:
            Task { [weak self] in
                guard let self else { return }
                await self.pro.settle()
                self.requireWeightPro(anchor, action)
            }
        }
    }

    /// Log weigh-in: the sheet, or the paywall first once the first weigh-in is used.
    func openWeighIn() {
        requireWeightPro { [weak self] in self?.sheet = .weighIn }
    }

    /// Save in the sheet: the soft haptic, the dot and the trend move, and "Weighed in 88.35 kg" with UNDO.
    func saveWeighIn(kg: Double) {
        guard let saved = weight.log(kg: kg, timeZone: clock.calendar.timeZone) else {
            show(Toast(message: WeightCopy.couldNotSave))
            return
        }
        Haptics.soft(hapticsOn)
        show(Toast(message: WeightCopy.weighedIn, time: WeightFormat.withUnit(saved.kg, unit: weight.unit),
                   undo: .removeWeighIn(saved.id)))
        announceWeight("Weighed in, \(WeightFormat.spoken(saved.kg, unit: weight.unit)).")
    }

    /// A new weight, day or time from All weigh-ins, with UNDO back to what it was.
    func updateWeighIn(_ id: UUID, kg: Double, at date: Date) {
        guard let before = weight.update(id, kg: kg, at: date, timeZone: clock.calendar.timeZone) else { return }
        Haptics.soft(hapticsOn)
        show(Toast(message: WeightCopy.updated, undo: .restoreWeighIn(before)))
    }

    /// A swipe in All weigh-ins, or Delete in its editor: always allowed, as removing a dose is, with UNDO.
    func deleteWeighIn(_ id: UUID) {
        guard let removed = weight.delete(id) else { return }
        Haptics.soft(hapticsOn)
        show(Toast(message: WeightCopy.deleted, time: WeightFormat.withUnit(removed.kg, unit: weight.unit),
                   undo: .restoreWeighIn(removed)))
        announceWeight("Weigh-in deleted.")
    }

    /// Hide Weight Tab in the More menu: Today comes to the front first (a hidden tab must not stay selected), then the
    /// tab goes, and the toast says where it comes back. Nothing is deleted, so nothing is asked.
    func hideWeightTab() {
        tab = .today
        withAnimation(.snappy(duration: 0.22)) { weight.setShowsTab(false) }
        show(Toast(message: WeightCopy.hidden, undo: .showWeightTab))
    }

    /// Profile > Weight > Weight tab. Off while the tab is in front brings Today forward first; on never switches tabs.
    func setWeightTab(_ on: Bool) {
        if !on && tab == .weight { tab = .today }
        withAnimation(.snappy(duration: 0.22)) { weight.setShowsTab(on) }
    }

    /// The More menu's Kilograms and Pounds.
    func setWeightUnit(_ unit: WeightUnit) {
        Haptics.selection(hapticsOn)
        weight.setUnit(unit)
    }

    /// The chart's W, 30D, 90D, Y and All, remembered in weights.json.
    func setWeightRange(_ range: WeightRange) {
        guard range != weight.range else { return }
        Haptics.selection(hapticsOn)
        withAnimation(.snappy(duration: 0.25)) { weight.setRange(range) }
    }

    /// taken://weight: the tab, or Today when it is off.
    func openWeightTab() {
        tab = weight.showsTab ? .weight : .today
    }

    /// Profile > Data > Import weight CSV, once the file is picked: the line under the row says what happened.
    func importWeights(from url: URL) -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let text = WeightImport.text(from: data) else {
            return WeightCopy.couldNotOpen
        }
        let line = weight.importCSV(text, timeZone: clock.calendar.timeZone)
        Haptics.soft(hapticsOn)
        return line
    }

    /// UNDO on a weight toast.
    func undoWeight(_ step: UndoStep) {
        switch step {
        case .removeWeighIn(let id):
            _ = weight.delete(id)
        case .restoreWeighIn(let weighIn):
            weight.restore(weighIn)
        case .showWeightTab:
            withAnimation(.snappy(duration: 0.22)) { weight.setShowsTab(true) }
            tab = .weight
        default:
            break
        }
    }

    /// The Weight tab's trend, chart window and changes, worked out from the file and the stack's weekly doses.
    func weightPicture(range: WeightRange) -> (trend: [WeightPoint], window: WeightWindow, changes: [WeightChange]) {
        let trend = WeightTrend.trend(weight.state.weighIns, clock: clock)
        let window = WeightWindow.make(weighIns: weight.state.weighIns, trend: trend, ticks: WeightTicks.days(engine: engine),
                                       range: range, today: today.day, clock: clock)
        return (trend, window, WeightTrend.changes(trend))
    }

    private func announceWeight(_ text: String) {
        guard !isDemo else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
#endif
