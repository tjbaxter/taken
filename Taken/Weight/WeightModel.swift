import Observation
import SwiftUI
import UIKit

/// The Weight tab's state (SPEC 3.12): weights.json through `WeightStore`, read and written on the main actor. The app
/// model owns one (`AppModel.weight`); `-demo` gives it a temporary file seeded for the screen.
@MainActor
@Observable
final class WeightModel {
    let store: WeightStore
    let isDemo: Bool
    @ObservationIgnored private let clockNow: @Sendable () -> Date
    private(set) var state: WeightState
    /// The point the weigh-in just saved lit, for this visit only: the small line under the number shows its sentence
    /// until the Weight tab disappears, the app leaves the foreground, UNDO is tapped or the next weigh-in is saved.
    var justReached: WeightMoment?
    // The page's in-memory state (REDESIGN.md, "Weight tab page: entry first"), never stored.
    /// What is typed into the big number; cleared whenever focus ends.
    var draft = ""
    /// Mirrors the page's focus, for DemoProbe.
    var entryFocused = false
    /// The weigh-in saved on this visit: the small line then says how close the trend is to the goal.
    var justSaved: UUID?
    /// The lit dot springs once per visit.
    var momentPlayed = false
    /// Edit… on today's number: All weigh-ins opens straight at this weigh-in.
    var editOnOpen: UUID?
    /// DemoProbe: screen two is at the top.
    var onTrend = false
    /// A tap on the number asked for the keypad and Pro allowed it (`requireWeightPro`): the page focuses the field.
    var entryRequested = false
    /// `-demo` only: what the Goal sheet's field holds when it opens (`weight-goal-low`).
    @ObservationIgnored private(set) var demoTypedGoal: String?
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

    #if DEBUG
    /// `-demo` (Debug only): a temporary file, the tab on for the Weight screens with a flat-to-gently-falling line of
    /// weigh-ins (`DemoData.weighIns`, ending yesterday unless the screen is about today), in kilograms (pounds on
    /// `weight-lb`) so every capture reads the same; off and empty for every other screen. The goal screens get
    /// Tom-like history, the goal and the height, and the in-memory state their line needs (a save on this visit, a
    /// point just lit).
    static func demo(screen: String?, now: Date) -> WeightModel {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("weights-demo-\(UUID().uuidString).json")
        let store = WeightStore(fileURL: url, postsChangeNotifications: false)
        let clock = DayClock(dayStartHour: DemoData.settings.dayStartHour)
        var state = WeightState()
        if WeightDemo.showsTab(screen) {
            state.showsTab = true
            state.unit = WeightDemo.unit(screen)
        }
        if WeightDemo.hasGoal(screen) {
            // Tom-like history from 97.8 kg with the goal 87.0 and 180 cm (REDESIGN.md, "Goal and moments").
            state.weighIns = DemoData.goalWeighIns(now: now, extraWeeks: WeightDemo.goalReached(screen) ? 6 : 0,
                                                   momentKg: screen == "weight-goal-moment" ? 87.1 : nil)
            if let first = state.weighIns.map({ clock.day(of: $0) }).min() {
                state.goal = WeightGoal(kg: 87.0, startDay: first)
                state.heightCm = 180
            }
        } else if screen == "weight-first" {
            // The first weigh-in, this morning: screen two with one dot.
            let at = clock.date(on: clock.day(for: now), hour: 7, minute: 6)
            state.weighIns = [WeighIn(kg: 88.35, weighedAt: at, utcOffset: TimeZone.current.secondsFromGMT(for: at))]
        } else if WeightDemo.hasWeighIns(screen) {
            state.weighIns = DemoData.weighIns(now: now, includeToday: WeightDemo.includesToday(screen))
        }
        state.firstWeighInAt = state.weighIns.map(\.weighedAt).min()
        try? store.replace(with: state)
        let model = WeightModel(store: store, isDemo: true, clockNow: { now })
        model.demoTypedGoal = WeightDemo.typedGoal(screen)
        model.draft = WeightDemo.draft(screen) ?? ""
        let moments = model.moments(clock: clock)
        switch screen {
        case "weight-goal-moment":
            model.justReached = moments.first { $0.kind == .percent(10) }
            model.justSaved = model.state.last?.id
        case "weight-goal-reached-moment":
            model.justReached = moments.first(where: \.isGoal)
            model.justSaved = model.state.last?.id
        case "weight-goal-saved":
            model.justSaved = model.state.last?.id
        default:
            break
        }
        return model
    }
    #endif

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

    var goal: WeightGoal? { state.goal }

    /// The goal's points, worked out from the weigh-ins, the goal and the height (`WeightGoals.moments`). None without a goal.
    func moments(clock: DayClock) -> [WeightMoment] {
        guard let goal = state.goal else { return [] }
        let trend = WeightTrend.trend(state.weighIns, clock: clock)
        return WeightGoals.moments(goal: goal, trend: trend, weighInDays: state.weighInDays(clock: clock),
                                   heightCm: state.heightCm)
    }

    /// The end of a visit to the tab (it disappears, the app leaves the foreground): the line's sentence and the draft go.
    func endVisit() {
        justReached = nil
        justSaved = nil
        momentPlayed = false
        draft = ""
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

    /// Set Goal or Change Goal: the goal and, if one was chosen, the height.
    @discardableResult
    func setGoal(_ goal: WeightGoal, heightCm: Double?) -> Bool {
        let saved: Void? = write { (state: inout WeightState) -> Void in
            state.goal = goal
            if let heightCm { state.heightCm = heightCm }
        }
        return saved != nil
    }

    /// Clear Goal: the goal as it was, for UNDO. The height stays for the next goal; Erase removes it.
    func clearGoal() -> WeightGoal? {
        guard state.goal != nil else { return nil }
        justReached = nil
        return write { state -> WeightGoal? in
            let removed = state.goal
            state.goal = nil
            return removed
        } ?? nil
    }

    /// UNDO on Goal cleared: the same goal, start included.
    func restoreGoal(_ goal: WeightGoal) {
        write { $0.goal = goal }
    }

    /// Erase all data: the weigh-ins, the goal and the height go; the tab setting, the unit, the offer's answer and the
    /// first weigh-in's date stay.
    func eraseAll() {
        justReached = nil
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

    /// Edit… on today's number: All weigh-ins, open straight at this weigh-in (editing follows the weigh-in rule).
    func editWeighIn(_ id: UUID) {
        requireWeightPro { [weak self] in
            guard let self else { return }
            self.weight.editOnOpen = id
            self.sheet = .weighIns
        }
    }

    /// The big number right now (`WeightEntry.figure`).
    var weightFigure: WeightFigure {
        WeightEntry.figure(last: weight.state.last, today: today.day, clock: clock, draft: weight.draft,
                           focused: weight.entryFocused)
    }

    /// The small line under it right now (`WeightEntry.line`).
    func weightLine(locale: Locale = .current) -> WeightLine {
        let readout = weight.goal == nil ? nil : weightPicture(range: weight.range).readout
        return WeightEntry.line(focused: weight.entryFocused, draft: weight.draft, unit: weight.unit, locale: locale,
                                hasGoal: weight.goal != nil, justSaved: weight.justSaved != nil,
                                justReached: weight.justReached, readout: readout)
    }

    /// Weigh in on the page: the number stays as today's, the trend moves, and "Weighed in" with UNDO. If this weigh-in
    /// lights a goal point dated its own day (`WeightGoals.fresh`), the small line shows its sentence for this visit;
    /// reaching the goal plays the success haptic All taken plays, 0.35 s later, in place of the soft one. One
    /// announcement 0.5 s after the save.
    func saveWeighIn(kg: Double) {
        let clock = self.clock
        let before = weight.moments(clock: clock)
        guard let saved = weight.log(kg: kg, timeZone: clock.calendar.timeZone) else {
            show(Toast(message: WeightCopy.couldNotSave))
            return
        }
        let fresh = WeightGoals.fresh(before: before, after: weight.moments(clock: clock), savedDay: clock.day(of: saved))
        weight.justReached = fresh
        weight.justSaved = saved.id
        weight.momentPlayed = false
        let unit = weight.unit
        if fresh?.isGoal == true {
            let haptics = hapticsOn
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                Haptics.success(haptics)
            }
        } else {
            Haptics.soft(hapticsOn)
        }
        show(Toast(message: WeightCopy.weighedIn, undo: .removeWeighIn(saved.id)))
        var announcement = "Weighed in, \(WeightFormat.spoken(saved.kg, unit: unit))."
        if let fresh, let goal = weight.goal {
            announcement += " " + WeightGoalCopy.spokenMoment(fresh, goalKg: goal.kg, unit: unit)
        }
        guard !isDemo else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
    }

    // MARK: The goal

    /// Set Goal or Change Goal in the More menu: the Goal sheet. Open in every Pro state, like the unit and the range.
    func openWeightGoal() {
        sheet = .weightGoal
    }

    /// Save in the Goal sheet: the goal (with the height, if new), the soft haptic and "Goal set, 87.0 kilograms." No toast.
    func saveWeightGoal(kg: Double, startDay: DayKey, startPicked: Bool, heightCm: Double?) {
        let goal = WeightGoal(kg: kg, startDay: startDay, startPicked: startPicked)
        weight.justReached = nil
        guard weight.setGoal(goal, heightCm: heightCm) else {
            show(Toast(message: WeightCopy.couldNotSave))
            return
        }
        Haptics.soft(hapticsOn)
        announceWeight(WeightGoalCopy.goalSet(kg, unit: weight.unit))
    }

    /// Clear Goal: at once, "Goal cleared" with UNDO, nothing asked, because nothing is deleted.
    func clearWeightGoal() {
        guard let removed = weight.clearGoal() else { return }
        Haptics.soft(hapticsOn)
        show(Toast(message: WeightGoalCopy.cleared, undo: .restoreWeightGoal(removed)))
        announceWeight(WeightGoalCopy.clearedSpoken)
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
            // The point that weigh-in lit, and its line, go with it; saving the same number again lights it again.
            weight.justReached = nil
            weight.justSaved = nil
            _ = weight.delete(id)
        case .restoreWeightGoal(let goal):
            weight.restoreGoal(goal)
        case .restoreWeighIn(let weighIn):
            weight.restore(weighIn)
        case .showWeightTab:
            withAnimation(.snappy(duration: 0.22)) { weight.setShowsTab(true) }
            tab = .weight
        default:
            break
        }
    }

    /// The Weight tab's trend, chart window, goal points, slot reading and change line, worked out from the file and the
    /// stack's weekly doses.
    func weightPicture(range: WeightRange) -> WeightPicture {
        let state = weight.state
        let trend = WeightTrend.trend(state.weighIns, clock: clock)
        let window = WeightWindow.make(weighIns: state.weighIns, trend: trend, ticks: WeightTicks.days(engine: engine),
                                       range: range, today: today.day, clock: clock, goalKg: state.goal?.kg)
        var moments: [WeightMoment] = []
        var readout: GoalReadout?
        if let goal = state.goal {
            moments = WeightGoals.moments(goal: goal, trend: trend, weighInDays: state.weighInDays(clock: clock),
                                          heightCm: state.heightCm)
            readout = WeightGoals.readout(goal: goal, trend: trend, moments: moments, unit: weight.unit)
        }
        return WeightPicture(trend: trend, window: window, moments: moments, readout: readout,
                             change: WeightChangeLine.make(range: range, trend: trend, window: window))
    }

    private func announceWeight(_ text: String) {
        guard !isDemo else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
/// Everything the Weight tab draws for one range.
struct WeightPicture {
    let trend: [WeightPoint]
    let window: WeightWindow
    /// Every goal point, oldest first.
    let moments: [WeightMoment]
    /// The slot's reading; nil without a goal.
    let readout: GoalReadout?
    /// The change line for the range; nil with fewer than two trend days in view.
    let change: (kg: Double, span: WeightChangeLine.Span)?

    /// The points inside the range.
    var momentsInView: [WeightMoment] { moments.filter { window.contains($0.day) } }
}
