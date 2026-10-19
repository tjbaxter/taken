import Foundation

/// One catalog name that matches what is typed in the Add sheet's field.
struct Suggestion: Identifiable, Hashable, Sendable {
    let entry: CatalogEntry
    /// The other name that matched (a brand, a UK name), shown faint after the name; nil when the name itself matched.
    let alias: String?
    /// 0 exact, 1 starts with what is typed, 2 every typed word starts a word, 3 within the typo budget.
    let tier: Int
    /// Typos for ranking: a first-letter typo counts twice, a known misspelling once.
    let typos: Int
    /// Already in the stack: shown faint with a check, and cannot be picked again.
    let owned: Bool
    var id: String { entry.name }
}

/// A row under the field: a suggestion, or what was typed, added as it is.
enum SuggestRow: Identifiable, Hashable, Sendable {
    case match(Suggestion)
    case literal(String, owned: Bool)

    /// The name a tap adds.
    var name: String {
        switch self {
        case .match(let suggestion): return suggestion.entry.name
        case .literal(let text, _): return text
        }
    }

    var isEnabled: Bool {
        switch self {
        case .match(let suggestion): return !suggestion.owned
        case .literal(_, let owned): return !owned
        }
    }

    var id: String {
        switch self {
        case .match(let suggestion): return "match-" + suggestion.entry.name
        case .literal(let text, _): return "literal-" + text
        }
    }
}

/// Type-ahead for the Add sheet, so nobody has to spell turmeric: catalog names ranked against what is typed, with the
/// typo tolerance search engines document as their defaults (Algolia: no typo under 4 letters, 1 from 4, 2 from 8, a
/// first-letter typo ranked as two; Meilisearch: a swap of two neighbouring letters is one typo). Pure and on the
/// phone: no phonetics, no model, no lookup anywhere.
enum Suggest {
    /// Text folded for matching: any case, accents and widths, apostrophes dropped (Lion's is lions), and everything
    /// else that is not a letter or digit a word break. `compact` is the words run together, so omega3 finds Omega-3.
    struct Folded: Hashable, Sendable {
        let words: [String]
        let compact: String
        let letters: [Character]

        init(_ text: String) {
            let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            var words: [String] = []
            var word = ""
            for c in folded {
                if c == "'" || c == "\u{2019}" { continue }
                if c.isLetter || c.isNumber {
                    word.append(c)
                } else if !word.isEmpty {
                    words.append(word)
                    word = ""
                }
            }
            if !word.isEmpty { words.append(word) }
            self.words = words
            self.compact = words.joined()
            self.letters = Array(compact)
        }
    }

    /// A catalog entry's names, folded once.
    struct Key: Sendable {
        enum Kind: Int, Sendable { case name, alias, misspelling }
        let entry: Int
        let kind: Kind
        let text: String
        let folded: Folded
    }

    /// The catalog ready to search: every name, alias and misspelling folded up front, so a keystroke folds only
    /// what was typed.
    struct Index: Sendable {
        let entries: [CatalogEntry]
        let keys: [Key]
        let names: Set<String>

        init(_ entries: [CatalogEntry]) {
            self.entries = entries
            var keys: [Key] = []
            for (index, entry) in entries.enumerated() {
                keys.append(Key(entry: index, kind: .name, text: entry.name, folded: Folded(entry.name)))
                for alias in entry.aliases {
                    keys.append(Key(entry: index, kind: .alias, text: alias, folded: Folded(alias)))
                }
                for misspelling in entry.misspellings {
                    keys.append(Key(entry: index, kind: .misspelling, text: misspelling, folded: Folded(misspelling)))
                }
            }
            self.keys = keys
            self.names = Set(entries.map { Catalog.lookupKey($0.name) })
        }

        static let catalog = Index(Catalog.entries)
    }

    /// Typos allowed for a query of this many letters and digits: none up to 3, 1 from 4, 2 from 8 (Algolia's defaults).
    static func typoBudget(_ length: Int) -> Int {
        length >= 8 ? 2 : (length >= 4 ? 1 : 0)
    }

    /// The best `limit` matches for what is typed, best first. `owned` holds `Catalog.lookupKey` of each stack name.
    /// Ties break on tier, then typos, then chips first, then weight, then a name match before an alias, then the
    /// shorter name, then alphabetical.
    static func rank(_ query: String, in index: Index = .catalog, owned: Set<String> = [], limit: Int = 4)
        -> [Suggestion] {
        let typed = Folded(query)
        guard !typed.letters.isEmpty, limit > 0 else { return [] }
        let budget = typoBudget(typed.letters.count)

        struct Best {
            var tier: Int
            var typos: Int
            var kind: Key.Kind
            var alias: String?
            var nameMatched: Bool
        }
        var best: [Int: Best] = [:]
        for key in index.keys {
            guard let found = match(typed, key.folded, budget: budget) else { continue }
            var tier = found.tier
            var typos = found.typos
            // A known misspelling is a typo match by definition, whatever its length.
            if key.kind == .misspelling {
                tier = 3
                typos += 1
            }
            let nameMatched = key.kind == .name && tier < 3
            if var current = best[key.entry] {
                current.nameMatched = current.nameMatched || nameMatched
                if (tier, typos, key.kind.rawValue) < (current.tier, current.typos, current.kind.rawValue) {
                    current.tier = tier
                    current.typos = typos
                    current.kind = key.kind
                    current.alias = key.kind == .alias ? key.text : nil
                }
                best[key.entry] = current
            } else {
                best[key.entry] = Best(tier: tier, typos: typos, kind: key.kind,
                                       alias: key.kind == .alias ? key.text : nil, nameMatched: nameMatched)
            }
        }

        let ordered = best.sorted { a, b in
            let x = index.entries[a.key]
            let y = index.entries[b.key]
            if a.value.tier != b.value.tier { return a.value.tier < b.value.tier }
            if a.value.typos != b.value.typos { return a.value.typos < b.value.typos }
            if x.isChip != y.isChip { return x.isChip }
            if x.weight != y.weight { return x.weight > y.weight }
            let aliasA = a.value.kind == .alias
            let aliasB = b.value.kind == .alias
            if aliasA != aliasB { return !aliasA }
            if x.name.count != y.name.count { return x.name.count < y.name.count }
            return x.name < y.name
        }
        return ordered.prefix(limit).map { position, found in
            let entry = index.entries[position]
            // "Vitamin D3 · Vitamin D" says nothing: the alias shows only when the name itself did not match.
            let alias = found.nameMatched ? nil : found.alias
            return Suggestion(entry: entry, alias: alias, tier: found.tier, typos: found.typos,
                              owned: owned.contains(Catalog.lookupKey(entry.name)))
        }
    }

    /// How one folded name matches what is typed, if it does: its tier and typos.
    static func match(_ typed: Folded, _ key: Folded, budget: Int) -> (tier: Int, typos: Int)? {
        if key.compact == typed.compact { return (0, 0) }
        if key.compact.hasPrefix(typed.compact) { return (1, 0) }
        if !typed.words.isEmpty,
           typed.words.allSatisfy({ word in key.words.contains { $0.hasPrefix(word) } }) {
            return (2, 0)
        }
        guard budget > 0, !key.letters.isEmpty, key.letters.count + budget >= typed.letters.count else { return nil }
        let distance = prefixDistance(typed.letters, key.letters, limit: budget)
        guard distance <= budget else { return nil }
        // A typo on the first letter counts once against the budget and twice for ranking (Algolia).
        let firstLetter = typed.letters.first != key.letters.first ? 1 : 0
        return (3, distance + firstLetter)
    }

    /// The fewest edits (insert, delete, change, or swap two neighbours: optimal string alignment) that turn `typed`
    /// into some prefix of `key`, or `limit + 1` once it cannot be `limit` or fewer.
    static func prefixDistance(_ typed: [Character], _ key: [Character], limit: Int) -> Int {
        let m = typed.count
        let n = min(key.count, m + limit)
        guard m > 0 else { return 0 }
        guard n > 0 else { return m }
        var before = [Int](repeating: 0, count: n + 1)
        var previous = Array(0...n)
        var current = [Int](repeating: 0, count: n + 1)
        var previousMin = 0
        for i in 1...m {
            current[0] = i
            var rowMin = i
            for j in 1...n {
                let cost = typed[i - 1] == key[j - 1] ? 0 : 1
                var value = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, typed[i - 1] == key[j - 2], typed[i - 2] == key[j - 1] {
                    value = min(value, before[j - 2] + 1)
                }
                current[j] = value
                rowMin = min(rowMin, value)
            }
            // No later row can come back under the limit once this row and the one before are both past it.
            if rowMin > limit && previousMin >= limit { return limit + 1 }
            previousMin = rowMin
            (before, previous, current) = (previous, current, before)
        }
        return min(previous.min() ?? m, limit + 1)
    }

    /// What was typed, as its own row: left out only when it is empty or exactly a catalog name, whose row it then is.
    static func literal(for query: String, in index: Index = .catalog) -> String? {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !index.names.contains(Catalog.lookupKey(text)) else { return nil }
        return text
    }

    /// The rows that fit: the matches, then the typed text last. With room for one row only, the best match.
    static func rows(_ matches: [Suggestion], literal: String?, owned: Set<String> = [], capacity: Int) -> [SuggestRow] {
        guard capacity > 0 else { return [] }
        let found = matches.map(SuggestRow.match)
        guard let literal else { return Array(found.prefix(capacity)) }
        let typed = SuggestRow.literal(literal, owned: owned.contains(Catalog.lookupKey(literal)))
        if capacity == 1 { return [found.first ?? typed] }
        return Array(found.prefix(capacity - 1)) + [typed]
    }

    /// What Return picks: the first row that can be picked. It never rewrites the field; it adds a row.
    static func firstPick(_ rows: [SuggestRow]) -> SuggestRow? {
        rows.first(where: \.isEnabled)
    }

    /// A piece of a suggested name: what was typed (muted) or the rest (emphasised).
    struct Segment: Hashable, Sendable {
        let text: String
        let typed: Bool
    }

    /// The name split into what was typed and the rest, so the completion stands out (Baymard): "Tur|meric",
    /// "Vit|amin |D|3". A typo or alias match has no typed part.
    static func segments(of name: String, typed query: String) -> [Segment] {
        let whole = [Segment(text: name, typed: false)]
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return whole }
        let options: String.CompareOptions = [.anchored, .caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        if let range = name.range(of: typed, options: options) {
            return split(name, marking: [range])
        }
        // Word by word: each typed word marks the start of a different word of the name.
        let typedWords = typed.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
        var free = wordRanges(of: name)
        var marked: [Range<String.Index>] = []
        for word in typedWords {
            guard let slot = free.firstIndex(where: { name.range(of: word, options: options, range: $0) != nil }),
                  let range = name.range(of: word, options: options, range: free[slot]) else { return whole }
            marked.append(range)
            free.remove(at: slot)
        }
        return split(name, marking: marked.sorted { $0.lowerBound < $1.lowerBound })
    }

    /// Runs of letters, digits and apostrophes.
    private static func wordRanges(of text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        for index in text.indices {
            let c = text[index]
            let inWord = c.isLetter || c.isNumber || c == "'" || c == "\u{2019}"
            if inWord, start == nil { start = index }
            if !inWord, let begun = start {
                ranges.append(begun..<index)
                start = nil
            }
        }
        if let begun = start { ranges.append(begun..<text.endIndex) }
        return ranges
    }

    private static func split(_ text: String, marking ranges: [Range<String.Index>]) -> [Segment] {
        var segments: [Segment] = []
        var cursor = text.startIndex
        for range in ranges where range.lowerBound >= cursor {
            if cursor < range.lowerBound { segments.append(Segment(text: String(text[cursor..<range.lowerBound]), typed: false)) }
            if !range.isEmpty { segments.append(Segment(text: String(text[range]), typed: true)) }
            cursor = range.upperBound
        }
        if cursor < text.endIndex { segments.append(Segment(text: String(text[cursor...]), typed: false)) }
        return segments
    }
}
