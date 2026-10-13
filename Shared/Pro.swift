import Foundation

// Taken Pro (PRO.md). Code owns money: the rule that decides Pro is a pure function over plain values, and its
// answer is cached in the App Group, so the widget extension, the Control Center control, App Intents and the
// nudge read the same answer the app worked out, without StoreKit. StoreKit itself lives in Taken/Pro/ProStore.swift.

/// Everyone whose first download of Taken was a 1.0 build keeps Pro for life.
enum FoundingMember {
    /// The last 1.0.x build number shipped. 1.0.0 build 7 is the build in App Review.
    /// Release engineer: if a later 1.0.x build ships, set this to that build's number before the 1.1 build goes
    /// out. Every 1.1+ build number must stay above it (release.yml refuses one that is not).
    static let maxBuild = 7

    /// On iOS `AppTransaction.originalAppVersion` is the CFBundleVersion of the customer's first download. Only a
    /// verified production app transaction counts: in the sandbox and TestFlight it is always "1.0", which is not a
    /// build number, so App Review and testers see Taken as a new customer does.
    static func qualifies(_ app: AppTransactionFact?, maxBuild: Int = FoundingMember.maxBuild) -> Bool {
        guard let app, app.verified, app.environment == .production else { return false }
        guard let build = Int(app.originalAppVersion.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return build >= 1 && build <= maxBuild
    }
}

/// The three products in App Store Connect. The ids are fixed.
enum ProPlan: String, CaseIterable, Codable, Identifiable, Sendable {
    case yearly
    case monthly
    case lifetime

    var id: String { rawValue }

    var productID: String {
        switch self {
        case .yearly: return "com.tombaxter.taken.pro.yearly"
        case .monthly: return "com.tombaxter.taken.pro.monthly"
        case .lifetime: return "com.tombaxter.taken.pro.lifetime"
        }
    }

    init?(productID: String) {
        guard let plan = ProPlan.allCases.first(where: { $0.productID == productID }) else { return nil }
        self = plan
    }

    var isSubscription: Bool { self != .lifetime }

    /// "Yearly"
    var title: String { rawValue.capitalized }
}

/// Where an App Store transaction was made.
enum StoreEnvironment: String, Codable, Sendable {
    case production
    case sandbox
    case xcode
    case other
}

/// The app transaction as the founding-member rule sees it.
struct AppTransactionFact: Hashable, Sendable {
    var verified: Bool
    var environment: StoreEnvironment
    var originalAppVersion: String

    init(verified: Bool, environment: StoreEnvironment, originalAppVersion: String) {
        self.verified = verified
        self.environment = environment
        self.originalAppVersion = originalAppVersion
    }
}

/// One App Store transaction as the entitlement rule sees it (ProStore builds these from StoreKit).
struct PurchaseFact: Hashable, Sendable {
    var productID: String
    /// StoreKit verified the signed transaction. Unverified ones never grant anything.
    var verified: Bool
    /// Set when Apple refunded or revoked the purchase.
    var revokedAt: Date?
    /// Subscriptions: the end of the current period (the end of the 7 days during the introductory offer).
    var expiresAt: Date?
    /// Subscriptions: Apple keeps access open through a billing grace period until this moment.
    var graceUntil: Date?
    /// The current period is the introductory offer.
    var isIntroOffer: Bool
    /// Subscriptions: whether it renews at `expiresAt`. Nil when StoreKit did not say.
    var willRenew: Bool?
    /// Subscriptions: a renewal payment failed and Apple is retrying it.
    var inBillingRetry: Bool
    /// Replaced by an upgrade to the other plan in the group.
    var isUpgraded: Bool

    init(productID: String, verified: Bool = true, revokedAt: Date? = nil, expiresAt: Date? = nil,
         graceUntil: Date? = nil, isIntroOffer: Bool = false, willRenew: Bool? = nil, inBillingRetry: Bool = false,
         isUpgraded: Bool = false) {
        self.productID = productID
        self.verified = verified
        self.revokedAt = revokedAt
        self.expiresAt = expiresAt
        self.graceUntil = graceUntil
        self.isIntroOffer = isIntroOffer
        self.willRenew = willRenew
        self.inBillingRetry = inBillingRetry
        self.isUpgraded = isUpgraded
    }

    /// Counts at all: verified, never refunded or revoked, and not replaced by an upgrade.
    var isValid: Bool { verified && revokedAt == nil && !isUpgraded }

    var isSubscription: Bool { ProPlan(productID: productID)?.isSubscription == true }

    /// Set to renew as far as StoreKit knows: not cancelled, and no failed payment being retried or held in grace.
    var renews: Bool { willRenew != false && !inBillingRetry && graceUntil == nil }

    /// Subscriptions: when access ends. A billing grace period holds it open to `graceUntil`. A plan set to renew holds
    /// it `ProStatus.renewalMargin` past `expiresAt`: StoreKit still lists it as subscribed, and the renewal is on its
    /// way to this iPhone. Nil when it grants nothing at `now`.
    func accessEnds(after now: Date) -> Date? {
        var end: Date?
        if let expiresAt {
            let until = renews ? expiresAt.addingTimeInterval(ProStatus.renewalMargin) : expiresAt
            if until > now { end = until }
        }
        if let graceUntil, graceUntil > now, graceUntil > (end ?? .distantPast) { end = graceUntil }
        return end
    }
}

/// Why someone has Pro, or `.none`.
enum ProReason: String, Codable, Sendable {
    case none
    case trial
    case yearly
    case monthly
    case lifetime
    case founding
}

/// The answer, as cached for every process: `{isPro, reason, checkedAt, expiresAt?}` (PRO.md).
struct ProStatus: Codable, Hashable, Sendable {
    var isPro: Bool
    var reason: ProReason
    var checkedAt: Date
    /// Subscriptions: the end of the current period (the end of a billing grace period while in one). Nil means for
    /// good (lifetime, founding).
    var expiresAt: Date?
    /// Subscriptions: renews at `expiresAt`. Nil when unknown.
    var willRenew: Bool?
    /// Subscriptions: the renewal payment failed and Apple's billing grace period is holding access open.
    var billingIssue: Bool
    /// Lifetime and founding members: a subscription on the same Apple Account still renews, so Settings offers to
    /// manage it.
    var renewingSubscription: Bool

    init(isPro: Bool, reason: ProReason, checkedAt: Date, expiresAt: Date? = nil, willRenew: Bool? = nil,
         billingIssue: Bool = false, renewingSubscription: Bool = false) {
        self.isPro = isPro
        self.reason = reason
        self.checkedAt = checkedAt
        self.expiresAt = expiresAt
        self.willRenew = willRenew
        self.billingIssue = billingIssue
        self.renewingSubscription = renewingSubscription
    }

    static func notPro(checkedAt: Date) -> ProStatus {
        ProStatus(isPro: false, reason: .none, checkedAt: checkedAt)
    }

    /// How long a plan set to renew stays on past the end of its period. The App Store renews it there, but only the
    /// app can see that, and the widgets, the control, Siri and the nudge read this cache: a payer is never locked out
    /// of them at a renewal, or when the introductory week converts, because Taken was not opened that day.
    static let renewalMargin: TimeInterval = 3 * 24 * 60 * 60

    /// When cached Pro ends. Nil for good (lifetime, founding). A plan set not to renew, or held open by a billing grace
    /// period, ends on time; any other plan runs `renewalMargin` past its period end.
    var activeUntil: Date? {
        guard let expiresAt else { return nil }
        if willRenew == false || billingIssue { return expiresAt }
        return expiresAt.addingTimeInterval(Self.renewalMargin)
    }

    /// Cached Pro holds until `activeUntil`, or for good (lifetime, founding).
    func isActive(at now: Date) -> Bool {
        guard isPro else { return false }
        guard let activeUntil else { return true }
        return now < activeUntil
    }

    /// The period has ended and the renewal has not shown yet: still Pro, inside the renewal margin.
    func awaitingRenewal(at now: Date) -> Bool {
        guard isPro, let expiresAt, expiresAt <= now, willRenew != false, !billingIssue else { return false }
        return isActive(at: now)
    }

    /// A plan set to renew whose margin ran out before anyone saw the renewal. Only the App Store knows whether it
    /// renewed, so where StoreKit runs it is asked before anything locks.
    func lapsedRenewal(at now: Date) -> Bool {
        isPro && expiresAt != nil && willRenew != false && !billingIssue && !isActive(at: now)
    }

    /// A subscription renews: this plan, or one alongside Pro for good.
    var renewsASubscription: Bool {
        renewingSubscription || (isPro && expiresAt != nil && willRenew == true)
    }

    /// The same entitlement, whenever it was checked.
    func sameEntitlement(as other: ProStatus?) -> Bool {
        guard let other else { return false }
        return isPro == other.isPro && reason == other.reason && expiresAt == other.expiresAt
            && willRenew == other.willRenew && billingIssue == other.billingIssue
            && renewingSubscription == other.renewingSubscription
    }

    private enum CodingKeys: String, CodingKey {
        case isPro, reason, checkedAt, expiresAt, willRenew, billingIssue, renewingSubscription
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isPro = try c.decodeIfPresent(Bool.self, forKey: .isPro) ?? false
        reason = (try? c.decodeIfPresent(ProReason.self, forKey: .reason)) ?? ProReason.none
        checkedAt = try c.decodeIfPresent(Date.self, forKey: .checkedAt) ?? .distantPast
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        willRenew = try c.decodeIfPresent(Bool.self, forKey: .willRenew)
        billingIssue = try c.decodeIfPresent(Bool.self, forKey: .billingIssue) ?? false
        renewingSubscription = try c.decodeIfPresent(Bool.self, forKey: .renewingSubscription) ?? false
    }
}

/// The entitlement rule (PRO.md): Pro when any of a live subscription, the lifetime purchase, or founding membership.
enum Entitlement {
    static func evaluate(purchases: [PurchaseFact], app: AppTransactionFact?, maxBuild: Int = FoundingMember.maxBuild,
                         now: Date) -> ProStatus {
        let valid = purchases.filter(\.isValid)
        // A subscription that still renews next to Pro for good: Settings offers to cancel it.
        let renewing = valid.contains { $0.isSubscription && $0.willRenew == true && $0.accessEnds(after: now) != nil }
        // For good beats for now, so the cache never expires for someone who owns Pro outright.
        if valid.contains(where: { $0.productID == ProPlan.lifetime.productID }) {
            return ProStatus(isPro: true, reason: .lifetime, checkedAt: now, renewingSubscription: renewing)
        }
        if FoundingMember.qualifies(app, maxBuild: maxBuild) {
            return ProStatus(isPro: true, reason: .founding, checkedAt: now, renewingSubscription: renewing)
        }
        var best: (fact: PurchaseFact, plan: ProPlan, until: Date)?
        for fact in valid {
            guard let plan = ProPlan(productID: fact.productID), plan.isSubscription,
                  let until = fact.accessEnds(after: now) else { continue }
            if let current = best, current.until >= until { continue }
            best = (fact, plan, until)
        }
        guard let best else { return .notPro(checkedAt: now) }
        let reason: ProReason = best.fact.isIntroOffer ? .trial : (best.plan == .yearly ? .yearly : .monthly)
        // In a billing grace period the cache holds to the grace end. Otherwise it keeps the period end, and ProStatus
        // adds the renewal margin to a plan set to renew.
        let pastEnd = best.fact.expiresAt.map { $0 <= now } ?? true
        let inGrace = pastEnd && (best.fact.graceUntil.map { $0 > now } ?? false)
        return ProStatus(isPro: true, reason: reason, checkedAt: now,
                         expiresAt: inGrace ? best.fact.graceUntil : best.fact.expiresAt,
                         willRenew: best.fact.willRenew, billingIssue: inGrace || best.fact.inBillingRetry)
    }

    /// What to keep after asking StoreKit: `fresh` is what it said, `app` the app transaction it gave (nil when it
    /// gave none). A no only replaces what was known when it proves something.
    static func next(previous: ProStatus?, fresh: ProStatus, app: AppTransactionFact?) -> ProStatus? {
        // A verified app transaction: everything was checked, founding membership included.
        if app?.verified == true { return fresh }
        // Founding membership needs a verified app transaction, so a known founding member stays one. Purchases read
        // meanwhile only say whether a subscription still renews next to it.
        if var founding = previous, founding.isPro, founding.reason == .founding {
            founding.checkedAt = fresh.checkedAt
            founding.renewingSubscription = fresh.renewsASubscription
            return founding
        }
        if fresh.isPro { return fresh }
        // No app transaction at all (offline, signed out): finding no purchase proves nothing, so what was known stands.
        guard app != nil else { return previous }
        // An unverified one: purchases were still read, so an ended plan or a refunded purchase stops counting. A log
        // never checked stays unchecked (a 1.0 log stays pending: every 1.0 App Store download is a founding member).
        return previous == nil ? nil : fresh
    }
}

// MARK: - Logging without Pro

/// A dose log the widget, the control, Siri or a nudge could not make without Pro.
enum ProPendingAction: Codable, Hashable, Sendable {
    case takeAll
    case log(UUID)
}

struct PendingLog: Codable, Hashable, Sendable {
    var action: ProPendingAction
    /// When it was asked for. The app logs it at this time once Pro is on.
    var at: Date

    init(action: ProPendingAction, at: Date) {
        self.action = action
        self.at = at
    }
}

/// What the app last learned about Pro: one small JSON file in the App Group, next to the log.
struct ProLedger: Codable, Hashable, Sendable {
    /// The last StoreKit answer. Nil until the first conclusive check.
    var status: ProStatus?
    /// When this version of Taken first ran.
    var firstSeenAt: Date
    /// The log already had doses when this version first ran: an update from 1.0, where every App Store download
    /// is a founding member. Until StoreKit has answered for them, they are never locked out on a guess.
    var legacyLog: Bool
    /// The first dose ever logged, from any surface. From then on the first session is over for good: erasing the
    /// log or deleting items never opens logging again without Pro.
    var firstDoseAt: Date?
    /// The one automatic paywall after the first dose has been shown.
    var introShownAt: Date?
    /// A log refused while locked, offered again when the app opens.
    var pending: PendingLog?

    init(status: ProStatus? = nil, firstSeenAt: Date, legacyLog: Bool, firstDoseAt: Date? = nil,
         introShownAt: Date? = nil, pending: PendingLog? = nil) {
        self.status = status
        self.firstSeenAt = firstSeenAt
        self.legacyLog = legacyLog
        self.firstDoseAt = firstDoseAt
        self.introShownAt = introShownAt
        self.pending = pending
    }

    private enum CodingKeys: String, CodingKey { case status, firstSeenAt, legacyLog, firstDoseAt, introShownAt, pending }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try? c.decodeIfPresent(ProStatus.self, forKey: .status)
        firstSeenAt = try c.decodeIfPresent(Date.self, forKey: .firstSeenAt) ?? .distantPast
        legacyLog = try c.decodeIfPresent(Bool.self, forKey: .legacyLog) ?? false
        firstDoseAt = try? c.decodeIfPresent(Date.self, forKey: .firstDoseAt)
        introShownAt = try c.decodeIfPresent(Date.self, forKey: .introShownAt)
        pending = try? c.decodeIfPresent(PendingLog.self, forKey: .pending)
    }
}

/// Reads and writes `pro.json` with the same file coordination as the log, so the app, the widget extension and
/// intents never overwrite each other.
final class ProLedgerStore: Sendable {
    static let fileName = "pro.json"
    static let shared = ProLedgerStore(fileURL: TakenStore.defaultFileURL().deletingLastPathComponent()
        .appendingPathComponent(ProLedgerStore.fileName))

    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Nil when the app has not run this version yet (or the file is unreadable).
    func load() -> ProLedger? {
        var ledger: ProLedger?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { url in
            if let data = try? Data(contentsOf: url) { ledger = try? Self.decode(data) }
        }
        return ledger
    }

    /// Coordinated read-modify-write. The closure sees the latest file (nil if there is none); a nil left in it
    /// writes nothing. A failed write keeps the old file: everything here can be worked out again.
    @discardableResult
    func update<T>(_ body: (inout ProLedger?) -> T) -> T {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var output: T?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: fileURL, options: .forMerging, error: &coordinationError) { url in
            var ledger = (try? Data(contentsOf: url)).flatMap { try? Self.decode($0) }
            let before = ledger
            output = body(&ledger)
            if let ledger, ledger != before, let data = try? Self.encode(ledger) {
                try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }
        if let output { return output }
        // Coordination failed: run the closure on what can be read, so callers still get an answer.
        var ledger = load()
        return body(&ledger)
    }

    /// The ledger, written fresh the first time this version runs.
    func loadOrCreate(_ make: () -> ProLedger) -> ProLedger {
        if let existing = load() { return existing }
        return update { ledger -> ProLedger in
            if let ledger { return ledger }
            let fresh = make()
            ledger = fresh
            return fresh
        }
    }

    /// Remember a refused log so the app can offer it when it opens.
    func recordPending(_ action: ProPendingAction, at date: Date) {
        update { ledger in ledger?.pending = PendingLog(action: action, at: date) }
    }

    /// A dose was logged: the first one ever ends the first session for good. Written once; a ledger the app has not
    /// created yet is left alone (until it runs, the log counts as one from 1.0).
    func noteFirstDose(at date: Date) {
        guard let current = load(), current.firstDoseAt == nil else { return }
        update { ledger in
            if let existing = ledger, existing.firstDoseAt == nil { ledger?.firstDoseAt = date }
        }
    }

    static func encode(_ ledger: ProLedger) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(ledger)
    }

    static func decode(_ data: Data) throws -> ProLedger {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(ProLedger.self, from: data)
    }
}

// MARK: - The gate

/// Whether a dose may be logged right now.
enum ProAccess: String, Sendable {
    /// Pro is active.
    case pro
    /// Nothing has been logged yet: the first dose (the moment Taken makes sense) needs no Pro.
    case firstSession
    /// Logged before this version and StoreKit has not answered yet: never locked out on a guess.
    case pending
    /// The app is still waiting for StoreKit's first answer of this launch.
    case checking
    /// Logging needs Pro.
    case locked

    var allowsLogging: Bool { self == .pro || self == .firstSession || self == .pending }
}

/// How far ahead the nudge may be scheduled.
enum NudgeWindow: Equatable, Sendable {
    case open
    /// A subscription set not to renew: nudges stop when it ends.
    case until(Date)
    /// Locked: no nudges.
    case closed
}

enum ProGate {
    /// The one rule for every surface. `settled` is false only in the app before StoreKit's first answer.
    static func access(status: ProStatus?, settled: Bool, legacyLog: Bool, hasLogged: Bool, now: Date) -> ProAccess {
        if let status, status.isActive(at: now) { return .pro }
        if !hasLogged { return .firstSession }
        if status == nil && legacyLog { return .pending }
        if !settled { return .checking }
        return .locked
    }

    /// Whether anything was ever logged: a dose in the log now, or the first dose the ledger remembers.
    static func hasLogged(state: StackState, ledger: ProLedger?) -> Bool {
        !state.doses.isEmpty || ledger?.firstDoseAt != nil
    }

    /// Widgets, the control, App Intents and the nudge read the ledger the app wrote and never ask StoreKit. A
    /// missing ledger means the app has not run since the update to 1.1: someone with a log from 1.0.
    static func access(ledger: ProLedger?, state: StackState, now: Date) -> ProAccess {
        access(status: ledger?.status, settled: true, legacyLog: ledger?.legacyLog ?? true,
               hasLogged: hasLogged(state: state, ledger: ledger), now: now)
    }

    /// Whether Siri, Shortcuts, a widget or the nudge may log now. In the app's process, where StoreKit runs, a plan set
    /// to renew whose cache ran out is checked with the App Store before the answer is no (`ProRecheck`).
    static func mayLog(state: StackState, now: Date, ledgerStore: ProLedgerStore = .shared) async -> Bool {
        let ledger = ledgerStore.load()
        if access(ledger: ledger, state: state, now: now).allowsLogging { return true }
        guard ledger?.status?.lapsedRenewal(at: now) == true, let recheck = await ProRecheck.handler else { return false }
        await recheck()
        return access(ledger: ledgerStore.load(), state: state, now: now).allowsLogging
    }

    static func nudgeWindow(access: ProAccess, status: ProStatus?) -> NudgeWindow {
        guard access.allowsLogging else { return .closed }
        if access == .pro, let status, status.willRenew == false, let end = status.activeUntil { return .until(end) }
        return .open
    }
}

/// How Siri and the nudge ask the App Store again before refusing a log. The app sets it at launch (StoreKit runs only
/// there); the widget extension never does, so its widgets and the control read the cache alone.
@MainActor
enum ProRecheck {
    static var handler: (@MainActor @Sendable () async -> Void)?
}

/// `taken://pro`, optionally with the log a locked widget tap asked for: `taken://pro?then=take-all`,
/// `taken://pro?then=log&item=<uuid>`.
struct ProRoute: Hashable, Sendable {
    static let scheme = "taken"
    static let host = "pro"

    let then: ProPendingAction?

    init(then: ProPendingAction? = nil) {
        self.then = then
    }

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == Self.scheme, components.host == Self.host else { return nil }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        switch value("then") {
        case "take-all":
            then = .takeAll
        case "log":
            then = value("item").flatMap(UUID.init(uuidString:)).map { ProPendingAction.log($0) }
        default:
            then = nil
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        switch then {
        case .takeAll:
            components.queryItems = [URLQueryItem(name: "then", value: "take-all")]
        case .log(let id):
            components.queryItems = [URLQueryItem(name: "then", value: "log"), URLQueryItem(name: "item", value: id.uuidString)]
        case nil:
            break
        }
        return components.url ?? URL(fileURLWithPath: "/")
    }
}
