import Foundation

/// Reads and writes `weights.json` in the App Group, next to the log, the way `TodoStore` keeps `todos.json`: coordinated
/// reads and read-modify-writes (NSFileCoordinator), atomic writes with complete protection until first unlock, a file
/// that cannot be read set aside rather than overwritten, and a Darwin notification after each write. Its own file, so a
/// build without the Weight tab never reads or rewrites it.
final class WeightStore: Sendable {
    static let fileName = "weights.json"
    static let darwinNotificationName = "com.tombaxter.taken.weights.didChange"
    static let shared = WeightStore(fileURL: TakenStore.defaultFileURL().deletingLastPathComponent()
        .appendingPathComponent(WeightStore.fileName))

    let fileURL: URL
    let postsChangeNotifications: Bool

    init(fileURL: URL, postsChangeNotifications: Bool = true) {
        self.fileURL = fileURL
        self.postsChangeNotifications = postsChangeNotifications
    }

    /// Coordinated read. A missing or unreadable file reads as no weigh-ins and the tab off.
    func load() -> WeightState {
        var state = WeightState()
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
    func update<T>(_ body: (inout WeightState) throws -> T) throws -> (state: WeightState, value: T) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var output: (state: WeightState, value: T)?
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
        if postsChangeNotifications { Self.postDarwinNotification() }
        return output
    }

    func replace(with state: WeightState) throws {
        try update { $0 = state }
    }

    /// Erase all data: the copies of a file that could not be read, set aside by a write (`weights-unreadable-*.json`).
    func removeSetAsideCopies() {
        TakenStore.removeFiles(in: fileURL.deletingLastPathComponent(), prefix: "weights-unreadable-")
    }

    static func postDarwinNotification() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(darwinNotificationName as CFString), nil, nil, true)
    }

    static func encode(_ state: WeightState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(state)
    }

    static func decode(_ data: Data) throws -> WeightState {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(WeightState.self, from: data)
    }

    /// Inside a write: a file that cannot be read is kept aside, never silently overwritten.
    private static func readForWrite(_ url: URL) -> WeightState {
        guard let data = try? Data(contentsOf: url) else { return WeightState() }
        if let state = try? decode(data) { return state }
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = url.deletingLastPathComponent().appendingPathComponent("weights-unreadable-\(stamp).json")
        try? data.write(to: backup, options: .atomic)
        return WeightState()
    }
}
