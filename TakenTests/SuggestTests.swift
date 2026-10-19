import XCTest
@testable import Taken

/// Type-ahead in the Add sheet (Shared/Suggest.swift): spelling-tolerant matches from the bundled list, the typed text
/// as its own row, and rows that fit the space.
final class SuggestTests: XCTestCase {

    private func top(_ query: String) -> String? {
        Suggest.rank(query).first?.entry.name
    }

    func testTumAndTumericPutTurmericFirst() {
        XCTAssertEqual(top("tum"), "Turmeric", "three letters allow no typo, so the known misspelling finds it")
        XCTAssertEqual(top("tumeric"), "Turmeric")
        XCTAssertEqual(top("Tur"), "Turmeric")
        XCTAssertNil(Suggest.rank("tumeric").first?.alias, "a misspelling is never shown")
    }

    func testTyposWordsAndOtherNamesFindTheRightEntry() {
        XCTAssertEqual(top("ashwaganda"), "Ashwagandha")
        XCTAssertEqual(top("ashwagnadha"), "Ashwagandha", "a swap of two letters is one typo")
        XCTAssertEqual(top("vit d"), "Vitamin D3")
        XCTAssertEqual(top("lions mane"), "Lion's Mane")
        XCTAssertEqual(top("lion"), "Lion's Mane")
        XCTAssertEqual(top("coq10"), "CoQ10")
        XCTAssertEqual(top("omega3"), "Omega-3")
        XCTAssertEqual(top("b12"), "Vitamin B12")
        XCTAssertEqual(top("magnisium"), "Magnesium")
        XCTAssertEqual(top("glucosomine"), "Glucosamine")
        XCTAssertEqual(top("Mélatonin"), "Melatonin", "accents fold")
        XCTAssertEqual(top("theanine"), "L-Theanine", "a later word matches too")

        let ozem = Suggest.rank("ozem").first
        XCTAssertEqual(ozem?.entry.name, "Semaglutide")
        XCTAssertEqual(ozem?.alias, "Ozempic", "the brand shows faint after the generic name")
        XCTAssertEqual(Suggest.rank("mounj").first?.entry.name, "Tirzepatide")
        XCTAssertEqual(Suggest.rank("mounj").first?.alias, "Mounjaro")
        XCTAssertEqual(top("paracetamol"), "Acetaminophen")
        XCTAssertNil(Suggest.rank("vitamin d").first?.alias, "no alias hint when the name itself matches")
    }

    func testTheTypoBudgetGrowsWithLength() {
        XCTAssertEqual((1...9).map(Suggest.typoBudget), [0, 0, 0, 1, 1, 1, 1, 2, 2])
        XCTAssertEqual(Suggest.prefixDistance(Array("teh"), Array("the"), limit: 2), 1, "a swap is one typo")
        XCTAssertEqual(Suggest.prefixDistance(Array("magnesim"), Array("magnesiumglycinate"), limit: 1), 1,
                       "against any prefix of the name")
        XCTAssertEqual(Suggest.prefixDistance(Array("zzqx"), Array("zinc"), limit: 1), 2, "past the limit")

        let zinx = Suggest.match(Suggest.Folded("zinx"), Suggest.Folded("Zinc"), budget: 1)
        XCTAssertEqual(zinx?.tier, 3)
        XCTAssertEqual(zinx?.typos, 1)
        let xinc = Suggest.match(Suggest.Folded("xinc"), Suggest.Folded("Zinc"), budget: 1)
        XCTAssertEqual(xinc?.typos, 2, "a first-letter typo counts once against the budget and twice for ranking")
        XCTAssertNil(Suggest.match(Suggest.Folded("zic"), Suggest.Folded("Zinc"), budget: Suggest.typoBudget(3)),
                     "no typo under four letters")
    }

    func testChipsAndWeightBreakTies() {
        XCTAssertEqual(Suggest.rank("vitamin").map(\.entry.name), ["Vitamin D3", "Vitamin C", "Vitamin B12", "Vitamin K2"])
        XCTAssertEqual(Suggest.rank("magnesium").first?.entry.name, "Magnesium")
        XCTAssertEqual(Suggest.rank("magnesium").count, 4, "up to four matches")
        XCTAssertEqual(Suggest.rank("oil").first?.entry.name, "Fish Oil")
    }

    func testNothingMatchingLeavesOnlyTheTypedRow() {
        XCTAssertTrue(Suggest.rank("zzqx").isEmpty)
        let rows = Suggest.rows(Suggest.rank("zzqx"), literal: Suggest.literal(for: "zzqx"), capacity: 5)
        XCTAssertEqual(rows, [.literal("zzqx", owned: false)])
        XCTAssertNil(Suggest.literal(for: "turmeric"), "an exact catalog name is its own row")
        XCTAssertNil(Suggest.literal(for: "   "))
        XCTAssertEqual(Suggest.literal(for: " Ozempic "), "Ozempic", "a brand typed in full can be added as it is")
        XCTAssertTrue(Suggest.rank("").isEmpty, "nothing shows while the field is empty")
        XCTAssertTrue(Suggest.rank(" - ").isEmpty)
    }

    func testOwnedItemsShowFaintAndCannotBePicked() {
        let owned: Set<String> = [Catalog.lookupKey("Zinc"), Catalog.lookupKey("Grandma's Tonic")]
        let zinc = Suggest.rank("zin", owned: owned)
        XCTAssertEqual(zinc.first?.entry.name, "Zinc")
        XCTAssertEqual(zinc.first?.owned, true)
        let rows = Suggest.rows(zinc, literal: Suggest.literal(for: "zin"), owned: owned, capacity: 5)
        XCTAssertFalse(rows[0].isEnabled)
        let pick = Suggest.firstPick(rows)
        XCTAssertNotNil(pick)
        XCTAssertNotEqual(pick?.name, "Zinc", "Return skips what is already in the stack")

        let tonic = Suggest.rows([], literal: Suggest.literal(for: "grandma's tonic"), owned: owned, capacity: 5)
        XCTAssertEqual(tonic, [.literal("grandma's tonic", owned: true)])
        XCTAssertNil(Suggest.firstPick(tonic))
    }

    func testRowsFitTheSpaceWithTheTypedRowLast() {
        let matches = Suggest.rank("vitamin")
        let literal = Suggest.literal(for: "vitamin")
        XCTAssertEqual(literal, "vitamin")
        XCTAssertEqual(Suggest.rows(matches, literal: literal, capacity: 9).count, 5, "four matches and the typed row")
        let three = Suggest.rows(matches, literal: literal, capacity: 3)
        XCTAssertEqual(three.map(\.name), ["Vitamin D3", "Vitamin C", "vitamin"])
        XCTAssertEqual(Suggest.rows(matches, literal: literal, capacity: 1).map(\.name), ["Vitamin D3"])
        XCTAssertTrue(Suggest.rows(matches, literal: literal, capacity: 0).isEmpty)
        XCTAssertEqual(Suggest.firstPick(three)?.name, "Vitamin D3", "Return picks row 1")
    }

    func testWhatWasTypedIsMutedAndTheCompletionStandsOut() {
        typealias S = Suggest.Segment
        XCTAssertEqual(Suggest.segments(of: "Turmeric", typed: "tur"), [S(text: "Tur", typed: true), S(text: "meric", typed: false)])
        XCTAssertEqual(Suggest.segments(of: "Vitamin D3", typed: "vit d"),
                       [S(text: "Vit", typed: true), S(text: "amin ", typed: false), S(text: "D", typed: true),
                        S(text: "3", typed: false)])
        XCTAssertEqual(Suggest.segments(of: "Fish Oil", typed: "oil"), [S(text: "Fish ", typed: false), S(text: "Oil", typed: true)])
        XCTAssertEqual(Suggest.segments(of: "Turmeric", typed: "tumeric"), [S(text: "Turmeric", typed: false)])
        XCTAssertEqual(Suggest.segments(of: "Turmeric", typed: ""), [S(text: "Turmeric", typed: false)])
    }

    func testNoResearchPeptideIsEverSuggested() {
        for term in ["retatrutide", "cagrisema", "bpc-157", "tb-500", "ipamorelin", "sermorelin", "semax", "epitalon"] {
            for suggestion in Suggest.rank(term) {
                XCTAssertFalse(Suggest.Folded(suggestion.entry.name).compact.contains(Suggest.Folded(term).compact), term)
            }
            XCTAssertNotNil(Suggest.literal(for: term), "\(term) can still be typed and added as it is")
        }
    }
}
