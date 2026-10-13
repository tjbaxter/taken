import StoreKit
import SwiftUI

/// Taken Pro. One sheet: what Pro is, three plans, one button, the terms Apple requires, and the way out. No carousel,
/// no countdown, nothing pressing (PRO.md).
struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.purchase) private var purchase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.theme) private var theme

    let request: PaywallRequest

    @State private var selected: ProPlan = .yearly
    @State private var busy: Busy?
    @State private var note: Note?
    @State private var unlocked = false
    @State private var redeeming = false

    init(request: PaywallRequest) {
        self.request = request
    }

    private enum Busy: Equatable {
        case buying
        case restoring
    }

    private struct Note: Equatable {
        let text: String
        let lit: Bool
    }

    private var pro: ProStore { model.pro }
    private var eligible: Bool { pro.introEligible == true }
    private var offer: PlanOffer? { pro.offers[selected] }

    /// StoreKit has answered, so a plan it did not return is missing, not loading.
    private var plansAnswered: Bool { pro.offersPhase == .ready || pro.offersPhase == .failed }

    /// A plan the App Store did not return (not on sale here, or not attached to this version): "--", not selectable.
    private func isMissing(_ plan: ProPlan) -> Bool { pro.offers[plan] == nil && plansAnswered }

    /// Yearly is chosen when the App Store returns it; otherwise the first plan it did return.
    private func preselect() {
        guard pro.offers[selected] == nil,
              let first = ProPlan.allCases.first(where: { pro.offers[$0] != nil }) else { return }
        selected = first
    }

    var body: some View {
        GeometryReader { geo in
            // Every plan sits above the button: with room to spare on a 6.9 inch iPhone, tighter on 6.1 and 6.3 inch
            // ones, where the smallest scroll, with the button and terms always in view.
            let compact = geo.size.height < 820
            VStack(spacing: 0) {
                topBar
                GeometryReader { area in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            header(compact: compact)
                            features(compact: compact)
                                .padding(.top, compact ? 18 : 26)
                            // Spare height goes here, so the plans sit right above the button.
                            Spacer(minLength: compact ? 18 : 26)
                            plans(compact: compact)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, compact ? 10 : 14)
                        .frame(minHeight: area.size.height, alignment: .top)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                }
                dock(compact: compact)
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(theme.bg)
        .offerCodeRedemption(isPresented: $redeeming) { _ in
            Task { await pro.refresh() }
        }
        .onChange(of: pro.status) { _, _ in
            // Pro came on another way while the sheet was up: a restore, an offer code, an approved Ask to Buy.
            if pro.isActive(at: Date()) { celebrate() }
        }
        .onChange(of: pro.offersPhase) { _, _ in preselect() }
        .task {
            preselect()
            await pro.loadOffers()
            preselect()
        }
    }

    // MARK: Top

    /// The glyph, Taken Pro, and the way out.
    private var topBar: some View {
        HStack(spacing: 10) {
            CapsuleGlyph()
                .frame(width: 22, height: 22)
                .scaleEffect(unlocked && !reduceMotion ? 1.12 : 1)
            Text("Taken Pro")
                .font(.sans(17, .sansSemibold, relativeTo: .body))
                .foregroundStyle(theme.fg)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                model.closePaywall()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.fgMuted)
                    .frame(width: 32, height: 32)
                    .background(theme.bgInset, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.leading, 20)
        .padding(.trailing, 10)
        .frame(height: 56)
    }

    private func header(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ProCopy.headline)
                .font(.sans(compact ? 32 : 36, .sansSemibold, relativeTo: .largeTitle))
                .tracking(-0.6)
                .foregroundStyle(unlocked ? theme.signalInk : theme.fg)
                .fixedSize(horizontal: false, vertical: true)
            Text(ProCopy.sublineLines)
                .font(.sans(compact ? 16 : 17, relativeTo: .body))
                .foregroundStyle(theme.fgMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, compact ? 8 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ProCopy.headline) \(ProCopy.subline)")
    }

    private func features(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 14) {
            ForEach(ProCopy.features, id: \.self) { line in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.onSignal)
                        .frame(width: 22, height: 22)
                        .background(theme.signal, in: Circle())
                    Text(line)
                        .font(.sans(16, .sansMedium, relativeTo: .body))
                        .foregroundStyle(theme.fg)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Plans

    private func plans(compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 10) {
            ForEach(ProPlan.allCases) { plan in
                planCard(plan, compact: compact)
            }
        }
    }

    private func planCard(_ plan: ProPlan, compact: Bool) -> some View {
        let offer = pro.offers[plan]
        let isOn = selected == plan
        let tag = ProCopy.introTag(ProCopy.liveIntro(offer, eligible: eligible))
        let shape = RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous)
        return Button {
            select(plan)
        } label: {
            HStack(alignment: .center, spacing: 14) {
                radio(isOn)
                VStack(alignment: .leading, spacing: 5) {
                    Text(plan.title)
                        .font(.sans(17, .sansSemibold, relativeTo: .body))
                        .foregroundStyle(theme.fg)
                    if let tag {
                        Text(tag)
                            .font(.sans(13, .sansSemibold, relativeTo: .footnote))
                            .foregroundStyle(theme.signalInk)
                    }
                }
                Spacer(minLength: 8)
                priceBlock(offer, isOn: isOn)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, compact ? 10 : 12)
            .frame(minHeight: compact ? 58 : 64)
            .background(isOn ? theme.signalWash : theme.bgRaised, in: shape)
            .overlay(shape.strokeBorder(isOn ? theme.signal : theme.line, lineWidth: isOn ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(unlocked || isMissing(plan))
        .opacity(isMissing(plan) ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cardLabel(plan, offer: offer, tag: tag))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func priceBlock(_ offer: PlanOffer?, isOn: Bool) -> some View {
        if let offer {
            let price = ProCopy.price(offer)
            VStack(alignment: .trailing, spacing: 4) {
                // The billed amount is the most prominent price on the card.
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(price.amount)
                        .font(.mono(20, .monoMedium, relativeTo: .title3))
                        .foregroundStyle(theme.fg)
                    Text(price.unit)
                        .font(.sans(14, .sans, relativeTo: .footnote))
                        .foregroundStyle(isOn ? theme.fgMuted : theme.fgSubtle)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                if let monthly = ProCopy.monthlyEquivalent(offer) {
                    // On the chosen card's signal wash the muted ink keeps it AA; the subtle one does on a plain card.
                    Text(monthly)
                        .font(.sans(13, .sans, relativeTo: .footnote))
                        .foregroundStyle(isOn ? theme.fgMuted : theme.fgSubtle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        } else {
            Text(plansAnswered ? "--" : "\u{00B7}\u{00B7}\u{00B7}")
                .font(.mono(16, .monoMedium, relativeTo: .body))
                .foregroundStyle(theme.fgFaint)
        }
    }

    /// A round radio, filled with the signal when chosen.
    private func radio(_ on: Bool) -> some View {
        ZStack {
            Circle()
                .strokeBorder(on ? theme.signal : theme.lineStrong, lineWidth: 1.5)
            if on {
                Circle()
                    .fill(theme.signal)
                    .padding(5)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: 22, height: 22)
    }

    private func cardLabel(_ plan: ProPlan, offer: PlanOffer?, tag: String?) -> String {
        var parts = [plan.title]
        if isMissing(plan) { parts.append("Not available right now") }
        if let offer {
            if let period = offer.period {
                parts.append("\(offer.displayPrice) \(ProCopy.per(period))")
            } else {
                parts.append("\(offer.displayPrice), one payment")
            }
            if let monthly = ProCopy.monthlyEquivalent(offer) {
                parts.append(monthly.replacingOccurrences(of: " / ", with: " per "))
            }
        }
        if let tag { parts.append(tag) }
        return parts.joined(separator: ". ")
    }

    // MARK: Dock

    private func dock(compact: Bool) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.line).frame(height: 1)
            VStack(alignment: .leading, spacing: compact ? 10 : 12) {
                if let note { noteView(note) }
                cta(height: compact ? 52 : 56)
                Text(termsLine)
                    .font(.sans(compact ? 12 : 12.5, relativeTo: .footnote))
                    .foregroundStyle(theme.fgMuted)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                links
            }
            .padding(.horizontal, 20)
            .padding(.top, compact ? 12 : 14)
            .padding(.bottom, 2)
        }
        .background(theme.bg)
        .animation(.snappy(duration: 0.22), value: note)
    }

    /// Always visible under the button: what the selected plan costs and how it renews.
    private var termsLine: String {
        guard let offer else { return ProCopy.termsWithoutPrices(selected) }
        return ProCopy.terms(offer, eligible: eligible)
    }

    private var ctaTitle: String {
        if unlocked { return "Taken Pro is on" }
        switch busy {
        case .buying: return "Confirming"
        case .restoring: return "Restoring"
        case nil: break
        }
        // A plan the App Store did not return is never left on a spinner: the button asks it again.
        if offer == nil { return plansAnswered ? "Try again" : "Loading plans" }
        return ProCopy.cta(offer, eligible: eligible)
    }

    private var ctaEnabled: Bool {
        !unlocked && busy == nil && (offer != nil || plansAnswered)
    }

    private func cta(height: CGFloat) -> some View {
        Button(action: primaryAction) {
            HStack(spacing: 10) {
                if busy == .buying || busy == .restoring {
                    ProgressView()
                        .tint(theme.buttonText)
                        .controlSize(.small)
                } else if unlocked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                }
                Text(ctaTitle)
                    .font(.sans(17, .sansSemibold, relativeTo: .body))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(theme.buttonText)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            // Pro on: the button lights in the signal, the readable shade of it in Blush.
            .background(unlocked ? theme.signalInk : theme.button.opacity(ctaEnabled || busy != nil ? 1 : 0.35),
                        in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .disabled(!ctaEnabled)
        .accessibilityHint(offer == nil ? "" : termsLine)
    }

    private var links: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                restoreLink
                separator
                redeemLink
                separator
                termsLink
                separator
                privacyLink
            }
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    restoreLink
                    separator
                    redeemLink
                }
                HStack(spacing: 0) {
                    termsLink
                    separator
                    privacyLink
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var restoreLink: some View {
        Button { restore() } label: { footerLabel("Restore") }
            .buttonStyle(.plain)
            .disabled(busy != nil || unlocked)
            .accessibilityLabel("Restore purchases")
    }

    private var redeemLink: some View {
        Button { redeeming = true } label: { footerLabel("Redeem code") }
            .buttonStyle(.plain)
            .disabled(busy != nil || unlocked)
            .accessibilityLabel("Redeem code")
    }

    private var termsLink: some View {
        Link(destination: ProCopy.termsOfUseURL) { footerLabel("Terms of Use") }
            .accessibilityLabel("Terms of Use")
    }

    private var privacyLink: some View {
        Link(destination: ProCopy.privacyURL) { footerLabel("Privacy") }
            .accessibilityLabel("Privacy Policy")
    }

    private func footerLabel(_ title: String) -> some View {
        Text(title)
            .font(.sans(13, .sansMedium, relativeTo: .footnote))
            .foregroundStyle(theme.fgMuted)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }

    private var separator: some View {
        Text("\u{00B7}")
            .font(.sans(13, .sans, relativeTo: .footnote))
            .foregroundStyle(theme.fgFaint)
            .accessibilityHidden(true)
    }

    private func noteView(_ note: Note) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(note.lit ? theme.signal : theme.fgSubtle)
                .frame(width: 7, height: 7)
                .padding(.top, 6)
            Text(note.text)
                .font(.sans(14, relativeTo: .callout))
                .foregroundStyle(theme.fgMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func select(_ plan: ProPlan) {
        guard selected != plan, !unlocked else { return }
        Haptics.selection(model.hapticsOn)
        withAnimation(.snappy(duration: 0.2)) { selected = plan }
    }

    private func primaryAction() {
        if offer == nil {
            Task {
                await pro.loadOffers(force: true)
                preselect()
            }
            return
        }
        buy()
    }

    private func buy() {
        guard busy == nil, !unlocked else { return }
        let plan = selected
        busy = .buying
        note = nil
        Task {
            let outcome = await pro.purchase(plan, with: purchase)
            busy = nil
            switch outcome {
            case .unlocked:
                celebrate()
            case .pending:
                note = Note(text: "Waiting for approval. Taken Pro turns on as soon as it goes through.", lit: true)
            case .cancelled:
                break
            case .failed(let text):
                note = Note(text: text, lit: false)
            }
        }
    }

    private func restore() {
        guard busy == nil, !unlocked else { return }
        busy = .restoring
        note = nil
        Task {
            let outcome = await pro.restore()
            busy = nil
            switch outcome {
            case .restored:
                celebrate()
            case .nothing:
                note = Note(text: ProCopy.nothingToRestore, lit: false)
            case .cancelled:
                break
            case .failed(let text):
                note = Note(text: text, lit: false)
            }
        }
    }

    /// Pro is on: the button lights with a check, the success haptic, then the sheet closes and the tap that opened it
    /// is applied.
    private func celebrate() {
        guard !unlocked else { return }
        model.paywallUnlocked()
        note = nil
        Haptics.success(model.hapticsOn)
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.32, dampingFraction: 0.62)) {
            unlocked = true
        }
        UIAccessibility.post(notification: .announcement, argument: "Taken Pro is on.")
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 700 : 1150))
            model.closePaywall()
        }
    }
}
