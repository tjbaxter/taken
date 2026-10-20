import Foundation

// Sorting a voice note into to-dos, part by part (SPEC 3.10). A note is cut into parts of 40 to 80 words
// (TodoChunker) and each part is sorted on its own, in a new model session, one after another: Apple's documented
// answer for input larger than the 4,096-token window is to split it into steps, each in a new session, and assemble
// the results (TN3193). With SpeechAnalyzer (iOS 26) the parts are sorted while the person is still talking, as they
// close, so at the stop usually only the last one is waited for, as Todoist Ramble captures tasks as you speak; with
// SFSpeechRecognizer, and for typed notes, they are sorted at the stop. A part that fails or runs past its time is
// saved as said (TodoValidation.lines); the other parts keep their tasks.
// https://developer.apple.com/tutorials/data/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window.md
// https://www.producttalk.org/building-todoist-ramble-how-doist-turned-voice-braindumps-into-real-time-task-capture/

/// What sorts one part: the on-device model (`FoundationModelsExtractor`), or canned answers in tests.
protocol ChunkSorting: Sendable {
    /// Nil when the model can sort now; otherwise why not, and every part is saved as said.
    var unavailable: TodoSorting? { get }
    /// Loads the model and a first session while the person is still talking.
    func prepare() async
    /// The model's answer for one part, as it wrote it, in a session of its own.
    func answer(chunk: TodoChunk, prompt: String) async throws -> [RawTodo]
}

enum ChunkSortError: Error, Equatable, Sendable {
    /// The part and its answer did not fit in the session's context window.
    case contextExceeded
    /// The model cannot run on this iPhone now.
    case unavailable(TodoSorting)
}

/// No model on this iPhone (no Apple Intelligence, iOS 17 to 25, or it is off or still getting ready): the note is
/// saved as said, one line per sentence. Never loses a word.
struct FallbackSorter: ChunkSorting {
    let reason: TodoSorting

    init(reason: TodoSorting = .needsAppleIntelligence) {
        self.reason = reason
    }

    var unavailable: TodoSorting? { reason }

    func prepare() async {}

    func answer(chunk: TodoChunk, prompt: String) async throws -> [RawTodo] {
        throw ChunkSortError.unavailable(reason)
    }
}

/// The sorter for this iPhone: the on-device model where it can run, otherwise the fallback.
enum TodoSorters {
    @MainActor
    static func best() -> any ChunkSorting {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if let reason = FoundationModelsExtractor.unavailableReason {
                return FallbackSorter(reason: reason)
            }
            return FoundationModelsExtractor()
        }
        #endif
        return FallbackSorter()
    }
}

/// What became of one part.
enum ChunkOutcome: Hashable, Sendable {
    /// The model's tasks, before any check.
    case model([RawTodo])
    /// No answer within its time.
    case timedOut
    /// The model failed (guardrails, a refusal, decoding, an unsupported language, rate limited).
    case failed(String)
    /// No model on this iPhone.
    case unavailable(TodoSorting)
}

/// One part as it was sorted. A part the model had no room for comes back as its two halves.
struct SortedChunk: Hashable, Sendable {
    var chunk: TodoChunk
    var outcome: ChunkOutcome
    /// When it was sent, in seconds from the note's start (the tap), and how long its answer took.
    var sentAt: Double
    var seconds: Double
    /// What the model was asked, for the internal voice note log.
    var prompt: String
}

/// A note's drafts as they are saved, and how it was sorted.
struct TodoNoteDrafts: Sendable {
    var drafts: [TodoDraft]
    var sorting: TodoSorting
    /// Keep as one may be offered: one part, sorted by the model into two or more tasks.
    var keepable: Bool
}

/// One note's parts, sorted in order, one at a time. Created when listening starts with the one `TodoContext` taken at
/// the tap.
actor NoteSorter {
    /// Parts are sorted while the person talks on the SpeechAnalyzer path. One switch, so a build can sort after the stop
    /// instead if the device check shows the transcript falling behind.
    static let sortsWhileListening = true

    /// How long the parts get.
    struct Budget: Sendable {
        /// While listening, per part: only a part that hangs reaches it.
        var whileListening: Duration = .seconds(30)
        /// After the stop, per part: 4 s plus 0.15 s a word, at most 15 s.
        var base: Duration = .seconds(4)
        var perWord: Duration = .milliseconds(150)
        var perPartCap: Duration = .seconds(15)
        /// After the stop, in all: 6 s a part still to sort, at least 20 s, at most 60 s.
        var totalPerPart: Duration = .seconds(6)
        var totalFloor: Duration = .seconds(20)
        var totalCap: Duration = .seconds(60)

        static let standard = Budget()

        func afterStop(words: Int) -> Duration { min(perPartCap, base + perWord * words) }

        func total(remaining: Int) -> Duration { min(totalCap, max(totalFloor, totalPerPart * remaining)) }

        /// Every time multiplied by `factor` (tests run the same rules in less time).
        func scaled(_ factor: Double) -> Budget {
            Budget(whileListening: whileListening * factor, base: base * factor, perWord: perWord * factor,
                   perPartCap: perPartCap * factor, totalPerPart: totalPerPart * factor, totalFloor: totalFloor * factor,
                   totalCap: totalCap * factor)
        }
    }

    private let sorter: any ChunkSorting
    private let context: TodoContext
    private let budget: Budget
    private let started = ContinuousClock.now
    private let onProgress: (@Sendable (_ part: Int, _ of: Int) -> Void)?

    /// The words the parts are cut from, and their parts so far.
    private var note = SpokenNote("")
    private var heard = ""
    private var parts: [TodoChunk] = []
    /// Parts handed over and not yet started.
    private var queue: [TodoChunk] = []
    private var results: [SortedChunk] = []
    private var running = false
    /// Set at the stop: everything after it must be answered by then.
    private var deadline: ContinuousClock.Instant?
    private var closed = false
    private var total: Int?
    /// The part being asked now, and what gives up on it before its own time is up.
    private var asking: (part: TodoChunk, cutoff: Cutoff)?
    /// Callers waiting for every part handed over to be sorted (`finish`, `settle`); `drain` resumes them.
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(sorter: any ChunkSorting, context: TodoContext, budget: Budget = .standard,
         onProgress: (@Sendable (_ part: Int, _ of: Int) -> Void)? = nil) {
        self.sorter = sorter
        self.context = context
        self.budget = budget
        self.onProgress = onProgress
    }

    /// The finished transcript so far, while listening: every part it closes is sorted, in order. Read from the
    /// capture's lock-guarded transcript, never from its event stream, which may drop events.
    func listen(finished text: String) {
        guard deadline == nil, text != heard, text.hasPrefix(heard) else { return }
        heard = text
        note = SpokenNote(text)
        let closedNow = TodoChunker.chunks(note: note, final: false)
        guard closedNow.count > parts.count else { return }
        let fresh = Array(closedNow[parts.count...])
        parts += fresh
        queue += fresh
        startIfIdle()
    }

    /// The whole note, at the stop: the rest is cut into its last parts and every part not sorted yet gets its time
    /// after the stop (`Budget`), the one still being sorted from while listening too. Returns every part in the order
    /// said, each with its answer, or timed out.
    func finish(note text: String) async -> [SortedChunk] {
        let whole = SpokenNote(text)
        var begun = parts.count - queue.count
        var all = TodoChunker.chunks(note: whole, final: true, sent: begun)
        // The parts already sorted must be the note's own; a transcript that changed under them starts again.
        if !text.hasPrefix(heard) || all.count < begun || Array(all.prefix(begun)) != Array(parts.prefix(begun)) {
            results = []
            all = TodoChunker.chunks(note: whole, final: true)
            begun = 0
        }
        note = whole
        heard = text
        queue = Array(all[begun...])
        parts = all
        total = all.count
        let remaining = queue.count + (running ? 1 : 0)
        let stop = ContinuousClock.now
        let end = stop + budget.total(remaining: remaining)
        deadline = end
        if running, let current = all.first(where: { part in !results.contains { $0.chunk.index == part.index } }) {
            onProgress?(current.index + 1, all.count)
        }
        // The part being asked was given 30 s while listening; from the stop it gets a part's time after the stop, or
        // the rest of the note's when nothing waits behind it.
        if let asking {
            let cutoff = asking.cutoff
            let limit = queue.isEmpty ? end - stop : min(budget.afterStop(words: asking.part.wordCount), end - stop)
            Task {
                try? await Task.sleep(for: limit)
                cutoff.fire()
            }
        }
        startIfIdle()
        // A continuation `drain` resumes, never a loop of sleeps: the stop can come from a task that was cancelled,
        // where every `Task.sleep` throws at once and the loop would spin for the whole budget.
        await firstResult(of: { await self.sorted() }, orAfter: end - ContinuousClock.now, fallback: ())
        closed = true
        asking?.cutoff.fire()
        var answered = results
        for part in all where !answered.contains(where: { $0.chunk.index == part.index }) {
            answered.append(SortedChunk(chunk: part, outcome: .timedOut, sentAt: elapsed(), seconds: 0,
                                        prompt: TodoPrompt.prompt(for: part, of: all.count, context: context)))
        }
        return answered.sorted { $0.chunk.wordRange.lowerBound < $1.chunk.wordRange.lowerBound }
    }

    /// Waits until every part handed over so far is sorted (the eval, which runs a long ramble back to back as while
    /// talking).
    func settle() async {
        await sorted()
    }

    /// Returns once every part handed over so far is sorted, or at once when none is waiting.
    private func sorted() async {
        guard !closed, running || !queue.isEmpty else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    // MARK: Sorting

    private func startIfIdle() {
        guard !running, !closed, !queue.isEmpty else { return }
        running = true
        Task { await drain() }
    }

    private func drain() async {
        while !closed, !queue.isEmpty {
            let part = queue.removeFirst()
            if let total { onProgress?(part.index + 1, total) }
            let sorted = await sort(part)
            guard !closed else { break }
            // A transcript that changed under the parts (`finish`) drops what was sorted from the old ones.
            guard parts.contains(part) else { continue }
            results += sorted
        }
        running = false
        let done = waiting
        waiting = []
        for waiter in done { waiter.resume() }
    }

    private func sort(_ part: TodoChunk, halved: Bool = false) async -> [SortedChunk] {
        let prompt = TodoPrompt.prompt(for: part, of: total ?? parts.count + 1, context: context)
        let sentAt = elapsed()
        if let reason = sorter.unavailable {
            return [SortedChunk(chunk: part, outcome: .unavailable(reason), sentAt: sentAt, seconds: 0, prompt: prompt)]
        }
        let sorter = self.sorter
        let cutoff = Cutoff()
        asking = (part, cutoff)
        defer { asking = nil }
        let answer = await firstResult(of: { () -> Answer in
            do {
                return .tasks(try await sorter.answer(chunk: part, prompt: prompt))
            } catch ChunkSortError.contextExceeded {
                return .contextExceeded
            } catch ChunkSortError.unavailable(let reason) {
                return .unavailable(reason)
            } catch {
                return .failed(String(describing: error))
            }
        }, orAfter: limit(for: part), fallback: .timedOut, cutoff: cutoff)
        let seconds = elapsed() - sentAt
        switch answer {
        case .tasks(let tasks):
            return [SortedChunk(chunk: part, outcome: .model(tasks), sentAt: sentAt, seconds: seconds, prompt: prompt)]
        case .contextExceeded:
            // No room in one session: once, each half in a new one.
            if !halved, !closed, let halves = TodoChunker.split(part, note: note) {
                var sorted: [SortedChunk] = []
                for half in halves { sorted += await sort(half, halved: true) }
                return sorted
            }
            return [SortedChunk(chunk: part, outcome: .failed("exceededContextWindowSize"), sentAt: sentAt,
                                seconds: seconds, prompt: prompt)]
        case .unavailable(let reason):
            return [SortedChunk(chunk: part, outcome: .unavailable(reason), sentAt: sentAt, seconds: seconds, prompt: prompt)]
        case .failed(let reason):
            return [SortedChunk(chunk: part, outcome: .failed(reason), sentAt: sentAt, seconds: seconds, prompt: prompt)]
        case .timedOut:
            return [SortedChunk(chunk: part, outcome: .timedOut, sentAt: sentAt, seconds: seconds, prompt: prompt)]
        }
    }

    /// While listening, 30 s; after the stop, the part's own time, never past the note's deadline. The note's last
    /// part gets the rest of the note's time: the cap on a part keeps one that hangs from taking the time of the parts
    /// behind it, and none is, so a short note of one part has the note's 20 s, not 5 to 10 s.
    private func limit(for part: TodoChunk) -> Duration {
        guard let deadline else { return budget.whileListening }
        let left = max(.zero, deadline - ContinuousClock.now)
        if queue.isEmpty, part.wordRange.upperBound >= note.words.count { return left }
        return min(budget.afterStop(words: part.wordCount), left)
    }

    private func elapsed() -> Double {
        let gone = ContinuousClock.now - started
        return Double(gone.components.seconds) + Double(gone.components.attoseconds) / 1e18
    }

    private enum Answer: Sendable {
        case tasks([RawTodo])
        case contextExceeded
        case unavailable(TodoSorting)
        case failed(String)
        case timedOut
    }
}
