import Foundation
import WidgetKit

/// What happens after any write, from any process (app, widget, intent, notification action).
enum Sync {
    static let darwinNotificationName = "com.tombaxter.taken.didChange"

    /// Refresh widgets and the Control Center control, tell other processes, reschedule the nudge.
    static func afterWrite(_ state: StackState) async {
        await MainActor.run {
            WidgetCenter.shared.reloadAllTimelines()
            if #available(iOS 18.0, *) {
                ControlCenter.shared.reloadAllControls()
            }
        }
        await Reminders.reschedule(state: state, now: Date())
    }

    static func postDarwinNotification() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(center, CFNotificationName(darwinNotificationName as CFString), nil, nil, true)
    }
}

/// Listens for writes made by another process (widget, intents) through a Darwin notification.
final class DarwinObserver: @unchecked Sendable {
    private let handler: @Sendable () -> Void

    init(name: String = Sync.darwinNotificationName, handler: @escaping @Sendable () -> Void) {
        self.handler = handler
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            Unmanaged<DarwinObserver>.fromOpaque(observer).takeUnretainedValue().fire()
        }, name as CFString, nil, .deliverImmediately)
    }

    private func fire() { handler() }

    deinit {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveEveryObserver(center, Unmanaged.passUnretained(self).toOpaque())
    }
}
