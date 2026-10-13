import XCTest
@testable import Taken

/// The money rule (PRO.md): Pro when a live subscription, the lifetime purchase, or founding membership says so.
final class EntitlementTests: XCTestCase {

    private let now = at(2026, 10, 13, 9)
    private let yearly = ProPlan.yearly.productID
    private let monthly = ProPlan.monthly.productID
    private let lifetime = ProPlan.lifetime.productID

    private func production(_ version: String, verified: Bool = true) -> AppTransactionFact {
        AppTransactionFact(verified: verified, environment: .production, originalAppVersion: version)
    }

    func testNothingBoughtIsNotPro() {
        let status = Entitlement.evaluate(purchases: [], app: production("8"), now: now)
        XCTAssertFalse(status.isPro)
        XCTAssertEqual(status.reason, ProReason.none)
        XCTAssertNil(status.expiresAt)
        XCTAssertFalse(status.isActive(at: now))
        XCTAssertFalse(Entitlement.evaluate(purchases: [], app: nil, now: now).isPro, "no app transaction, no purchases")
    }

    func testLiveYearlySubscription() {
        let renews = at(2027, 10, 12, 9)
        let status = Entitlement.evaluate(purchases: [PurchaseFact(productID: yearly, expiresAt: renews, willRenew: true)],
                                          app: production("12"), now: now)
        XCTAssertTrue(status.isPro)
        XCTAssertEqual(status.reason, .yearly)
        XCTAssertEqual(status.expiresAt, renews)
        XCTAssertEqual(status.willRenew, true)
        XCTAssertFalse(status.billingIssue)
        XCTAssertTrue(status.isActive(at: now))
        XCTAssertTrue(status.isActive(at: renews.addingTimeInterval(-1)))
        XCTAssertFalse(status.isActive(at: renews), "cached Pro holds until expiresAt, not after")
    }

    func testLiveMonthlySubscription() {
        let status = Entitlement.evaluate(purchases: [PurchaseFact(productID: monthly, expiresAt: at(2026, 11, 13, 9))],
                                          app: nil, now: now)
        XCTAssertTrue(status.isPro)
        XCTAssertEqual(status.reason, .monthly)
    }

    func testIntroductoryWeekIsTheTrial() {
        let ends = at(2026, 10, 20, 9)
        let status = Entitlement.evaluate(
            purchases: [PurchaseFact(productID: yearly, expiresAt: ends, isIntroOffer: true, willRenew: true)],
            app: production("12"), now: now)
        XCTAssertTrue(status.isPro)
        XCTAssertEqual(status.reason, .trial)
        XCTAssertEqual(status.expiresAt, ends)
    }

    func testExpiredSubscriptionIsNotPro() {
        let lapsed = PurchaseFact(productID: yearly, expiresAt: at(2026, 10, 12, 9), willRenew: false)
        XCTAssertFalse(Entitlement.evaluate(purchases: [lapsed], app: production("12"), now: now).isPro)
        let endsNow = PurchaseFact(productID: monthly, expiresAt: now)
        XCTAssertFalse(Entitlement.evaluate(purchases: [endsNow], app: nil, now: now).isPro, "the end moment is already out")
        let noDate = PurchaseFact(productID: monthly)
        XCTAssertFalse(Entitlement.evaluate(purchases: [noDate], app: nil, now: now).isPro,
                       "a subscription with no period end grants nothing")
    }

    func testBillingGracePeriodKeepsPro() {
        let grace = at(2026, 10, 25, 9)
        let fact = PurchaseFact(productID: monthly, expiresAt: at(2026, 10, 12, 9), graceUntil: grace, willRenew: true)
        let status = Entitlement.evaluate(purchases: [fact], app: nil, now: now)
        XCTAssertTrue(status.isPro)
        XCTAssertEqual(status.reason, .monthly)
        XCTAssertTrue(status.billingIssue)
        XCTAssertEqual(status.expiresAt, grace, "the cache holds through the grace period")
        XCTAssertFalse(Entitlement.evaluate(purchases: [fact], app: nil, now: at(2026, 10, 25, 10)).isPro, "and no longer")
    }

    func testRevokedTransactionsNeverCount() {
        let refunded = PurchaseFact(productID: yearly, revokedAt: at(2026, 10, 10, 9), expiresAt: at(2027, 10, 1, 9))
        XCTAssertFalse(Entitlement.evaluate(purchases: [refunded], app: nil, now: now).isPro)
        let refundedLifetime = PurchaseFact(productID: lifetime, revokedAt: at(2026, 10, 10, 9))
        XCTAssertFalse(Entitlement.evaluate(purchases: [refundedLifetime], app: nil, now: now).isPro)
    }

    func testUnverifiedTransactionsNeverCount() {
        let forged = [PurchaseFact(productID: lifetime, verified: false),
                      PurchaseFact(productID: yearly, verified: false, expiresAt: at(2027, 10, 1, 9))]
        XCTAssertFalse(Entitlement.evaluate(purchases: forged, app: nil, now: now).isPro)
    }

    func testLifetimeIsForGood() {
        let status = Entitlement.evaluate(purchases: [PurchaseFact(productID: lifetime)], app: production("40"), now: now)
        XCTAssertTrue(status.isPro)
        XCTAssertEqual(status.reason, .lifetime)
        XCTAssertNil(status.expiresAt)
        XCTAssertTrue(status.isActive(at: at(2040, 1, 1, 0)), "lifetime never expires in the cache")
    }

    func testLifetimeWinsOverASubscription() {
        let status = Entitlement.evaluate(
            purchases: [PurchaseFact(productID: monthly, expiresAt: at(2026, 11, 1, 9)), PurchaseFact(productID: lifetime)],
            app: nil, now: now)
        XCTAssertEqual(status.reason, .lifetime)
        XCTAssertNil(status.expiresAt)
    }

    func testFoundingMembers() {
        XCTAssertTrue(FoundingMember.qualifies(production("7"), maxBuild: 7), "the build in App Review")
        XCTAssertTrue(FoundingMember.qualifies(production("1"), maxBuild: 7))
        XCTAssertTrue(FoundingMember.qualifies(production(" 5 "), maxBuild: 7))
        XCTAssertFalse(FoundingMember.qualifies(production("8"), maxBuild: 7), "the first 1.1 build is past the cutoff")
        XCTAssertFalse(FoundingMember.qualifies(production("0"), maxBuild: 7))
        XCTAssertFalse(FoundingMember.qualifies(production("7.1"), maxBuild: 7))
        XCTAssertFalse(FoundingMember.qualifies(production(""), maxBuild: 7))
        XCTAssertFalse(FoundingMember.qualifies(production("5", verified: false), maxBuild: 7), "unverified")
        XCTAssertFalse(FoundingMember.qualifies(nil, maxBuild: 7))
        XCTAssertTrue(FoundingMember.qualifies(production("9"), maxBuild: 9), "the release engineer can raise the cutoff")
        XCTAssertEqual(FoundingMember.maxBuild, 7)
    }

    func testSandboxAndTestFlightAreNeverFoundingMembers() {
        // In the sandbox (TestFlight, App Review) originalAppVersion is always "1.0".
        let sandbox = AppTransactionFact(verified: true, environment: .sandbox, originalAppVersion: "1.0")
        XCTAssertFalse(FoundingMember.qualifies(sandbox))
        XCTAssertFalse(Entitlement.evaluate(purchases: [], app: sandbox, now: now).isPro, "App Review sees the paywall")
        let sandboxBuild = AppTransactionFact(verified: true, environment: .sandbox, originalAppVersion: "3")
        XCTAssertFalse(FoundingMember.qualifies(sandboxBuild), "only production counts")
        let xcode = AppTransactionFact(verified: true, environment: .xcode, originalAppVersion: "1")
        XCTAssertFalse(FoundingMember.qualifies(xcode))
        XCTAssertFalse(FoundingMember.qualifies(production("1.0")), "1.0 is not a build number")
    }

    func testFoundingMemberIsProForLife() {
        let status = Entitlement.evaluate(purchases: [], app: production("6"), now: now)
        XCTAssertTrue(status.isPro)
        XCTAssertEqual(status.reason, .founding)
        XCTAssertNil(status.expiresAt)
        XCTAssertTrue(status.isActive(at: at(2050, 1, 1, 0)))
        let alsoSubscribed = Entitlement.evaluate(
            purchases: [PurchaseFact(productID: yearly, expiresAt: at(2027, 10, 1, 9))], app: production("6"), now: now)
        XCTAssertEqual(alsoSubscribed.reason, .founding, "for good beats for now")
    }

    func testUpgradedAndUnknownTransactionsAreIgnored() {
        let upgradedAway = PurchaseFact(productID: monthly, expiresAt: at(2026, 11, 1, 9), isUpgraded: true)
        XCTAssertFalse(Entitlement.evaluate(purchases: [upgradedAway], app: nil, now: now).isPro)
        let stranger = PurchaseFact(productID: "com.example.other", expiresAt: at(2027, 1, 1, 9))
        XCTAssertFalse(Entitlement.evaluate(purchases: [stranger], app: nil, now: now).isPro)
    }

    func testTheLaterOfTwoLiveSubscriptionsWins() {
        let status = Entitlement.evaluate(purchases: [
            PurchaseFact(productID: monthly, expiresAt: at(2026, 11, 1, 9)),
            PurchaseFact(productID: yearly, expiresAt: at(2027, 10, 1, 9), willRenew: false),
        ], app: nil, now: now)
        XCTAssertEqual(status.reason, .yearly)
        XCTAssertEqual(status.expiresAt, at(2027, 10, 1, 9))
        XCTAssertEqual(status.willRenew, false)
    }

    func testSameEntitlementIgnoresTheCheckTime() {
        let first = ProStatus(isPro: true, reason: .lifetime, checkedAt: now)
        var later = first
        later.checkedAt = now.addingTimeInterval(3600)
        XCTAssertTrue(later.sameEntitlement(as: first))
        XCTAssertFalse(later.sameEntitlement(as: nil))
        later.reason = .founding
        XCTAssertFalse(later.sameEntitlement(as: first))
    }

    func testProductIDsAreFixed() {
        XCTAssertEqual(ProPlan.allCases.map(\.productID), [
            "com.tombaxter.taken.pro.yearly",
            "com.tombaxter.taken.pro.monthly",
            "com.tombaxter.taken.pro.lifetime",
        ])
        XCTAssertEqual(ProPlan(productID: "com.tombaxter.taken.pro.lifetime"), .lifetime)
        XCTAssertNil(ProPlan(productID: "com.tombaxter.taken.pro"))
    }
}
