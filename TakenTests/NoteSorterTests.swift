import XCTest
@testable import Taken

/// Sorting a long note part by part (NoteSorter, SPEC 3.10): in order, one part at a time, each in its own session; a
/// part past its time or failing is saved as said while the others keep their tasks; a part too big for the window is
/// halved once; the time after the stop holds; a task said in two parts is saved once. A fake sorter with canned answers
/// and delays stands in for the on-device model, with every time scaled down.
final class NoteSorterTests: XCTestCase {
    /// What the fake sorter was asked, in order, and how many at once.
    private actor Calls {
        private(set) var parts: [Int] = []
        private(set) var prompts: [String] = []
        private(set) var mostAtOnce = 0
        private var running = 0

        func begin(_ part: TodoChunk, _ prompt: String) {
            parts.append(part.index)
            prompts.append(prompt)
            running += 1
            mostAtOnce = max(mostAtOnce, running)
        }

        func end() {
            running -= 1
        }
    }

    private struct Fake: ChunkSorting {
        var unavailable: TodoSorting?
        let calls: Calls
        var delay: @Sendable (TodoChunk) -> Duration = { _ in .milliseconds(10) }
        var failure: @Sendable (TodoChunk) -> (any Error)? = { _ in nil }
        var answers: @Sendable (TodoChunk) -> [RawTodo] = NoteSorterTests.calls

        func prepare() async {}

        func answer(chunk: TodoChunk, prompt: String) async throws -> [RawTodo] {
            await calls.begin(chunk, prompt)
            try? await Task.sleep(for: delay(chunk))
            await calls.end()
            if let error = failure(chunk) { throw error }
            return answers(chunk)
        }
    }

    /// A good model: one task for each "call <name>" in the part.
    private static let calls: @Sendable (TodoChunk) -> [RawTodo] = { chunk in
        let words = SpokenNote(chunk.text).words
        return words.indices.compactMap { index -> RawTodo? in
            guard words[index].key == "call", index + 1 < words.count else { return nil }
            let name = words[index + 1].surface
            return RawTodo(spoken: "call \(name)", title: "Call \(name)")
        }
    }

    /// Twelve sentences of twenty words, one call each: six parts of 40 words.
    private let note = (0..<12)
        .map { "Please call person\($0) about the thing number \($0) today, and then there are a few more words to fill it." }
        .joined(separator: " ")
    private let context = TodoEval.context
    /// The real rules at a twentieth of the time: 1.5 s a part while listening, 0.5 s a 40-word part after the stop.
    private let budget = NoteSorter.Budget.standard.scaled(0.05)

    private func isSorted(_ part: SortedChunk) -> Bool {
        if case .model = part.outcome { return true }
        return false
    }

    func testThePartsAreSortedInOrderOneAtATimeEachWithItsOwnPrompt() async {
        let calls = Calls()
        let sorter = NoteSorter(sorter: Fake(calls: calls), context: context, budget: budget)
        let parts = TodoChunker.chunks(text: note, final: true)
        XCTAssertEqual(parts.count, 6)
        // While listening the closed parts are sorted; at the stop only the rest is left.
        await sorter.listen(finished: note)
        let sorted = await sorter.finish(note: note)
        let order = await calls.parts
        let most = await calls.mostAtOnce
        XCTAssertEqual(order, Array(0..<6), "in the order said, each once")
        XCTAssertEqual(most, 1, "never two at once")
        XCTAssertTrue(sorted.allSatisfy(isSorted))
        let prompts = await calls.prompts
        XCTAssertTrue(prompts[0].contains("Voice note, part 1: \"Please call person0"), prompts[0])
        XCTAssertTrue(prompts[1].contains("Voice note, part 2: \""), prompts[1])
        XCTAssertFalse(prompts[1].contains("Call person0"), "the tasks of earlier parts are never sent")

        let saved = TodoValidation.assemble(note: note, parts: sorted, context: context)
        XCTAssertEqual(saved.drafts.map(\.title), (0..<12).map { "Call person\($0)" })
        XCTAssertEqual(saved.sorting, .model)
        XCTAssertFalse(saved.keepable, "Keep as one is for a note of one part")
    }

    func testAPartPastItsTimeIsSavedAsSaidAndTheOthersKeepTheirTasks() async {
        let fake = Fake(calls: Calls(), delay: { $0.index == 1 ? .seconds(10) : .milliseconds(10) })
        let sorter = NoteSorter(sorter: fake, context: context, budget: budget)
        let started = Date()
        let sorted = await sorter.finish(note: note)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3.5, "a hung part never holds the note")
        XCTAssertEqual(sorted.map { $0.outcome == .timedOut }, [false, true, false, false, false, false])
        let saved = TodoValidation.assemble(note: note, parts: sorted, context: context)
        XCTAssertEqual(saved.sorting, .partlySorted)
        // Part 2's words are there, as said, in their place.
        let titles = saved.drafts.map(\.title)
        XCTAssertEqual(Array(titles.prefix(2)), ["Call person0", "Call person1"])
        XCTAssertTrue(titles[2].hasPrefix("Please call person2 about the thing number 2 today"), titles[2])
        let kept = Set(saved.drafts.flatMap { SpokenNote.tokens(of: $0.title) })
        let said = Set(SpokenNote(sorted[1].chunk.text).tokens).subtracting(["please", "and", "then"])
        XCTAssertTrue(said.isSubset(of: kept), "every word of the late part: \(said.subtracting(kept))")
    }

    func testAPartTooBigForTheWindowIsHalvedOnce() async {
        let calls = Calls()
        let fake = Fake(calls: calls, failure: { $0.index == 0 && $0.cut != .split ? ChunkSortError.contextExceeded : nil })
        let sorted = await NoteSorter(sorter: fake, context: context, budget: budget).finish(note: note)
        XCTAssertEqual(sorted.filter { $0.chunk.cut == .split }.count, 2, "two halves, each in a new session")
        XCTAssertTrue(sorted.allSatisfy(isSorted))
        XCTAssertEqual(TodoValidation.assemble(note: note, parts: sorted, context: context).drafts.count, 12)

        let always = Fake(calls: Calls(), failure: { $0.index == 0 ? ChunkSortError.contextExceeded : nil })
        let halved = await NoteSorter(sorter: always, context: context, budget: budget).finish(note: note)
        XCTAssertEqual(halved.filter { $0.chunk.cut == .split }.count, 2, "halved once, never again")
        XCTAssertFalse(halved.filter { $0.chunk.index == 0 }.contains(where: isSorted))
    }

    func testAnErrorSendsOnlyThatPartToLines() async {
        struct Refusal: Error {}
        let fake = Fake(calls: Calls(), failure: { $0.index == 2 ? Refusal() : nil })
        let sorted = await NoteSorter(sorter: fake, context: context, budget: budget).finish(note: note)
        XCTAssertFalse(isSorted(sorted[2]))
        XCTAssertEqual(sorted.filter(isSorted).count, 5)
    }

    func testTheTimeAfterTheStopHoldsForTheWholeNote() async {
        let fake = Fake(calls: Calls(), delay: { _ in .milliseconds(400) })
        let total = budget.total(remaining: 6)
        let started = Date()
        let sorted = await NoteSorter(sorter: fake, context: context, budget: budget).finish(note: note)
        let took = Date().timeIntervalSince(started)
        let limit = Double(total.components.seconds) + Double(total.components.attoseconds) / 1e18
        XCTAssertLessThan(took, limit + 0.6, "\(took) s for a budget of \(limit) s")
        XCTAssertTrue(sorted.contains { $0.outcome == .timedOut }, "the parts past the budget are saved as said")
        XCTAssertTrue(isSorted(sorted[0]))
        XCTAssertEqual(NoteSorter.Budget.standard.total(remaining: 1), .seconds(20), "at least 20 s")
        XCTAssertEqual(NoteSorter.Budget.standard.total(remaining: 5), .seconds(30), "6 s a part")
        XCTAssertEqual(NoteSorter.Budget.standard.total(remaining: 15), .seconds(60), "at most 60 s")
        XCTAssertEqual(NoteSorter.Budget.standard.afterStop(words: 40), .seconds(10), "4 s and 0.15 s a word")
        XCTAssertEqual(NoteSorter.Budget.standard.afterStop(words: 80), .seconds(15), "at most 15 s")
    }

    func testATaskSaidInTwoPartsIsSavedOnce() async {
        // "call person0" said again in the last part: two good answers, one to-do.
        let repeated = note + " Please call person0 about the thing number 0 today, and then there are a few more words."
        let sorted = await NoteSorter(sorter: Fake(calls: Calls()), context: context, budget: budget).finish(note: repeated)
        let saved = TodoValidation.assemble(note: repeated, parts: sorted, context: context)
        XCTAssertEqual(saved.drafts.map(\.title), (0..<12).map { "Call person\($0)" })

        // A task copied into a part that never said it is not placed there, so it is not saved twice either.
        let copied = Fake(calls: Calls(), answers: { _ in [RawTodo(spoken: "call person0", title: "Call person0")] })
        let everywhere = await NoteSorter(sorter: copied, context: context, budget: budget).finish(note: note)
        XCTAssertEqual(TodoValidation.assemble(note: note, parts: everywhere, context: context).drafts.map(\.title),
                       ["Call person0"])
    }

    func testNoModelSavesTheNoteAsSaid() async {
        let fake = Fake(unavailable: .needsAppleIntelligence, calls: Calls())
        let words = "Call the dentist. Buy milk."
        let sorted = await NoteSorter(sorter: fake, context: context, budget: budget).finish(note: words)
        let saved = TodoValidation.assemble(note: words, parts: sorted, context: context)
        XCTAssertEqual(saved.drafts.map(\.title), ["Call the dentist", "Buy milk"])
        XCTAssertEqual(saved.sorting, .needsAppleIntelligence)
        let asked = await fake.calls.parts
        XCTAssertTrue(asked.isEmpty, "the model is never asked")
        let fallback = FallbackSorter(reason: .appleIntelligenceOff)
        XCTAssertEqual(fallback.unavailable, .appleIntelligenceOff)
    }

    func testOneShortPartSplitByTheModelMayBeKeptAsOne() async {
        let fake = Fake(calls: Calls(), answers: { _ in
            [RawTodo(spoken: "call the dentist", title: "Call the dentist"), RawTodo(spoken: "buy milk", title: "Buy milk")]
        })
        let words = "call the dentist and buy milk"
        let sorted = await NoteSorter(sorter: fake, context: context, budget: budget).finish(note: words)
        let prompt = sorted.first?.prompt ?? ""
        XCTAssertTrue(prompt.hasSuffix("Voice note: \"call the dentist and buy milk\""), "one part: no part number")
        let saved = TodoValidation.assemble(note: words, parts: sorted, context: context)
        XCTAssertEqual(saved.drafts.map(\.title), ["Call the dentist", "Buy milk"])
        XCTAssertTrue(saved.keepable)
    }

    /// The 30 s quiet stop and the 5-minute stop finish the note from the listening watch's own task, which finishing
    /// cancels. In a cancelled task every `Task.sleep` throws at once, so the stop's wait must not be a loop of sleeps:
    /// it would spin for the whole budget. It waits, and uses almost no CPU while it does.
    func testTheStopFromACancelledTaskWaitsForTheModelWithoutSpinning() async {
        let fake = Fake(calls: Calls(), delay: { _ in .milliseconds(400) })
        let sorter = NoteSorter(sorter: fake, context: context, budget: budget)
        let before = Self.cpuSeconds()
        let stop = Task { () -> [SortedChunk] in
            withUnsafeCurrentTask { $0?.cancel() }
            return await sorter.finish(note: "call the dentist and buy milk")
        }
        let sorted = await stop.value
        let used = Self.cpuSeconds() - before
        XCTAssertTrue(sorted.allSatisfy(isSorted), "\(sorted.map(\.outcome))")
        XCTAssertLessThan(used, 0.15, "\(used) s of CPU while waiting 0.4 s for the model")

        let listened = NoteSorter(sorter: Fake(calls: Calls()), context: context, budget: budget)
        await listened.listen(finished: note)
        let settle = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await listened.settle()
        }
        await settle.value
        let parts = await listened.finish(note: note)
        XCTAssertGreaterThanOrEqual(parts.filter(isSorted).count, 5, "settle waited for the parts said so far")
    }

    /// A part still being sorted at the stop (SpeechAnalyzer sorts while the person talks) gets a part's time after
    /// the stop like any other, not the 30 s it had while listening, so the part said last is still sent.
    func testAPartStillBeingSortedAtTheStopGetsThePostStopTime() async {
        let opening = (0..<2)
            .map { "Please call person\($0) about the thing number \($0) today, and then there are a few more words to fill it." }
            .joined(separator: " ")
        let words = opening + " Please call the dentist."
        let calls = Calls()
        let fake = Fake(calls: calls, delay: { $0.index == 0 ? .seconds(10) : .milliseconds(10) })
        let sorter = NoteSorter(sorter: fake, context: context, budget: budget)
        await sorter.listen(finished: words)
        let deadline = Date().addingTimeInterval(2)
        while await calls.parts.isEmpty, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        let started = Date()
        let sorted = await sorter.finish(note: words)
        let took = Date().timeIntervalSince(started)
        XCTAssertEqual(sorted.count, 2)
        XCTAssertEqual(sorted.first?.outcome, .timedOut, "the hung part is saved as said")
        XCTAssertTrue(sorted.count == 2 && isSorted(sorted[1]), "the part said last is sorted: \(sorted.map(\.outcome))")
        // A 40-word part gets 0.5 s after the stop here (10 s at full scale), out of the note's 1 s (20 s).
        XCTAssertLessThan(took, 0.95, "\(took) s")
    }

    /// A short note is one part, and nothing waits behind the last part, so it has the note's whole time after the
    /// stop (20 s), not a part's own 5 to 10 s: an everyday note of a few tasks keeps its times.
    func testTheLastPartHasTheRestOfTheNotesTime() async {
        let words = "I should send messages to my LinkedIn ICPs"
        let answer = [RawTodo(spoken: "send messages to my linkedin icps", title: "Send messages to my LinkedIn ICPs")]
        // 8 s at full scale, past this 8-word part's own 5.2 s.
        let fake = Fake(calls: Calls(), delay: { _ in .milliseconds(400) }, answers: { _ in answer })
        let sorted = await NoteSorter(sorter: fake, context: context, budget: budget).finish(note: words)
        XCTAssertEqual(sorted.count, 1)
        XCTAssertTrue(sorted.allSatisfy(isSorted), "\(sorted.map(\.outcome))")
        let saved = TodoValidation.assemble(note: words, parts: sorted, context: context)
        XCTAssertEqual(saved.drafts.map(\.title), ["Send messages to my LinkedIn ICPs"])
    }

    /// User and system CPU time of this process, in seconds.
    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
        return user + system
    }

    func testATranscriptThatChangedUnderItsPartsIsSortedAgain() async {
        let calls = Calls()
        let sorter = NoteSorter(sorter: Fake(calls: calls), context: context, budget: budget)
        await sorter.listen(finished: note)
        await sorter.settle()
        let changed = "Call Sam about the deck. " + note
        let sorted = await sorter.finish(note: changed)
        let covered = sorted.map(\.chunk.wordRange)
        XCTAssertEqual(covered.first?.lowerBound, 0)
        XCTAssertEqual(covered.last?.upperBound, SpokenNote(changed).words.count, "the new words, every one")
        let saved = TodoValidation.assemble(note: changed, parts: sorted, context: context)
        XCTAssertEqual(saved.drafts.first?.title, "Call Sam")
    }
}
