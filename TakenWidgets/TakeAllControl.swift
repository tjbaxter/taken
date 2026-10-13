import AppIntents
import SwiftUI
import WidgetKit

/// Control Center, Lock Screen and Action button: one tap logs every pending dose. Without Taken Pro it shows a
/// lock and logs nothing; the tap is kept, and Taken offers it with the paywall the next time it opens.
@available(iOS 18.0, *)
struct TakeAllControl: ControlWidget {
    static let kind = "com.tombaxter.taken.control.take-all"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: LockedProvider()) { locked in
            ControlWidgetButton(action: TakeAllIntent()) {
                Label(locked ? "Taken Pro" : "Take all", systemImage: locked ? "lock.fill" : "pill.fill")
            }
        }
        .displayName("Take all")
        .description("Log every pending dose in your stack.")
    }
}

/// Whether logging needs Taken Pro, read from the answer the app cached in the App Group.
@available(iOS 18.0, *)
struct LockedProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        let state = TakenStore.shared.load()
        return !ProGate.access(ledger: ProLedgerStore.shared.load(), state: state, now: Date()).allowsLogging
    }
}
