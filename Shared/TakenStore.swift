import Foundation

/// The only reader and writer of Taken's data: one JSON file in the App Group container.
/// Every write is a coordinated read-modify-write (NSFileCoordinator), so the app, the widget
/// extension, App Intents and notification actions never clobber each other.
final class TakenStore: Sendable {
    static let appGroupID = "group.com.tombaxter.taken"
    static let fileName = "taken.json"
    static let shared = TakenStore(fileURL: TakenStore.defaultFileURL())

    let fileURL: URL
    let postsChangeNotifications: Bool

    init(fileURL: URL, postsChangeNotifications: Bool = true) {
        self.fileURL = fileURL
        self.postsChangeNotifications = postsChangeNotifications
    }

    static func defaultFileURL() -> URL {
        let fileManager = FileManager.default
        let directory: URL
        if let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            directory = group.appendingPathComponent("Library/Application Support", isDirectory: true)
        } else if let support = try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true) {
            directory = support
        } else {
            directory = fileManager.temporaryDirectory
        }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }

    /// Coordinated read. A missing or unreadable file reads as an empty stack.
    func load() -> StackState {
        var state = StackState()
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { url in
            if let data = try? Data(contentsOf: url), let decoded = try? Self.decode(data) {
                state = decoded
            }
        }
        return state
    }

    /// Coordinated read-modify-write. The closure sees the latest state on disk.
    @discardableResult
    func update<T>(_ body: (inout StackState) throws -> T) throws -> (state: StackState, value: T) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var output: (state: StackState, value: T)?
        var thrown: (any Error)?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: fileURL, options: .forMerging, error: &coordinationError) { url in
            do {
                var state = Self.readForWrite(url)
                let value = try body(&state)
                let data = try Self.encode(state)
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                output = (state, value)
            } catch {
                thrown = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let thrown { throw thrown }
        guard let output else { throw CocoaError(.fileWriteUnknown) }
        if postsChangeNotifications { Sync.postDarwinNotification() }
        return output
    }

    /// Replace everything (demo seeding, erase).
    func replace(with state: StackState) throws {
        try update { current in current = state }
    }

    // MARK: Encoding

    static func encode(_ state: StackState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(state)
    }

    static func decode(_ data: Data) throws -> StackState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(StackState.self, from: data)
    }

    /// Inside a write: a corrupt file is kept aside (never silently overwritten) and the stack starts fresh.
    private static func readForWrite(_ url: URL) -> StackState {
        guard let data = try? Data(contentsOf: url) else { return StackState() }
        if let state = try? decode(data) { return state }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingLastPathComponent().appendingPathComponent("taken-unreadable-\(stamp).json")
        try? data.write(to: backup, options: .atomic)
        return StackState()
    }
}
