import XCTest
@testable import Taken

/// A long note in parts (TodoChunker, SPEC 3.10): cut at sentence ends after 40 words, never before a word that carries
/// on what came before or right after a day header, forced at 80 words at the latest comma or "and", carrying the day
/// a cut sentence started with, a short tail joined to the part before, and every word in exactly one part.
final class TodoChunkingTests: XCTestCase {
    /// `count` sentences of `words` distinct words each.
    private func sentences(_ count: Int, words: Int, prefix: String = "w") -> String {
        (0..<count).map { s in (0..<words).map { "\(prefix)\(s)x\($0)" }.joined(separator: " ") + "." }
            .joined(separator: " ")
    }

    func testNoCutBeforeFortyWordsThenAtTheFirstSentenceEnd() {
        XCTAssertTrue(TodoChunker.chunks(text: sentences(3, words: 10), final: false).isEmpty, "30 words: nothing closed")
        XCTAssertEqual(TodoChunker.chunks(text: sentences(3, words: 10), final: true).map(\.wordCount), [30],
                       "at the stop the rest is one part")
        let parts = TodoChunker.chunks(text: sentences(6, words: 10), final: true)
        XCTAssertEqual(parts.map(\.wordCount), [40, 20])
        XCTAssertEqual(parts.map(\.cut), [.sentence, .end])
        XCTAssertEqual(parts.map(\.index), [0, 1])
        XCTAssertTrue(parts[0].text.hasSuffix("w3x9."), "the part keeps its punctuation: \(parts[0].text)")
    }

    func testNeverACutBeforeAndOrAShopOrRightAfterADayHeader() {
        let andNote = sentences(4, words: 10) + " And then the rest of the note runs on for a good few words more here. "
            + "On Amazon. Buy milk tomorrow. Call mum."
        for part in TodoChunker.chunks(text: andNote, final: true).dropFirst() {
            let first = SpokenNote(part.text).words.first?.key ?? ""
            XCTAssertFalse(TodoChunker.noCutBefore.contains(first), "a part starts on \(first): \(part.text)")
        }
        let header = sentences(3, words: 13) + " Tomorrow. Call the bank about the card and the loan. Then the rest of it."
        let parts = TodoChunker.chunks(text: header, final: true)
        XCTAssertFalse(parts.contains { $0.text.hasSuffix("Tomorrow.") }, "the header stays with its sentence")
        XCTAssertTrue(parts.contains { $0.text.contains("Tomorrow. Call the bank") })
    }

    func testAForcedCutFallsOnACommaThenASentenceEndThenWordEighty() {
        let commas = (0..<10).map { i in (0..<9).map { "f\(i)x\($0)" }.joined(separator: " ") }.joined(separator: ", ") + "."
        let atComma = TodoChunker.chunks(text: commas, final: true)
        XCTAssertEqual(atComma.first?.cut, .forced)
        XCTAssertEqual(atComma.first?.wordCount, 72, "the latest comma in the last 25 words")
        XCTAssertTrue(atComma.first?.text.hasSuffix(",") ?? false)

        // Sentence ends only before 40 words: no comma late on, so the latest full stop.
        let early = sentences(1, words: 30) + " " + (0..<70).map { "e\($0)" }.joined(separator: " ")
        XCTAssertEqual(TodoChunker.chunks(text: early, final: true).first?.wordCount, 30)
        XCTAssertEqual(TodoChunker.chunks(text: early, final: true).first?.cut, .forced)

        let plain = (0..<120).map { "p\($0)" }.joined(separator: " ")
        XCTAssertEqual(TodoChunker.chunks(text: plain, final: true).map(\.wordCount), [80, 40], "else after word 80")
    }

    func testAForcedCutInsideASentenceCarriesItsDayOrTime() {
        let note = "Today by 4 pm I need to " + (0..<100).map { "c\($0)" }.joined(separator: " ")
        let parts = TodoChunker.chunks(text: note, final: true)
        XCTAssertEqual(parts.count, 2)
        XCTAssertNil(parts[0].carried)
        XCTAssertEqual(parts[1].carried, "Today by 4 pm")
        let prompt = TodoPrompt.prompt(for: parts[1], of: parts.count, context: TodoEval.context)
        XCTAssertTrue(prompt.contains("Said just before, for the same list: \"Today by 4 pm\"."), prompt)
        XCTAssertTrue(prompt.contains("Voice note, part 2: \""), prompt)
        XCTAssertNil(TodoChunker.carriedPhrase(SpokenNote("Call the bank. Tomorrow I will"), cutBefore: 3),
                     "a cut at a sentence end carries nothing")
    }

    func testAShortTailJoinsThePartBeforeUnlessThatWasSent() {
        let note = sentences(5, words: 10) + " Short tail here now."
        XCTAssertEqual(TodoChunker.chunks(text: note, final: true).map(\.wordCount), [54], "14 words join")
        XCTAssertEqual(TodoChunker.chunks(text: note, final: true, sent: 1).map(\.wordCount), [40, 14],
                       "a part already sorted is never sent again")
    }

    func testTheWordRangesCoverANineHundredWordNoteOnceAndClosedPartsNeverChange() {
        var note = ""
        for i in 0..<900 { note += "b\(i)" + (i % 23 == 22 ? ". " : (i % 7 == 6 ? ", " : " ")) }
        let parts = TodoChunker.chunks(text: note, final: true)
        var covered = 0
        for part in parts {
            XCTAssertEqual(part.wordRange.lowerBound, covered, "contiguous")
            XCTAssertLessThanOrEqual(part.wordCount, TodoChunker.maximumWords)
            covered = part.wordRange.upperBound
        }
        XCTAssertEqual(covered, SpokenNote(note).words.count, "every word once")
        let words = Set(parts.flatMap { SpokenNote($0.text).tokens })
        XCTAssertTrue((0..<900).allSatisfy { words.contains("b\($0)") })

        // While listening, the parts closed so far are the same once more words come.
        let early = TodoChunker.chunks(text: String(note.prefix(2_000)), final: false)
        let later = TodoChunker.chunks(text: note, final: false)
        XCTAssertFalse(early.isEmpty)
        XCTAssertEqual(Array(later.prefix(early.count)), early)
    }

    func testTextModeOnATypedParagraph() {
        let typed = """
            Call the dentist about the crown and ask whether they have anything next week. Then email Sam the deck, \
            the one with the new numbers. Pick up the parcel from the post office before it goes back. Book the car in \
            for its service and remember to ask about the noise from the brakes. Order more printer ink. Text Jo about \
            Saturday. Water the plants on the balcony and the ones in the kitchen. Renew the parking permit online \
            before Friday.
            """
        let parts = TodoChunker.chunks(text: typed, final: true)
        XCTAssertEqual(parts.map(\.wordCount), [54, 27], "the first sentence end after 40 words")
        XCTAssertEqual(parts.map(\.cut), [.sentence, .end])
        XCTAssertTrue(parts.last?.text.hasPrefix("Order more printer ink.") ?? false, parts.last?.text ?? "")
    }

    func testAPartTooBigForTheWindowSplitsAtItsMiddleSentenceEnd() throws {
        let note = SpokenNote(sentences(6, words: 10))
        let first = try XCTUnwrap(TodoChunker.chunks(note: note, final: true).first)
        let halves = try XCTUnwrap(TodoChunker.split(first, note: note))
        XCTAssertEqual(halves.map(\.wordCount), [20, 20])
        XCTAssertEqual(halves.map(\.cut), [.split, .split])
        XCTAssertEqual(halves[0].wordRange.lowerBound, first.wordRange.lowerBound)
        XCTAssertEqual(halves[1].wordRange.upperBound, first.wordRange.upperBound)
    }
}
