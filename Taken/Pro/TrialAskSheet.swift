import SwiftUI

/// The one notification ask right after a trial starts (`TrialAsk`, SPEC 3.9): both reasons on one short sheet,
/// Continue (iOS's own prompt follows) and a quiet Not now. Apple: ask in context, and title the pre-prompt button
/// like Continue, never Allow (https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications,
/// https://developer.apple.com/design/human-interface-guidelines/privacy).
struct TrialAskSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var busy = false
    /// The content's own height: the sheet is as tall as what it says, not half the screen.
    @State private var contentHeight: CGFloat = 340

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
                    answer(allow: true)
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
                .padding(.top, 28)
                Button {
                    answer(allow: false)
                } label: {
                    Text(TrialAsk.notNow)
                        .font(.sans(15, .sansMedium, relativeTo: .callout))
                        .foregroundStyle(theme.fgMuted)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .padding(.top, 6)
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, 12)
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
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.bg)
    }

    private func answer(allow: Bool) {
        guard !busy else { return }
        busy = true
        Task {
            await model.answerTrialAsk(allow: allow)
            busy = false
        }
    }
}
