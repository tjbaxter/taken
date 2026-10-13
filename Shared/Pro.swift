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

    /// "YEARLY"
    var title: String { rawValue.uppercased() }
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
    /// Replaced by an upgrade to the other plan in the group.
    var isUpgraded: Bool

    init(productID: String, verified: Bool = true, revokedAt: Date? = nil, expiresAt: Date? = nil,
         graceUntil: Date? = nil, isIntroOffer: Bool = false, willRenew: Bool? = nil, isUpgraded: Bool = false) {
        self.productID = productID
        self.verified = verified
        self.revokedAt = revokedAt
        self.expiresAt = expiresAt
        self.graceUntil = graceUntil
        self.isIntroOffer = isIntroOffer
        self.willRenew = willRenew
        self.isUpgraded = isUpgraded
    }

    /// Counts at all: verified, never refunded or revoked, and not replaced by an upgrade.
    var isValid: Bool { verified && revokedAt == nil && !isUpgraded }

    /// Subscriptions: when access ends, counting a billing grace period. Nil when it grants nothing at `now`.
    func accessEnds(after now: Date) -> Date? {
        var end: Date?
        if let expiresAt, expiresAt > now { end = expiresAt }
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
    /// Subscriptions: access ends here unless a renewal arrives. Nil means for good (lifetime, founding).
    var expiresAt: Date?
    /// Subscriptions: renews at `expiresAt`. Nil when unknown.
    var willRenew: Bool?
    /// Subscriptions: the renewal payment failed and Apple's billing grace period is holding access open.
    var billingIssue: Bool

    init(isPro: Bool, reason: ProReason, checkedAt: Date, expiresAt: Date? = nil, willRenew: Bool? = nil,
         billingIssue: Bool = false) {
        self.isPro = isPro
        self.reason = reason
        self.checkedAt = checkedAt
        self.expiresAt = expiresAt
        self.willRenew = willRenew
        self.billingIssue = billingIssue
    }

    static func notPro(checkedAt: Date) -> ProStatus {
        ProStatus(isPro: false, reason: .none, checkedAt: checkedAt)
    }

    /// Cached Pro holds until `expiresAt` (a subscription) or for good (lifetime, founding).
    func isActive(at now: Date) -> Bool {
        guard isPro else { return false }
        guard let expiresAt else { return true }
        return now < expiresAt
    }

    /// The same entitlement, whenever it was checked.
    func sameEntitlement(as other: ProStatus?) -> Bool {
        guard let other else { return false }
        return isPro == other.isPro && reason == other.reason && expiresAt == other.expiresAt
            && willRenew == other.willRenew && billingIssue == other.billingIssue
    }

    private enum CodingKeys: String, CodingKey { case isPro, reason, checkedAt, expiresAt, willRenew, billingIssue }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isPro = try c.decodeIfPresent(Bool.self, forKey: .isPro) ?? false
        reason = (try? c.decodeIfPresent(ProReason.self, forKey: .reason)) ?? ProReason.none
        checkedAt = try c.decodeIfPresent(Date.self, forKey: .checkedAt) ?? .distantPast
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        willRenew = try c.decodeIfPresent(Bool.self, forKey: .willRenew)
        billingIssue = try c.decodeIfPresent(Bool.self, forKey: .billingIssue) ?? false
    }
}

/// The entitlement rule (PRO.md): Pro when any of a live subscription, the lifetime purchase, or founding membership.
enum Entitlement {
    static func evaluate(purchases: [PurchaseFact], app: AppTransactionFact?, maxBuild: Int = FoundingMember.maxBuild,
                         now: Date) -> ProStatus {
        let valid = purchases.filter(\.isValid)
        // For good beats for now, so the cache never expires for someone who owns Pro outright.
        if valid.contains(where: { $0.productID == ProPlan.lifetime.productID }) {
            return ProStatus(isPro: true, reason: .lifetime, checkedAt: now)
        }
        if FoundingMember.qualifies(app, maxBuild: maxBuild) {
            return ProStatus(isPro: true, reason: .founding, checkedAt: now)
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
        let inGrace = best.fact.expiresAt.map { $0 <= now } ?? false
        return ProStatus(isPro: true, reason: reason, checkedAt: now, expiresAt: best.until,
                         willRenew: best.fact.willRenew, billingIssue: inGrace)
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
    /// The one automatic paywall after the first dose has been shown.
    var introShownAt: Date?
    /// A log refused while locked, offered again when the app opens.
    var pending: PendingLog?

    init(status: ProStatus? = nil, firstSeenAt: Date, legacyLog: Bool, introShownAt: Date? = nil, pending: PendingLog? = nil) {
        self.status = status
        self.firstSeenAt = firstSeenAt
        self.legacyLog = legacyLog
        self.introShownAt = introShownAt
        self.pending = pending
    }

    private enum CodingKeys: String, CodingKey { case status, firstSeenAt, legacyLog, introShownAt, pending }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try? c.decodeIfPresent(ProStatus.self, forKey: .status)
        firstSeenAt = try c.decodeIfPresent(Date.self, forKey: .firstSeenAt) ?? .distantPast
        legacyLog = try c.decodeIfPresent(Bool.self, forKey: .legacyLog) ?? false
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

    /// Widgets, the control, App Intents and the nudge read the ledger the app wrote and never ask StoreKit. A
    /// missing ledger means the app has not run since the update to 1.1: someone with a log from 1.0.
    static func access(ledger: ProLedger?, state: StackState, now: Date) -> ProAccess {
        access(status: ledger?.status, settled: true, legacyLog: ledger?.legacyLog ?? true,
               hasLogged: !state.doses.isEmpty, now: now)
    }

    static func nudgeWindow(access: ProAccess, status: ProStatus?) -> NudgeWindow {
        guard access.allowsLogging else { return .closed }
        if access == .pro, let status, status.willRenew == false, let end = status.expiresAt { return .until(end) }
        return .open
    }
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
