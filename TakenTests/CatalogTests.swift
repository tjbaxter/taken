import XCTest
@testable import Taken

/// The bundled name list (Shared/Catalog.swift): the chips, the type-ahead names, their codes, and what is left out.
final class CatalogTests: XCTestCase {

    func testTheListIsAboutThreeHundredIngredientLevelNames() {
        XCTAssertTrue((250...300).contains(Catalog.entries.count), "\(Catalog.entries.count) names")
        for entry in Catalog.entries {
            XCTAssertEqual(entry.name, entry.name.trimmingCharacters(in: .whitespacesAndNewlines), entry.name)
            XCTAssertFalse(entry.name.contains("  "), entry.name)
            let first = entry.name.first.map { $0.isUppercase || $0.isNumber } ?? false
            XCTAssertTrue(first, "title case: \(entry.name)")
        }
    }

    func testNamesAndCodesAreUniqueAndChipCodesAreThreeCharacters() {
        let names = Catalog.entries.map { Catalog.lookupKey($0.name) }
        XCTAssertEqual(Set(names).count, names.count, "names are unique in any case")
        let codes = Catalog.entries.map(\.code)
        XCTAssertEqual(Set(codes).count, codes.count,
                       "codes are unique: \(Dictionary(grouping: codes, by: { $0 }).filter { $0.value.count > 1 }.keys)")
        for entry in Catalog.entries {
            XCTAssertEqual(Catalog.sanitizeCode(entry.code), entry.code, "\(entry.name): A-Z and 0-9")
            XCTAssertTrue((1...4).contains(entry.code.count), entry.name)
        }
        for preset in Catalog.presets {
            XCTAssertEqual(preset.code.count, 3, preset.name)
        }
    }

    func testTheChipGridGainsBirthControlAndTheTwoGLP1s() {
        let names = Catalog.presets.map(\.name)
        XCTAssertEqual(names.count, 27, "27 chips plus + CUSTOM")
        XCTAssertEqual(Array(names[14...20]),
                       ["Finasteride", "Minoxidil", "Birth Control", "Metformin", "Semaglutide", "Tirzepatide",
                        "Electrolytes"])
        XCTAssertEqual(Catalog.presets, Catalog.entries.filter(\.isChip).map { Preset(name: $0.name, code: $0.code) },
                       "the grid is the chip entries, in order")
        // SPEC 3.3's chips are all still there.
        for name in ["Vitamin D3", "Fish Oil", "Omega-3", "Magnesium", "Creatine", "Multivitamin", "Zinc", "Vitamin C",
                     "Vitamin B12", "Iron", "Probiotic", "Ashwagandha", "Melatonin", "Collagen", "Finasteride",
                     "Minoxidil", "Metformin", "Electrolytes", "Vitamin K2", "Folate", "Calcium", "Turmeric", "CoQ10",
                     "L-Theanine"] {
            XCTAssertTrue(names.contains(name), name)
        }
        XCTAssertEqual(Catalog.code(for: "Semaglutide"), "SEM")
        XCTAssertEqual(Catalog.code(for: "Tirzepatide"), "TRZ")
        XCTAssertEqual(Catalog.code(for: "Birth control"), "BCP")
        XCTAssertEqual(Catalog.code(for: "Vitamin D3"), "VD3")
    }

    func testOnlyTheInjectableGLP1sStartWeekly() {
        XCTAssertEqual(Catalog.entries.filter(\.weekly).map(\.name), ["Semaglutide", "Tirzepatide"])
    }

    func testAliasesFindTheirEntryAndBrandsAreNeverChipLabels() {
        XCTAssertEqual(Catalog.entry(matching: "Mounjaro")?.name, "Tirzepatide")
        XCTAssertEqual(Catalog.entry(matching: " ozempic ")?.name, "Semaglutide")
        XCTAssertEqual(Catalog.entry(matching: "Paracetamol")?.name, "Acetaminophen")
        XCTAssertEqual(Catalog.entry(matching: "tumeric")?.name, "Turmeric", "a misspelling finds it too")
        XCTAssertNil(Catalog.entry(named: "Mounjaro"), "a brand is never a name")
        XCTAssertEqual(Catalog.code(for: "Mounjaro"), "TRZ")
        XCTAssertEqual(Catalog.code(for: "Zepbound"), "TRZ")
        XCTAssertEqual(Catalog.code(for: "Wegovy"), "SEM")

        let names = Set(Catalog.entries.map { Catalog.lookupKey($0.name) })
        var others: [String: String] = [:]
        for entry in Catalog.entries {
            for other in entry.aliases + entry.misspellings {
                let key = Catalog.lookupKey(other)
                XCTAssertFalse(names.contains(key), "\(other) is another entry's name")
                XCTAssertNil(others[key], "\(other) is an alias of \(others[key] ?? "") and \(entry.name)")
                others[key] = entry.name
            }
        }
        let brands = ["ozempic", "wegovy", "rybelsus", "mounjaro", "zepbound", "propecia", "rogaine", "glucophage"]
        for preset in Catalog.presets {
            XCTAssertFalse(brands.contains(Catalog.lookupKey(preset.name)), preset.name)
        }
    }

    /// None is approved: the FDA says retatrutide and cagrilintide cannot be compounded and warns sellers labelling
    /// peptides "for research purposes". Typing one still works through the + Add row.
    func testNoResearchPeptideOrUnapprovedGLP1IsListed() {
        let banned = ["retatrutide", "cagrisema", "cagrilintide", "bpc", "tb500", "ghkcu", "cjc1295", "ipamorelin",
                      "motsc", "semax", "epitalon", "epithalon", "sermorelin", "peptide"]
        for entry in Catalog.entries {
            for text in [entry.name] + entry.aliases + entry.misspellings {
                // Letters and digits only, so "BPC-157" and "TB 500" are caught however they are written.
                let folded = String(Catalog.lookupKey(text).filter { $0.isLetter || $0.isNumber })
                for term in banned {
                    XCTAssertFalse(folded.contains(term), "\(text) in \(entry.name)")
                }
            }
        }
    }

    func testEveryNameKeepsTheCopyRules() {
        for entry in Catalog.entries {
            for text in [entry.name] + entry.aliases {
                XCTAssertNil(text.range(of: "free", options: .caseInsensitive), text)
                XCTAssertFalse(text.contains("\u{2014}") || text.contains("\u{2013}"), "no em or en dash: \(text)")
                XCTAssertFalse(text.contains("!"), text)
            }
        }
    }

    func testCodesForNamesTheCatalogDoesNotKnowAreDerivedAsBefore() {
        XCTAssertEqual(Catalog.code(for: "Lion's Mane"), "LMN")
        XCTAssertEqual(Catalog.code(for: "Berberine"), "BRB")
        XCTAssertEqual(Catalog.code(for: "Grandma's Tonic"), "GTN")
        XCTAssertEqual(Catalog.code(for: "   "), "ITM")
        XCTAssertEqual(Catalog.derivedCode(for: "Magnesium Glycinate"), "MGL", "derived, but the entry has its own")
        XCTAssertEqual(Catalog.code(for: "Magnesium Glycinate"), "MGG")
    }
}
