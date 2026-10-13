import Foundation
#if canImport(FoundationModels)
import FoundationModels

// Apple Foundation Models (iOS 26, Apple Intelligence): the on-device model sorts a ramble into tasks with guided
// generation, so its answer is always this shape. Nothing leaves the iPhone. Code then checks every date and title
// (TodoValidation) before anything is saved.

@available(iOS 26.0, *)
@Generable(description: "The to-do list from one voice note")
struct GeneratedTodoList {
    @Guide(description: "Every separate thing the speaker needs to do, in the order it was said")
    var tasks: [GeneratedTodo]
}

@available(iOS 26.0, *)
@Generable(description: "One thing to do")
struct GeneratedTodo {
    @Guide(description: "Short, starts with a verb, in the speaker's words, like: Call the dentist")
    var title: String

    @Guide(description: "When it is due, as local ISO 8601 like 2026-10-13T16:00:00, or a date like 2026-10-14. Empty when no day or time was said for it.")
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

    /// The model can run now: an Apple Intelligence iPhone with it turned on and the model downloaded.
    static var isAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available: return true
        default: return false
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
        // One session per note, so one note's answer never colours the next.
        let session = lock.withLock { () -> LanguageModelSession in
            defer { prepared = nil }
            return prepared ?? Self.makeSession()
        }
        do {
            let response = try await session.respond(
                to: TodoPrompt.prompt(transcript: words, context: context),
                generating: GeneratedTodoList.self,
                options: GenerationOptions(sampling: .greedy)
            )
            let raw = response.content.tasks.map { RawTodo(title: $0.title, dueISO8601: $0.dueISO8601, hasTime: $0.hasTime) }
            return TodoExtraction(drafts: TodoValidation.validate(raw, transcript: words, context: context), sorting: .model)
        } catch {
            // Guardrails, an unsupported language, a context that ran out: the note is still saved, as one task.
            return TodoExtraction(drafts: TodoValidation.wholeNote(words), sorting: .couldNotSort)
        }
    }

    private static func makeSession() -> LanguageModelSession {
        LanguageModelSession(instructions: TodoPrompt.instructions)
    }
}
#endif
