import StoreKit
import SwiftUI

/// Taken Pro. One sheet: what Pro is, the person's own record so far, three plans, one button, the terms Apple
/// requires, and the way out. No carousel, no countdown, nothing pressing (PRO.md).
struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.purchase) private var purchase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let request: PaywallRequest

    @State private var selected: ProPlan = .yearly
    @State private var busy: Busy?
    @State private var note: Note?
    @State private var unlocked = false
    @State private var redeeming = false
    @State private var bracket: CGFloat = 12
    @State private var sweep: CGFloat = 0
    @State private var sweeping = false

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

    var body: some View {
        GeometryReader { geo in
            // Every plan above the button on a 6.9 inch iPhone; smaller ones drop the ruler and tighten up.
            let compact = geo.size.height < 820
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header(compact: compact)
                        features
                            .padding(.top, compact ? 16 : 22)
                        planHeader
                            .padding(.top, compact ? 18 : 22)
                            .padding(.bottom, 12)
                        plans
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                dock
            }
        }
        .background(Palette.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Palette.bg)
        .offerCodeRedemption(isPresented: $redeeming) { _ in
            Task { await pro.refresh() }
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.7).delay(0.12)) {
                bracket = 18
            }
        }
        .onChange(of: pro.status) { _, _ in
            // Pro came on another way while the sheet was up: a restore, an offer code, an approved Ask to Buy.
            if pro.isActive(at: Date()) { celebrate() }
        }
        .task { await pro.loadOffers() }
    }

    // MARK: Top

    /// TODAY's wordmark with PRO lit, and the way out.
    private var topBar: some View {
        HStack(spacing: 10) {
            CapsuleGlyph()
                .frame(width: 20, height: 20)
                .shadow(color: Palette.signal.opacity(0.5), radius: 6)
            HStack(spacing: 9) {
                Text("TAKEN").foregroundStyle(Palette.fg)
                Text("PRO").foregroundStyle(Palette.signal)
            }
            .font(.monoFixed(15, .monoSemibold))
            .tracking(15 * 0.3)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Taken Pro")
            .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                model.closePaywall()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.fgMuted)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.leading, 20)
        .padding(.trailing, 8)
        .frame(height: 56)
    }

    private func header(compact: Bool) -> some View {
        let today = model.today
        return VStack(alignment: .leading, spacing: 0) {
            Text(ProCopy.headline)
                .font(.sans(compact ? 30 : 34, .sansSemibold, relativeTo: .largeTitle))
                .tracking(-0.6)
                .foregroundStyle(Palette.fg)
                .fixedSize(horizontal: false, vertical: true)
            Text(ProCopy.sublineLines)
                .font(.sans(compact ? 15 : 16, relativeTo: .body))
                .foregroundStyle(Palette.fgMuted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            if !compact {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("TODAY").hud(10, Palette.fgSubtle, tracking: 0.14)
                        Text(loggedLabel(today))
                            .hud(10, today.allDoses.isEmpty ? Palette.fgFaint : Palette.signal, tracking: 0.12)
                    }
                    // The record so far, on the ruler TODAY uses: every dose at its minute.
                    DayRuler(dayStart: model.clock.start(of: today.day), dayEnd: model.clock.end(of: today.day),
                             doses: today.allDoses.map(\.takenAt), now: model.now, dayStartHour: model.clock.dayStartHour)
                }
                .padding(.top, 20)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, compact ? 18 : 22)
        .padding(.bottom, compact ? 18 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topLeading) {
                (unlocked ? Palette.signalWash.opacity(0.35) : Palette.bgRaised.opacity(0.6))
                // A faint signal glow behind the headline.
                RadialGradient(colors: [Palette.signal.opacity(unlocked ? 0.16 : 0.08), Palette.signal.opacity(0)],
                               center: .topLeading, startRadius: 0, endRadius: 260)
            }
        }
        .overlay {
            CornerBrackets(length: unlocked ? 30 : bracket)
                .stroke(unlocked ? Palette.signal : Palette.fgSubtle, style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
                .shadow(color: unlocked ? Palette.signal.opacity(0.55) : .clear, radius: 6)
                .padding(0.75)
        }
        .overlay(alignment: .top) { scanline }
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ProCopy.headline) \(ProCopy.subline)")
    }

    private func loggedLabel(_ today: DaySummary) -> String {
        let count = today.allDoses.count
        if count == 0 { return "NOTHING LOGGED YET" }
        return count == 1 ? "1 DOSE LOGGED" : "\(count) DOSES LOGGED"
    }

    @ViewBuilder
    private var scanline: some View {
        if sweeping {
            GeometryReader { geo in
                Rectangle()
                    .fill(Palette.signal)
                    .frame(height: 2)
                    .shadow(color: Palette.signal.opacity(0.9), radius: 8)
                    .offset(y: sweep * geo.size.height)
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 11) {
            ForEach(ProCopy.features, id: \.self) { line in
                HStack(spacing: 12) {
                    Rectangle()
                        .fill(Palette.signal)
                        .frame(width: 6, height: 6)
                        .shadow(color: Palette.signal.opacity(0.7), radius: 3)
                    Text(line)
                        .hud(12, Palette.fg, face: .monoMedium, tracking: 0.1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: Plans

    private var planHeader: some View {
        HStack(spacing: 10) {
            Text("[01]").hud(11, Palette.fgFaint, tracking: 0.06)
            Text("PLAN").hud(11, Palette.fgMuted, tracking: 0.16)
            DashedRule().frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var plans: some View {
        VStack(spacing: 10) {
            ForEach(ProPlan.allCases) { plan in
                planCard(plan)
            }
        }
        // Room for the brackets on the chosen plan.
        .padding(.horizontal, 3)
        .padding(.vertical, 3)
    }

    private func planCard(_ plan: ProPlan) -> some View {
        let offer = pro.offers[plan]
        let isOn = selected == plan
        let tag = ProCopy.introTag(ProCopy.liveIntro(offer, eligible: eligible))
        return Button {
            select(plan)
        } label: {
            HStack(alignment: .center, spacing: 14) {
                radio(isOn)
                VStack(alignment: .leading, spacing: 7) {
                    Text(plan.title)
                        .font(.monoFixed(13, .monoSemibold))
                        .tracking(13 * 0.14)
                        .foregroundStyle(isOn ? Palette.fg : Palette.fgMuted)
                    if let tag {
                        Text(tag)
                            .font(.monoFixed(9.5, .monoSemibold))
                            .tracking(9.5 * 0.12)
                            .foregroundStyle(Palette.signal)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Palette.signalEdge, lineWidth: 1))
                    }
                }
                Spacer(minLength: 8)
                priceBlock(offer, isOn: isOn)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 58)
            .background(isOn ? Palette.signalWash : Palette.bgRaised, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(isOn ? Palette.signalEdge : Palette.line, lineWidth: 1))
            .overlay {
                // The viewfinder locks onto the chosen plan.
                if isOn {
                    CornerBrackets(length: 9)
                        .stroke(Palette.signal, style: StrokeStyle(lineWidth: 1.5, lineCap: .square))
                        .shadow(color: Palette.signal.opacity(0.6), radius: 4)
                        .padding(-3)
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .disabled(unlocked)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cardLabel(plan, offer: offer, tag: tag))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func priceBlock(_ offer: PlanOffer?, isOn: Bool) -> some View {
        if let offer {
            let price = ProCopy.price(offer)
            VStack(alignment: .trailing, spacing: 5) {
                // The billed amount is the most prominent price on the card.
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(price.amount)
                        .font(.monoFixed(20, .monoMedium))
                        .foregroundStyle(Palette.fg)
                    Text(price.unit)
                        .font(.monoFixed(12, .monoMedium))
                        .foregroundStyle(isOn ? Palette.fgMuted : Palette.fgSubtle)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                if let monthly = ProCopy.monthlyEquivalent(offer) {
                    Text(monthly)
                        .font(.monoFixed(11, .monoMedium))
                        .foregroundStyle(Palette.fgSubtle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        } else {
            Text(pro.offersPhase == .failed ? "--" : "\u{00B7}\u{00B7}\u{00B7}")
                .font(.monoFixed(16, .monoMedium))
                .foregroundStyle(Palette.fgFaint)
        }
    }

    /// Square radio, lit when chosen.
    private func radio(_ on: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(on ? Palette.signal : Palette.fgFaint, lineWidth: 1.2)
                .frame(width: 16, height: 16)
            if on {
                Rectangle()
                    .fill(Palette.signal)
                    .frame(width: 8, height: 8)
                    .shadow(color: Palette.signal.opacity(0.8), radius: 4)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: 18, height: 18)
    }

    private func cardLabel(_ plan: ProPlan, offer: PlanOffer?, tag: String?) -> String {
        var parts = [plan.rawValue.capitalized]
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
        if let tag { parts.append(tag.lowercased()) }
        return parts.joined(separator: ". ")
    }

    // MARK: Dock

    private var dock: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.line).frame(height: 1)
            VStack(alignment: .leading, spacing: 12) {
                if let note { noteView(note) }
                cta
                Text(termsLine)
                    .font(.sans(12.5, relativeTo: .footnote))
                    .foregroundStyle(Palette.fgMuted)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                links
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 2)
        }
        .background(Palette.bg)
        .animation(.snappy(duration: 0.22), value: note)
    }

    /// Always visible under the button: what the selected plan costs and how it renews.
    private var termsLine: String {
        guard let offer else { return ProCopy.termsWithoutPrices(selected) }
        return ProCopy.terms(offer, eligible: eligible)
    }

    private var ctaTitle: String {
        if unlocked { return "PRO ACTIVE" }
        switch busy {
        case .buying: return "CONFIRMING"
        case .restoring: return "RESTORING"
        case nil: break
        }
        if offer == nil { return pro.offersPhase == .failed ? "TRY AGAIN" : "LOADING PLANS" }
        return ProCopy.cta(offer, eligible: eligible)
    }

    private var ctaEnabled: Bool {
        !unlocked && busy == nil && (offer != nil || pro.offersPhase == .failed)
    }

    private var cta: some View {
        Button(action: primaryAction) {
            HStack(spacing: 10) {
                if busy == .buying || busy == .restoring {
                    ProgressView()
                        .tint(Palette.buttonText)
                        .controlSize(.small)
                } else if unlocked {
                    CheckShape()
                        .stroke(Palette.buttonText, style: StrokeStyle(lineWidth: 2.2, lineCap: .square, lineJoin: .miter))
                        .frame(width: 14, height: 14)
                } else {
                    Rectangle().fill(Palette.signal).frame(width: 7, height: 7)
                }
                Text(ctaTitle)
                    .font(.monoFixed(14, .monoSemibold))
                    .tracking(14 * 0.12)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Palette.buttonText)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(unlocked ? Palette.signal : Palette.button.opacity(ctaEnabled || busy != nil ? 1 : 0.35),
                        in: RoundedRectangle(cornerRadius: 4))
            .shadow(color: unlocked ? Palette.signal.opacity(0.5) : .clear, radius: 12)
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
        Button { restore() } label: { footerLabel("RESTORE") }
            .buttonStyle(.plain)
            .disabled(busy != nil || unlocked)
            .accessibilityLabel("Restore purchases")
    }

    private var redeemLink: some View {
        Button { redeeming = true } label: { footerLabel("REDEEM CODE") }
            .buttonStyle(.plain)
            .disabled(busy != nil || unlocked)
            .accessibilityLabel("Redeem code")
    }

    private var termsLink: some View {
        Link(destination: ProCopy.termsOfUseURL) { footerLabel("TERMS OF USE") }
            .accessibilityLabel("Terms of Use")
    }

    private var privacyLink: some View {
        Link(destination: ProCopy.privacyURL) { footerLabel("PRIVACY") }
            .accessibilityLabel("Privacy Policy")
    }

    private func footerLabel(_ title: String) -> some View {
        Text(title)
            .hudFixed(10, Palette.fgMuted, face: .monoMedium, tracking: 0.1)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 5)
            .frame(minHeight: 40)
            .contentShape(Rectangle())
    }

    private var separator: some View {
        Text("\u{00B7}")
            .hudFixed(10, Palette.fgFaint, tracking: 0)
            .accessibilityHidden(true)
    }

    private func noteView(_ note: Note) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(note.lit ? Palette.signal : Palette.fgSubtle)
                .frame(width: 6, height: 6)
                .padding(.top, 6)
            Text(note.text)
                .font(.sans(14, relativeTo: .callout))
                .foregroundStyle(Palette.fgMuted)
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
            Task { await pro.loadOffers(force: true) }
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
                note = Note(text: "No Taken Pro purchase on this Apple Account yet.", lit: false)
            case .cancelled:
                break
            case .failed(let text):
                note = Note(text: text, lit: false)
            }
        }
    }

    /// Pro is on: the lock-in, the success haptic, then the sheet closes and the tap that opened it is applied.
    private func celebrate() {
        guard !unlocked else { return }
        model.paywallUnlocked()
        note = nil
        Haptics.success(model.hapticsOn)
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.32, dampingFraction: 0.62)) {
            unlocked = true
        }
        runSweep()
        UIAccessibility.post(notification: .announcement, argument: "Taken Pro is on.")
        Task {
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 700 : 1150))
            model.closePaywall()
        }
    }

    private func runSweep() {
        guard !reduceMotion else { return }
        sweep = 0
        sweeping = true
        withAnimation(.easeInOut(duration: 0.55)) { sweep = 1 }
        Task {
            try? await Task.sleep(for: .milliseconds(620))
            withAnimation(.easeOut(duration: 0.2)) { sweeping = false }
        }
    }
}
