import Observation
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

/// The To-do tab: one tap starts listening, the words show as they are said, a pause of about 1.5 s (or a second tap)
/// stops, and the on-device model sorts the ramble into tasks. Reads and writes go through `TodoStore`.
@MainActor
@Observable
final class TodoModel {
    static let shared = TodoModel.fromLaunchArguments()

    enum Phase: Equatable, Sendable {
        case idle
        /// Permissions and the microphone are coming up.
        case starting
        case listening
        /// The note is being sorted into tasks.
        case sorting
    }

    /// A note the model split into several to-dos, offered back as one ("Keep as one"): Apple's generative AI guidance
    /// asks for results that are easy to revert, and one tap after the save does that without a review screen.
    struct KeepOffer: Equatable, Sendable {
        let noteId: UUID
        /// The note's tasks, in the order said.
        let ids: [UUID]
        /// The words as they were said.
        let transcript: String
    }

    /// Why voice capture cannot run right now.
    enum Blocker: Equatable, Sendable {
        case microphone
        case speech
        /// No on-device speech recognition for this language on this iPhone.
        case unavailable
    }

    let store: TodoStore
    let isDemo: Bool
    let launchScreen: String?
    private let clockNow: @Sendable () -> Date

    private(set) var state: TodoState
    private(set) var phase: Phase = .idle
    /// What has been heard so far.
    private(set) var transcript = ""
    /// Recent input levels from 0 to 1, oldest first, for the waveform.
    private(set) var levels: [Double]
    /// A one-line note under the list ("Nothing heard...", "Automatic sorting needs Apple Intelligence.").
    private(set) var notice: String?
    private(set) var blocker: Blocker?
    /// Tasks that just came in from a note, drawn with a short highlight.
    private(set) var arrived: Set<UUID> = []
    /// Tasks whose check is filling before they move to Done today.
    private(set) var completing: Set<UUID> = []
    /// A swiped-away task, offered back for a few seconds.
    private(set) var deleted: TodoTask?
    /// "3 to-dos from your note, Keep as one": for `keepOfferDuration`, or until the list changes, the mic is tapped or
    /// the tab is left, whichever comes first. VoiceOver gets the same as an action on each of the note's tasks.
    private(set) var keepOffer: KeepOffer?
    /// The note being sorted: saved whole already, kept out of the list until its tasks replace it.
    private(set) var sortingNote: UUID?
    /// The list a note goes to: the one in view when the mic was tapped (or a quick capture asked), fixed until the
    /// note is saved. The live card names it, so the destination shows before a word is said. The model never
    /// chooses the list.
    private(set) var captureArea: TodoArea = .personal
    /// The moment the list reads from (due labels, Done today). Moves with the clock while the tab is open.
    private(set) var now: Date

    @ObservationIgnored private var capture: SpeechCapture?
    @ObservationIgnored private var extractor: (any TaskExtractor)?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private var deletedTask: Task<Void, Never>?
    @ObservationIgnored private var keepTask: Task<Void, Never>?
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var lastVoiceAt = Date()
    @ObservationIgnored private var noiseFloor: Float = -60
    @ObservationIgnored private var wordCount = 0
    @ObservationIgnored private var levelTick = 0
    @ObservationIgnored private(set) var dayStartHour = 4
    @ObservationIgnored private var hapticsOn = true

    nonisolated static let levelCount = 32
    /// Quiet after speech this long stops listening.
    nonisolated static let silenceToStop: TimeInterval = 1.5
    /// Nothing said this long after the tap stops listening.
    nonisolated static let nothingHeardAfter: TimeInterval = 8
    /// One note is at most this long.
    nonisolated static let longestNote: TimeInterval = 120
    /// The model gets this long to sort a note before it is saved whole.
    nonisolated static let sortingLimit: Duration = .seconds(15)
    /// Keep as one stays on screen this long at most.
    nonisolated static let keepOfferDuration: Duration = .seconds(10)

    init(store: TodoStore, isDemo: Bool, launchScreen: String?, clockNow: @escaping @Sendable () -> Date) {
        self.store = store
        self.isDemo = isDemo
        self.launchScreen = launchScreen
        self.clockNow = clockNow
        self.state = store.load()
        self.now = clockNow()
        self.levels = Array(repeating: 0, count: Self.levelCount)
    }

    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> TodoModel {
        var screen: String?
        if let index = arguments.firstIndex(of: "-screen"), index + 1 < arguments.count {
            screen = arguments[index + 1]
        }
        guard arguments.contains("-demo") else {
            return TodoModel(store: .shared, isDemo: false, launchScreen: nil, clockNow: { Date() })
        }
        // Screenshots: demo tasks in a temporary file, never the real one, at the demo's moment.
        let demoNow = DemoData.referenceNow()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("todos-demo-\(UUID().uuidString).json")
        let store = TodoStore(fileURL: url)
        let seeded = screen == "todo-empty"
            ? TodoState()
            : TodoDemo.state(now: demoNow, recording: screen == "todo-recording", inView: screen == "todo-work" ? .work : .personal)
        try? store.replace(with: seeded)
        let model = TodoModel(store: store, isDemo: true, launchScreen: screen, clockNow: { demoNow })
        if screen == "todo-recording" { model.showDemoRecording() }
        return model
    }

    /// `-screen todo`, `todo-work`, `todo-recording` and `todo-empty` open on the To-do tab (`todo-work` with Work in
    /// view).
    static func opensOnTodo(_ launchScreen: String?) -> Bool {
        launchScreen?.hasPrefix("todo") == true
    }

    // MARK: Reading

    var clock: DayClock { DayClock(dayStartHour: dayStartHour) }
    /// The list in view: Personal or Work. One at a time, never mixed.
    var area: TodoArea { state.lastArea }
    var openTasks: [TodoTask] { openTasks(in: area) }
    var doneToday: [TodoTask] { state.doneTasks(on: clock.day(for: now), in: area, clock: clock) }
    var isEmpty: Bool { openTasks.isEmpty && doneToday.isEmpty }
    var isListening: Bool { phase == .listening }

    /// One list's open tasks, without the note still being sorted.
    func openTasks(in area: TodoArea) -> [TodoTask] {
        state.openTasks(in: area, clock: clock).filter { $0.id != sortingNote }
    }

    func dueLabel(_ task: TodoTask) -> String? { TodoText.dueLabel(task, now: now, clock: clock) }
    func dueParts(_ task: TodoTask) -> (day: String?, time: String?)? { TodoText.dueParts(task, now: now, clock: clock) }
    func isOverdue(_ task: TodoTask) -> Bool { TodoText.isOverdue(task, now: now, clock: clock) }

    /// "16:00" for a done task: when it was done.
    func doneLabel(_ task: TodoTask) -> String? {
        task.completedAt.map { TodoText.clockTime($0, clock: clock) }
    }

    func spoken(_ task: TodoTask) -> String {
        if let done = task.completedAt {
            return "\(task.title), done at \(done.formatted(date: .omitted, time: .shortened))"
        }
        let due = TodoText.spokenDue(task, now: now, clock: clock).map { ", \($0)" } ?? ""
        return "\(task.title)\(due)"
    }

    // MARK: Lifecycle

    /// Follows the app's day-start hour (from the wake-up time) and haptics setting.
    func attach(_ app: AppModel) {
        dayStartHour = app.clock.dayStartHour
        hapticsOn = app.hapticsOn
        refresh()
    }

    /// Re-reads the file and the clock (on appear, on return to the foreground).
    func refresh() {
        now = clockNow()
        let fresh = store.load()
        if fresh != state {
            state = fresh
            // Changed elsewhere (a Shortcut, another build): the note's tasks may not be the ones offered.
            dismissKeepOffer()
        }
    }

    /// Voice to-dos need Taken Pro after the first note (REDESIGN.md); the first note is on the house.
    func access(_ app: AppModel) -> ProAccess {
        TodoGate.access(firstNoteAt: state.firstNoteAt, status: app.pro.status, settled: app.pro.settled,
                        legacyLog: app.pro.legacyLog, now: clockNow())
    }

    // MARK: Capture

    /// The mic button: start, or stop and sort.
    func micTapped(_ app: AppModel) {
        dismissKeepOffer()
        attach(app)
        switch phase {
        case .listening:
            Task { await finishListening() }
        case .starting, .sorting:
            break
        case .idle:
            // The list in view at the tap is where the note goes, even if the paywall comes first.
            let area = self.area
            whenAllowed(app) { [weak self] in
                guard let self else { return }
                Task { await self.startListening(into: area) }
            }
        }
    }

    /// A quick capture (Siri, the control, the Lock Screen, the quick action) asked to start listening. Taken opens on
    /// the list last in view and records into it.
    func startFromRequest(_ app: AppModel) {
        dismissKeepOffer()
        attach(app)
        guard phase == .idle else { return }
        let area = self.area
        whenAllowed(app) { [weak self] in
            guard let self else { return }
            // Siri may still be handing the microphone back: a busy microphone gets two more tries.
            Task { await self.startListening(into: area, busyRetries: 2) }
        }
    }

    /// Runs `action` when voice capture is open, otherwise opens the paywall and runs it once Pro is on.
    func whenAllowed(_ app: AppModel, _ action: @escaping @MainActor () -> Void) {
        switch access(app) {
        case .pro, .firstSession, .pending:
            action()
        case .locked:
            app.presentPaywall(anchor: .root, origin: .action, pending: action)
        case .checking:
            Task { [weak self, weak app] in
                guard let app else { return }
                await app.pro.settle()
                self?.whenAllowed(app, action)
            }
        }
    }

    private func startListening(into area: TodoArea, busyRetries: Int = 0) async {
        guard phase == .idle else { return }
        captureArea = area
        if isDemo {
            // CI has no microphone: the demo shows the listening state a tap or a quick capture opens on.
            showDemoRecording()
            return
        }
        phase = .starting
        blocker = nil
        clearNotice()
        transcript = ""
        levels = Array(repeating: 0, count: Self.levelCount)
        let permission = await VoicePermissions.request()
        guard permission == .granted else {
            blocker = permission == .microphoneDenied ? .microphone : .speech
            phase = .idle
            return
        }
        let extractor = TodoExtractors.best()
        self.extractor = extractor
        // The model loads while the person talks, so the tasks come back about a second after they stop.
        Task.detached(priority: .userInitiated) { await extractor.prepare() }
        let capture = SpeechCapture()
        do {
            try await capture.start(locale: .current)
        } catch SpeechCaptureError.unavailable {
            self.extractor = nil
            blocker = .unavailable
            phase = .idle
            return
        } catch {
            // A call or another app has the microphone.
            self.extractor = nil
            phase = .idle
            if busyRetries > 0 {
                try? await Task.sleep(for: .milliseconds(700))
                await startListening(into: area, busyRetries: busyRetries - 1)
            } else {
                show(TodoCopy.microphoneBusy)
            }
            return
        }
        self.capture = capture
        startedAt = Date()
        lastVoiceAt = startedAt
        noiseFloor = -60
        wordCount = 0
        phase = .listening
        // No spoken "listening" for VoiceOver: the microphone would hear it. The haptic and the button say it.
        TodoHaptics.soft(hapticsOn)
        eventsTask = Task { [weak self] in
            for await event in capture.events {
                self?.handle(event)
            }
        }
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, self.phase == .listening else { return }
                if TodoModel.shouldStop(now: Date(), startedAt: self.startedAt, lastVoiceAt: self.lastVoiceAt,
                                        heardWords: self.wordCount > 0) {
                    await self.finishListening()
                    return
                }
            }
        }
    }

    private func handle(_ event: SpeechCaptureEvent) {
        guard phase == .listening else { return }
        switch event {
        case .text(let text):
            let words = text.split(whereSeparator: { $0.isWhitespace }).count
            if words > wordCount {
                wordCount = words
                lastVoiceAt = Date()
            }
            transcript = text
        case .level(let decibels):
            // A slow-rising noise floor: speech is anything clearly above the room.
            if decibels < noiseFloor {
                noiseFloor = decibels
            } else {
                noiseFloor += (decibels - noiseFloor) * 0.004
            }
            if decibels > max(noiseFloor + 10, -50) { lastVoiceAt = Date() }
            levelTick += 1
            guard levelTick % 2 == 0 else { return }
            var next = levels
            next.removeFirst()
            next.append(Double(max(0, min(1, (decibels + 55) / 45))))
            levels = next
        case .interrupted:
            Task { await finishListening() }
        }
    }

    /// Stop listening: after a pause of about 1.5 s once words have come, after 8 s with nothing said, or at 2 minutes.
    nonisolated static func shouldStop(now: Date, startedAt: Date, lastVoiceAt: Date, heardWords: Bool) -> Bool {
        let elapsed = now.timeIntervalSince(startedAt)
        if elapsed >= longestNote { return true }
        let quiet = now.timeIntervalSince(lastVoiceAt)
        if heardWords { return quiet >= silenceToStop }
        return elapsed >= nothingHeardAfter && quiet >= silenceToStop
    }

    /// Stops listening and sorts what was said. Locking the phone or leaving Taken mid-note lands here too, so iOS is
    /// asked for the time to finish: the words are saved the moment they are known, sorted or not.
    func finishListening() async {
        guard phase == .listening, let capture else { return }
        phase = .sorting
        watchTask?.cancel()
        TodoHaptics.light(hapticsOn)
        let background = BackgroundTime.begin("Saving a voice note")
        defer { background.end() }
        let finalText = await capture.finish()
        eventsTask?.cancel()
        self.capture = nil
        let heard = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = heard.isEmpty ? transcript.trimmingCharacters(in: .whitespacesAndNewlines) : heard
        guard !words.isEmpty else {
            extractor = nil
            transcript = ""
            phase = .idle
            show(TodoCopy.nothingHeard)
            return
        }
        transcript = words
        await save(note: words, area: captureArea)
    }

    /// Typed instead of said (no microphone, or no on-device speech): the same sorting, the same Pro rule, into the
    /// list in view.
    func submitTyped(_ text: String, app: AppModel) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, phase == .idle else { return }
        dismissKeepOffer()
        attach(app)
        let area = self.area
        whenAllowed(app) { [weak self] in
            guard let self, self.phase == .idle else { return }
            self.phase = .sorting
            self.captureArea = area
            self.transcript = words
            Task {
                let background = BackgroundTime.begin("Saving typed to-dos")
                defer { background.end() }
                await self.save(note: words, area: area)
            }
        }
    }

    private func save(note words: String, area: TodoArea) async {
        let context = TodoContext(now: clockNow(), timeZone: .current, dayStartHour: dayStartHour)
        // Saved whole first, out of sight, so nothing said is lost if iOS ends Taken before the model answers. The
        // model's tasks replace it on the same list.
        let whole = write { $0.add(TodoValidation.wholeNote(words), area: area, at: context.now) }?.first
        sortingNote = whole?.id
        let extractor = self.extractor ?? TodoExtractors.best()
        self.extractor = nil
        let extraction = await Self.extract(words, with: extractor, context: context)
        let drafts = extraction.drafts.isEmpty ? TodoValidation.wholeNote(words) : extraction.drafts
        let added = withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { () -> [TodoTask] in
            defer { sortingNote = nil }
            if let whole {
                return write { $0.replaceNote(whole.id, with: drafts, at: context.now) } ?? [whole]
            }
            return write { $0.add(drafts, area: area, at: context.now) } ?? []
        }
        transcript = ""
        phase = .idle
        guard !added.isEmpty else { return }
        arrived = Set(added.map(\.id))
        TodoHaptics.success(hapticsOn)
        announce(added.count == 1 ? "1 to-do added: \(added[0].title)." : "\(added.count) to-dos added.")
        // The sorting line only shows when the model did not sort, and Keep as one only when it did and split the
        // note, so the two never compete for the line.
        if extraction.sorting == .model && added.count >= 2 {
            offerKeep(KeepOffer(noteId: added[0].noteId, ids: added.map(\.id), transcript: words))
        } else if let line = TodoCopy.sortingNote(extraction.sorting) {
            show(line, for: .seconds(8))
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeOut(duration: 0.4)) { self?.arrived = [] }
        }
    }

    /// The extractor's answer, or the whole note as one task when it takes longer than `limit`.
    nonisolated static func extract(_ words: String, with extractor: any TaskExtractor, context: TodoContext,
                                    limit: Duration = sortingLimit) async -> TodoExtraction {
        await firstResult(of: { await extractor.extract(transcript: words, context: context) }, orAfter: limit,
                          fallback: TodoExtraction(drafts: TodoValidation.wholeNote(words), sorting: .couldNotSort))
    }

    /// Stops listening and keeps what was said (the app went to the background mid-note). The background time is asked
    /// for here, before the app can be suspended, and held until the note is saved.
    func stopIfListening() {
        guard phase == .listening else { return }
        let background = BackgroundTime.begin("Saving a voice note")
        Task {
            await finishListening()
            background.end()
        }
    }

    // MARK: Tasks

    /// The circle: done (the check fills, then the task moves to Done today), or back to open.
    func toggle(_ task: TodoTask) {
        if task.isDone {
            withAnimation(.snappy(duration: 0.28)) { _ = write { $0.reopen(task.id) } }
            TodoHaptics.soft(hapticsOn)
            announce("\(task.title), not done.")
            return
        }
        guard !completing.contains(task.id) else { return }
        withAnimation(.snappy(duration: 0.2)) { _ = completing.insert(task.id) }
        TodoHaptics.impact(hapticsOn)
        announce("\(task.title), done.")
        let at = clockNow()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(420))
            guard let self else { return }
            withAnimation(.snappy(duration: 0.32)) {
                _ = self.write { $0.complete(task.id, at: at) }
                self.completing.remove(task.id)
            }
        }
    }

    /// The edit sheet: the words, when it is due, and which list it is on.
    func edit(_ id: UUID, title: String, due: TodoDue?, area: TodoArea? = nil) {
        withAnimation(.snappy(duration: 0.25)) {
            _ = write { (saved: inout TodoState) -> Void in
                saved.update(id, title: title, due: due)
                if let area { saved.move(id, to: area) }
            }
        }
    }

    /// A leading swipe or the VoiceOver action: the task leaves this list for the other one, whose count goes up.
    func move(_ task: TodoTask, to area: TodoArea) {
        guard task.area != area else { return }
        let moved = withAnimation(.snappy(duration: 0.25), { write { $0.move(task.id, to: area) } }) ?? false
        guard moved else { return }
        TodoHaptics.soft(hapticsOn)
        announce("\(task.title), moved to \(area.title).")
    }

    /// The Personal and Work switch. The choice is `lastArea` in todos.json, so Taken reopens on it, quick captures
    /// record into it and the Lock Screen widget shows it. Fixed while a note is being heard or sorted: the note goes
    /// to the list the live card names.
    func select(_ area: TodoArea) {
        guard area != self.area, phase == .idle else { return }
        Haptics.selection(hapticsOn)
        withAnimation(.snappy(duration: 0.25)) { _ = write { $0.lastArea = area } }
    }

    func delete(_ task: TodoTask) {
        guard let removed = withAnimation(.snappy(duration: 0.25), { write { $0.delete(task.id) } }) ?? nil else { return }
        TodoHaptics.soft(hapticsOn)
        deletedTask?.cancel()
        withAnimation(.snappy(duration: 0.2)) { deleted = removed }
        announce("\(removed.title), deleted.")
        deletedTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.2)) { self?.deleted = nil }
        }
    }

    func undoDelete() {
        guard let task = deleted else { return }
        deletedTask?.cancel()
        withAnimation(.snappy(duration: 0.25)) {
            _ = write { $0.restore(task) }
            deleted = nil
        }
        TodoHaptics.soft(hapticsOn)
    }

    /// Settings > Erase all data: the tasks go too. The first free note stays used.
    func eraseAll() {
        write { $0.eraseAll() }
    }

    // MARK: Keep as one

    /// The note's tasks become one task again: the words as said for a short note (otherwise the titles joined), the
    /// earliest due date, the same note. Nothing changes when one of them was done or deleted meanwhile.
    func keepAsOne() {
        guard let offer = keepOffer else { return }
        dismissKeepOffer()
        let tasks = offer.ids.compactMap { state.task($0) }
        guard tasks.count == offer.ids.count,
              let title = TodoMerge.title(transcript: offer.transcript, titles: tasks.map(\.title)) else { return }
        let due = TodoMerge.earliestDue(tasks.map(\.due), clock: clock)
        let merged = withAnimation(.snappy(duration: 0.3), {
            write { $0.mergeNote(ids: offer.ids, title: title, due: due) }
        }) ?? nil
        guard let merged else { return }
        TodoHaptics.soft(hapticsOn)
        arrived = [merged.id]
        announce(TodoCopy.keptAsOne)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeOut(duration: 0.4)) { self?.arrived = [] }
        }
    }

    /// Takes Keep as one away: any change to the list, a mic tap, leaving the tab, or its time running out.
    func dismissKeepOffer() {
        keepTask?.cancel()
        keepTask = nil
        guard keepOffer != nil else { return }
        withAnimation(.snappy(duration: 0.2)) { keepOffer = nil }
    }

    private func offerKeep(_ offer: KeepOffer) {
        clearNotice()
        keepTask?.cancel()
        withAnimation(.snappy(duration: 0.2)) { keepOffer = offer }
        keepTask = Task { [weak self] in
            try? await Task.sleep(for: Self.keepOfferDuration)
            guard !Task.isCancelled else { return }
            self?.dismissKeepOffer()
        }
    }

    // MARK: Writing

    @discardableResult
    private func write<T>(_ body: (inout TodoState) throws -> T) -> T? {
        do {
            let before = state.tasks
            let result = try store.update(body)
            state = result.state
            now = clockNow()
            // Any change to the list takes Keep as one away (a note just sorted offers it after its write).
            dismissKeepOffer()
            if !isDemo {
                let tasks = result.state.tasks
                // Switching between Personal and Work changes no task, so no notification needs rebuilding.
                if tasks != before {
                    Task { await TodoNotificationScheduler.shared.reschedule(tasks) }
                }
                // The Lock Screen widget shows the list in view, so it reloads when either changes.
                WidgetCenter.shared.reloadTimelines(ofKind: TodoCaptureRoute.widgetKind)
            }
            return result.value
        } catch {
            show(TodoCopy.couldNotSave)
            return nil
        }
    }

    // MARK: Notice

    private func show(_ text: String, for duration: Duration = .seconds(5)) {
        // One line under the list at a time.
        dismissKeepOffer()
        noticeTask?.cancel()
        withAnimation(.snappy(duration: 0.2)) { notice = text }
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.2)) { self?.notice = nil }
        }
    }

    private func clearNotice() {
        noticeTask?.cancel()
        notice = nil
    }

    private func announce(_ text: String) {
        guard !isDemo else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    // MARK: Demo

    /// `-screen todo-recording`: listening, words on screen, a live-looking waveform. No microphone.
    private func showDemoRecording() {
        phase = .listening
        transcript = TodoDemo.transcript
        levels = TodoDemo.levels(count: Self.levelCount)
    }
}

/// The copy of the To-do tab, in one place (no dashes, never "free", no exclamation marks).
enum TodoCopy {
    static let empty = "Tap the mic and say what you need to do"
    static let listening = "Listening"
    static let sorting = "Sorting into to-dos"
    static let tapToFinish = "Tap to finish"
    static let needsAppleIntelligence = "Saved as one to-do. Automatic sorting needs Apple Intelligence."
    static let couldNotSort = "Saved as one to-do. Tap it to edit."
    static let appleIntelligenceOff = "Saved as one to-do. Turn on Apple Intelligence in Settings to sort notes into to-dos."
    static let modelNotReady = "Saved as one to-do. Apple Intelligence is still getting ready on this iPhone."

    /// The line under the list after a note, when it was not sorted into separate to-dos.
    static func sortingNote(_ sorting: TodoSorting) -> String? {
        switch sorting {
        case .model: return nil
        case .needsAppleIntelligence: return needsAppleIntelligence
        case .appleIntelligenceOff: return appleIntelligenceOff
        case .modelNotReady: return modelNotReady
        case .couldNotSort: return couldNotSort
        }
    }
    static let microphoneOff = "Microphone access is off for Taken."
    static let speechOff = "Speech recognition is off for Taken."
    static let unavailable = "Voice to-dos need on-device speech recognition, which this iPhone does not have for your language."
    static let microphoneBusy = "The microphone is busy. Try again in a moment."
    static let nothingHeard = "Nothing heard. Tap the mic and try again."
    static let couldNotSave = "Could not save. Try again."
    static let openSettings = "Open Settings"
    static let typeInstead = "Type it instead"
    static let doneToday = "Done today"
    /// Keep as one: the button beside the line, and what VoiceOver says once it is done.
    static let keepAsOne = "Keep as one"
    static let keptAsOne = "Kept as one to-do."

    /// "3 to-dos from your note": the line beside Keep as one.
    static func fromYourNote(_ count: Int) -> String { "\(count) to-dos from your note" }

    /// Personal and Work. The Work list's empty line; Personal keeps `empty`.
    static let emptyWork = "Tap the mic and say what needs doing for work"
    /// The edit sheet's section.
    static let list = "List"

    static func emptyLine(for area: TodoArea) -> String { area == .work ? emptyWork : empty }

    /// "Listening · Work": where the note goes, before a word is said.
    static func listeningLine(into area: TodoArea) -> String { "\(TodoCopy.listening) \u{00B7} \(area.title)" }

    /// "Move to Work": the VoiceOver action, named for where the task goes.
    static func moveAction(to area: TodoArea) -> String { "Move to \(area.title)" }

    static let all: [String] = [empty, listening, sorting, tapToFinish, needsAppleIntelligence, couldNotSort,
                                appleIntelligenceOff, modelNotReady,
                                microphoneOff, speechOff, unavailable, microphoneBusy, nothingHeard, couldNotSave,
                                openSettings, typeInstead, doneToday, keepAsOne, keptAsOne, fromYourNote(3),
                                emptyWork, list]
        + TodoArea.allCases.flatMap { [$0.title, TodoCopy.listeningLine(into: $0), TodoCopy.moveAction(to: $0)] }
}

@MainActor
enum TodoHaptics {
    static func impact(_ enabled: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func light(_ enabled: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.6)
    }

    static func soft(_ enabled: Bool) {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func success(_ enabled: Bool) {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// Due-time reminders for tasks with a clock time, only when Taken may already notify (the nudge asked once).
enum TodoNotifications {
    static let prefix = "taken.todo."
    /// iOS keeps 64 pending requests per app; the nudge uses up to 14.
    static let limit = 30

    struct Plan: Equatable, Sendable {
        let identifier: String
        let fireDate: Date
        let title: String
        let body: String
    }

    /// Pure planning, unit tested: open tasks with a clock time still to come, soonest first.
    static func plan(tasks: [TodoTask], now: Date, clock: DayClock = DayClock(dayStartHour: 4)) -> [Plan] {
        tasks.compactMap { task -> (task: TodoTask, due: Date)? in
            guard !task.isDone, let due = task.dueTime, due > now else { return nil }
            return (task, due)
        }
        .sorted { $0.due < $1.due }
        .prefix(limit)
        .map { open in
            Plan(identifier: identifier(open.task.id), fireDate: open.due, title: open.task.title,
                 body: "Due \(TodoText.clockTime(open.due, clock: clock))")
        }
    }

    static func identifier(_ id: UUID) -> String { prefix + id.uuidString }

    static func isTodo(_ identifier: String) -> Bool { identifier.hasPrefix(prefix) }

    /// Delivered due-time notifications to withdraw: every one whose to-do is done or deleted.
    static func staleDelivered(_ identifiers: [String], tasks: [TodoTask]) -> [String] {
        let open = Set(tasks.filter { !$0.isDone }.map { identifier($0.id) })
        return identifiers.filter { isTodo($0) && !open.contains($0) }
    }

    /// Replaces every pending due-time notification with a fresh plan and withdraws delivered ones that no longer
    /// apply. Runs through `TodoNotificationScheduler`, one rebuild at a time.
    static func apply(tasks: [TodoTask], now: Date) async {
        let center = UNUserNotificationCenter.current()
        let ours = await center.pendingNotificationRequests().map(\.identifier).filter(isTodo)
        if !ours.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ours) }
        let delivered = await center.deliveredNotifications().map(\.request.identifier)
        let stale = staleDelivered(delivered, tasks: tasks)
        if !stale.isEmpty { center.removeDeliveredNotifications(withIdentifiers: stale) }
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: break
        default: return
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        for plan in plan(tasks: tasks, now: now, clock: DayClock(dayStartHour: 4)) {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            content.threadIdentifier = "taken.todo"
            var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: plan.fireDate)
            components.timeZone = .current
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger))
        }
    }
}

/// Rebuilds the due-time notifications one run at a time, the newest tasks winning: two changes a moment apart never
/// interleave, so a finished to-do's notification is never left scheduled. Every rebuild comes through here: a change to
/// the list, Taken coming to the front, and notifications being allowed.
actor TodoNotificationScheduler {
    static let shared = TodoNotificationScheduler { tasks in
        await TodoNotifications.apply(tasks: tasks, now: Date())
    }

    private let apply: @Sendable ([TodoTask]) async -> Void
    private var latest: [TodoTask]?
    private var running = false

    init(apply: @escaping @Sendable ([TodoTask]) async -> Void) {
        self.apply = apply
    }

    /// Asks for a rebuild with these tasks. While one runs, a newer request replaces any waiting one and runs next.
    func reschedule(_ tasks: [TodoTask]) async {
        latest = tasks
        guard !running else { return }
        running = true
        while let next = latest {
            latest = nil
            await apply(next)
        }
        running = false
    }
}

/// Time iOS gives Taken to finish a voice note after it leaves the foreground (a lock, a swipe home).
@MainActor
final class BackgroundTime {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    private init() {}

    static func begin(_ name: String) -> BackgroundTime {
        let time = BackgroundTime()
        time.identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak time] in
            time?.end()
        }
        return time
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
