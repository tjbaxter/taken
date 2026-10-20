import Observation
import SwiftUI
import UIKit

// The on-device sorting eval, for the owner's internal TestFlight builds only. CI cannot run Apple's model, so fifteen
// fixed notes run through the real sorter on the iPhone, one after another, and a sheet shows what the model wrote,
// what was saved, each part's time and whether it matches what should be. The two long rambles (2 and 5 minutes) are
// cut into parts and sorted back to back as they would be while someone talks, and pass only if every part takes 15 s
// or less, so the last part lands inside the time after the stop. Opened with the link taken://todo-eval (from Safari,
// after each internal build: a TestFlight app takes no launch arguments). Compiled only into Debug (for the tests) and
// the EAS "internal" profile's builds (project.internal.yml adds TAKEN_INTERNAL), so an App Store build does not
// contain it (App Review Guideline 2.5.19). Inside those, only a build carrying the TakenInternalPro marker answers
// the link. Results stay on the phone, and Copy results puts them on the clipboard.

#if DEBUG || TAKEN_INTERNAL
enum TodoEval {
    static let host = "todo-eval"
    static let link = URL(string: "taken://todo-eval")!
    /// 14 of the 15 notes must pass. Run again after every iOS model update.
    static let passBar = 14
    /// A long ramble's parts must each be sorted within this many seconds.
    static let partLimit: Double = 15

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
        /// How many to-dos are saved: exactly one number, or a range for a long ramble.
        let counts: ClosedRange<Int>
        /// One per saved task, in any order. Nil checks no dates.
        let dues: [ExpectedDue]?
        /// Words the saved titles must keep, ignoring case.
        let keeps: [String]
        /// Nothing to do was said: the whole note is saved as it is.
        let wholeNote: Bool
        /// A long ramble: cut into parts and sorted back to back as while talking, every part within `partLimit`.
        let timed: Bool
        /// What should happen, in words.
        let expected: String

        init(_ id: Int, _ note: String, count: Int = 1, counts: ClosedRange<Int>? = nil, dues: [ExpectedDue]? = nil,
             keeps: [String] = [], wholeNote: Bool = false, timed: Bool = false, expected: String) {
            self.id = id
            self.note = note
            self.counts = counts ?? count...count
            self.dues = dues
            self.keeps = keeps
            self.wholeNote = wholeNote
            self.timed = timed
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
        // The shape of Tom's cut-off note (20 Oct 2026), not his words: the verb and its object kept, no due.
        Case(13, "I should send messages to my LinkedIn leads", dues: [.none], keeps: ["send", "messages", "leads"],
             expected: "1 to-do, keeps send, messages and leads, no due"),
        Case(14, twoMinuteRamble, counts: 9...11, keeps: ["Patel", "Marcus", "Admiral", "Sophie", "Raj", "Netflix"],
             timed: true, expected: "9 to 11 to-dos, every name kept, each part sorted in 15 s or less"),
        Case(15, fiveMinuteRamble, counts: 18...22,
             keeps: ["Elena", "Brightwater", "Daniel", "British Gas", "Callum", "Fitzone", "Jess", "Owen", "Grandad"],
             timed: true, expected: "18 to 22 to-dos, every name kept, each part sorted in 15 s or less"),
    ]

    /// About two minutes said (about 290 words): ten clear actions with chat between, and two day headers. Not
    /// Tom's words.
    static let twoMinuteRamble = """
        Okay so it's Monday and I've got loads on, let me just get it all out. I've been putting most of this off \
        since the weekend and it's starting to pile up. First thing, I need to call Dr Patel about the blood test \
        results, they said to ring after ten. Then I should email Marcus the revised budget for the Lisbon trip, he's \
        been waiting since last week and I feel bad about it. The kitchen tap is still dripping, which is driving me \
        mad, so book a plumber, maybe the one Hannah recommended. Honestly the weather has been grim all week and I \
        keep forgetting my umbrella. Anyway, that's not important right now. Tomorrow. Pick up the dry cleaning from \
        Clean Express before they close at six. Oh and renew the car insurance with Admiral, the letter came on \
        Saturday. I was thinking about the garden as well but that can wait until spring, there's no point now. Cancel \
        the Netflix trial before it renews, I never watch it anyway. Order a birthday present for Sophie, she's into \
        pottery at the moment so something from that shop on Etsy would be good. Text Raj about five a side, I think \
        we're short of players again. It was a good game last week though, we nearly won for once. My back has been a \
        bit sore after the gym so I'm taking it easy this week. On Friday. Pay the window cleaner, I owe him for two \
        visits now. And finally, back up the photos from my phone to the laptop, it's nearly full and I don't want to \
        lose anything from the holiday. That's about it I think, it felt like more in my head.
        """

    /// About five minutes said (about 760 words): twenty actions over work, home, money and friends, with chat
    /// between. Not Tom's words.
    static let fiveMinuteRamble = """
        Right, it's been one of those weeks so I'm just going to talk through everything and hope it sorts itself out. \
        I've had about four hours of sleep and my brain is all over the place, so bear with me. Work first. I need to \
        send Elena the slides for the quarterly review, she wants them before the meeting so that's the priority. The \
        meeting itself got moved to Wednesday afternoon, which is annoying because I had the dentist then. So I have \
        to rebook the dentist, the practice on Mill Road, and ask for a morning slot next week if they have one. Then \
        there's the contract with Brightwater, legal sent comments back and I haven't even opened them yet. Review the \
        Brightwater contract comments and reply to legal by Thursday. I keep saying I'll do it and then something else \
        comes up, it's the story of my life at the moment. Also chase Daniel for the invoice from September, accounts \
        keep asking me about it and it's not even my invoice. Honestly I don't know why that one always lands on me, I \
        think it's because I answered the first email. Book the team lunch for Friday, somewhere near the office, \
        maybe the Italian place on the corner, it needs to fit twelve people. And update the project tracker before \
        standup tomorrow, nobody has touched it since the offsite and it looks terrible. Last time I looked there were \
        tasks on it from August that nobody had closed, which says it all really. Okay, home stuff now. The boiler \
        made that noise again this morning, the clanking one, so call British Gas and get an engineer out. It's \
        probably nothing but I'd rather know before it gets properly cold. Last winter it went out the week before \
        Christmas and we had no hot water for three days, which was miserable. The car is due its MOT at the end of \
        the month, so book the MOT at the garage in town, the one we used last year. Buy a new phone charger, the \
        cable by the bed has gone frayed and it's started to look a bit dodgy. I don't want it catching fire in the \
        night or anything dramatic like that. I was going to fix the shelf in the hall at the weekend but I don't \
        think I have the right screws, so get screws for the hall shelf from the hardware shop. Mum's birthday is on \
        the twenty third, I nearly forgot again, which would not have gone down well. Last year my card got there two \
        days late and I'm still hearing about it. Order flowers for Mum from Bloom and Wild and get them delivered on \
        the day. Then there's the recycling, which I always forget, so put the green bin out on Tuesday night. Money \
        stuff, which I hate. I always feel like I'm behind on something, even when I'm not. Transfer the rent to \
        Callum by the first, he sent a reminder already which was a bit embarrassing to be honest. Cancel the Fitzone \
        gym membership, I never use it and I think there's a thirty day notice period so it has to be soon. I think \
        that's the boring list done, at least for now. Social things. Reply to Jess about the wedding, she needs \
        numbers by the end of next week and I still haven't asked about plus ones. Text Owen happy birthday, it's \
        today and I always leave it until midnight. Book tickets for the Arctic Monkeys gig before they sell out, the \
        presale opens at ten tomorrow morning. And I promised I'd send Grandad the photos from the holiday, so print \
        the holiday photos for Grandad, he doesn't really do email. I was also thinking about learning Spanish again \
        before the trip in the summer, but that's more of a someday thing, not a to-do, so I won't count it. My knee \
        has been sore when I run so maybe I'll take a week off and see how it goes, I don't want to make it worse \
        before the half marathon. It's only six weeks away now and I've barely done any long runs, so that's a worry \
        for another day. Last few things. Pick up the parcel from the post office, the card said it's there until \
        Saturday. And renew my passport, it runs out in March and the summer trip needs six months left on it. That \
        really is everything, I think, unless I remember something in the shower like I always do.
        """

    /// Whether what was saved for a case is what should be. A long ramble also needs every part sorted within
    /// `partLimit` seconds (`partSeconds`, one per part).
    static func passes(_ test: Case, drafts: [TodoDraft], partSeconds: [Double] = []) -> Bool {
        if test.wholeNote { return drafts == TodoValidation.asSaid(test.note) }
        if test.timed, partSeconds.isEmpty || partSeconds.contains(where: { $0 > partLimit }) { return false }
        guard test.counts.contains(drafts.count) else { return false }
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

    /// One note through the real sorter with the real deadlines: the model's own answers, what Taken saves from them,
    /// and each part's cut and time.
    struct Outcome: Sendable {
        var model: [RawTodo]?
        var saved: [TodoDraft]
        var sorting: TodoSorting
        var parts: [SortedChunk]
    }

    /// Each part's seconds for the timing check; a part with no answer in time never passes it.
    static func partSeconds(_ parts: [SortedChunk]) -> [Double] {
        parts.map { $0.outcome == .timedOut ? .infinity : $0.seconds }
    }

    /// The best sorter on this iPhone, prepared first, as when the mic is tapped.
    @MainActor
    static func sort(_ test: Case, context: TodoContext) async -> Outcome {
        let sorter = TodoSorters.best()
        await sorter.prepare()
        return await sort(test, with: sorter, context: context)
    }

    /// A note as the app sorts it: a short one at the stop, with the time after the stop; a long ramble part by part
    /// as it closes, back to back as while talking (30 s each), then the rest at the stop.
    static func sort(_ test: Case, with sorter: any ChunkSorting, context: TodoContext,
                     budget: NoteSorter.Budget = .standard) async -> Outcome {
        let noteSorter = NoteSorter(sorter: sorter, context: context, budget: budget)
        if test.timed {
            await noteSorter.listen(finished: test.note)
            await noteSorter.settle()
        }
        let parts = await noteSorter.finish(note: test.note)
        let note = TodoValidation.assemble(note: test.note, parts: parts, context: context)
        let answers = parts.flatMap { part -> [RawTodo] in
            if case .model(let tasks) = part.outcome { return tasks }
            return []
        }
        let sorted = parts.contains { if case .model = $0.outcome { return true } else { return false } }
        return Outcome(model: sorted ? answers : nil, saved: note.drafts, sorting: note.sorting, parts: parts)
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
            for part in result.parts {
                lines.append(TodoEvalCopy.part(part))
            }
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
    /// Each part's cut, words and time.
    var parts: [SortedChunk] = []
}

/// Runs the fifteen notes one after another and keeps the results while the sheet is open.
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
            let outcome = await TodoEval.sort(test, context: context)
            results.append(TodoEvalResult(id: test.id, model: outcome.model, saved: outcome.saved,
                                          sorting: outcome.sorting, seconds: Date().timeIntervalSince(started),
                                          passed: TodoEval.passes(test, drafts: outcome.saved,
                                                                  partSeconds: TodoEval.partSeconds(outcome.parts)),
                                          parts: outcome.parts))
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
                if result.parts.count > 1 || test.timed {
                    ForEach(Array(result.parts.enumerated()), id: \.offset) { _, part in
                        Text(verbatim: TodoEvalCopy.part(part))
                            .font(.mono(11))
                            .foregroundStyle(part.seconds > TodoEval.partLimit || part.outcome == .timedOut
                                             ? theme.danger : theme.fgMuted)
                    }
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
    static let notAllSorted = "Some notes were not all sorted by the on-device model: those parts were saved as said."

    static func total(_ passed: Int, of count: Int) -> String {
        "\(passed) of \(count) passed. The bar is \(TodoEval.passBar) of \(count)."
    }

    static func running(done: Int, of count: Int) -> String { "Running note \(min(done + 1, count)) of \(count)" }

    static func timing(_ seconds: Double) -> String { String(format: "%.1f s in all, on this iPhone", seconds) }

    static func sorting(_ sorting: TodoSorting) -> String {
        switch sorting {
        case .model: return "sorted on this iPhone"
        case .partlySorted: return "some parts saved as said"
        case .needsAppleIntelligence: return "no Apple Intelligence on this iPhone"
        case .appleIntelligenceOff: return "Apple Intelligence is off"
        case .modelNotReady: return "the model is still getting ready"
        case .couldNotSort: return "the model gave no answer in time"
        }
    }

    /// "Part 2: sentence cut, 52 words, 3.4 s, model"
    static func part(_ part: SortedChunk) -> String {
        "Part \(part.chunk.index + 1): \(part.chunk.cut.rawValue) cut, \(part.chunk.wordCount) words, "
            + String(format: "%.1f s, ", part.seconds) + outcome(part.outcome)
    }

    static func outcome(_ outcome: ChunkOutcome) -> String {
        switch outcome {
        case .model: return "model"
        case .timedOut: return "timed out"
        case .failed(let reason): return "error \(reason)"
        case .unavailable(let sorting): return self.sorting(sorting)
        }
    }

    static let all: [String] = [
        title, done, copy, copied, runAgain, pass, fail, expected, saved, model, noDue, notAllSorted,
        total(14, of: 15), running(done: 0, of: 15), timing(12.5),
        sorting(.model), sorting(.partlySorted), sorting(.needsAppleIntelligence), sorting(.appleIntelligenceOff),
        sorting(.modelNotReady), sorting(.couldNotSort), outcome(.timedOut),
        part(SortedChunk(chunk: TodoChunk(index: 1, text: "", wordRange: 48..<100, carried: nil, cut: .sentence),
                         outcome: .model([]), sentAt: 20, seconds: 3.4, prompt: "")),
    ] + TodoEval.cases.map(\.expected)
}
#endif
