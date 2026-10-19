import Foundation

// The names the on-device recogniser should expect, so "Ashwagandha" or the person's own "Reach" floss is heard as said:
// the items in this person's stack first, then the Add sheet's chips and the rest of the catalog. Apple's guidance for
// contextual strings: short phrases, one or two words where possible, and no more than 100 in all. Read once when
// listening starts, never stored or sent anywhere, and the recogniser works the same without them.

enum TranscriptionVocabulary {
    /// Apple: "Limit the total number of phrases to no more than 100."
    static let limit = 100
    /// Chips and catalog names together, so the person's own names always fit.
    static let catalogLimit = 80
    /// Longer phrases are "less likely to be recognized", so they are left out.
    static let maxWords = 4

    /// The phrases to hand the recogniser: the stack's names, then up to `catalogLimit` chip and catalog names, each
    /// once (ignoring case), at most `maxWords` words each and `limit` in all.
    static func strings(stack: [String], chips: [String], catalog: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        func add(_ name: String) -> Bool {
            let words = name.split(whereSeparator: { $0.isWhitespace })
            guard !words.isEmpty, words.count <= maxWords, result.count < limit else { return false }
            let phrase = words.joined(separator: " ")
            guard seen.insert(phrase.lowercased()).inserted else { return false }
            result.append(phrase)
            return true
        }
        for name in stack { _ = add(name) }
        var fromCatalog = 0
        for name in chips + catalog where fromCatalog < catalogLimit {
            if add(name) { fromCatalog += 1 }
        }
        return result
    }

    /// This person's phrases now: the items they take (not archived, in stack order) and the chip names. Called off the
    /// main actor once the microphone is already on, so listening never waits on it.
    static func current(store: TakenStore = .shared) -> [String] {
        let items = store.load().items.filter { !$0.archived }.sorted { $0.sortIndex < $1.sortIndex }
        return strings(stack: items.map(\.name), chips: Catalog.presets.map(\.name), catalog: [])
    }
}
