import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// The voice note log, for the owner's internal TestFlight builds only. What each note heard, how it was cut into
// parts, what the model answered and what was saved, so the next cut-off or wrong title can be read from the record
// instead of guessed (Tom, 20 Oct 2026: "it'd be really helpful if you could see it"). iOS cannot read an app's logs
// from earlier runs (OSLogStore reads only the current process), so it is the app's own file: in its own container, never
// the App Group, kept on the phone, never uploaded, so Taken stays Data Not Collected; Copy puts one note on the
// clipboard for ten minutes. Compiled only into Debug (for the tests) and the EAS "internal" profile's builds
// (TAKEN_INTERNAL), so an App Store build does not contain it (App Review Guideline 2.5.19), and inside those it records
// and opens only with the TakenInternalPro marker. It only watches: the speech, sorting and saving it records are the
// same code an App Store build runs. Never audio.
// https://developer.apple.com/documentation/oslog/oslogstore
// https://developer.apple.com/forums/thread/691093
// https://developer.apple.com/app-store/app-privacy-details/
// https://developer.apple.com/app-store/review/guidelines/
// https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup
// https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files
// https://developer.apple.com/documentation/uikit/uipasteboard/optionskey/expirationdate
// https://developer.apple.com/documentation/swiftui/sharelink

#if DEBUG || TAKEN_INTERNAL
enum VoiceNoteInput: String, Codable, Sendable {
    case voice
    case typed
}

/// One note, from the tap to the save.
struct VoiceNoteTrace: Codable, Identifiable, Hashable, Sendable {
    /// A moment, in seconds from the tap.
    struct Mark: Codable, Hashable, Sendable {
        var label: String
        var seconds: Double
    }

    /// One part of the note and what became of it.
    struct Part: Codable, Hashable, Sendable {
        var index: Int
        var cut: String
        var words: String
        var carried: String?
        var text: String
        var prompt: String
        var promptTokens: Int?
        var sentAt: Double
        var seconds: Double
        var outcome: String
        var answer: [RawTodo]
    }

    struct Saved: Codable, Hashable, Sendable {
        var title: String
        var due: String?
        var list: String
        var id: UUID
    }

    var id = UUID()
    var startedAt: Date
    var build: String
    var system: String
    var input: VoiceNoteInput
    /// The list the note went to, and whether its chip changed it.
    var list: String
    var chipChanged: Bool
    var locale: String
    var vocabulary = 0
    var engine: String?
    var engineWhy: String?
    var marks: [Mark] = []
    var stopReason: String?
    var wordsAtStop = 0
    var liveTranscript = ""
    var finalTranscript = ""
    /// The final transcript was empty, so the live card's words were saved.
    var usedLiveText = false
    var phrases: [TimedPhrase] = []
    var parts: [Part] = []
    var resets: [TranscriptReset] = []
    var restarts = 0
    var eventCount = 0
    var contextNow: String?
    var timeZone: String?
    var dayStartHour: Int?
    var contextSize: Int?
    var sorting: String?
    /// The tasks after grounding, before they were saved: "Call the dentist (2026-10-21 09:00)".
    var grounded: [String] = []
    var saved: [Saved] = []

    init(input: VoiceNoteInput, list: TodoArea, chipChanged: Bool = false, at start: Date = Date()) {
        startedAt = start
        build = "\(AppInfo.version) (\(AppInfo.build))"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        system = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        self.input = input
        self.list = list.rawValue
        self.chipChanged = chipChanged
        locale = Locale.current.identifier
    }

    // MARK: Recording

    mutating func mark(_ label: String, at moment: Date = Date()) {
        marks.append(Mark(label: label, seconds: moment.timeIntervalSince(startedAt)))
    }

    /// The chip sent the note to another list.
    mutating func chose(_ area: TodoArea) {
        chipChanged = true
        list = area.rawValue
        mark("chip: \(area.rawValue)")
    }

    /// The transcriber is listening.
    mutating func listening(context: TodoContext, capture: SpeechCapture) {
        mark("transcriber ready")
        record(context)
        if let speech = capture.diagnostics() {
            engine = speech.engine.rawValue
            engineWhy = speech.why
            vocabulary = speech.vocabulary
        }
    }

    mutating func typed(_ words: String, context: TodoContext) {
        finalTranscript = words
        record(context)
    }

    mutating func stopped(_ reason: TodoStopReason, lastVoice: TimeInterval, words: Int) {
        mark("stop")
        stopReason = reason.rawValue
        wordsAtStop = words
        if let ready = marks.first(where: { $0.label == "transcriber ready" }) {
            marks.append(Mark(label: "last voice", seconds: ready.seconds + lastVoice))
        }
    }

    mutating func heard(live: String, final: String, speech: SpeechDiagnostics?) {
        mark("final text")
        liveTranscript = live
        finalTranscript = final.isEmpty ? live : final
        usedLiveText = final.isEmpty && !live.isEmpty
        if let speech {
            engine = speech.engine.rawValue
            engineWhy = speech.why
            phrases = speech.phrases
            resets = speech.resets
            restarts = speech.restarts
        }
    }

    mutating func sorted(_ sorted: [SortedChunk], drafts: TodoNoteDrafts, saved tasks: [TodoTask], clock: DayClock) {
        parts = sorted.map { part in
            Part(index: part.chunk.index, cut: part.chunk.cut.rawValue,
                 words: "\(part.chunk.wordRange.lowerBound)..<\(part.chunk.wordRange.upperBound)",
                 carried: part.chunk.carried, text: part.chunk.text, prompt: part.prompt, promptTokens: nil,
                 sentAt: part.sentAt, seconds: part.seconds, outcome: VoiceNoteLog.outcome(part.outcome),
                 answer: { if case .model(let tasks) = part.outcome { return tasks } else { return [] } }())
        }
        sorting = "\(drafts.sorting)"
        grounded = drafts.drafts.map { draft in
            VoiceNoteLog.due(draft.due, clock: clock).map { "\(draft.title) (\($0))" } ?? draft.title
        }
        saved = tasks.map { Saved(title: $0.title, due: VoiceNoteLog.due($0.due, clock: clock), list: $0.area.rawValue,
                                  id: $0.id) }
        mark("saved")
    }

    private mutating func record(_ context: TodoContext) {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = context.timeZone
        contextNow = formatter.string(from: context.now)
        timeZone = context.timeZone.identifier
        dayStartHour = context.dayStartHour
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { contextSize = FoundationModelsExtractor.contextSize }
        #endif
    }

    /// Each part's prompt in tokens (iOS 26.4 and later), counted after the note is saved so the count never slows the
    /// sorting it measures, then written again.
    static func countTokens(of trace: VoiceNoteTrace, into store: VoiceNoteLogStore) {
        #if canImport(FoundationModels)
        guard #available(iOS 26.4, *), !trace.parts.isEmpty, FoundationModelsExtractor.unavailableReason == nil else { return }
        Task.detached(priority: .utility) {
            var counted = trace
            for index in counted.parts.indices {
                counted.parts[index].promptTokens = await FoundationModelsExtractor.tokenCount(counted.parts[index].prompt)
            }
            store.save(counted)
        }
        #endif
    }

    /// Every string at most `limit` characters, so one runaway note cannot fill the file.
    func capped(_ limit: Int) -> VoiceNoteTrace {
        func cap(_ text: String) -> String { text.count > limit ? String(text.prefix(limit)) : text }
        var copy = self
        copy.liveTranscript = cap(liveTranscript)
        copy.finalTranscript = cap(finalTranscript)
        copy.engineWhy = engineWhy.map(cap)
        copy.phrases = phrases.map { TimedPhrase(text: cap($0.text), start: $0.start, end: $0.end) }
        copy.resets = resets.map { TranscriptReset(at: $0.at, before: cap($0.before), after: cap($0.after)) }
        copy.grounded = grounded.map(cap)
        copy.saved = saved.map { Saved(title: cap($0.title), due: $0.due, list: $0.list, id: $0.id) }
        copy.parts = parts.map { part in
            var part = part
            part.text = cap(part.text)
            part.prompt = cap(part.prompt)
            part.carried = part.carried.map(cap)
            part.outcome = cap(part.outcome)
            part.answer = part.answer.map {
                RawTodo(spoken: $0.spoken.map(cap), title: cap($0.title), dueISO8601: $0.dueISO8601.map(cap),
                        hasTime: $0.hasTime)
            }
            return part
        }
        return copy
    }
}

/// The log's file: Library/Application Support/Internal/voice-notes.json in Taken's own container. The newest 20
/// notes, none older than 14 days, every string at most 20,000 characters, the file under 2 MB (the oldest go first),
/// written atomically, readable after the first unlock (a note can finish after a lock, as todos.json can), and left
/// out of iCloud and device backups.
final class VoiceNoteLogStore: @unchecked Sendable {
    static let shared = VoiceNoteLogStore(fileURL: defaultURL)
    static let maxNotes = 20
    static let maxAge: TimeInterval = 14 * 24 * 60 * 60
    static let maxCharacters = 20_000
    static let maxBytes = 2_000_000

    static var defaultURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("Internal", isDirectory: true).appendingPathComponent("voice-notes.json")
    }

    let fileURL: URL
    private let queue = DispatchQueue(label: "com.tombaxter.taken.voice-note-log")
    /// When the log was last cleared, read and written on `queue` only: a note begun before it never writes the file
    /// back (a note still being sorted, or its token count, finishing after Clear or Erase all data).
    private var erasedAt: Date?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Newest first.
    func load() -> [VoiceNoteTrace] {
        queue.sync { read() }
    }

    /// Adds the note, or replaces its earlier record, off the main thread.
    func save(_ trace: VoiceNoteTrace, now: Date = Date()) {
        queue.async { [self] in
            if let erasedAt, trace.startedAt < erasedAt { return }
            var all = read()
            all.removeAll { $0.id == trace.id }
            all.insert(trace, at: 0)
            write(Self.trimmed(all, now: now))
        }
    }

    /// Clear, and Erase all data: no file is left, and none comes back from a note begun before.
    func erase() {
        queue.sync {
            erasedAt = Date()
            _ = try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Waits for writes still on their way (tests).
    func flush() {
        queue.sync {}
    }

    /// The notes kept: newest first, at most `maxNotes`, none older than `maxAge`, strings capped, under `maxBytes`.
    static func trimmed(_ traces: [VoiceNoteTrace], now: Date) -> [VoiceNoteTrace] {
        var kept = traces
            .filter { now.timeIntervalSince($0.startedAt) <= maxAge }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(maxNotes)
            .map { $0.capped(maxCharacters) }
        // Each note's share of the file, measured once; the oldest go until the rest fits.
        let encoder = makeEncoder()
        var sizes = kept.map { (try? encoder.encode($0))?.count ?? 0 }
        while kept.count > 1, sizes.reduce(0, +) + kept.count + 1 > maxBytes {
            kept.removeLast()
            sizes.removeLast()
        }
        return kept
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func read() -> [VoiceNoteTrace] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([VoiceNoteTrace].self, from: data)) ?? []
    }

    private func write(_ traces: [VoiceNoteTrace]) {
        guard let data = try? Self.makeEncoder().encode(traces) else { return }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard (try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
        else { return }
        // Set on every save: an atomic write replaces the file, and with it the old file's flag.
        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}

/// The log as plain text, one labelled line per field, in the sorting eval's report style.
enum VoiceNoteLog {
    /// "17:18 · Work · 34 s · stopped: tap · 1 to-do"
    static func row(_ trace: VoiceNoteTrace, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: trace.startedAt)
        let list = TodoArea(stored: trace.list).title
        let seconds = Int((trace.marks.first { $0.label == "stop" } ?? trace.marks.last)?.seconds ?? 0)
        var fields = [String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0), list, "\(seconds) s"]
        fields.append(trace.input == .typed ? VoiceNoteLogCopy.typed : "\(VoiceNoteLogCopy.stopped): \(trace.stopReason ?? "?")")
        fields.append(VoiceNoteLogCopy.toDos(trace.saved.count))
        return fields.joined(separator: " \u{00B7} ")
    }

    static func report(_ traces: [VoiceNoteTrace]) -> String {
        traces.map(report).joined(separator: "\n\n")
    }

    static func report(_ trace: VoiceNoteTrace) -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["Taken voice note, build \(trace.build), iOS \(trace.system)",
                     "Started: \(formatter.string(from: trace.startedAt))",
                     "Input: \(trace.input.rawValue)",
                     "List: \(trace.list), chip changed: \(trace.chipChanged ? "yes" : "no")",
                     "Locale: \(trace.locale), vocabulary \(trace.vocabulary)",
                     "Engine: \(trace.engine ?? "none")" + (trace.engineWhy.map { ", because \($0)" } ?? ""),
                     "Stopped: \(trace.stopReason ?? "none"), \(trace.wordsAtStop) words heard",
                     "Heard: \(trace.finalTranscript)"]
        if trace.liveTranscript != trace.finalTranscript && !trace.liveTranscript.isEmpty {
            lines.append("Live card: \(trace.liveTranscript)")
        }
        lines.append("Used the live text: \(trace.usedLiveText ? "yes" : "no")")
        lines.append("Events: \(trace.eventCount), restarts: \(trace.restarts)")
        for phrase in trace.phrases {
            lines.append(String(format: "Phrase %.1f to %.1f s: ", phrase.start, phrase.end) + phrase.text)
        }
        for reset in trace.resets {
            lines.append(String(format: "Reset at %.1f s: ", reset.at) + "before \"\(reset.before)\", after \"\(reset.after)\"")
        }
        for part in trace.parts {
            let tokens = part.promptTokens.map { ", \($0) tokens" } ?? ""
            lines.append("Part \(part.index + 1): \(part.cut) cut, words \(part.words), "
                         + String(format: "sent at %.1f s, %.1f s, ", part.sentAt, part.seconds)
                         + "\(part.outcome), \(part.prompt.count) prompt characters\(tokens)")
            if let carried = part.carried { lines.append("Part \(part.index + 1) carried: \(carried)") }
            lines.append("Part \(part.index + 1) words: \(part.text)")
            for task in part.answer {
                lines.append("Part \(part.index + 1) model: spoken \"\(task.spoken ?? "")\", title \"\(task.title)\", due "
                             + "\(task.dueISO8601 ?? "none"), time \(task.hasTime)")
            }
        }
        lines.append("Sorting: \(trace.sorting ?? "none")")
        for task in trace.grounded { lines.append("After grounding: \(task)") }
        for task in trace.saved {
            lines.append("Saved: \(task.title)" + (task.due.map { " (\($0))" } ?? "") + " on \(task.list), \(task.id.uuidString)")
        }
        lines.append("Timings: " + trace.marks.map { String(format: "%@ %.1f s", $0.label, $0.seconds) }.joined(separator: ", "))
        lines.append("Context: now \(trace.contextNow ?? "none"), zone \(trace.timeZone ?? "none"), day starts "
                     + String(format: "%02d:00", trace.dayStartHour ?? 0)
                     + ", context size \(trace.contextSize.map(String.init) ?? "unknown")")
        return lines.joined(separator: "\n")
    }

    static func outcome(_ outcome: ChunkOutcome) -> String {
        switch outcome {
        case .model: return "model"
        case .timedOut: return "timed out"
        case .failed(let reason): return "error: \(reason)"
        case .unavailable(let sorting): return "unavailable: \(sorting)"
        }
    }

    /// "2026-10-21 09:00", "2026-10-23", nil.
    static func due(_ due: TodoDue?, clock: DayClock) -> String? {
        switch due {
        case nil: return nil
        case .day(let day): return day.iso
        case .time(let date):
            let parts = clock.calendar.dateComponents([.hour, .minute], from: date)
            return TodoText.calendarDay(date, clock: clock).iso + String(format: " %02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        }
    }

    /// On the clipboard for ten minutes, then gone: a note's words are personal.
    @MainActor
    static func copy(_ text: String) {
        UIPasteboard.general.setItems([[UTType.plainText.identifier: text]],
                                      options: [.expirationDate: Date().addingTimeInterval(10 * 60)])
    }
}

/// Where taken://todo-log sends the app: the log over whatever is open, in an internal build with the marker only.
@MainActor
@Observable
final class VoiceNoteLogRoute {
    static let shared = VoiceNoteLogRoute()
    static let host = "todo-log"
    static let link = URL(string: "taken://todo-log")!

    var isPresented = false

    static func isRequest(_ url: URL, unlocked: Bool = InternalBuild.unlocksPro) -> Bool {
        guard unlocked, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.scheme == TodoCaptureRoute.scheme && components.host == host
    }

    /// The log link: the sheet comes up once any sheet the link closed has gone. False for any other link, and for
    /// every link without the TakenInternalPro marker.
    @discardableResult
    func handle(url: URL, unlocked: Bool = InternalBuild.unlocksPro) -> Bool {
        guard Self.isRequest(url, unlocked: unlocked) else { return false }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.isPresented = true
        }
        return true
    }
}

/// The log: the newest note first; a note's detail; Copy, Share, Copy all and Clear.
struct VoiceNoteLogView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var traces: [VoiceNoteTrace] = []
    @State private var confirmClear = false
    @State private var copied = false
    private let store: VoiceNoteLogStore

    init(store: VoiceNoteLogStore = .shared) {
        self.store = store
    }

    var body: some View {
        NavigationStack {
            List {
                if traces.isEmpty {
                    Text(verbatim: VoiceNoteLogCopy.empty)
                        .font(.sans(15, relativeTo: .body))
                        .foregroundStyle(theme.fgMuted)
                        .listRowBackground(theme.bgRaised)
                }
                ForEach(traces) { trace in
                    NavigationLink {
                        VoiceNoteDetailView(trace: trace)
                    } label: {
                        Text(verbatim: VoiceNoteLog.row(trace))
                            .font(.mono(13, .monoMedium, relativeTo: .footnote))
                            .foregroundStyle(theme.fg)
                            .padding(.vertical, 6)
                    }
                    .listRowBackground(theme.bgRaised)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle(VoiceNoteLogCopy.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(VoiceNoteLogCopy.done) { dismiss() }
                        .foregroundStyle(theme.fgMuted)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button(copied ? VoiceNoteLogCopy.copied : VoiceNoteLogCopy.copyAll) {
                        VoiceNoteLog.copy(VoiceNoteLog.report(traces))
                        copied = true
                    }
                    .disabled(traces.isEmpty)
                    Button(VoiceNoteLogCopy.clear, role: .destructive) { confirmClear = true }
                        .disabled(traces.isEmpty)
                }
            }
            .confirmationDialog(VoiceNoteLogCopy.clearQuestion, isPresented: $confirmClear, titleVisibility: .visible) {
                Button(VoiceNoteLogCopy.clear, role: .destructive) {
                    store.erase()
                    traces = []
                }
                Button(VoiceNoteLogCopy.cancel, role: .cancel) {}
            }
        }
        .onAppear { traces = store.load() }
        .presentationBackground(theme.bg)
        .preferredColorScheme(theme.scheme)
        .tint(theme.signalInk)
    }
}

/// One note: Heard, the live card (when it differs), the parts, the resets, the model's answers, the tasks after
/// grounding, what was saved, the timings and the context.
private struct VoiceNoteDetailView: View {
    @Environment(\.theme) private var theme
    let trace: VoiceNoteTrace
    @State private var copied = false

    init(trace: VoiceNoteTrace) {
        self.trace = trace
    }

    var body: some View {
        List {
            section(VoiceNoteLogCopy.heard, [trace.finalTranscript])
            if !trace.liveTranscript.isEmpty && trace.liveTranscript != trace.finalTranscript {
                section(VoiceNoteLogCopy.liveCard, [trace.liveTranscript])
            }
            section(VoiceNoteLogCopy.parts, trace.parts.map { part in
                "\(part.index + 1). \(part.cut), words \(part.words), " + String(format: "%.1f s, ", part.seconds)
                    + part.outcome + (part.carried.map { ", carried \"\($0)\"" } ?? "") + "\n" + part.text
            })
            if !trace.resets.isEmpty {
                section(VoiceNoteLogCopy.resets, trace.resets.map { String(format: "%.1f s: ", $0.at) + "\($0.before) | \($0.after)" },
                        color: theme.signalInk)
            }
            section(VoiceNoteLogCopy.model, trace.parts.flatMap { part in
                part.answer.map { "\(part.index + 1). \($0.title) (\"\($0.spoken ?? "")\", \($0.dueISO8601 ?? "no due"))" }
            })
            section(VoiceNoteLogCopy.afterGrounding, trace.grounded)
            section(VoiceNoteLogCopy.saved, trace.saved.map { $0.title + ($0.due.map { " (\($0))" } ?? "") + ", \($0.list)" })
            section(VoiceNoteLogCopy.timings, trace.marks.map { String(format: "%@ %.1f s", $0.label, $0.seconds) })
            section(VoiceNoteLogCopy.context, [
                "\(trace.input.rawValue), \(trace.list), chip changed \(trace.chipChanged ? "yes" : "no")",
                "\(trace.engine ?? "none")" + (trace.engineWhy.map { ", \($0)" } ?? ""),
                "\(trace.contextNow ?? "none"), \(trace.timeZone ?? "none"), build \(trace.build), iOS \(trace.system)",
            ])
        }
        .scrollContentBackground(.hidden)
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle(VoiceNoteLog.row(trace))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(copied ? VoiceNoteLogCopy.copied : VoiceNoteLogCopy.copy) {
                    VoiceNoteLog.copy(VoiceNoteLog.report(trace))
                    copied = true
                }
                ShareLink(item: VoiceNoteLog.report(trace)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(VoiceNoteLogCopy.share)
            }
        }
    }

    private func section(_ title: String, _ lines: [String], color: Color? = nil) -> some View {
        Section {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: line)
                    .font(.mono(12, .mono, relativeTo: .footnote))
                    .foregroundStyle(color ?? theme.fg)
                    .textSelection(.enabled)
            }
            if lines.isEmpty {
                Text(verbatim: VoiceNoteLogCopy.none)
                    .font(.mono(12, .mono, relativeTo: .footnote))
                    .foregroundStyle(theme.fgSubtle)
            }
        } header: {
            Text(verbatim: title)
                .font(.sans(13, .sansSemibold, relativeTo: .footnote))
                .foregroundStyle(theme.fgSubtle)
                .textCase(nil)
        }
        .listRowBackground(theme.bgRaised)
    }
}

/// The log's words. In `all`, so the copy test holds them to the same rules as every other string.
enum VoiceNoteLogCopy {
    static let title = "Voice note log"
    static let section = "Internal"
    static let done = "Done"
    static let copy = "Copy"
    static let copyAll = "Copy all"
    static let copied = "Copied"
    static let share = "Share"
    static let clear = "Clear"
    static let cancel = "Cancel"
    static let clearQuestion = "Clear the voice note log?"
    static let empty = "No voice notes yet. Each note you make shows here for 14 days."
    static let typed = "typed"
    static let stopped = "stopped"
    static let heard = "Heard"
    static let liveCard = "Live card"
    static let parts = "Parts"
    static let resets = "Resets"
    static let model = "Model"
    static let afterGrounding = "After grounding"
    static let saved = "Saved"
    static let timings = "Timings"
    static let context = "Context"
    static let none = "None"

    static func toDos(_ count: Int) -> String { count == 1 ? "1 to-do" : "\(count) to-dos" }

    static let all: [String] = [title, section, done, copy, copyAll, copied, share, clear, cancel, clearQuestion, empty,
                                typed, stopped, heard, liveCard, parts, resets, model, afterGrounding, saved, timings,
                                context, none, toDos(1), toDos(3)]
}
#endif
