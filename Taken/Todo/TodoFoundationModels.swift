import Foundation
#if canImport(FoundationModels)
import FoundationModels

// Apple Foundation Models (iOS 26, Apple Intelligence): the on-device model sorts a ramble into tasks with guided
// generation, so its answer is always this shape. Nothing leaves the iPhone. Code then checks every task against the
// words said (TodoGrounding) and every date and title (TodoValidation) before anything is saved.

@available(iOS 26.0, *)
@Generable(description: "The to-do list from one voice note")
struct GeneratedTodoList {
    // One part of a note is 80 words at most (TodoChunker); 12 tasks is room for every action in it, and a cap keeps
    // the answer inside the session's 4,096 tokens (TN3193: ask for less output).
    @Guide(description: "One entry for each separate action, in the order said", .maximumCount(12))
    var tasks: [GeneratedTodo]
}

/// Properties are generated in the order they are declared, so `spoken` is written first: the model copies the words
/// it is working from before it names the task, and code can check them.
@available(iOS 26.0, *)
@Generable(description: "One thing to do")
struct GeneratedTodo {
    // Short on purpose: the iPhone writes about 30 tokens a second, and a part that misses its time is saved as said.
    // TodoGrounding still places a shortened span.
    @Guide(description: "The exact words of the note for this action, at most 12 words, copied")
    var spoken: String

    @Guide(description: "2 to 7 of the speaker's words, starting with the verb, keeping what it is done to and every name as said")
    var title: String

    @Guide(description: "When it is due in local time, YYYY-MM-DDTHH:MM:00, or YYYY-MM-DD when only a day was said. Empty when no day or time was said for it.")
    var dueISO8601: String?

    @Guide(description: "True only when a clock time was said for it")
    var hasTime: Bool
}

/// The on-device model as a `ChunkSorting`. Each part is answered in a new session (one part's answer never colours
/// the next, and a session never takes a second prompt while it answers the first); the next session is made and
/// prewarmed while the current one answers, so the model is loaded when the next part comes.
@available(iOS 26.0, *)
final class FoundationModelsExtractor: ChunkSorting, @unchecked Sendable {
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

    /// The model's context window in tokens, for the internal voice note log. Read only while the model is available:
    /// Apple says it can fail otherwise.
    static var contextSize: Int? {
        guard unavailableReason == nil else { return nil }
        return SystemLanguageModel.default.contextSize
    }

    /// How many tokens a prompt takes (iOS 26.4 and later), for the log. Nil on earlier versions or on failure.
    static func tokenCount(_ prompt: String) async -> Int? {
        guard #available(iOS 26.4, *), unavailableReason == nil else { return nil }
        return try? await SystemLanguageModel.default.tokenCount(for: prompt)
    }

    var unavailable: TodoSorting? { Self.unavailableReason }

    func prepare() async {
        let session = Self.makeSession()
        session.prewarm()
        lock.withLock { prepared = session }
    }

    func answer(chunk: TodoChunk, prompt: String) async throws -> [RawTodo] {
        let next = Self.makeSession()
        let session = lock.withLock { () -> LanguageModelSession in
            defer { prepared = next }
            return prepared ?? Self.makeSession()
        }
        next.prewarm()
        do {
            let response = try await session.respond(
                to: prompt,
                generating: GeneratedTodoList.self,
                // Non-streaming, as Apple advises for work that may finish in the background (rateLimited applies there).
                options: GenerationOptions(sampling: .greedy)
            )
            return response.content.tasks.map {
                RawTodo(spoken: $0.spoken, title: $0.title, dueISO8601: $0.dueISO8601, hasTime: $0.hasTime)
            }
        } catch let error as LanguageModelSession.GenerationError {
            if case .exceededContextWindowSize = error { throw ChunkSortError.contextExceeded }
            throw error
        }
    }

    private static func makeSession() -> LanguageModelSession {
        LanguageModelSession(instructions: TodoPrompt.instructions)
    }
}
#endif
