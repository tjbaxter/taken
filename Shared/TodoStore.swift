import Foundation

/// Reads and writes `todos.json` in the App Group, next to the log, with the same file coordination as `TakenStore`,
/// so the app, the widget extension and App Intents never overwrite each other.
final class TodoStore: Sendable {
    static let fileName = "todos.json"
    static let shared = TodoStore(fileURL: TakenStore.defaultFileURL().deletingLastPathComponent()
        .appendingPathComponent(TodoStore.fileName))

    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Coordinated read. A missing or unreadable file reads as no tasks.
    func load() -> TodoState {
        var state = TodoState()
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { url in
            if let data = try? Data(contentsOf: url), let decoded = try? Self.decode(data) {
                state = decoded
            }
        }
        return state
    }

    /// Coordinated read-modify-write. The closure sees the latest file.
    @discardableResult
    func update<T>(_ body: (inout TodoState) throws -> T) throws -> (state: TodoState, value: T) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var output: (state: TodoState, value: T)?
        var thrown: (any Error)?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: fileURL, options: .forMerging, error: &coordinationError) { url in
            do {
                var state = Self.readForWrite(url)
                let value = try body(&state)
                try Self.encode(state).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                output = (state, value)
            } catch {
                thrown = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let thrown { throw thrown }
        guard let output else { throw CocoaError(.fileWriteUnknown) }
        return output
    }

    func replace(with state: TodoState) throws {
        try update { $0 = state }
    }

    static func encode(_ state: TodoState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(state)
    }

    static func decode(_ data: Data) throws -> TodoState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(TodoState.self, from: data)
    }

    /// Inside a write: a file that cannot be read is kept aside, never silently overwritten.
    private static func readForWrite(_ url: URL) -> TodoState {
        guard let data = try? Data(contentsOf: url) else { return TodoState() }
        if let state = try? decode(data) { return state }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingLastPathComponent().appendingPathComponent("todos-unreadable-\(stamp).json")
        try? data.write(to: backup, options: .atomic)
        return TodoState()
    }
}
