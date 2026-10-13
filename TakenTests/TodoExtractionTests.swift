import XCTest
@testable import Taken

/// The layer between the on-device model and what is saved. The model cannot run in CI, so these feed it canned
/// answers in the guided generation's shape and check what code keeps (SPEC 3.10).
final class TodoExtractionTests: XCTestCase {
    /// Tuesday 13 October 2026, 09:41 in London, the day starting at 04:00.
    private let context = TodoContext(now: at(2026, 10, 13, 9, 41), timeZone: london, dayStartHour: 4)

    func testACannedAnswerBecomesTasks() throws {
        let json = """
            {"tasks":[
              {"title":"call the dentist","dueISO8601":"2026-10-13T16:00:00","hasTime":true},
              {"title":"Pick up the dry cleaning.","dueISO8601":"2026-10-13T16:00","hasTime":true},
              {"title":"- email Sam the deck","dueISO8601":"2026-10-14","hasTime":false},
              {"title":"Book flights for March","dueISO8601":null,"hasTime":false}
            ]}
            """
        let raw = try XCTUnwrap(TodoValidation.decode(json: json))
        let drafts = TodoValidation.validate(raw, transcript: "today by 4 call the dentist ...", context: context)
        XCTAssertEqual(drafts.map(\.title),
                       ["Call the dentist", "Pick up the dry cleaning", "Email Sam the deck", "Book flights for March"])
        XCTAssertEqual(drafts[0].dueDate, at(2026, 10, 13, 16))
        XCTAssertTrue(drafts[0].hasTime)
        XCTAssertEqual(drafts[1].dueDate, at(2026, 10, 13, 16))
        XCTAssertEqual(drafts[2].dueDate, at(2026, 10, 14, 12), "a day alone is kept at noon")
        XCTAssertFalse(drafts[2].hasTime)
        XCTAssertNil(drafts[3].dueDate)
        XCTAssertFalse(drafts[3].hasTime)
    }

    func testCannedAnswersInOtherShapesDecode() {
        XCTAssertEqual(TodoValidation.decode(json: #"[{"title":"Buy milk"}]"#), [RawTodo(title: "Buy milk")])
        XCTAssertEqual(TodoValidation.decode(json: #"{"tasks":[{"title":"Call Sam","due":"2026-10-14"}]}"#)?.first?.dueISO8601,
                       "2026-10-14")
        XCTAssertEqual(TodoValidation.decode(json: #"{"tasks":[]}"#), [])
        XCTAssertNil(TodoValidation.decode(json: "not json"))
    }

    func testDatesAreCheckedNeverTrusted() {
        func due(_ text: String, _ hasTime: Bool = true) -> Date? {
            TodoValidation.parseDue(text, hasTime: hasTime, context: context)?.date
        }
        XCTAssertEqual(due("2026-10-13T16:00:00+02:00"), at(2026, 10, 13, 15), "an offset is honoured")
        XCTAssertEqual(due("2026-10-13T15:00:00Z"), at(2026, 10, 13, 16), "UTC")
        XCTAssertEqual(due("2026-10-13T15:00:00.000Z"), at(2026, 10, 13, 16))
        XCTAssertEqual(due("2026-10-13 16:00"), at(2026, 10, 13, 16))
        XCTAssertEqual(due(" 2026-10-13T16:00:00 "), at(2026, 10, 13, 16))
        XCTAssertEqual(TodoValidation.parseDue("2026-10-14T00:00:00", hasTime: false, context: context)?.hasTime, false,
                       "midnight with no time said is a day")
        XCTAssertEqual(TodoValidation.parseDue("2026-10-14", hasTime: true, context: context)?.hasTime, false,
                       "no time written, no time kept")
        XCTAssertEqual(due("2026-10-13T08:00:00"), at(2026, 10, 13, 8), "an hour and a half ago is kept (said late)")
        XCTAssertNil(due("2026-10-12T08:00:00"), "more than a day in the past")
        XCTAssertNotNil(due("2026-10-12", false), "yesterday, said late at night")
        XCTAssertNil(due("2026-10-11", false), "the day before yesterday")
        XCTAssertNil(due("2062-10-13T16:00:00"), "a wrong year")
        XCTAssertNil(due("2027-12-01", false), "more than a year ahead")
        XCTAssertNil(due("2026-11-31", false), "a day that does not exist")
        XCTAssertNil(due("2026-13-01", false))
        XCTAssertNil(due("2026-10-13T25:00:00"))
        XCTAssertNil(due("2026-10-13T16:75:00"))
        XCTAssertNil(due("2026-10-13T16:00:00+25:00"))
        XCTAssertNil(due("tomorrow"))
        XCTAssertNil(due(""))
    }

    func testTitlesAreCleanedDedupedAndCapped() {
        let raw = [
            RawTodo(title: "  1. call   the dentist  "),
            RawTodo(title: "Call the dentist."),
            RawTodo(title: "\u{201C}Buy milk\u{201D}"),
            RawTodo(title: "   "),
            RawTodo(title: "Call Sam", dueISO8601: "2026-10-13T16:00:00", hasTime: true),
            RawTodo(title: "Call Sam", dueISO8601: "2026-10-14T16:00:00", hasTime: true),
            RawTodo(title: String(repeating: "word ", count: 60)),
        ]
        let drafts = TodoValidation.validate(raw, transcript: "x", context: context)
        XCTAssertEqual(drafts.map(\.title).prefix(4).map { $0 }, ["Call the dentist", "Buy milk", "Call Sam", "Call Sam"],
                       "the same words due at two times are two tasks")
        XCTAssertEqual(drafts.count, 5)
        XCTAssertLessThanOrEqual(drafts[4].title.count, TodoText.maxTitleLength)

        let many = (1...30).map { RawTodo(title: "Task \($0)") }
        XCTAssertEqual(TodoValidation.validate(many, transcript: "x", context: context).count, TodoValidation.maxTasks)
    }

    func testAnEmptyAnswerKeepsTheWholeNote() async {
        let drafts = TodoValidation.validate([], transcript: "  um so I need to sort out the garage  ", context: context)
        XCTAssertEqual(drafts.map(\.title), ["Um so I need to sort out the garage"])
        XCTAssertNil(drafts.first?.dueDate)
        XCTAssertTrue(TodoValidation.validate([], transcript: "   ", context: context).isEmpty, "no words, no task")

        let fallback = await FallbackExtractor().extract(transcript: "call mum and buy milk", context: context)
        XCTAssertEqual(fallback.drafts.map(\.title), ["Call mum and buy milk"], "no model: the note is one task")
        XCTAssertEqual(fallback.sorting, .needsAppleIntelligence)

        let long = String(repeating: "and then the next thing ", count: 40)
        let whole = TodoValidation.wholeNote(long)
        XCTAssertEqual(whole.count, 1)
        XCTAssertLessThanOrEqual(whole[0].title.count, TodoValidation.maxNoteLength)
    }

    func testTheExtractorsAnswerIsWhatIsSaved() async {
        struct Stub: TaskExtractor {
            let drafts: [TodoDraft]
            func prepare() async {}
            func extract(transcript: String, context: TodoContext) async -> TodoExtraction {
                TodoExtraction(drafts: drafts, sorting: .model)
            }
        }
        let sorted = await TodoModel.extract("call the dentist and buy milk",
                                             with: Stub(drafts: [TodoDraft(title: "Call the dentist"), TodoDraft(title: "Buy milk")]),
                                             context: context)
        XCTAssertEqual(sorted.drafts.map(\.title), ["Call the dentist", "Buy milk"])
        XCTAssertEqual(sorted.sorting, .model)

        // A model that never answers (and never notices it was cancelled) still lets the note be saved, whole.
        struct Hanging: TaskExtractor {
            func prepare() async {}
            func extract(transcript: String, context: TodoContext) async -> TodoExtraction {
                for _ in 0..<5 { try? await Task.sleep(for: .seconds(1)) }
                return TodoExtraction(drafts: [], sorting: .model)
            }
        }
        let started = Date()
        let late = await TodoModel.extract("call the dentist", with: Hanging(), context: context, limit: .milliseconds(200))
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "the deadline holds")
        XCTAssertEqual(late.drafts.map(\.title), ["Call the dentist"])
        XCTAssertEqual(late.sorting, .couldNotSort)
    }

    func testThePromptCarriesNowTheZoneAndTheDayStart() {
        let prompt = TodoPrompt.prompt(transcript: " call the dentist by 4 ", context: context)
        XCTAssertTrue(prompt.contains("Now: Tuesday 13 October 2026, 09:41, time zone Europe/London."), prompt)
        XCTAssertTrue(prompt.contains("Tomorrow is Wednesday 14 October 2026 (2026-10-14)."), prompt)
        XCTAssertTrue(prompt.contains("Friday 2026-10-16"), prompt)
        XCTAssertTrue(prompt.hasSuffix("Voice note: \"call the dentist by 4\""), prompt)
        XCTAssertFalse(prompt.contains("still"), "awake in the day it is: no day-start line")

        let late = TodoContext(now: at(2026, 10, 14, 1, 30), timeZone: london, dayStartHour: 4)
        let latePrompt = TodoPrompt.prompt(transcript: "x", context: late)
        XCTAssertTrue(latePrompt.contains("Now: Wednesday 14 October 2026, 01:30"), latePrompt)
        XCTAssertTrue(latePrompt.contains("The speaker's day starts at 04:00, so their today is still Tuesday 13 October 2026."),
                      latePrompt)
        XCTAssertTrue(latePrompt.contains("Tomorrow is Wednesday 14 October 2026"), latePrompt)
    }

    @MainActor
    func testQuickCaptureLinksAndRequests() {
        XCTAssertEqual(TodoCaptureRoute.route(for: TodoCaptureRoute.recordURL), .record)
        XCTAssertEqual(TodoCaptureRoute.route(for: TodoCaptureRoute.listURL), .list)
        XCTAssertNil(TodoCaptureRoute.route(for: ProRoute().url), "taken://pro is the paywall's")
        XCTAssertNil(TodoCaptureRoute.route(for: URL(string: "https://example.com/todo")!))

        let route = TodoCaptureRoute()
        XCTAssertFalse(route.takeTabRequest())
        route.requestRecording(at: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(route.tabRequests, 1)
        XCTAssertTrue(route.takeTabRequest(), "the tab bar switches to To-do")
        XCTAssertFalse(route.takeTabRequest(), "once")
        XCTAssertTrue(route.takePendingRecording(now: Date(timeIntervalSince1970: 110)))
        XCTAssertFalse(route.takePendingRecording(now: Date(timeIntervalSince1970: 111)), "taken once")
        route.requestRecording(at: Date(timeIntervalSince1970: 100))
        XCTAssertFalse(route.takePendingRecording(now: Date(timeIntervalSince1970: 400)), "a stale request never opens the mic")

        let links = TodoCaptureRoute()
        XCTAssertFalse(links.handle(url: ProRoute().url), "the paywall's link is not ours")
        XCTAssertTrue(links.handle(url: TodoCaptureRoute.listURL))
        XCTAssertNil(links.pendingRecording, "the list link opens the tab without listening")
        XCTAssertTrue(links.takeTabRequest())
        XCTAssertTrue(links.handle(url: TodoCaptureRoute.recordURL))
        XCTAssertTrue(links.takePendingRecording(), "the Lock Screen mic opens the tab listening")
    }

    @MainActor
    func testNewVoiceTodoOpensTheTabListening() async throws {
        let route = TodoCaptureRoute.shared
        let before = route.tabRequests
        _ = try await NewVoiceTodoIntent(target: .recording).perform()
        XCTAssertEqual(route.tabRequests, before + 1, "the tab bar is asked for the To-do tab")
        XCTAssertNotNil(route.pendingRecording, "and the tab starts listening")
        // The test host never opens the microphone.
        _ = route.takePendingRecording()
        _ = route.takeTabRequest()
    }

    func testInfoPlistDeclaresVoiceCaptureAndTheCopyKeepsTheRules() throws {
        let info = Bundle.main.infoDictionary ?? [:]
        let microphone = try XCTUnwrap(info["NSMicrophoneUsageDescription"] as? String)
        let speech = try XCTUnwrap(info["NSSpeechRecognitionUsageDescription"] as? String)
        let items = try XCTUnwrap(info["UIApplicationShortcutItems"] as? [[String: Any]])
        XCTAssertEqual(items.first?["UIApplicationShortcutItemType"] as? String, TodoCaptureRoute.quickActionType)

        for text in [microphone, speech, TodoPrompt.instructions] + TodoCopy.all + ProCopy.features {
            XCTAssertNil(text.range(of: "free", options: .caseInsensitive), text)
            XCTAssertFalse(text.contains("\u{2014}") || text.contains("\u{2013}"), "no em or en dash: \(text)")
            XCTAssertFalse(text.contains("!"), text)
        }
    }
}
