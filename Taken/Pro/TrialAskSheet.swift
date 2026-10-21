import SwiftUI

/// The one notification ask right after a trial starts (`TrialAsk`, SPEC 3.9): both reasons on one short sheet and one
/// button, Continue, which opens iOS's own prompt. Apple: ask in context, title the pre-prompt button like Continue,
/// never Allow, "Include only one button", and offer no way "to leave the screen or window without viewing the system
/// alert, like offering an option to close or cancel"
/// (https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications,
/// https://developer.apple.com/design/human-interface-guidelines/privacy). So it has no second button and cannot be
/// swiped away; iOS's alert carries the no.
struct TrialAskSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var busy = false
    /// The content's own height: the sheet is as tall as what it says, not half the screen.
    @State private var contentHeight: CGFloat = 300

    init() {}

    private var bodyText: String {
        TrialAsk.body(mentionsReminder: TrialAsk.mentionsReminder(status: model.pro.status, now: Date()))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "bell")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.onSignal)
                    .frame(width: 40, height: 40)
                    .background(theme.signal, in: Circle())
                    .accessibilityHidden(true)
                Text(TrialAsk.title)
                    .font(.sans(24, .sansSemibold, relativeTo: .title2))
                    .tracking(-0.3)
                    .foregroundStyle(theme.fg)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
                    .accessibilityAddTraits(.isHeader)
                Text(bodyText)
                    .font(.sans(17, relativeTo: .body))
                    .foregroundStyle(theme.fgMuted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                Button {
                    answer()
                } label: {
                    Text(TrialAsk.allow)
                        .font(.sans(17, .sansSemibold, relativeTo: .body))
                        .foregroundStyle(theme.buttonText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(theme.button, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
                }
                .buttonStyle(PressStyle())
                .disabled(busy)
                .accessibilityHint("Shows the iPhone's notification prompt.")
                .padding(.top, 28)
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, 16)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { contentHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, height in contentHeight = height }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(theme.bg.ignoresSafeArea())
        // Larger text than fits scrolls inside the sheet.
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(true)
        .presentationBackground(theme.bg)
        // Only an ask that is on screen uses up the one ask.
        .onAppear { model.trialAskDidAppear() }
    }

    private func answer() {
        guard !busy else { return }
        busy = true
        Task {
            await model.answerTrialAsk()
            busy = false
        }
    }
}
