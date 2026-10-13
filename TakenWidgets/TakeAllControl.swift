import AppIntents
import SwiftUI
import WidgetKit

/// Control Center, Lock Screen and Action button: one tap logs every pending dose. Without Taken Pro it shows a
/// lock and logs nothing; the tap is kept, and Taken offers it with the paywall the next time it opens. Its tint is
/// the signal colour of the look chosen in the app.
@available(iOS 18.0, *)
struct TakeAllControl: ControlWidget {
    static let kind = "com.tombaxter.taken.control.take-all"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: ControlLookProvider()) { look in
            ControlWidgetButton(action: TakeAllIntent()) {
                Label(look.locked ? "Taken Pro" : "Take all", systemImage: look.locked ? "lock.fill" : "pill.fill")
            }
            .tint(look.theme.theme.signal)
        }
        .displayName("Take all")
        .description("Log every pending dose in your stack.")
    }
}

/// What the control shows, read from the App Group store the app writes: whether logging needs Taken Pro, and the look.
@available(iOS 18.0, *)
struct ControlLook: Hashable, Sendable {
    var locked: Bool
    var theme: ThemeID
}

@available(iOS 18.0, *)
struct ControlLookProvider: ControlValueProvider {
    /// The controls gallery: unlocked, in the look chosen in the app.
    var previewValue: ControlLook { ControlLook(locked: false, theme: TakenStore.shared.load().settings.theme) }

    func currentValue() async throws -> ControlLook {
        let state = TakenStore.shared.load()
        let locked = !ProGate.access(ledger: ProLedgerStore.shared.load(), state: state, now: Date()).allowsLogging
        return ControlLook(locked: locked, theme: state.settings.theme)
    }
}
