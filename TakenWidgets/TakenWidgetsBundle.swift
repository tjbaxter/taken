import SwiftUI
import WidgetKit

@main
struct TakenWidgetsBundle: WidgetBundle {
    var body: some Widget {
        StackWidget()
        if #available(iOS 18.0, *) {
            TakeAllControl()
        }
    }
}
