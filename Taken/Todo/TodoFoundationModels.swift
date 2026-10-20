import Foundation
#if canImport(FoundationModels)
import FoundationModels

// Apple Foundation Models (iOS 26, Apple Intelligence): the on-device model sorts a ramble into tasks with guided
// generation, so its answer is always this shape. Nothing leaves the iPhone. Code then checks every task against the
// words said (TodoGrounding) and every date and title (TodoValidation) before anything is saved.

@available(iOS 26.0, *)
@Generable(description: "The to-do list from one voice note")
struct GeneratedTodoList {
    @Guide(description: "One entry for each separate action, in the order said", .maximumCount(20))
    var tasks: [GeneratedTodo]
}

/// Properties are generated in the order they are declared, so `spoken` is written first: the model copies the words
/// it is working from before it names the task, and code can check them.
@available(iOS 26.0, *)
@Generable(description: "One thing to do")
struct GeneratedTodo {
    // Short on purpose: the iPhone writes about 30 tokens a second, and a note falls back to one task after
    // TodoModel.sortingLimit. TodoGrounding still places a shortened span.
    @Guide(description: "The exact words of the note for this action, at most 12 words, copied")
    var spoken: String

    @Guide(description: "2 to 7 of the speaker's words, starting with the action, every name kept as said")
    var title: String

    @Guide(description: "When it is due in local time, YYYY-MM-DDTHH:MM:00, or YYYY-MM-DD when only a day was said. Empty when no day or time was said for it.")
    var dueISO8601: String?

    @Guide(description: "True only when a clock time was said for it")
    var hasTime: Bool
}

/// The on-device model as a `TaskExtractor`. `prepare()` loads it while the person is still talking, so the tasks
/// come back about a second after they stop.
@available(iOS 26.0, *)
final class FoundationModelsExtractor: TaskExtractor, @unchecked Sendable {
    private let lock = NSLock()
    private var prepared: LanguageModelSession?

    init() {}

    /// Nil when the model can run now (an Apple Intelligence iPhone with it turned on and the model downloaded),
    /// otherwise why not, for the one line under the list.
    static var unavailableReason: TodoSorting? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.appleIntelligenceNotEnabled): return .appleIntelligenceOff
        case .unavailable(.modelNotReady): return .modelNotReady
        default: return .needsAppleIntelligence
        }
    }

    func prepare() async {
        let session = Self.makeSession()
        session.prewarm()
        lock.withLock { prepared = session }
    }

    func extract(transcript: String, context: TodoContext) async -> TodoExtraction {
        let words = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return TodoExtraction(drafts: [], sorting: .model) }
        do {
            let raw = try await answer(transcript: words, context: context)
            return TodoExtraction(drafts: TodoValidation.validate(raw, transcript: words, context: context), sorting: .model)
        } catch {
            // Guardrails, an unsupported language, a context that ran out: the note is still saved, as one task.
            return TodoExtraction(drafts: TodoValidation.wholeNote(words), sorting: .couldNotSort)
        }
    }

    /// The model's answer as it wrote it, before any check: what `extract` validates, and what the internal sorting
    /// eval shows beside the saved tasks.
    func answer(transcript words: String, context: TodoContext) async throws -> [RawTodo] {
        // One session per note, so one note's answer never colours the next.
        let session = lock.withLock { () -> LanguageModelSession in
            defer { prepared = nil }
            return prepared ?? Self.makeSession()
        }
        let response = try await session.respond(
            to: TodoPrompt.prompt(transcript: words, context: context),
            generating: GeneratedTodoList.self,
            options: GenerationOptions(samplingMode: .greedy)
        )
        return response.content.tasks.map {
            RawTodo(spoken: $0.spoken, title: $0.title, dueISO8601: $0.dueISO8601, hasTime: $0.hasTime)
        }
    }

    private static func makeSession() -> LanguageModelSession {
        LanguageModelSession(instructions: TodoPrompt.instructions)
    }
}
#endif
