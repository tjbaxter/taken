import XCTest
@testable import Taken

/// The paywall's and Settings' words are built from StoreKit's values (PRO.md), so the lines Apple requires are
/// checked here for every plan and offer shape.
final class ProCopyTests: XCTestCase {

    private let us = Locale(identifier: "en_US")
    private let week = PlanPeriod(value: 1, unit: .week)

    private func yearly(intro: IntroTerms? = nil, price: String = "19.99", display: String = "$19.99",
                        currency: String = "USD", locale: Locale? = nil) -> PlanOffer {
        PlanOffer(plan: .yearly, displayPrice: display, price: Decimal(string: price)!, currencyCode: currency,
                  locale: locale ?? us, period: PlanPeriod(value: 1, unit: .year), intro: intro)
    }

    private var onUsWeek: IntroTerms { IntroTerms(mode: .onUs, period: week, periodCount: 1, displayPrice: "$0.00") }
    private var monthly: PlanOffer {
        PlanOffer(plan: .monthly, displayPrice: "$3.99", price: Decimal(string: "3.99")!, currencyCode: "USD", locale: us,
                  period: PlanPeriod(value: 1, unit: .month), intro: nil)
    }
    private var lifetime: PlanOffer {
        PlanOffer(plan: .lifetime, displayPrice: "$49.99", price: Decimal(string: "49.99")!, currencyCode: "USD", locale: us,
                  period: nil, intro: nil)
    }

    func testYearlyWithTheIntroductoryWeek() {
        let offer = yearly(intro: onUsWeek)
        XCTAssertEqual(ProCopy.introTag(offer.intro), "7 days on us")
        XCTAssertEqual(ProCopy.price(offer).amount, "$19.99")
        XCTAssertEqual(ProCopy.price(offer).unit, "/ year")
        XCTAssertEqual(ProCopy.monthlyEquivalent(offer), "about $1.67 / month")
        XCTAssertEqual(ProCopy.cta(offer, eligible: true), "Start 7 days on us")
        XCTAssertEqual(ProCopy.terms(offer, eligible: true),
                       "7 days on us, then $19.99 per year. Renews automatically until cancelled. Cancel anytime in Settings at least 24 hours before renewal.")
    }

    func testYearlyAfterTheOfferWasUsed() {
        let offer = yearly(intro: onUsWeek)
        XCTAssertNil(ProCopy.liveIntro(offer, eligible: false))
        XCTAssertEqual(ProCopy.cta(offer, eligible: false), "Continue")
        XCTAssertEqual(ProCopy.terms(offer, eligible: false),
                       "$19.99 per year. Renews automatically until cancelled. Cancel anytime in Settings at least 24 hours before renewal.")
    }

    func testSevenDaysReadsTheSameAsOneWeek() {
        let days = IntroTerms(mode: .onUs, period: PlanPeriod(value: 7, unit: .day), periodCount: 1, displayPrice: "$0.00")
        XCTAssertEqual(ProCopy.introTag(days), "7 days on us")
        XCTAssertEqual(ProCopy.span(IntroTerms(mode: .onUs, period: week, periodCount: 2, displayPrice: "$0.00")), "14 days")
        XCTAssertEqual(ProCopy.introTag(IntroTerms(mode: .onUs, period: PlanPeriod(value: 1, unit: .month), periodCount: 1,
                                                   displayPrice: "$0.00")), "1 month on us")
        XCTAssertEqual(ProCopy.span(IntroTerms(mode: .onUs, period: PlanPeriod(value: 1, unit: .day), periodCount: 1,
                                               displayPrice: "$0.00")), "1 day")
    }

    func testMonthly() {
        XCTAssertEqual(ProCopy.price(monthly).amount, "$3.99")
        XCTAssertEqual(ProCopy.price(monthly).unit, "/ month")
        XCTAssertNil(ProCopy.monthlyEquivalent(monthly))
        XCTAssertNil(ProCopy.introTag(monthly.intro))
        XCTAssertEqual(ProCopy.cta(monthly, eligible: true), "Continue", "monthly has no introductory offer")
        XCTAssertEqual(ProCopy.terms(monthly, eligible: true),
                       "$3.99 per month. Renews automatically until cancelled. Cancel anytime in Settings at least 24 hours before renewal.")
    }

    func testLifetime() {
        XCTAssertEqual(ProCopy.price(lifetime).amount, "$49.99")
        XCTAssertEqual(ProCopy.price(lifetime).unit, "once")
        XCTAssertNil(ProCopy.monthlyEquivalent(lifetime))
        XCTAssertEqual(ProCopy.cta(lifetime, eligible: true), "Continue")
        XCTAssertEqual(ProCopy.terms(lifetime, eligible: true), "One payment. Yours for good.")
        XCTAssertEqual(ProCopy.termsWithoutPrices(.lifetime), "One payment. Yours for good.")
        XCTAssertEqual(ProCopy.termsWithoutPrices(.yearly), ProCopy.renewalTerms)
        XCTAssertEqual(ProCopy.cta(nil, eligible: true), "Continue")
    }

    func testPricesFollowTheStorefront() {
        let gb = yearly(price: "19.99", display: "£19.99", currency: "GBP", locale: Locale(identifier: "en_GB"))
        XCTAssertEqual(ProCopy.price(gb).amount, "£19.99", "the billed amount is StoreKit's own display price")
        XCTAssertEqual(ProCopy.monthlyEquivalent(gb), "about £1.67 / month")
        let de = yearly(price: "19.99", display: "19,99 €", currency: "EUR", locale: Locale(identifier: "de_DE"))
        let perMonth = ProCopy.monthlyEquivalent(de) ?? ""
        XCTAssertTrue(perMonth.hasPrefix("about 1,67"), perMonth)
        XCTAssertTrue(perMonth.contains("€"), perMonth)
        let jp = yearly(price: "3000", display: "¥3,000", currency: "JPY")
        XCTAssertEqual(ProCopy.monthlyEquivalent(jp), "about ¥250 / month")
        XCTAssertEqual(ProCopy.terms(jp, eligible: false).prefix(16), "¥3,000 per year.")
    }

    func testOtherIntroductoryOfferShapes() {
        let payAsYouGo = IntroTerms(mode: .payAsYouGo, period: PlanPeriod(value: 1, unit: .month), periodCount: 3,
                                    displayPrice: "$0.99")
        let monthlyIntro = PlanOffer(plan: .monthly, displayPrice: "$3.99", price: Decimal(string: "3.99")!,
                                     currencyCode: "USD", locale: us, period: PlanPeriod(value: 1, unit: .month),
                                     intro: payAsYouGo)
        XCTAssertNil(ProCopy.introTag(payAsYouGo), "only an offer that costs nothing is on us")
        XCTAssertEqual(ProCopy.cta(monthlyIntro, eligible: true), "Continue")
        XCTAssertEqual(ProCopy.terms(monthlyIntro, eligible: true),
                       "$0.99 per month for 3 months, then $3.99 per month. \(ProCopy.renewalTerms)")
        let upFront = IntroTerms(mode: .payUpFront, period: PlanPeriod(value: 3, unit: .month), periodCount: 1,
                                 displayPrice: "$1.99")
        XCTAssertEqual(ProCopy.terms(yearly(intro: upFront), eligible: true),
                       "$1.99 for 3 months, then $19.99 per year. \(ProCopy.renewalTerms)")
        let quarterly = PlanOffer(plan: .monthly, displayPrice: "$9.99", price: 9.99, currencyCode: "USD", locale: us,
                                  period: PlanPeriod(value: 3, unit: .month), intro: nil)
        XCTAssertEqual(ProCopy.price(quarterly).unit, "/ 3 months")
        XCTAssertEqual(ProCopy.per(PlanPeriod(value: 3, unit: .month)), "every 3 months")
    }

    func testLockedBar() {
        XCTAssertEqual(ProCopy.lockedBar(eligible: true, intro: onUsWeek), "Start 7 days on us")
        XCTAssertEqual(ProCopy.lockedBar(eligible: false, intro: onUsWeek), "Pro ended. Tap to continue")
        XCTAssertEqual(ProCopy.lockedBar(eligible: nil, intro: nil), "Taken Pro. Tap to continue",
                       "never promises the week before StoreKit says it applies")
        XCTAssertEqual(ProCopy.lockedBar(eligible: true, intro: nil), "Taken Pro. Tap to continue")
    }

    func testSettingsStatusLines() {
        let now = at(2026, 10, 13, 9)
        func line(_ status: ProStatus?) -> String { ProCopy.statusLine(status, now: now, timeZone: london) }

        XCTAssertEqual(line(ProStatus(isPro: true, reason: .founding, checkedAt: now)), "Founding member \u{00B7} Pro for life")
        XCTAssertEqual(line(ProStatus(isPro: true, reason: .lifetime, checkedAt: now)), "Pro lifetime")
        XCTAssertEqual(line(ProStatus(isPro: true, reason: .yearly, checkedAt: now, expiresAt: at(2027, 10, 12, 9), willRenew: true)),
                       "Pro yearly \u{00B7} renews 12 Oct 2027")
        XCTAssertEqual(line(ProStatus(isPro: true, reason: .yearly, checkedAt: now, expiresAt: at(2027, 10, 12, 9), willRenew: false)),
                       "Pro yearly \u{00B7} ends 12 Oct 2027")
        XCTAssertEqual(line(ProStatus(isPro: true, reason: .monthly, checkedAt: now, expiresAt: at(2026, 11, 13, 9))),
                       "Pro monthly \u{00B7} renews 13 Nov 2026")
        XCTAssertEqual(line(ProStatus(isPro: true, reason: .trial, checkedAt: now, expiresAt: at(2026, 10, 19, 9), willRenew: true)),
                       "Trial \u{00B7} ends 19 Oct")
        XCTAssertEqual(line(ProStatus(isPro: true, reason: .monthly, checkedAt: now, expiresAt: at(2026, 10, 20, 9),
                                      willRenew: true, billingIssue: true)),
                       "Pro monthly \u{00B7} billing issue")
        XCTAssertEqual(line(.notPro(checkedAt: now)), "Not active")
        XCTAssertEqual(line(nil), "Not active")
        XCTAssertEqual(line(ProStatus(isPro: true, reason: .monthly, checkedAt: now, expiresAt: at(2026, 10, 12, 9),
                                      willRenew: false)),
                       "Not active", "an ended plan is not Pro")
        XCTAssertEqual(line(ProStatus(isPro: true, reason: .monthly, checkedAt: now, expiresAt: at(2026, 10, 12, 9),
                                      willRenew: true)),
                       "Pro monthly \u{00B7} renewing", "the period ended and the renewal has not shown yet")
        XCTAssertEqual(line(ProStatus(isPro: true, reason: .trial, checkedAt: now, expiresAt: at(2026, 10, 13, 8),
                                      willRenew: true)),
                       "Trial \u{00B7} renewing")
        XCTAssertEqual(line(ProStatus(isPro: true, reason: .yearly, checkedAt: now, expiresAt: at(2026, 10, 1, 9),
                                      willRenew: true)),
                       "Not active", "a renewal that never came, once the margin is over")
    }

    func testThePaywallSellsOnlyWhatProUnlocks() {
        // The log, the history grid, the day sheet and CSV export stay open without Pro: no bullet may sell them.
        XCTAssertEqual(ProCopy.features.count, 4)
        XCTAssertEqual(ProCopy.features.last, "Voice to-dos", "voice to-dos need Pro after the first note")
        for line in ProCopy.features {
            XCTAssertNil(line.range(of: "history", options: .caseInsensitive), line)
            XCTAssertNil(line.range(of: "csv", options: .caseInsensitive), line)
            XCTAssertNil(line.range(of: "export", options: .caseInsensitive), line)
        }
        XCTAssertTrue(ProCopy.features.contains { $0.contains("nudge") }, "the nudge is a Pro feature, so the paywall says so")
        XCTAssertEqual(ProPlan.allCases.map(\.title), ["Yearly", "Monthly", "Lifetime"])
    }

    func testRestoreLinesAreTrueForEveryone() {
        // Said to someone who never bought and to a subscriber whose plan ended: neither has anything active.
        XCTAssertEqual(ProCopy.nothingToRestore, "No active Taken Pro on this Apple Account.")
        XCTAssertNil(ProCopy.nothingToRestore.range(of: "yet"))
        XCTAssertEqual(ProCopy.restored, "Restored. Taken Pro is on.")
    }

    func testEveryLineKeepsTheCopyRules() {
        let now = at(2026, 10, 13, 9)
        var lines: [String] = [ProCopy.headline, ProCopy.subline, ProCopy.lockedDialog, ProCopy.renewalTerms,
                               ProCopy.lifetimeTerms, ProCopy.nudgeLocked, ProCopy.restored, ProCopy.nothingToRestore,
                               ProCopy.renewingNextToProForGood] + ProCopy.features
        let offers = [yearly(intro: onUsWeek), yearly(), monthly, lifetime]
        for offer in offers {
            for eligible in [true, false] {
                lines.append(ProCopy.cta(offer, eligible: eligible))
                lines.append(ProCopy.terms(offer, eligible: eligible))
            }
            lines.append(ProCopy.price(offer).amount + " " + ProCopy.price(offer).unit)
            lines.append(ProCopy.monthlyEquivalent(offer) ?? "")
        }
        for eligible in [true, false, nil] as [Bool?] {
            lines.append(ProCopy.lockedBar(eligible: eligible, intro: onUsWeek))
        }
        for reason in [ProReason.none, .trial, .yearly, .monthly, .lifetime, .founding] {
            lines.append(ProCopy.statusLine(ProStatus(isPro: reason != ProReason.none, reason: reason, checkedAt: now,
                                                      expiresAt: at(2027, 1, 1, 0)), now: now, timeZone: london))
        }
        for text in lines {
            XCTAssertNil(text.range(of: "free", options: .caseInsensitive), text)
            XCTAssertFalse(text.contains("\u{2014}") || text.contains("\u{2013}"), "no em or en dash: \(text)")
            XCTAssertFalse(text.contains("!"), text)
        }
    }
}
