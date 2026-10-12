import Foundation

/// A quick-pick chip in the Add sheet.
struct Preset: Identifiable, Hashable, Sendable {
    let name: String
    let code: String
    var id: String { name }
}

enum Catalog {
    static let presets: [Preset] = [
        Preset(name: "Vitamin D3", code: "VD3"),
        Preset(name: "Fish Oil", code: "FSH"),
        Preset(name: "Omega-3", code: "OM3"),
        Preset(name: "Magnesium", code: "MAG"),
        Preset(name: "Creatine", code: "CRE"),
        Preset(name: "Multivitamin", code: "MLT"),
        Preset(name: "Zinc", code: "ZNC"),
        Preset(name: "Vitamin C", code: "VTC"),
        Preset(name: "Vitamin B12", code: "B12"),
        Preset(name: "Iron", code: "IRN"),
        Preset(name: "Probiotic", code: "PRB"),
        Preset(name: "Ashwagandha", code: "ASH"),
        Preset(name: "Melatonin", code: "MEL"),
        Preset(name: "Collagen", code: "COL"),
        Preset(name: "Finasteride", code: "FIN"),
        Preset(name: "Minoxidil", code: "MIN"),
        Preset(name: "Metformin", code: "MET"),
        Preset(name: "Electrolytes", code: "ELC"),
        Preset(name: "Vitamin K2", code: "VK2"),
        Preset(name: "Folate", code: "FOL"),
        Preset(name: "Calcium", code: "CAL"),
        Preset(name: "Turmeric", code: "TUR"),
        Preset(name: "CoQ10", code: "Q10"),
        Preset(name: "L-Theanine", code: "LTH"),
    ]

    private static func isCodeCharacter(_ c: Character) -> Bool {
        ("A"..."Z").contains(c) || ("0"..."9").contains(c)
    }

    /// Code tags are 1 to 4 characters, A-Z and 0-9.
    static func sanitizeCode(_ raw: String) -> String {
        String(raw.uppercased().filter(isCodeCharacter).prefix(4))
    }

    /// A short code for any name: the preset's code, else initials plus consonants.
    static func code(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let preset = presets.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return preset.code
        }
        let words = trimmed
            .uppercased()
            .replacingOccurrences(of: "'", with: "")
            .split(whereSeparator: { !isCodeCharacter($0) })
            .map(String.init)
        guard let first = words.first, let firstLetter = first.first else { return "ITM" }

        var result = String(firstLetter)
        if words.count >= 2 {
            for word in words.dropFirst().prefix(2) {
                if let c = word.first { result.append(c) }
            }
            if result.count < 3, let last = words.last {
                for c in last.dropFirst() where result.count < 3 && !"AEIOU".contains(c) { result.append(c) }
            }
        } else {
            let rest = Array(first.dropFirst())
            for c in rest where result.count < 3 && !"AEIOU".contains(c) { result.append(c) }
            for c in rest where result.count < 3 && "AEIOU".contains(c) { result.append(c) }
        }
        let code = sanitizeCode(result)
        return code.isEmpty ? "ITM" : code
    }
}
