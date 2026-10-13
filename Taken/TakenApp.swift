import SwiftUI
import UserNotifications

@main
struct TakenApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.fromLaunchArguments()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .onOpenURL { model.handle(url: $0) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.didBecomeActive() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationHandler.shared
        Reminders.registerCategories()
        return true
    }
}

/// Handles the nudge: TAKE ALL runs in the background without opening the app; a tap or OPEN opens the
/// app on the day the nudge was for.
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationHandler()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let request = response.notification.request
        let day = Reminders.nudgeDay(identifier: request.identifier, userInfo: request.content.userInfo)
        let action = response.actionIdentifier
        let now = Date()
        if action == Reminders.takeAllActionID {
            // A nudge left over from an earlier day never logs today's doses.
            guard Reminders.isCurrent(nudgeDay: day, state: TakenStore.shared.load(), now: now) else {
                if let day { await Reminders.explainStale(day: day) }
                return
            }
            let result = try? TakenStore.shared.update { state -> [Dose] in
                state.takeAllPending(now: now, clock: DayClock(dayStartHour: state.settings.dayStartHour))
            }
            if let result {
                await Sync.afterWrite(result.state)
            }
        } else if action == UNNotificationDefaultActionIdentifier || action == Reminders.openActionID, let day {
            await MainActor.run { NudgeRoute.shared.open(day) }
        }
    }
}

/// Where a tapped nudge sends the app: the day it was for. The notification handler sets it and the
/// app model opens it, whichever of the two is ready first.
@MainActor
final class NudgeRoute {
    static let shared = NudgeRoute()

    private var handler: (@MainActor (DayKey) -> Void)?
    private var waiting: DayKey?

    func open(_ day: DayKey) {
        if let handler {
            handler(day)
        } else {
            waiting = day
        }
    }

    func attach(_ handler: @escaping @MainActor (DayKey) -> Void) {
        self.handler = handler
        if let day = waiting {
            waiting = nil
            handler(day)
        }
    }
}
