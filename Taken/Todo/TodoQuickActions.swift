import SwiftUI
import UIKit

// The Home Screen quick action (touch and hold the icon): "New voice to-do", declared in Info.plist
// (UIApplicationShortcutItems). SwiftUI has no hook for quick actions, so UIKit's: a cold launch brings the item to
// the app delegate's scene configuration, a running app to the scene delegate (UIKit, "Add Home Screen quick actions").

extension AppDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if let item = options.shortcutItem {
            TodoQuickAction.handle(item)
        }
        #if DEBUG
        TodoQuickAction.openDemoLinkIfAsked()
        #endif
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = TodoSceneDelegate.self
        return configuration
    }
}

/// Receives quick actions while Taken is running. SwiftUI keeps its own scene handling.
final class TodoSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem) async -> Bool {
        TodoQuickAction.handle(shortcutItem)
    }
}

@MainActor
enum TodoQuickAction {
    @discardableResult
    static func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard item.type == TodoCaptureRoute.quickActionType else { return false }
        TodoCaptureRoute.shared.requestRecording()
        return true
    }

    #if DEBUG
    /// CI only (`-demo -open-url taken://pro`): Taken opens one of its own links after launch, the way a widget does,
    /// so the screenshots prove links still reach SwiftUI with this scene delegate in place. Debug builds only, like
    /// every `-demo` argument (Guideline 2.5.19).
    static func openDemoLinkIfAsked(_ arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard arguments.contains("-demo"), let index = arguments.firstIndex(of: "-open-url"), index + 1 < arguments.count,
              let url = URL(string: arguments[index + 1]), url.scheme == TodoCaptureRoute.scheme else { return }
        Task {
            try? await Task.sleep(for: .seconds(2))
            _ = await UIApplication.shared.open(url)
        }
    }
    #endif
}
