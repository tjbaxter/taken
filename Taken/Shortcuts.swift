import AppIntents

/// Siri phrases. Every phrase names the app, as App Shortcuts require.
struct TakenShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TakeAllIntent(),
            phrases: [
                "Log my stack in \(.applicationName)",
                "I took my pills in \(.applicationName)",
                "Take all in \(.applicationName)",
            ],
            shortTitle: "Take all",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: CheckStackIntent(),
            phrases: [
                "Did I take my pills in \(.applicationName)",
                "Check my stack in \(.applicationName)",
                "Did I take it in \(.applicationName)",
            ],
            shortTitle: "Did I take it?",
            systemImageName: "questionmark.circle"
        )
        AppShortcut(
            intent: LogItemIntent(),
            phrases: [
                "Log \(\.$item) in \(.applicationName)",
                "I took \(\.$item) in \(.applicationName)",
            ],
            shortTitle: "Log item",
            systemImageName: "pill"
        )
        AppShortcut(
            intent: NewVoiceTodoIntent(target: .recording),
            phrases: [
                "Add to-dos in \(.applicationName)",
                "New voice to-do in \(.applicationName)",
                "Add a to-do in \(.applicationName)",
            ],
            shortTitle: "New voice to-do",
            systemImageName: "mic"
        )
        // Reads the list out, and hands it on in a shortcut (TodoAgentIntents.swift). "Add to-do" needs a title, which
        // a phrase cannot carry, so it stays an action in Shortcuts.
        AppShortcut(
            intent: GetTodosIntent(),
            phrases: [
                "What's on my to-do list in \(.applicationName)",
            ],
            shortTitle: "Get to-dos",
            systemImageName: "checklist"
        )
    }
}
