import Observation
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

/// The To-do tab: one tap starts listening, the words show as they are said, a second tap finishes (30 s of quiet or 5
/// minutes stop it too), and the on-device model sorts the ramble into tasks, a long one part by part, all onto the one
/// list. Reads and writes go through `TodoStore`.
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

    /// After the stop, the part of a long note being sorted: "part 2 of 5".
    struct SortingProgress: Equatable, Sendable {
        let part: Int
        let of: Int
    }

    let store: TodoStore
    let isDemo: Bool
    let launchScreen: String?
    private let clockNow: @Sendable () -> Date

    private(set) var state: TodoState
    private(set) var phase: Phase = .idle
    /// What has been heard so far.
    private(set) var transcript = ""
    /// The latest input level from 0 to 1, for the ring around the stop button.
    private(set) var level: Double = 0
    /// A one-line note under the list ("Nothing heard...", "Saved as you said it...").
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
    /// The notes being sorted: saved as said already, kept out of the list until their tasks replace them.
    private(set) var sortingNotes: Set<UUID> = []
    /// A task the list should bring into view; the list clears it once it has scrolled there.
    var scrollTarget: UUID?
    /// The note being heard has reached 4:00: the Listening card says "1 minute left", once, and never changes it.
    private(set) var inLastMinute = false
    /// After the stop, which part of a long note is being sorted. Nil for a note of one part.
    private(set) var sortingProgress: SortingProgress?
    /// The moment the list reads from (due labels, Done today). Moves with the clock while the tab is open.
    private(set) var now: Date

    @ObservationIgnored private var capture: SpeechCapture?
    @ObservationIgnored private var sorter: NoteSorter?
    /// What sorts each note: the best this iPhone has (`TodoSorters.best`), or canned answers in tests.
    @ObservationIgnored private let makeSorter: @MainActor () -> any ChunkSorting
    @ObservationIgnored private let budget: NoteSorter.Budget
    /// The moment, zone and day-start the note is sorted against, taken at the tap.
    @ObservationIgnored private var noteContext: TodoContext?
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
    /// The parts of this note are sorted while it is said (SpeechAnalyzer).
    @ObservationIgnored private var sortsWhileListening = false
    /// The finished words last handed to the sorter.
    @ObservationIgnored private var finishedHeard = ""
    @ObservationIgnored private(set) var dayStartHour = 4
    @ObservationIgnored private(set) var hapticsOn = true
    #if DEBUG || TAKEN_INTERNAL
    /// The internal voice note log: on only in a build carrying the TakenInternalPro marker; tests give it a file.
    @ObservationIgnored var voiceLog: VoiceNoteLogStore? = InternalBuild.unlocksPro ? .shared : nil
    /// The note being recorded for it.
    @ObservationIgnored var trace: VoiceNoteTrace?
    #endif

    /// Quiet this long stops listening: no new words and nothing above the room's noise, words or not. Apple's own
    /// dictation stops after 30 s of silence; a pause to think is never the end of a note.
    nonisolated static let silenceToStop: TimeInterval = 30
    /// One note is at most this long. Tom asked for at least 5 minutes; a tap on the mic starts the next note.
    nonisolated static let longestNote: TimeInterval = 300
    /// From here the Listening card says "1 minute left", after one soft tap; nothing before it. No countdown (Tom
    /// 2026-10-21: "don't count them down").
    nonisolated static let capWarningAt: TimeInterval = 240
    /// Keep as one stays on screen this long at most.
    nonisolated static let keepOfferDuration: Duration = .seconds(10)
    /// The line after a note stopped at 5 minutes stays this long.
    nonisolated static let capNoticeDuration: Duration = .seconds(8)

    init(store: TodoStore, isDemo: Bool, launchScreen: String?, clockNow: @escaping @Sendable () -> Date,
         makeSorter: @escaping @MainActor () -> any ChunkSorting = { TodoSorters.best() },
         budget: NoteSorter.Budget = .standard) {
        self.store = store
        self.isDemo = isDemo
        self.launchScreen = launchScreen
        self.clockNow = clockNow
        self.makeSorter = makeSorter
        self.budget = budget
        self.state = store.load()
        self.now = clockNow()
    }

    /// The to-dos as launched. `-demo` and `-screen` are CI's screenshot mode, read only in Debug builds, as
    /// `AppModel.fromLaunchArguments`: a Release build always opens the real todos.json (Guideline 2.5.19).
    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> TodoModel {
        #if DEBUG
        var screen: String?
        if let index = arguments.firstIndex(of: "-screen"), index + 1 < arguments.count {
            screen = arguments[index + 1]
        }
        guard arguments.contains("-demo") else {
            return TodoModel(store: .shared, isDemo: false, launchScreen: nil, clockNow: { Date() })
        }
        // Screenshots: demo tasks in a temporary file, never the real one, at the demo's moment (the store sets' Thursday
        // under -demo-stack, as AppModel's).
        let demoNow = DemoData.referenceNow(stack: DemoStack(arguments: arguments))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("todos-demo-\(UUID().uuidString).json")
        let store = TodoStore(fileURL: url)
        let recording = screen == "todo-recording" || screen == "todo-cap"
        let seeded = screen == "todo-empty" ? TodoState() : TodoDemo.state(now: demoNow, recording: recording)
        try? store.replace(with: seeded)
        let model = TodoModel(store: store, isDemo: true, launchScreen: screen, clockNow: { demoNow })
        if recording { model.showDemoRecording() }
        return model
        #else
        return TodoModel(store: .shared, isDemo: false, launchScreen: nil, clockNow: { Date() })
        #endif
    }

    /// `-screen todo`, `todo-recording`, `todo-cap` and `todo-empty` open on the To-do tab.
    static func opensOnTodo(_ launchScreen: String?) -> Bool {
        launchScreen?.hasPrefix("todo") == true
    }

    // MARK: Reading

    var clock: DayClock { DayClock(dayStartHour: dayStartHour) }
    var isListening: Bool { phase == .listening }

    /// Tasks kept out of the list for now: the lines of each note still being sorted, saved as said until its tasks
    /// replace them.
    var hiddenTaskIDs: Set<UUID> {
        let notes = sortingNotes
        guard !notes.isEmpty else { return [] }
        return Set(state.tasks.filter { notes.contains($0.noteId) }.map(\.id))
    }

    /// The one list's open tasks, due first (`TodoOrdering`), without the notes still being sorted. Tasks a 1.1
    /// internal build put on Work are here too.
    var openTasks: [TodoTask] {
        let hidden = hiddenTaskIDs
        return state.openTasks(clock: clock).filter { !hidden.contains($0.id) }
    }

    /// Done on the day being lived, newest first.
    var doneToday: [TodoTask] {
        let hidden = hiddenTaskIDs
        return state.doneTasks(on: clock.day(for: now), clock: clock).filter { !hidden.contains($0.id) }
    }

    /// Nothing open and nothing done today: the tab shows the one line that teaches it.
    var isEmpty: Bool { openTasks.isEmpty && doneToday.isEmpty }

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

    /// The mic button: start, or finish and sort.
    func micTapped(_ app: AppModel) {
        dismissKeepOffer()
        attach(app)
        switch phase {
        case .listening:
            Task { await finishListening(.tap) }
        case .starting, .sorting:
            break
        case .idle:
            whenAllowed(app) { [weak self] in
                guard let self else { return }
                Task { await self.startListening() }
            }
        }
    }

    /// A quick capture (Siri, the control, the Lock Screen, the quick action) asked to start listening.
    func startFromRequest(_ app: AppModel) {
        dismissKeepOffer()
        attach(app)
        guard phase == .idle else { return }
        whenAllowed(app) { [weak self] in
            guard let self else { return }
            // Siri may still be handing the microphone back: a busy microphone gets two more tries.
            Task { await self.startListening(busyRetries: 2) }
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

    private func startListening(busyRetries: Int = 0) async {
        guard phase == .idle else { return }
        if isDemo {
            // CI has no microphone: the demo shows the listening state a tap or a quick capture opens on.
            showDemoRecording()
            return
        }
        setPhase(.starting)
        blocker = nil
        clearNotice()
        transcript = ""
        level = 0
        #if DEBUG || TAKEN_INTERNAL
        if voiceLog != nil { trace = VoiceNoteTrace(input: .voice) }
        #endif
        let permission = await VoicePermissions.request()
        guard permission == .granted else {
            blocker = permission == .microphoneDenied ? .microphone : .speech
            setPhase(.idle)
            dropTrace()
            return
        }
        // One sorter and one moment per note, from the tap. The model loads while the person talks, so the tasks come
        // back about a second after they stop.
        let chunkSorter = makeSorter()
        let context = TodoContext(now: clockNow(), timeZone: .current, dayStartHour: dayStartHour)
        noteContext = context
        sorter = makeNoteSorter(chunkSorter, context: context)
        Task.detached(priority: .userInitiated) { await chunkSorter.prepare() }
        let capture = SpeechCapture()
        do {
            try await capture.start(locale: .current)
        } catch SpeechCaptureError.unavailable {
            sorter = nil
            noteContext = nil
            blocker = .unavailable
            setPhase(.idle)
            dropTrace()
            return
        } catch {
            // A call or another app has the microphone.
            sorter = nil
            noteContext = nil
            setPhase(.idle)
            dropTrace()
            if busyRetries > 0 {
                try? await Task.sleep(for: .milliseconds(700))
                await startListening(busyRetries: busyRetries - 1)
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
        inLastMinute = false
        finishedHeard = ""
        sortsWhileListening = NoteSorter.sortsWhileListening && capture.engine == .analyzer
        setPhase(.listening)
        #if DEBUG || TAKEN_INTERNAL
        trace?.listening(context: context, capture: capture)
        #endif
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
                let now = Date()
                self.tick(now: now)
                if let reason = TodoModel.shouldStop(now: now, startedAt: self.startedAt, lastVoiceAt: self.lastVoiceAt) {
                    // In a task of its own: finishing cancels this one, and in a cancelled task every wait of the stop
                    // (the recogniser's last words, the time the parts get) would end at once.
                    Task { await self.finishListening(reason) }
                    return
                }
            }
        }
    }

    private func handle(_ event: SpeechCaptureEvent) {
        guard phase == .listening else { return }
        #if DEBUG || TAKEN_INTERNAL
        trace?.eventCount += 1
        #endif
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
            level = Double(max(0, min(1, (decibels + 55) / 45)))
        case .interrupted:
            Task { await finishListening(.interrupted) }
        }
    }

    /// Every few hundred milliseconds while listening: at 4:00 "1 minute left" fades in on the card with one soft tap,
    /// and on SpeechAnalyzer the finished words go to the sorter, read from the capture's lock-guarded transcript.
    private func tick(now: Date) {
        if !inLastMinute, Self.capWarning(elapsed: now.timeIntervalSince(startedAt)) {
            withAnimation(.easeIn(duration: 0.4)) { inLastMinute = true }
            // A tap only: no sound and no VoiceOver speech, the microphone is on.
            TodoHaptics.soft(hapticsOn)
        }
        guard sortsWhileListening, let capture, let sorter else { return }
        let finished = capture.finishedText()
        guard finished != finishedHeard else { return }
        finishedHeard = finished
        Task { await sorter.listen(finished: finished) }
    }

    /// A tap finishes a note. Listening also stops after `silenceToStop` of quiet, words or not (a quiet stop with no
    /// words says "Nothing heard"), and at `longestNote`.
    nonisolated static func shouldStop(now: Date, startedAt: Date, lastVoiceAt: Date) -> TodoStopReason? {
        if now.timeIntervalSince(startedAt) >= longestNote { return .cap }
        if now.timeIntervalSince(lastVoiceAt) >= silenceToStop { return .quiet }
        return nil
    }

    /// From 4:00 the card says "1 minute left".
    nonisolated static func capWarning(elapsed: TimeInterval) -> Bool { elapsed >= capWarningAt }

    /// The screen stays on only while a note is starting or being heard, and never in the demo.
    nonisolated static func keepsScreenOn(phase: Phase, isDemo: Bool) -> Bool {
        !isDemo && (phase == .starting || phase == .listening)
    }

    /// Stops listening and sorts what was said. Locking the phone or leaving Taken mid-note lands here too, so iOS is
    /// asked for the time to finish: the words are saved the moment they are known, sorted or not.
    func finishListening(_ reason: TodoStopReason = .tap) async {
        guard phase == .listening, let capture else { return }
        setPhase(.sorting)
        watchTask?.cancel()
        inLastMinute = false
        TodoHaptics.light(hapticsOn)
        let background = BackgroundTime.begin("Saving a voice note")
        defer { background.end() }
        let live = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        #if DEBUG || TAKEN_INTERNAL
        trace?.stopped(reason, lastVoice: lastVoiceAt.timeIntervalSince(startedAt), words: wordCount)
        #endif
        let finalText = await capture.finish()
        eventsTask?.cancel()
        self.capture = nil
        let heard = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = heard.isEmpty ? live : heard
        #if DEBUG || TAKEN_INTERNAL
        trace?.heard(live: live, final: heard, speech: capture.diagnostics())
        #endif
        guard !words.isEmpty else {
            sorter = nil
            noteContext = nil
            transcript = ""
            setPhase(.idle)
            show(TodoCopy.nothingHeard)
            saveTrace()
            dropTrace()
            return
        }
        transcript = words
        await save(note: words, stoppedAtCap: reason == .cap)
    }

    /// Typed instead of said (no microphone, or no on-device speech): the same sorting, the same Pro rule, onto the
    /// one list.
    func submitTyped(_ text: String, app: AppModel) {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty, phase == .idle else { return }
        dismissKeepOffer()
        attach(app)
        whenAllowed(app) { [weak self] in
            guard let self, self.phase == .idle else { return }
            self.setPhase(.sorting)
            self.transcript = words
            let chunkSorter = self.makeSorter()
            let context = TodoContext(now: self.clockNow(), timeZone: .current, dayStartHour: self.dayStartHour)
            self.noteContext = context
            self.sorter = self.makeNoteSorter(chunkSorter, context: context)
            #if DEBUG || TAKEN_INTERNAL
            if self.voiceLog != nil {
                self.trace = VoiceNoteTrace(input: .typed)
                self.trace?.typed(words, context: context)
            }
            #endif
            Task.detached(priority: .userInitiated) { await chunkSorter.prepare() }
            Task {
                let background = BackgroundTime.begin("Saving typed to-dos")
                defer { background.end() }
                await self.save(note: words, stoppedAtCap: false)
            }
        }
    }

    /// Saves a finished note onto the one list and sorts it (the stop and typing come here; tests call it to stand in
    /// for a note that stopped at 5 minutes, which needs a microphone).
    func save(note words: String, stoppedAtCap: Bool) async {
        let context = noteContext ?? TodoContext(now: clockNow(), timeZone: .current, dayStartHour: dayStartHour)
        let sorter = self.sorter ?? makeNoteSorter(makeSorter(), context: context)
        self.sorter = nil
        noteContext = nil
        // Saved at once as said, out of sight, so nothing said is lost if iOS ends Taken before the model answers. The
        // sorted tasks replace those lines. The Lock Screen widget is not reloaded for the lines: it would show every
        // one of them, and a count of them, for up to a minute, just when a lock (the side button stops a note) has
        // left the person on the Lock Screen. It goes straight to the sorted tasks with the replace; if iOS ends Taken
        // first, the lines show at its next refresh, so no word is lost.
        let noteId = UUID()
        let saved = write(reloadsWidget: false) {
            $0.add(TodoValidation.asSaid(words), noteId: noteId, at: clockNow())
        } ?? []
        if !saved.isEmpty { sortingNotes.insert(noteId) }
        saveTrace()
        let parts = await sorter.finish(note: words)
        let note = TodoValidation.assemble(note: words, parts: parts, context: context)
        let added = withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { () -> [TodoTask] in
            defer { sortingNotes.remove(noteId) }
            if !saved.isEmpty {
                return write { $0.replaceNote(noteId: noteId, saved: saved, with: note.drafts, at: clockNow()) } ?? saved
            }
            return write { $0.add(note.drafts, noteId: noteId, at: clockNow()) } ?? []
        }
        transcript = ""
        sortingProgress = nil
        setPhase(.idle)
        #if DEBUG || TAKEN_INTERNAL
        trace?.sorted(parts, drafts: note, saved: added, clock: clock)
        saveTrace()
        if let trace, let voiceLog { VoiceNoteTrace.countTokens(of: trace, into: voiceLog) }
        dropTrace()
        #endif
        guard !added.isEmpty else { return }
        arrived = Set(added.map(\.id))
        scrollTarget = added.first?.id
        TodoHaptics.success(hapticsOn)
        announce(added.count == 1 ? "1 to-do added: \(added[0].title)." : "\(added.count) to-dos added.")
        // One line under the list: the 5-minute stop first, then Keep as one (a short note the model split), then how
        // the note was saved when the model did not sort all of it.
        if stoppedAtCap {
            show(TodoCopy.stoppedAtCap, for: Self.capNoticeDuration)
        } else if note.keepable {
            offerKeep(KeepOffer(noteId: added[0].noteId, ids: added.map(\.id), transcript: words))
        } else if let line = TodoCopy.sortingNote(note.sorting) {
            show(line, for: .seconds(8))
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(.easeOut(duration: 0.4)) { self?.arrived = [] }
        }
    }

    private func makeNoteSorter(_ chunkSorter: any ChunkSorting, context: TodoContext) -> NoteSorter {
        NoteSorter(sorter: chunkSorter, context: context, budget: budget) { [weak self] part, total in
            Task { @MainActor in
                guard let self, self.phase == .sorting else { return }
                self.sortingProgress = total > 1 ? SortingProgress(part: part, of: total) : nil
            }
        }
    }

    /// Stops listening and keeps what was said (the app went to the background mid-note). The background time is asked
    /// for here, before the app can be suspended, and held until the note is saved.
    func stopIfListening() {
        guard phase == .listening else { return }
        let background = BackgroundTime.begin("Saving a voice note")
        Task {
            await finishListening(.leftApp)
            background.end()
        }
    }

    /// Every phase change. The screen stays on only while a note is starting or being heard: locking the phone ends
    /// listening, because speech recognition does not run in the background (Apple DTS, forum 53784), so Auto-Lock
    /// would cut a monologue short. Every way out of listening comes through here, so it never stays on after a note,
    /// and it is on for 5 minutes at most.
    /// https://developer.apple.com/forums/thread/53784
    /// https://developer.apple.com/documentation/uikit/uiapplication/isidletimerdisabled
    private func setPhase(_ next: Phase) {
        phase = next
        guard !isDemo else { return }
        let keepOn = Self.keepsScreenOn(phase: next, isDemo: isDemo)
        if UIApplication.shared.isIdleTimerDisabled != keepOn { UIApplication.shared.isIdleTimerDisabled = keepOn }
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

    /// The edit sheet: the words, and when it is due.
    func edit(_ id: UUID, title: String, due: TodoDue?) {
        withAnimation(.snappy(duration: 0.25)) {
            _ = write { $0.update(id, title: title, due: due) }
        }
    }

    /// A tapped due-time notification: the list scrolls to its task and washes it for a moment. Left alone while a note
    /// is heard or sorted.
    func reveal(_ id: UUID) {
        refresh()
        guard phase == .idle, state.task(id) != nil else { return }
        scrollTarget = id
        arrived = [id]
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard let self, self.arrived == [id] else { return }
            withAnimation(.easeOut(duration: 0.4)) { self.arrived = [] }
        }
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

    /// Settings > Erase all data: the tasks go too, and the internal voice note log. The first free note stays used.
    func eraseAll() {
        write { $0.eraseAll() }
        #if DEBUG || TAKEN_INTERNAL
        // A note still being sorted keeps no record: its save after the sort would write the file back.
        dropTrace()
        (voiceLog ?? .shared).erase()
        #endif
    }

    // MARK: Keep as one

    /// The note's tasks become one task again: the words said for a short note, without filler or the day and time
    /// (otherwise the titles joined), the earliest due date, the same note. Nothing changes when one of them was done or
    /// deleted meanwhile.
    func keepAsOne() {
        guard let offer = keepOffer else { return }
        dismissKeepOffer()
        let tasks = offer.ids.compactMap { state.task($0) }
        let due = TodoMerge.earliestDue(tasks.map(\.due), clock: clock)
        guard tasks.count == offer.ids.count,
              let title = TodoMerge.title(transcript: offer.transcript, titles: tasks.map(\.title), hasDue: due != nil)
        else { return }
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

    /// Every change to todos.json goes through here: the file is read, changed and written under coordination, and the
    /// list, notifications and widget follow (the widget not for a note's lines saved as said while it is sorted). Nil
    /// when it could not be saved (the line under the list says so).
    @discardableResult
    func write<T>(reloadsWidget: Bool = true, _ body: (inout TodoState) throws -> T) -> T? {
        do {
            let before = state.tasks
            let result = try store.update(body)
            state = result.state
            now = clockNow()
            // Any change to the list takes Keep as one away (a note just sorted offers it after its write).
            dismissKeepOffer()
            if !isDemo {
                let tasks = result.state.tasks
                // A write that changed no task needs no notification rebuilt.
                if tasks != before {
                    Task { await TodoNotificationScheduler.shared.reschedule(tasks) }
                }
                // The Lock Screen widget reads the file, so it reloads on every write.
                if reloadsWidget { WidgetCenter.shared.reloadTimelines(ofKind: TodoCaptureRoute.widgetKind) }
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

    /// Says `text` to VoiceOver, never in the demo. Not for use while a note is heard: the microphone would hear it.
    func announce(_ text: String) {
        guard !isDemo else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    // MARK: Voice note log

    /// Writes the note's record now (at the stop, and again once it is saved), so a kill mid-sort still keeps the words.
    private func saveTrace() {
        #if DEBUG || TAKEN_INTERNAL
        if let trace { voiceLog?.save(trace) }
        #endif
    }

    private func dropTrace() {
        #if DEBUG || TAKEN_INTERNAL
        trace = nil
        #endif
    }

    // MARK: Demo

    /// `-screen todo-recording` and `todo-cap`: listening, words on screen and the ring at a speaking level; `todo-cap`
    /// is a note past 4:00, with "1 minute left". No microphone.
    private func showDemoRecording() {
        setPhase(.listening)
        transcript = TodoDemo.transcript
        level = TodoDemo.level
        inLastMinute = launchScreen == "todo-cap"
    }
}

/// Why a note stopped listening, for the 5-minute line and the internal voice note log.
enum TodoStopReason: String, Codable, Sendable {
    case tap
    case quiet = "quiet 30 s"
    case cap = "5 minutes"
    /// A call, Siri or a route change took the microphone.
    case interrupted
    /// Taken went to the background: a lock, a swipe home.
    case leftApp = "left the app"
}

/// The copy of the To-do tab, in one place (no dashes, never "free", no exclamation marks).
enum TodoCopy {
    static let empty = "Tap the mic and say what you need to do"
    static let listening = "Listening"
    static let sorting = "Sorting into to-dos"
    static let tapToFinish = "Tap to finish"
    /// The Listening card before a word is said.
    static let sayIt = "Say what you need to do"
    static let needsAppleIntelligence = "Saved as you said it. Automatic sorting needs Apple Intelligence."
    static let appleIntelligenceOff = "Saved as you said it. Turn on Apple Intelligence in Settings to sort notes into to-dos."
    static let modelNotReady = "Saved as you said it. Apple Intelligence is still getting ready on this iPhone."
    /// The model could not sort any of the note in time.
    static let allUnsorted = "Saved as you said it, one line per sentence. Tap one to edit."
    /// It sorted some parts of a long note; the rest is saved as said.
    static let partUnsorted = "Part of your note was saved as you said it."
    static let stoppedAtCap = "Stopped at 5 minutes. Tap the mic to keep going."

    /// The line under the list after a note, when it was not all sorted into separate to-dos.
    static func sortingNote(_ sorting: TodoSorting) -> String? {
        switch sorting {
        case .model: return nil
        case .partlySorted: return partUnsorted
        case .needsAppleIntelligence: return needsAppleIntelligence
        case .appleIntelligenceOff: return appleIntelligenceOff
        case .modelNotReady: return modelNotReady
        case .couldNotSort: return allUnsorted
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
    /// Keep as one: the button beside the line, and what VoiceOver says once it is done.
    static let keepAsOne = "Keep as one"
    static let keptAsOne = "Kept as one to-do."

    /// "3 to-dos from your note": the line beside Keep as one.
    static func fromYourNote(_ count: Int) -> String { "\(count) to-dos from your note" }

    /// The label over the tasks done on the day being lived.
    static let doneToday = "Done today"

    /// "3 open, 2 done today", "3 open", "0 open, 2 done today": the line under the title, as before 1.1's lists. Nil
    /// with nothing open and nothing done today, when the tab shows the line that teaches it instead.
    static func summary(open: Int, doneToday: Int) -> String? {
        guard open > 0 || doneToday > 0 else { return nil }
        return doneToday > 0 ? "\(open) open, \(doneToday) done today" : "\(open) open"
    }

    /// From 4:00 of a 5-minute note, on the Listening card where the waveform was: said once, never counted down.
    static let oneMinuteLeft = "1 minute left"

    /// "part 2 of 5": a long note being sorted after the stop, beside "Sorting into to-dos".
    static func part(_ part: Int, of total: Int) -> String { "part \(part) of \(total)" }

    static let all: [String] = [empty, listening, sorting, tapToFinish, sayIt, needsAppleIntelligence,
                                appleIntelligenceOff, modelNotReady, allUnsorted, partUnsorted, stoppedAtCap,
                                microphoneOff, speechOff, unavailable, microphoneBusy, nothingHeard, couldNotSave,
                                openSettings, typeInstead, keepAsOne, keptAsOne, fromYourNote(3), doneToday,
                                oneMinuteLeft, part(2, of: 5)]
        + [summary(open: 3, doneToday: 2), summary(open: 3, doneToday: 0), summary(open: 0, doneToday: 2)].compactMap { $0 }
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

    /// The to-do a due-time notification is for, or nil for any other identifier.
    static func taskID(_ identifier: String) -> UUID? {
        guard isTodo(identifier) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(prefix.count)))
    }

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
