import AppIntents
import Foundation
import Observation

// Quick capture (REDESIGN.md): "one tap, voice note, done". Every way in (Siri, Shortcuts, the Action button, the
// Control Center control, the Lock Screen widget, the Home Screen quick action) opens Taken on the To-do tab already
// listening. Compiled into the app and the widget extension: the control lives in the extension, and the system opens
// the app to run the intent there.

/// Where a voice to-do request sends the app. Set by the intent, a `taken://todo` link or the quick action; the tab
/// bar and the To-do tab read it, whichever is ready first.
@MainActor
@Observable
final class TodoCaptureRoute {
    static let shared = TodoCaptureRoute()

    nonisolated static let scheme = "taken"
    nonisolated static let host = "todo"
    /// `taken://todo/record`: open the To-do tab listening (the Lock Screen mic).
    nonisolated static let recordURL = URL(string: "taken://todo/record")!
    /// `taken://todo`: open the To-do tab (the Lock Screen list).
    nonisolated static let listURL = URL(string: "taken://todo")!
    /// The Home Screen quick action (`UIApplicationShortcutItems` in Info.plist).
    nonisolated static let quickActionType = "com.tombaxter.taken.voice-todo"
    /// The Lock Screen widget (the mic and the open to-dos), reloaded whenever the tasks change.
    nonisolated static let widgetKind = "TakenVoiceTodo"

    /// Goes up by one each time something asks for the To-do tab (the tab bar watches it).
    private(set) var tabRequests = 0
    /// A recording asked for and not started yet.
    private(set) var pendingRecording: Date?
    /// The To-do tab was asked for and the tab bar has not switched yet (a cold launch asks before the tab bar exists).
    @ObservationIgnored private var tabPending = false

    /// Opens the To-do tab listening.
    func requestRecording(at date: Date = Date()) {
        pendingRecording = date
        tabPending = true
        tabRequests += 1
    }

    /// Opens the To-do tab.
    func showList() {
        tabPending = true
        tabRequests += 1
    }

    /// For the tab bar, on appear and whenever `tabRequests` changes: true once per request.
    func takeTabRequest() -> Bool {
        defer { tabPending = false }
        return tabPending
    }

    /// The recording asked for in the last `maxAge` seconds, once.
    func takePendingRecording(now: Date = Date(), maxAge: TimeInterval = 90) -> Bool {
        guard let asked = pendingRecording else { return false }
        pendingRecording = nil
        return now.timeIntervalSince(asked) <= maxAge
    }

    /// `taken://todo` and `taken://todo/record`. False for any other link.
    @discardableResult
    func handle(url: URL) -> Bool {
        guard let route = Self.route(for: url) else { return false }
        switch route {
        case .record: requestRecording()
        case .list: showList()
        }
        return true
    }

    enum Route: Equatable, Sendable {
        case record
        case list
    }

    nonisolated static func route(for url: URL) -> Route? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == scheme, components.host == host else { return nil }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path == "record" ? .record : .list
    }
}

/// The one place "New voice to-do" opens. An enum so the intent can be an `OpenIntent`, which is how a control opens
/// its app (WidgetKit, "Creating controls to perform actions across the system").
enum VoiceTodoTarget: String, AppEnum {
    case recording

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Voice to-do" }
    static var caseDisplayRepresentations: [VoiceTodoTarget: DisplayRepresentation] {
        [.recording: DisplayRepresentation(title: "Start listening")]
    }
}

/// "New voice to-do": opens Taken on the To-do tab, already listening. Siri ("Add to-dos in Taken"), Shortcuts, the
/// Action button and the Control Center control run it.
struct NewVoiceTodoIntent: OpenIntent {
    static var title: LocalizedStringResource { "New voice to-do" }
    static var description: IntentDescription {
        IntentDescription("Opens Taken listening. Say what you need to do and Taken sorts it into to-dos.")
    }

    @Parameter(title: "Open", default: .recording)
    var target: VoiceTodoTarget

    init() {}

    init(target: VoiceTodoTarget) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        TodoCaptureRoute.shared.requestRecording()
        return .result()
    }
}
