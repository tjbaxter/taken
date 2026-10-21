import SwiftUI

extension View {
    /// On RootView's tab bar: switches to the To-do tab when Siri, Shortcuts, the Action button, the control, the Lock
    /// Screen, a `taken://todo` link, a due-time notification or the Home Screen quick action ask for it, and on launch
    /// for `-screen todo`, `todo-recording`, `todo-cap` and `todo-empty`. `select` brings the To-do tab to the front (and closes any
    /// sheet over it: `AppModel.openTodoTab`).
    func opensTodoTab(_ select: @escaping @MainActor () -> Void) -> some View {
        modifier(TodoTabSwitch(select: select))
    }
}

private struct TodoTabSwitch: ViewModifier {
    @State private var route = TodoCaptureRoute.shared
    let select: @MainActor () -> Void

    init(select: @escaping @MainActor () -> Void) {
        self.select = select
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                // A cold launch asks before the tab bar exists; the screenshots name the tab.
                let screenshot = TodoModel.opensOnTodo(TodoModel.shared.launchScreen)
                if route.takeTabRequest() || screenshot { select() }
            }
            .onChange(of: route.tabRequests) { _, _ in
                if route.takeTabRequest() { select() }
            }
    }
}
