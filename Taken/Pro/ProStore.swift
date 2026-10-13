import Foundation
import Observation
import StoreKit
import SwiftUI

enum PurchaseOutcome: Equatable, Sendable {
    case unlocked
    /// Waiting on Ask to Buy or a bank check. Transaction.updates delivers it later.
    case pending
    case cancelled
    case failed(String)
}

enum RestoreOutcome: Equatable, Sendable {
    case restored
    case nothing
    case cancelled
    case failed(String)
}

/// Taken Pro through StoreKit 2. Listens to Transaction.updates from launch, refreshes on every return to the
/// foreground, works the answer out with the pure rule in Shared/Pro.swift and caches it in the App Group, where
/// the widgets, the control, Siri and the nudge read it. No third-party code.
@MainActor
@Observable
final class ProStore {
    enum OffersPhase: Equatable, Sendable {
        case idle
        case loading
        case ready
        case failed
    }

    /// The best answer so far: the cached one at launch, then StoreKit's.
    private(set) var status: ProStatus?
    /// StoreKit has answered this launch, or the wait for it ran out.
    private(set) var settled: Bool
    /// The log already had doses when this version first ran (an update from 1.0).
    private(set) var legacyLog: Bool
    /// The one automatic paywall after the first dose has been shown.
    private(set) var introShown: Bool
    private(set) var offers: [ProPlan: PlanOffer] = [:]
    private(set) var offersPhase: OffersPhase = .idle
    /// Whether this Apple Account can still have the introductory offer. Nil until StoreKit says.
    private(set) var introEligible: Bool?

    let isDemo: Bool
    /// Runs when an answer changes Pro itself (not just when it was checked): the app reloads the widgets, the
    /// control and the nudges.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    private let ledger: ProLedgerStore
    @ObservationIgnored private var products: [ProPlan: Product] = [:]
    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private var refreshing: Task<Bool, Never>?
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []

    /// The live store. `hasLogged` is whether the log already holds doses, recorded the first time this version runs.
    init(ledger: ProLedgerStore, hasLogged: Bool) {
        let record = ledger.loadOrCreate { ProLedger(firstSeenAt: Date(), legacyLog: hasLogged) }
        self.isDemo = false
        self.ledger = ledger
        self.status = record.status
        self.settled = false
        self.legacyLog = record.legacyLog
        self.introShown = record.introShownAt != nil
    }

    /// `-demo`: no StoreKit at all. Screenshots show Pro, or a locked log with the plans as StoreKit shapes them.
    init(demoLocked: Bool, now: Date) {
        self.isDemo = true
        self.ledger = ProLedgerStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("taken-demo-pro-\(UUID().uuidString).json"))
        self.status = demoLocked
            ? .notPro(checkedAt: now)
            : ProStatus(isPro: true, reason: .yearly, checkedAt: now,
                        expiresAt: Calendar(identifier: .gregorian).date(byAdding: .year, value: 1, to: now),
                        willRenew: true)
        self.settled = true
        self.legacyLog = false
        self.introShown = true
        self.offers = DemoOffers.all
        self.offersPhase = .ready
        self.introEligible = true
    }

    func isActive(at now: Date) -> Bool {
        status?.isActive(at: now) ?? false
    }

    /// Starts listening for transactions (renewals, Ask to Buy approvals, offer codes, refunds) and asks StoreKit.
    func start() {
        guard !isDemo, updates == nil else { return }
        updates = Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refresh()
            }
        }
        Task { [weak self] in
            await Self.finishUnfinished()
            await self?.refresh()
            await self?.loadOffers()
        }
        // Never keep the app waiting on StoreKit: after a few seconds the cached answer stands.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.markSettled()
        }
    }

    /// Waits for StoreKit's first answer of this launch, at most a few seconds.
    func settle() async {
        if settled { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func markSettled() {
        guard !settled else { return }
        settled = true
        let waiting = waiters
        waiters = []
        for continuation in waiting { continuation.resume() }
    }

    // MARK: Entitlement

    /// Asks StoreKit again. Returns true when Pro itself changed. Calls made while one is running share it.
    @discardableResult
    func refresh() async -> Bool {
        guard !isDemo else { return false }
        if let refreshing { return await refreshing.value }
        let task = Task { [weak self] () async -> Bool in
            guard let self else { return false }
            return await self.performRefresh()
        }
        refreshing = task
        let changed = await task.value
        refreshing = nil
        return changed
    }

    private func performRefresh() async -> Bool {
        let facts = await Self.entitlementFacts()
        let app = await Self.appTransactionFact()
        let now = Date()
        let fresh = Entitlement.evaluate(purchases: facts, app: app, now: now)
        let previous = status
        // Without the app transaction (offline, not signed in), finding no purchase proves nothing: a founding
        // member would read as locked. Keep what was known until StoreKit can tell.
        let next: ProStatus? = (app != nil || fresh.isPro) ? fresh : previous
        status = next
        if let next {
            ledger.update { ledger in ledger?.status = next }
        }
        markSettled()
        let changed: Bool
        switch (previous, next) {
        case (nil, nil): changed = false
        case let (old?, new?): changed = !new.sameEntitlement(as: old)
        default: changed = true
        }
        if changed {
            await refreshEligibility()
            onChange?()
        }
        return changed
    }

    /// A purchase StoreKit just verified counts at once, even before currentEntitlements shows it.
    private func grant(_ fact: PurchaseFact) {
        let granted = Entitlement.evaluate(purchases: [fact], app: nil, now: Date())
        guard granted.isPro else { return }
        let previous = status
        status = granted
        ledger.update { ledger in ledger?.status = granted }
        markSettled()
        if !granted.sameEntitlement(as: previous) { onChange?() }
    }

    private nonisolated static func entitlementFacts() async -> [PurchaseFact] {
        var facts: [PurchaseFact] = []
        for await result in Transaction.currentEntitlements {
            facts.append(await PurchaseFact.make(from: result))
        }
        return facts
    }

    private nonisolated static func appTransactionFact() async -> AppTransactionFact? {
        do {
            switch try await AppTransaction.shared {
            case .verified(let app):
                return AppTransactionFact(verified: true, environment: StoreEnvironment(app.environment),
                                          originalAppVersion: app.originalAppVersion)
            case .unverified(let app, _):
                return AppTransactionFact(verified: false, environment: StoreEnvironment(app.environment),
                                          originalAppVersion: app.originalAppVersion)
            }
        } catch {
            return nil
        }
    }

    private nonisolated static func finishUnfinished() async {
        for await result in Transaction.unfinished {
            if case .verified(let transaction) = result {
                await transaction.finish()
            }
        }
    }

    // MARK: Plans

    /// Loads the three products. Prices, periods and the introductory offer always come from here.
    func loadOffers(force: Bool = false) async {
        guard !isDemo, offersPhase != .loading else { return }
        if offersPhase == .ready && !force { return }
        offersPhase = .loading
        do {
            let found = try await Product.products(for: ProPlan.allCases.map(\.productID))
            var map: [ProPlan: Product] = [:]
            for product in found {
                if let plan = ProPlan(productID: product.id) { map[plan] = product }
            }
            products = map
            var loaded: [ProPlan: PlanOffer] = [:]
            for (plan, product) in map { loaded[plan] = PlanOffer(plan: plan, product: product) }
            offers = loaded
            offersPhase = map.isEmpty ? .failed : .ready
            await refreshEligibility()
        } catch {
            offersPhase = .failed
        }
    }

    private func refreshEligibility() async {
        guard let subscription = (products[.yearly] ?? products[.monthly])?.subscription else { return }
        introEligible = await subscription.isEligibleForIntroOffer
    }

    // MARK: Buying

    func purchase(_ plan: ProPlan, with action: PurchaseAction) async -> PurchaseOutcome {
        guard !isDemo else { return .cancelled }
        guard let product = products[plan] else { return .failed("Plans are still loading. Try again in a moment.") }
        do {
            let result = try await action(product, options: [])
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return .failed("Apple could not verify that purchase. Try Restore.")
                }
                let fact = await PurchaseFact.make(from: verification)
                await transaction.finish()
                await refresh()
                if !isActive(at: Date()) { grant(fact) }
                return .unlocked
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch {
            if let storeError = error as? StoreKitError, case .userCancelled = storeError { return .cancelled }
            return .failed(Self.message(for: error))
        }
    }

    /// Restore purchases: syncs with the App Store (it may ask for the Apple Account password), then asks again.
    func restore() async -> RestoreOutcome {
        guard !isDemo else { return .nothing }
        do {
            try await AppStore.sync()
        } catch {
            if let storeError = error as? StoreKitError, case .userCancelled = storeError { return .cancelled }
            return .failed(Self.message(for: error))
        }
        await refresh()
        return isActive(at: Date()) ? .restored : .nothing
    }

    private static func message(for error: any Error) -> String {
        if let storeError = error as? StoreKitError {
            switch storeError {
            case .networkError:
                return "No connection to the App Store. Try again."
            case .notAvailableInStorefront:
                return "Taken Pro is not sold in this country yet."
            default:
                break
            }
        }
        if let purchaseError = error as? Product.PurchaseError, case .purchaseNotAllowed = purchaseError {
            return "Purchases are turned off on this iPhone."
        }
        return "The App Store did not finish that. Try again."
    }

    // MARK: Ledger

    func markIntroShown() {
        guard !introShown else { return }
        introShown = true
        guard !isDemo else { return }
        let now = Date()
        ledger.update { ledger in
            if ledger?.introShownAt == nil { ledger?.introShownAt = now }
        }
    }

    /// The log a widget, the control, Siri or a nudge was refused while locked, if it was asked for recently.
    func takePendingLog(maxAge: TimeInterval, now: Date) -> PendingLog? {
        guard !isDemo, ledger.load()?.pending != nil else { return nil }
        return ledger.update { ledger -> PendingLog? in
            guard let pending = ledger?.pending else { return nil }
            ledger?.pending = nil
            let age = now.timeIntervalSince(pending.at)
            return age > -60 && age <= maxAge ? pending : nil
        }
    }
}

// MARK: - StoreKit to plain values

extension PurchaseFact {
    static func make(from result: VerificationResult<Transaction>) async -> PurchaseFact {
        let transaction: Transaction
        let verified: Bool
        switch result {
        case .verified(let value):
            transaction = value
            verified = true
        case .unverified(let value, _):
            transaction = value
            verified = false
        }
        var fact = PurchaseFact(productID: transaction.productID, verified: verified,
                                revokedAt: transaction.revocationDate, expiresAt: transaction.expirationDate,
                                isIntroOffer: transaction.isIntroductoryOffer, isUpgraded: transaction.isUpgraded)
        if transaction.productType == .autoRenewable, let status = await transaction.subscriptionStatus,
           case .verified(let renewal) = status.renewalInfo {
            fact.willRenew = renewal.willAutoRenew
            fact.graceUntil = renewal.gracePeriodExpirationDate
        }
        return fact
    }
}

private extension Transaction {
    /// The current period is the introductory offer.
    var isIntroductoryOffer: Bool {
        if #available(iOS 17.2, *) {
            return offer?.type == .introductory
        }
        return offerType == .introductory
    }
}

extension StoreEnvironment {
    init(_ environment: AppStore.Environment) {
        if environment == .production {
            self = .production
        } else if environment == .sandbox {
            self = .sandbox
        } else if environment == .xcode {
            self = .xcode
        } else {
            self = .other
        }
    }
}

extension PlanPeriod {
    init(_ period: Product.SubscriptionPeriod) {
        switch period.unit {
        case .day: self.init(value: period.value, unit: .day)
        case .week: self.init(value: period.value, unit: .week)
        case .month: self.init(value: period.value, unit: .month)
        case .year: self.init(value: period.value, unit: .year)
        @unknown default: self.init(value: period.value, unit: .month)
        }
    }
}

extension IntroTerms {
    init?(_ offer: Product.SubscriptionOffer) {
        let mode: Mode
        if offer.paymentMode == .freeTrial {
            mode = .onUs
        } else if offer.paymentMode == .payAsYouGo {
            mode = .payAsYouGo
        } else if offer.paymentMode == .payUpFront {
            mode = .payUpFront
        } else {
            return nil
        }
        self.init(mode: mode, period: PlanPeriod(offer.period), periodCount: offer.periodCount,
                  displayPrice: offer.displayPrice)
    }
}

extension PlanOffer {
    init(plan: ProPlan, product: Product) {
        let style = product.priceFormatStyle
        self.init(plan: plan, displayPrice: product.displayPrice, price: product.price,
                  currencyCode: style.currencyCode, locale: style.locale,
                  period: product.subscription.map { PlanPeriod($0.subscriptionPeriod) },
                  intro: product.subscription?.introductoryOffer.flatMap { IntroTerms($0) })
    }
}

/// The plans as StoreKit shapes them, for `-demo` screenshots only: CI has no App Store account to load products
/// from. Outside -demo every price, period and offer comes from StoreKit.
enum DemoOffers {
    private static let usd = Locale(identifier: "en_US")

    static var all: [ProPlan: PlanOffer] {
        [
            .yearly: PlanOffer(plan: .yearly, displayPrice: "$19.99", price: Decimal(string: "19.99") ?? 0,
                               currencyCode: "USD", locale: usd, period: PlanPeriod(value: 1, unit: .year),
                               intro: IntroTerms(mode: .onUs, period: PlanPeriod(value: 1, unit: .week),
                                                 periodCount: 1, displayPrice: "$0.00")),
            .monthly: PlanOffer(plan: .monthly, displayPrice: "$3.99", price: Decimal(string: "3.99") ?? 0,
                                currencyCode: "USD", locale: usd, period: PlanPeriod(value: 1, unit: .month), intro: nil),
            .lifetime: PlanOffer(plan: .lifetime, displayPrice: "$49.99", price: Decimal(string: "49.99") ?? 0,
                                 currencyCode: "USD", locale: usd, period: nil, intro: nil),
        ]
    }
}
