import AppIntents
import SwiftUI
import WidgetKit

/// Control Center, Lock Screen and Action button: one tap logs every pending dose.
@available(iOS 18.0, *)
struct TakeAllControl: ControlWidget {
    static let kind = "com.tombaxter.taken.control.take-all"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: TakeAllIntent()) {
                Label("Take all", systemImage: "pill.fill")
            }
        }
        .displayName("Take all")
        .description("Log every pending dose in your stack.")
    }
}
