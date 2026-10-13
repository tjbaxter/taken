import SwiftUI

/// Which presentation level shows the paywall: TODAY, a sheet on TODAY, or a sheet inside that sheet. The paywall
/// slides up over whatever the person was using, and closing it returns them there.
enum PaywallAnchor: Hashable, Sendable {
    case root
    case sheet
    case nested
}

/// Why the paywall opened.
enum PaywallOrigin: Hashable, Sendable {
    /// Once, about 1.5 s after the first dose.
    case intro
    /// A log, TAKE ALL, backfill, Set time or an add in locked mode.
    case action
    /// The bar under the status panel.
    case bar
    /// Settings > PRO.
    case settings
    /// taken://pro from a widget, or a log refused elsewhere.
    case link
}

struct PaywallRequest: Identifiable {
    let id = UUID()
    let anchor: PaywallAnchor
    let origin: PaywallOrigin
    /// What it was opened for: run once Pro is on (the dose tap that opened it is applied).
    let pending: (@MainActor () -> Void)?

    init(anchor: PaywallAnchor, origin: PaywallOrigin, pending: (@MainActor () -> Void)? = nil) {
        self.anchor = anchor
        self.origin = origin
        self.pending = pending
    }
}

private struct PaywallAnchorKey: EnvironmentKey {
    static let defaultValue: PaywallAnchor = .root
}

extension EnvironmentValues {
    /// The level a view sits on, so a locked action inside a sheet opens the paywall over that sheet.
    var paywallAnchor: PaywallAnchor {
        get { self[PaywallAnchorKey.self] }
        set { self[PaywallAnchorKey.self] = newValue }
    }
}

private struct PaywallHost: ViewModifier {
    @Environment(AppModel.self) private var model
    let anchor: PaywallAnchor

    func body(content: Content) -> some View {
        content
            .environment(\.paywallAnchor, anchor)
            .sheet(item: binding, onDismiss: { model.paywallDidDismiss() }) { request in
                PaywallView(request: request)
                    .environment(model)
                    .preferredColorScheme(.dark)
            }
    }

    private var binding: Binding<PaywallRequest?> {
        Binding(
            get: { model.paywall?.anchor == anchor ? model.paywall : nil },
            set: { value in
                if value == nil, model.paywall?.anchor == anchor { model.closePaywall() }
            }
        )
    }
}

extension View {
    /// Presents the paywall when it is requested for this level.
    func paywallHost(_ anchor: PaywallAnchor) -> some View {
        modifier(PaywallHost(anchor: anchor))
    }
}
