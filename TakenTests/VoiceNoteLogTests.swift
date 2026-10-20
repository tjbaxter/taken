import XCTest
@testable import Taken

/// The voice note log (internal builds only, SPEC 3.10): the newest 20 notes for 14 days, every string capped, the
/// file under 2 MB, erased with Clear and Erase all data, opened by taken://todo-log only with the TakenInternalPro
/// marker, and a note's record as plain text.
final class VoiceNoteLogTests: XCTestCase {
    private func store() -> VoiceNoteLogStore {
        VoiceNoteLogStore(fileURL: temporaryStoreURL().deletingLastPathComponent()
            .appendingPathComponent("Internal", isDirectory: true).appendingPathComponent("voice-notes.json"))
    }

    private func trace(at start: Date, words: String = "Call the dentist and buy milk") -> VoiceNoteTrace {
        var trace = VoiceNoteTrace(input: .voice, list: .work, at: start)
        trace.finalTranscript = words
        trace.liveTranscript = words
        return trace
    }

    func testTheLogKeepsTheNewestTwentyNotesForFourteenDays() {
        let now = at(2026, 10, 20, 18)
        let notes = (0..<25).map { trace(at: now.addingTimeInterval(TimeInterval(-$0 * 3_600))) }
        let kept = VoiceNoteLogStore.trimmed(notes.shuffled(), now: now)
        XCTAssertEqual(kept.count, VoiceNoteLogStore.maxNotes)
        XCTAssertEqual(kept.map(\.id), Array(notes.prefix(20)).map(\.id), "newest first")

        let old = trace(at: now.addingTimeInterval(-15 * 24 * 3_600))
        let recent = trace(at: now.addingTimeInterval(-13 * 24 * 3_600))
        XCTAssertEqual(VoiceNoteLogStore.trimmed([old, recent], now: now).map(\.id), [recent.id], "14 days at most")
    }

    func testEveryStringIsCappedAndTheFileStaysUnderTwoMegabytes() throws {
        let now = at(2026, 10, 20, 18)
        let long = String(repeating: "word ", count: 6_000)
        var big = trace(at: now, words: long)
        big.phrases = (0..<300).map { TimedPhrase(text: String(repeating: "x", count: 1_000), start: Double($0), end: Double($0) + 1) }
        big.parts = [VoiceNoteTrace.Part(index: 0, cut: "sentence", words: "0..<48", carried: nil, text: long, prompt: long,
                                         promptTokens: nil, sentAt: 1, seconds: 2, outcome: "model",
                                         answer: [RawTodo(spoken: long, title: long)])]
        let capped = try XCTUnwrap(VoiceNoteLogStore.trimmed([big], now: now).first)
        XCTAssertEqual(capped.finalTranscript.count, VoiceNoteLogStore.maxCharacters)
        XCTAssertEqual(capped.parts[0].prompt.count, VoiceNoteLogStore.maxCharacters)
        XCTAssertEqual(capped.parts[0].answer[0].title.count, VoiceNoteLogStore.maxCharacters)

        let notes = (0..<20).map { index -> VoiceNoteTrace in
            var note = big
            note.id = UUID()
            note.startedAt = now.addingTimeInterval(TimeInterval(-index * 60))
            return note
        }
        let kept = VoiceNoteLogStore.trimmed(notes, now: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        XCTAssertLessThanOrEqual(try encoder.encode(kept).count, VoiceNoteLogStore.maxBytes)
        XCTAssertLessThan(kept.count, 20, "the oldest went first")
        XCTAssertEqual(kept.first?.id, notes[0].id)
    }

    func testANoteIsSavedTwiceAsOneRecordAndClearLeavesNoFile() throws {
        let log = store()
        var note = trace(at: Date())
        log.save(note)
        note.saved = [VoiceNoteTrace.Saved(title: "Call the dentist", due: nil, list: "work", id: UUID())]
        log.save(note)
        log.flush()
        XCTAssertEqual(log.load().map(\.id), [note.id], "written at the stop and again at the save, one record")
        XCTAssertEqual(log.load().first?.saved.count, 1)
        let values = try log.fileURL.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true, "never in a backup")
        log.erase()
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.fileURL.path))
        XCTAssertTrue(log.load().isEmpty)
    }

    func testANoteBegunBeforeClearIsNeverWrittenBack() {
        let log = store()
        let sorting = trace(at: Date().addingTimeInterval(-5))
        log.save(sorting)
        log.erase()
        // Its save after the sort, and the token count after that, come once the log was cleared.
        log.save(sorting)
        log.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: log.fileURL.path), "Clear leaves no file, and none comes back")
        let next = trace(at: Date().addingTimeInterval(1))
        log.save(next)
        log.flush()
        XCTAssertEqual(log.load().map(\.id), [next.id], "a note begun after it is kept")
    }

    @MainActor
    func testTheLinkOpensTheLogOnlyInAnInternalBuild() {
        XCTAssertTrue(VoiceNoteLogRoute.isRequest(VoiceNoteLogRoute.link, unlocked: true))
        XCTAssertFalse(VoiceNoteLogRoute.isRequest(VoiceNoteLogRoute.link, unlocked: false))
        XCTAssertFalse(VoiceNoteLogRoute.isRequest(TodoEval.link, unlocked: true))
        XCTAssertFalse(VoiceNoteLogRoute.isRequest(TodoCaptureRoute.listURL, unlocked: true))
        XCTAssertNil(TodoCaptureRoute.route(for: VoiceNoteLogRoute.link), "the To-do tab's routes never take it")
        XCTAssertFalse(InternalBuild.unlocksPro, "CI is not an internal build")
        XCTAssertFalse(VoiceNoteLogRoute().handle(url: VoiceNoteLogRoute.link), "so the link does nothing here")
    }

    func testTheReportOfATwoPartNote() {
        var note = trace(at: at(2026, 10, 20, 17, 18), words: "Call the dentist tomorrow. Buy milk and eggs.")
        note.liveTranscript = "Call the dentist tomorrow. Buy milk and"
        note.stopReason = TodoStopReason.tap.rawValue
        note.engine = SpeechEngine.analyzer.rawValue
        note.chipChanged = true
        note.marks = [.init(label: "transcriber ready", seconds: 0.8), .init(label: "stop", seconds: 34.2)]
        note.resets = [TranscriptReset(at: 12, before: "Call the dentist tomorrow", after: "Buy")]
        note.parts = [
            .init(index: 0, cut: "sentence", words: "0..<4", carried: nil, text: "Call the dentist tomorrow.",
                  prompt: "p", promptTokens: 300, sentAt: 10, seconds: 2.5, outcome: "model",
                  answer: [RawTodo(spoken: "Call the dentist tomorrow", title: "Call the dentist", dueISO8601: "2026-10-21")]),
            .init(index: 1, cut: "end", words: "4..<8", carried: nil, text: "Buy milk and eggs.", prompt: "p",
                  promptTokens: nil, sentAt: 34.5, seconds: 15.2, outcome: "timed out", answer: []),
        ]
        note.saved = [.init(title: "Call the dentist", due: "2026-10-21", list: "work", id: UUID()),
                      .init(title: "Buy milk and eggs", due: nil, list: "work", id: UUID())]
        let report = VoiceNoteLog.report(note)
        XCTAssertTrue(report.contains("List: work, chip changed: yes"), report)
        XCTAssertTrue(report.contains("Heard: Call the dentist tomorrow. Buy milk and eggs."), report)
        XCTAssertTrue(report.contains("Live card: Call the dentist tomorrow. Buy milk and"), "the live card differed")
        XCTAssertTrue(report.contains("Reset at 12.0 s: before \"Call the dentist tomorrow\", after \"Buy\""), report)
        XCTAssertTrue(report.contains("Part 1: sentence cut, words 0..<4, sent at 10.0 s, 2.5 s, model, 1 prompt characters, 300 tokens"), report)
        XCTAssertTrue(report.contains("Part 2: end cut, words 4..<8, sent at 34.5 s, 15.2 s, timed out"), report)
        XCTAssertTrue(report.contains("Part 1 model: spoken \"Call the dentist tomorrow\", title \"Call the dentist\", due 2026-10-21"), report)
        XCTAssertTrue(report.contains("Saved: Buy milk and eggs on work"), report)
        XCTAssertTrue(report.contains("Timings: transcriber ready 0.8 s, stop 34.2 s"), report)
        XCTAssertEqual(VoiceNoteLog.row(note, timeZone: london), "17:18 \u{00B7} Work \u{00B7} 34 s \u{00B7} stopped: tap \u{00B7} 2 to-dos")
    }

    func testTheRecordKeepsWhatTheTranscriberSaidAndWhereTheNoteWent() {
        var note = VoiceNoteTrace(input: .voice, list: .personal)
        note.chose(.work)
        XCTAssertEqual(note.list, "work")
        XCTAssertTrue(note.chipChanged, "the chip sent it to Work")
        var speech = SpeechDiagnostics(engine: .recognizer, why: "iOS 17 to 25")
        speech.resets = [TranscriptReset(at: 3, before: "Call the dentist", after: "Buy")]
        speech.restarts = 1
        note.heard(live: "Call the dentist Buy milk", final: "", speech: speech)
        XCTAssertEqual(note.finalTranscript, "Call the dentist Buy milk")
        XCTAssertTrue(note.usedLiveText, "the final text was empty")
        XCTAssertEqual(note.resets.count, 1)
        XCTAssertEqual(note.engine, "SFSpeechRecognizer")
        XCTAssertEqual(note.engineWhy, "iOS 17 to 25")
    }

    func testTheLogCopyKeepsTheRules() {
        for text in VoiceNoteLogCopy.all {
            XCTAssertNil(text.range(of: "free", options: .caseInsensitive), text)
            XCTAssertFalse(text.contains("\u{2014}") || text.contains("\u{2013}"), "no em or en dash: \(text)")
            XCTAssertFalse(text.contains("!"), text)
        }
    }
}
