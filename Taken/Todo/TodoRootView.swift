import SwiftUI

/// The To-do tab (voice to-dos). Placeholder while the voice capture screen is built.
struct TodoRootView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic")
                .font(.system(size: 34, weight: .regular))
                .accessibilityHidden(true)
            Text("Tap the mic and say what you need to do")
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
