import SwiftUI
import WidgetKit

@main
struct TakenWidgetsBundle: WidgetBundle {
    var body: some Widget {
        StackWidget()
        TodoCaptureWidget()
        if #available(iOS 18.0, *) {
            TakeAllControl()
        }
        if #available(iOS 18.0, *) {
            VoiceTodoControl()
        }
    }
}
