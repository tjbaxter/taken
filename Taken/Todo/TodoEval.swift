import Observation
import SwiftUI
import UIKit

// The on-device sorting eval, for the owner's internal TestFlight builds only. CI cannot run Apple's model, so twelve
// fixed notes run through the real extractor on the iPhone, one after another, and a sheet shows what the model wrote,
// what was saved and whether it matches what should be. Opened with the link taken://todo-eval (from Safari, after
// each internal build: a TestFlight app takes no launch arguments). Compiled only into Debug (for the tests) and the
// EAS "internal" profile's builds (project.internal.yml adds TAKEN_INTERNAL), so an App Store build does not contain it
// (App Review Guideline 2.5.19). Inside those, only a build carrying the TakenInternalPro marker answers the link.
// Results stay on the phone, and Copy results puts them on the clipboard.

#if DEBUG || TAKEN_INTERNAL
enum TodoEval {
    static let host = "todo-eval"
    static let link = URL(string: "taken://todo-eval")!
    /// 11 of the 12 notes must pass. Run again after every iOS model update.
    static let passBar = 11

    /// `taken://todo-eval` in an internal build. False without the TakenInternalPro marker (Debug and CI), whatever the
    /// link; an App Store build does not contain this code.
    static func isRequest(_ url: URL, unlocked: Bool = InternalBuild.unlocksPro) -> Bool {
        guard unlocked, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme == TodoCaptureRoute.scheme && components.host == host
    }

    static let zone = TimeZone(identifier: "Europe/London") ?? .current

    /// Monday 19 October 2026, 10:00 in London, the day starting at 04:00: the same "now" on every run.
    static var context: TodoContext {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 10)) ?? Date()
        return TodoContext(now: now, timeZone: zone, dayStartHour: 4)
    }

    /// What one saved task must be due.
    enum ExpectedDue: Equatable, Sendable {
        case none
        /// That day at that clock time.
        case at(DayKey, hour: Int, minute: Int)
        /// That day, no time.
        case day(DayKey)
        /// That day, with or without a time.
        case on(DayKey)
    }

    struct Case: Identifiable, Sendable {
        let id: Int
        let note: String
        let count: Int
        /// One per saved task, in any order. Nil checks no dates.
        let dues: [ExpectedDue]?
        /// Words the saved titles must keep, ignoring case.
        let keeps: [String]
        /// Nothing to do was said: the whole note is saved as it is.
        let wholeNote: Bool
        /// What should happen, in words.
        let expected: String

        init(_ id: Int, _ note: String, count: Int = 1, dues: [ExpectedDue]? = nil, keeps: [String] = [],
             wholeNote: Bool = false, expected: String) {
            self.id = id
            self.note = note
            self.count = count
            self.dues = dues
            self.keeps = keeps
            self.wholeNote = wholeNote
            self.expected = expected
        }
    }

    private static let monday = DayKey(year: 2026, month: 10, day: 19)

    /// None of these is Tom's own note word for word in the prompt's examples, so passing is not memory.
    static let cases: [Case] = [
        Case(1, "Order Reach toothbrushes on Amazon", dues: [.none], keeps: ["Reach"],
             expected: "1 to-do, no due, keeps Reach"),
        Case(2, "order reach toothbrushes on amazon", dues: [.none], keeps: ["order", "reach", "toothbrushes"],
             expected: "1 to-do, keeps order, reach and toothbrushes"),
        Case(3, "Reach out to Dan about the contract and order Reach floss", count: 2, expected: "2 to-dos"),
        Case(4, "Today by 4 pm I need to email Sam the invoice, call the bank and pick up my prescription from Boots",
             count: 3, dues: Array(repeating: .at(monday, hour: 16, minute: 0), count: 3),
             expected: "3 to-dos, each due today at 16:00"),
        Case(5, "Buy oat milk, bananas and coffee", expected: "1 to-do"),
        Case(6, "Restock Always pads and Native deodorant", keeps: ["Always", "Native"],
             expected: "1 to-do, keeps Always and Native"),
        Case(7, "Um so I was thinking I should finally book the dentist, it's been ages. Oh and text Jess back about Saturday",
             count: 2, dues: [.none, .none], expected: "2 to-dos, no due"),
        Case(8, "Remind me to renew my passport on Friday", dues: [.day(monday.adding(4))],
             expected: "1 to-do, due Friday 23 October, no time"),
        Case(9, "Call mum at 8 tonight, and tomorrow take the car in for its MOT", count: 2,
             dues: [.at(monday, hour: 20, minute: 0), .day(monday.adding(1))],
             expected: "2 to-dos, due today at 20:00 and tomorrow with no time"),
        Case(10, "Gym at 6", dues: [.at(monday, hour: 18, minute: 0)], expected: "1 to-do, due today at 18:00"),
        Case(11, "Honestly today was mad, the meeting ran over and I'm knackered. Anyway the main thing is send the Q3 deck to Priya by Thursday",
             dues: [.on(monday.adding(3))], expected: "1 to-do, due Thursday 22 October"),
        Case(12, "Note to self, the wifi password is on the fridge", wholeNote: true,
             expected: "No to-do made up: the whole note is saved as it is"),
    ]

    /// Whether what was saved for a case is what should be.
    static func passes(_ test: Case, drafts: [TodoDraft]) -> Bool {
        if test.wholeNote { return drafts == TodoValidation.wholeNote(test.note) }
        guard drafts.count == test.count else { return false }
        let said = Set(drafts.flatMap { SpokenNote.tokens(of: $0.title) })
        guard test.keeps.allSatisfy({ word in SpokenNote.tokens(of: word).allSatisfy(said.contains) }) else { return false }
        guard let dues = test.dues else { return true }
        var left = drafts.map(\.due)
        for expected in dues {
            guard let match = left.firstIndex(where: { matches($0, expected) }) else { return false }
            left.remove(at: match)
        }
        return true
    }

    static func matches(_ due: TodoDue?, _ expected: ExpectedDue) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        switch (due, expected) {
        case (nil, .none):
            return true
        case (.time(let date), .at(let day, let hour, let minute)):
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return DayKey(calendarDateOf: date, in: zone) == day && parts.hour == hour && parts.minute == minute
        case (.day(let saved), .day(let day)), (.day(let saved), .on(let day)):
            return saved == day
        case (.time(let date), .on(let day)):
            return DayKey(calendarDateOf: date, in: zone) == day
        default:
            return false
        }
    }

    /// One note through the real extractor with the real deadline (`TodoModel.sortingLimit`): the model's own answer
    /// and what Taken saves from it.
    struct Outcome: Sendable {
        var model: [RawTodo]?
        var saved: [TodoDraft]
        var sorting: TodoSorting
    }

    @MainActor
    static func sort(_ note: String, context: TodoContext) async -> Outcome {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if let reason = FoundationModelsExtractor.unavailableReason {
                return Outcome(model: nil, saved: TodoValidation.wholeNote(note), sorting: reason)
            }
            let extractor = FoundationModelsExtractor()
            await extractor.prepare()
            let answer = await firstResult(of: { try? await extractor.answer(transcript: note, context: context) },
                                           orAfter: TodoModel.sortingLimit, fallback: nil)
            guard let answer else {
                return Outcome(model: nil, saved: TodoValidation.wholeNote(note), sorting: .couldNotSort)
            }
            return Outcome(model: answer, saved: TodoValidation.validate(answer, transcript: note, context: context),
                           sorting: .model)
        }
        #endif
        return Outcome(model: nil, saved: TodoValidation.wholeNote(note), sorting: .needsAppleIntelligence)
    }

    /// "2026-10-19 16:00", "2026-10-23", "no due".
    static func label(_ due: TodoDue?) -> String {
        switch due {
        case nil:
            return TodoEvalCopy.noDue
        case .day(let day):
            return day.iso
        case .time(let date):
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            let day = DayKey(calendarDateOf: date, in: zone)
            return day.iso + String(format: " %02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        }
    }

    /// The whole run as plain text, for the clipboard.
    static func report(_ results: [TodoEvalResult], system: String, build: String) -> String {
        let passed = results.filter(\.passed).count
        var lines = ["Taken sorting eval, iOS \(system), build \(build)", TodoEvalCopy.total(passed, of: cases.count)]
        for test in cases {
            guard let result = results.first(where: { $0.id == test.id }) else { continue }
            lines.append("")
            lines.append("\(test.id) \(result.passed ? TodoEvalCopy.pass : TodoEvalCopy.fail), "
                         + String(format: "%.1f s", result.seconds) + ", \(TodoEvalCopy.sorting(result.sorting))")
            lines.append("Note: \(test.note)")
            lines.append("\(TodoEvalCopy.expected): \(test.expected)")
            for task in result.model ?? [] {
                lines.append("\(TodoEvalCopy.model): spoken \"\(task.spoken ?? "")\", title \"\(task.title)\", due "
                             + "\(task.dueISO8601 ?? "none"), time \(task.hasTime)")
            }
            for draft in result.saved {
                lines.append("\(TodoEvalCopy.saved): \(draft.title) (\(label(draft.due)))")
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// One note's run.
struct TodoEvalResult: Identifiable, Sendable {
    let id: Int
    let model: [RawTodo]?
    let saved: [TodoDraft]
    let sorting: TodoSorting
    let seconds: Double
    let passed: Bool
}

/// Runs the twelve notes one after another and keeps the results while the sheet is open.
@MainActor
@Observable
final class TodoEvalRunner {
    private(set) var results: [TodoEvalResult] = []
    private(set) var running = false

    func run() async {
        guard !running else { return }
        running = true
        results = []
        let context = TodoEval.context
        for test in TodoEval.cases {
            let started = Date()
            let outcome = await TodoEval.sort(test.note, context: context)
            results.append(TodoEvalResult(id: test.id, model: outcome.model, saved: outcome.saved,
                                          sorting: outcome.sorting, seconds: Date().timeIntervalSince(started),
                                          passed: TodoEval.passes(test, drafts: outcome.saved)))
        }
        running = false
    }
}

/// Where the eval link sends the app: the sheet over whatever is open.
@MainActor
@Observable
final class TodoEvalRoute {
    static let shared = TodoEvalRoute()

    var isPresented = false

    /// The eval link in an internal build: the sheet comes up once any sheet the link closed (AppModel closes them for
    /// every taken:// link) has gone. False for any other link, and for every link without the TakenInternalPro marker.
    @discardableResult
    func handle(url: URL, unlocked: Bool = InternalBuild.unlocksPro) -> Bool {
        guard TodoEval.isRequest(url, unlocked: unlocked) else { return false }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.isPresented = true
        }
        return true
    }
}

/// The eval sheet: each note, what should happen, what the model wrote and what was saved, pass or fail, and the total.
struct TodoEvalView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var runner = TodoEvalRunner()
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    summary
                }
                .listRowBackground(theme.bgRaised)
                ForEach(TodoEval.cases) { test in
                    Section {
                        row(test, result: runner.results.first { $0.id == test.id })
                    }
                    .listRowBackground(theme.bgRaised)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle(TodoEvalCopy.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(TodoEvalCopy.done) { dismiss() }
                        .foregroundStyle(theme.fgMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(copied ? TodoEvalCopy.copied : TodoEvalCopy.copy) {
                        let info = Bundle.main.infoDictionary ?? [:]
                        let build = "\(info["CFBundleShortVersionString"] as? String ?? "") (\(info["CFBundleVersion"] as? String ?? ""))"
                        UIPasteboard.general.string = TodoEval.report(runner.results,
                                                                      system: UIDevice.current.systemVersion,
                                                                      build: build)
                        copied = true
                    }
                    .font(.sans(16, .sansSemibold, relativeTo: .body))
                    .foregroundStyle(theme.signalInk)
                    .disabled(runner.running || runner.results.isEmpty)
                }
            }
        }
        .task { await runner.run() }
        .presentationBackground(theme.bg)
        .preferredColorScheme(theme.scheme)
        .tint(theme.signalInk)
    }

    private var summary: some View {
        let passed = runner.results.filter(\.passed).count
        let seconds = runner.results.map(\.seconds).reduce(0, +)
        return VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: runner.running
                 ? TodoEvalCopy.running(done: runner.results.count, of: TodoEval.cases.count)
                 : TodoEvalCopy.total(passed, of: TodoEval.cases.count))
                .font(.sans(17, .sansMedium, relativeTo: .body))
                .foregroundStyle(theme.fg)
            Text(verbatim: TodoEvalCopy.timing(seconds))
                .font(.mono(12))
                .foregroundStyle(theme.fgMuted)
            if !runner.running, runner.results.contains(where: { $0.sorting != .model }) {
                Text(verbatim: TodoEvalCopy.notAllSorted)
                    .font(.sans(14, relativeTo: .footnote))
                    .foregroundStyle(theme.fgMuted)
            }
            if !runner.running {
                Button(TodoEvalCopy.runAgain) {
                    copied = false
                    Task { await runner.run() }
                }
                .font(.sans(15, .sansMedium, relativeTo: .body))
                .foregroundStyle(theme.signalInk)
                .frame(minHeight: 44)
            }
        }
        .padding(.vertical, 4)
    }

    private func row(_ test: TodoEval.Case, result: TodoEvalResult?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: "\(test.id)")
                    .font(.mono(12))
                    .foregroundStyle(theme.fgSubtle)
                Spacer()
                if let result {
                    Text(verbatim: (result.passed ? TodoEvalCopy.pass : TodoEvalCopy.fail)
                         + String(format: "  %.1f s", result.seconds))
                        .font(.mono(12))
                        .foregroundStyle(result.passed ? theme.signalInk : theme.danger)
                }
            }
            Text(verbatim: test.note)
                .font(.sans(15, relativeTo: .body))
                .foregroundStyle(theme.fg)
            Text(verbatim: "\(TodoEvalCopy.expected): \(test.expected)")
                .font(.sans(13, relativeTo: .footnote))
                .foregroundStyle(theme.fgMuted)
            if let result {
                ForEach(Array(result.saved.enumerated()), id: \.offset) { _, draft in
                    Text(verbatim: "\(TodoEvalCopy.saved): \(draft.title) (\(TodoEval.label(draft.due)))")
                        .font(.sans(13, .sansMedium, relativeTo: .footnote))
                        .foregroundStyle(theme.fg)
                }
                if let model = result.model {
                    ForEach(Array(model.enumerated()), id: \.offset) { _, task in
                        Text(verbatim: "\(TodoEvalCopy.model): \(task.title) (\"\(task.spoken ?? "")\")")
                            .font(.mono(11))
                            .foregroundStyle(theme.fgSubtle)
                    }
                } else {
                    Text(verbatim: TodoEvalCopy.sorting(result.sorting))
                        .font(.mono(11))
                        .foregroundStyle(theme.fgSubtle)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// The eval's words. In `all`, so the copy test holds them to the same rules as every other string.
enum TodoEvalCopy {
    static let title = "Sorting eval"
    static let done = "Done"
    static let copy = "Copy results"
    static let copied = "Copied"
    static let runAgain = "Run again"
    static let pass = "PASS"
    static let fail = "FAIL"
    static let expected = "Expected"
    static let saved = "Saved"
    static let model = "Model"
    static let noDue = "no due"
    static let notAllSorted = "Some notes were not sorted by the on-device model, so they were saved whole."

    static func total(_ passed: Int, of count: Int) -> String {
        "\(passed) of \(count) passed. The bar is \(TodoEval.passBar) of \(count)."
    }

    static func running(done: Int, of count: Int) -> String { "Running note \(min(done + 1, count)) of \(count)" }

    static func timing(_ seconds: Double) -> String { String(format: "%.1f s in all, on this iPhone", seconds) }

    static func sorting(_ sorting: TodoSorting) -> String {
        switch sorting {
        case .model: return "sorted on this iPhone"
        case .needsAppleIntelligence: return "no Apple Intelligence on this iPhone"
        case .appleIntelligenceOff: return "Apple Intelligence is off"
        case .modelNotReady: return "the model is still getting ready"
        case .couldNotSort: return "the model gave no answer in time"
        }
    }

    static let all: [String] = [
        title, done, copy, copied, runAgain, pass, fail, expected, saved, model, noDue, notAllSorted,
        total(11, of: 12), running(done: 0, of: 12), timing(12.5),
        sorting(.model), sorting(.needsAppleIntelligence), sorting(.appleIntelligenceOff), sorting(.modelNotReady),
        sorting(.couldNotSort),
    ] + TodoEval.cases.map(\.expected)
}
#endif
