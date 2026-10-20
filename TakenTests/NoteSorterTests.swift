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
        let fake = Fake(calls: Calls(), answers: { _ in [RawTodo(spoken: "call person0", title: "Call person0")] })
        let sorted = await NoteSorter(sorter: fake, context: context, budget: budget).finish(note: note)
        let saved = TodoValidation.assemble(note: note, parts: sorted, context: context)
        XCTAssertEqual(saved.drafts.map(\.title), ["Call person0"], "only part 1 said it; the others' copies are dropped")
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
