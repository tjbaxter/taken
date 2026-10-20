import XCTest
@testable import Taken

/// Every word kept on iOS 17 to 25 (RecognizerTranscript, SPEC 3.10): the on-device SFSpeechRecognizer can start over
/// after a pause and report only the new words. A start-over is told from the text, never from partial results'
/// timestamps (Apple: not accurate), the text so far is kept, and a task that ends by itself is followed by a new one
/// whose words come after.
final class RecognizerTranscriptTests: XCTestCase {
    private func heard(_ results: [String]) -> RecognizerTranscript {
        var transcript = RecognizerTranscript()
        for result in results { transcript.apply(result) }
        return transcript
    }

    func testCumulativeResultsGiveTheLastText() {
        XCTAssertEqual(heard(["Call", "Call the", "Call the dentist", "Call the dentist tomorrow"]).text,
                       "Call the dentist tomorrow")
        XCTAssertEqual(heard(["I need to call", "I need to call the dentist.", "I need to call the dentist. And buy"]).text,
                       "I need to call the dentist. And buy", "iOS 18.1 and later: one growing result")
    }

    func testAStartOverAfterAPauseKeepsBothPartsInOrder() {
        var transcript = RecognizerTranscript()
        for result in ["Call", "Call the", "Call the dentist."] { transcript.apply(result) }
        XCTAssertTrue(transcript.apply("Buy"), "a shorter result that does not continue the text started over")
        transcript.apply("Buy milk")
        transcript.apply("Buy milk and eggs")
        XCTAssertEqual(transcript.text, "Call the dentist. Buy milk and eggs")
    }

    func testAStartOverWithTheSameOpeningWordsIsCaughtOnceItGoesItsOwnWay() {
        let transcript = heard(["I need to call the dentist", "I", "I need", "I need milk", "I need milk and eggs"])
        XCTAssertEqual(transcript.text, "I need to call the dentist I need milk and eggs")
        XCTAssertEqual(heard(["Call the dentist", "Call", "Call mum"]).text, "Call the dentist Call mum",
                       "not yet seen as a start-over at the stop: both are kept, never the shorter alone")
    }

    func testRevisionsAreNotStartOvers() {
        XCTAssertEqual(heard(["Cold", "Call the", "Call the dentist to", "Call the dentist"]).text,
                       "Call the dentist to", "the end revised away: the longer text stays")
        XCTAssertEqual(heard(["I need to call the dentists at", "I need to call the dentist"]).text,
                       "I need to call the dentist", "a word revised and one dropped: the latest")
        var transcript = RecognizerTranscript()
        XCTAssertFalse(transcript.apply("Call the"))
        XCTAssertFalse(transcript.apply("Paul the dentist"), "one word changed in three carries on")
    }

    /// iOS 18.1 and later report one growing result, and may rewrite its opening words as more is heard. A longer
    /// result is never a start-over (a start-over begins again with the new words), so the old opening is not kept
    /// beside its correction.
    func testALongerResultThatRewritesTheOpeningWordsIsARevision() {
        XCTAssertEqual(heard(["Book", "Book a", "Book a table", "Look at the table for six"]).text,
                       "Look at the table for six")
        XCTAssertEqual(heard(["Send", "Send messages", "Sent message is to my LinkedIn"]).text,
                       "Sent message is to my LinkedIn")
        XCTAssertEqual(heard(["Remind", "Remind me", "Remember to call the dentist"]).text,
                       "Remember to call the dentist")
        var transcript = RecognizerTranscript()
        transcript.apply("Remind me")
        XCTAssertFalse(transcript.apply("Remember to call the dentist"), "longer: a revision, not a start-over")
        XCTAssertEqual(heard(["I need to call the dentist", "I", "I need", "I need milk", "I need milk and eggs",
                              "I need milk and eggs and bread"]).text,
                       "I need to call the dentist I need milk and eggs and bread",
                       "a start-over sharing the opening words is still caught while it is no longer")
    }

    func testARestartAfterIsFinalAppendsTheNewTasksWords() {
        var transcript = RecognizerTranscript()
        transcript.apply("Call the dentist.")
        transcript.commit()
        transcript.apply("Buy")
        transcript.apply("Buy milk.")
        XCTAssertEqual(transcript.text, "Call the dentist. Buy milk.")
        transcript.commit()
        XCTAssertEqual(transcript.text, "Call the dentist. Buy milk.", "committing twice changes nothing")
    }

    func testJoinNeverDoublesASpaceOrDropsAWord() {
        XCTAssertEqual(TranscriptBuffer.join("Call the dentist. ", "  Buy milk"), "Call the dentist. Buy milk")
        XCTAssertEqual(TranscriptBuffer.join("", "Buy milk"), "Buy milk")
        XCTAssertEqual(TranscriptBuffer.join("Call the dentist", ""), "Call the dentist")
        var transcript = RecognizerTranscript()
        transcript.apply("   ")
        XCTAssertEqual(transcript.text, "", "an empty result is nothing")
        XCTAssertEqual(RecognizerTranscript.words("Call, the DENTIST."), ["call", "the", "dentist"])
        XCTAssertEqual(RecognizerTranscript.matched(["i", "need", "milk"], ["i", "need", "to", "call"]), 2)
    }
}
