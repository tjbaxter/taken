package com.tombaxter.taken.core.catalog

/** One catalog name that matches what is typed in the Add sheet's field. */
data class Suggestion(
    val entry: CatalogEntry,
    /** The other name that matched (a brand, a UK name), shown faint after the name; null when the name itself matched. */
    val alias: String?,
    /** 0 exact, 1 starts with what is typed, 2 every typed word starts a word, 3 within the typo budget. */
    val tier: Int,
    /** Typos for ranking: a first-letter typo counts twice, a known misspelling once. */
    val typos: Int,
    /** Already in the stack: shown faint with a check, and cannot be picked again. */
    val owned: Boolean,
)

/** A row under the field: a suggestion, or what was typed, added as it is. */
sealed class SuggestRow {
    data class Match(val suggestion: Suggestion) : SuggestRow()
    data class Literal(val text: String, val owned: Boolean) : SuggestRow()

    /** The name a tap adds. */
    val name: String
        get() = when (this) {
            is Match -> suggestion.entry.name
            is Literal -> text
        }

    val isEnabled: Boolean
        get() = when (this) {
            is Match -> !suggestion.owned
            is Literal -> !owned
        }

    val id: String
        get() = when (this) {
            is Match -> "match-" + suggestion.entry.name
            is Literal -> "literal-$text"
        }
}

/**
 * Type-ahead for the Add sheet, so nobody has to spell turmeric: catalog names ranked against what is typed, with the
 * typo tolerance search engines document as their defaults (Algolia: no typo under 4 letters, 1 from 4, 2 from 8, a
 * first-letter typo ranked as two; Meilisearch: a swap of two neighbouring letters is one typo). Pure and on the phone.
 * Ported from Shared/Suggest.swift.
 */
object Suggest {
    /**
     * Text folded for matching: any case, accents and widths, apostrophes dropped (Lion's is lions), and everything else
     * that is not a letter or digit a word break. `compact` is the words run together, so omega3 finds Omega-3.
     */
    class Folded(text: String) {
        val words: List<String>
        val compact: String
        val letters: CharArray

        init {
            val folded = Catalog.fold(text)
            val found = ArrayList<String>()
            val word = StringBuilder()
            for (c in folded) {
                if (c == '\'' || c == '’') continue
                if (c.isLetterOrDigit()) {
                    word.append(c)
                } else if (word.isNotEmpty()) {
                    found.add(word.toString())
                    word.clear()
                }
            }
            if (word.isNotEmpty()) found.add(word.toString())
            words = found
            compact = found.joinToString("")
            letters = compact.toCharArray()
        }
    }

    /** A catalog entry's names, folded once. */
    class Key(val entry: Int, val kind: Kind, val text: String, val folded: Folded) {
        enum class Kind { NAME, ALIAS, MISSPELLING }
    }

    /** The catalog ready to search: every name, alias and misspelling folded up front. */
    class Index(val entries: List<CatalogEntry>) {
        val keys: List<Key>
        val names: Set<String> = entries.map { Catalog.lookupKey(it.name) }.toSet()

        init {
            val all = ArrayList<Key>()
            entries.forEachIndexed { index, entry ->
                all.add(Key(index, Key.Kind.NAME, entry.name, Folded(entry.name)))
                for (alias in entry.aliases) all.add(Key(index, Key.Kind.ALIAS, alias, Folded(alias)))
                for (misspelling in entry.misspellings) all.add(Key(index, Key.Kind.MISSPELLING, misspelling, Folded(misspelling)))
            }
            keys = all
        }

        companion object {
            val catalog: Index by lazy { Index(Catalog.entries) }
        }
    }

    /** Typos allowed for a query of this many letters and digits: none up to 3, 1 from 4, 2 from 8 (Algolia's defaults). */
    fun typoBudget(length: Int): Int = if (length >= 8) 2 else if (length >= 4) 1 else 0

    private class Best(var tier: Int, var typos: Int, var kind: Key.Kind, var alias: String?, var nameMatched: Boolean)

    /**
     * The best `limit` matches for what is typed, best first. `owned` holds `Catalog.lookupKey` of each stack name. Ties
     * break on tier, then typos, then chips first, then weight, then a name match before an alias, then the shorter name,
     * then alphabetical.
     */
    fun rank(query: String, index: Index = Index.catalog, owned: Set<String> = emptySet(), limit: Int = 4): List<Suggestion> {
        val typed = Folded(query)
        if (typed.letters.isEmpty() || limit <= 0) return emptyList()
        val budget = typoBudget(typed.letters.size)

        val best = LinkedHashMap<Int, Best>()
        for (key in index.keys) {
            val found = match(typed, key.folded, budget) ?: continue
            var tier = found.first
            var typos = found.second
            // A known misspelling is a typo match by definition, whatever its length.
            if (key.kind == Key.Kind.MISSPELLING) {
                tier = 3
                typos += 1
            }
            val nameMatched = key.kind == Key.Kind.NAME && tier < 3
            val current = best[key.entry]
            if (current != null) {
                current.nameMatched = current.nameMatched || nameMatched
                val better = compareValuesBy(
                    Triple(tier, typos, key.kind.ordinal), Triple(current.tier, current.typos, current.kind.ordinal),
                    { it.first }, { it.second }, { it.third },
                ) < 0
                if (better) {
                    current.tier = tier
                    current.typos = typos
                    current.kind = key.kind
                    current.alias = if (key.kind == Key.Kind.ALIAS) key.text else null
                }
            } else {
                best[key.entry] = Best(tier, typos, key.kind, if (key.kind == Key.Kind.ALIAS) key.text else null, nameMatched)
            }
        }

        val ordered = best.entries.sortedWith { a, b ->
            val x = index.entries[a.key]
            val y = index.entries[b.key]
            when {
                a.value.tier != b.value.tier -> a.value.tier.compareTo(b.value.tier)
                a.value.typos != b.value.typos -> a.value.typos.compareTo(b.value.typos)
                x.isChip != y.isChip -> if (x.isChip) -1 else 1
                x.weight != y.weight -> y.weight.compareTo(x.weight)
                (a.value.kind == Key.Kind.ALIAS) != (b.value.kind == Key.Kind.ALIAS) ->
                    if (a.value.kind != Key.Kind.ALIAS) -1 else 1
                x.name.length != y.name.length -> x.name.length.compareTo(y.name.length)
                else -> x.name.compareTo(y.name)
            }
        }
        return ordered.take(limit).map { (position, found) ->
            val entry = index.entries[position]
            // "Vitamin D3 · Vitamin D" says nothing: the alias shows only when the name itself did not match.
            val alias = if (found.nameMatched) null else found.alias
            Suggestion(entry, alias, found.tier, found.typos, owned.contains(Catalog.lookupKey(entry.name)))
        }
    }

    /** How one folded name matches what is typed, if it does: its tier and typos. */
    fun match(typed: Folded, key: Folded, budget: Int): Pair<Int, Int>? {
        if (key.compact == typed.compact) return 0 to 0
        if (key.compact.startsWith(typed.compact)) return 1 to 0
        if (typed.words.isNotEmpty() && typed.words.all { word -> key.words.any { it.startsWith(word) } }) return 2 to 0
        if (budget <= 0 || key.letters.isEmpty() || key.letters.size + budget < typed.letters.size) return null
        val distance = prefixDistance(typed.letters, key.letters, budget)
        if (distance > budget) return null
        // A typo on the first letter counts once against the budget and twice for ranking (Algolia).
        val firstLetter = if (typed.letters.firstOrNull() != key.letters.firstOrNull()) 1 else 0
        return 3 to distance + firstLetter
    }

    fun prefixDistance(typed: String, key: String, limit: Int): Int =
        prefixDistance(typed.toCharArray(), key.toCharArray(), limit)

    /**
     * The fewest edits (insert, delete, change, or swap two neighbours: optimal string alignment) that turn `typed` into
     * some prefix of `key`, or `limit + 1` once it cannot be `limit` or fewer.
     */
    fun prefixDistance(typed: CharArray, key: CharArray, limit: Int): Int {
        val m = typed.size
        val n = minOf(key.size, m + limit)
        if (m <= 0) return 0
        if (n <= 0) return m
        var before = IntArray(n + 1)
        var previous = IntArray(n + 1) { it }
        var current = IntArray(n + 1)
        var previousMin = 0
        for (i in 1..m) {
            current[0] = i
            var rowMin = i
            for (j in 1..n) {
                val cost = if (typed[i - 1] == key[j - 1]) 0 else 1
                var value = minOf(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if (i > 1 && j > 1 && typed[i - 1] == key[j - 2] && typed[i - 2] == key[j - 1]) {
                    value = minOf(value, before[j - 2] + 1)
                }
                current[j] = value
                rowMin = minOf(rowMin, value)
            }
            // No later row can come back under the limit once this row and the one before are both past it.
            if (rowMin > limit && previousMin >= limit) return limit + 1
            previousMin = rowMin
            val oldBefore = before
            before = previous
            previous = current
            current = oldBefore
        }
        return minOf(previous.minOrNull() ?: m, limit + 1)
    }

    /** What was typed, as its own row: left out only when it is empty or exactly a catalog name, whose row it then is. */
    fun literal(query: String, index: Index = Index.catalog): String? {
        val text = query.trim()
        if (text.isEmpty() || index.names.contains(Catalog.lookupKey(text))) return null
        return text
    }

    /** The rows that fit: the matches, then the typed text last. With room for one row only, the best match. */
    fun rows(matches: List<Suggestion>, literal: String?, owned: Set<String> = emptySet(), capacity: Int): List<SuggestRow> {
        if (capacity <= 0) return emptyList()
        val found = matches.map { SuggestRow.Match(it) }
        if (literal == null) return found.take(capacity)
        val typed = SuggestRow.Literal(literal, owned.contains(Catalog.lookupKey(literal)))
        if (capacity == 1) return listOf(found.firstOrNull() ?: typed)
        return found.take(capacity - 1) + typed
    }

    /** What Return picks: the first row that can be picked. It never rewrites the field; it adds a row. */
    fun firstPick(rows: List<SuggestRow>): SuggestRow? = rows.firstOrNull { it.isEnabled }

    /** A piece of a suggested name: what was typed (muted) or the rest (emphasised). */
    data class Segment(val text: String, val typed: Boolean)

    /**
     * The name split into what was typed and the rest, so the completion stands out (Baymard): "Tur|meric",
     * "Vit|amin |D|3". A typo or alias match has no typed part.
     */
    fun segments(name: String, typed: String): List<Segment> {
        val whole = listOf(Segment(name, false))
        val query = typed.trim()
        if (query.isEmpty()) return whole
        anchoredMatch(name, 0, name.length, query)?.let { end -> return split(name, listOf(0 until end)) }
        // Word by word: each typed word marks the start of a different word of the name.
        val typedWords = query.split(Regex("[^\\p{L}\\p{N}]+")).filter { it.isNotEmpty() }
        val free = wordRanges(name).toMutableList()
        val marked = ArrayList<IntRange>()
        for (word in typedWords) {
            val slot = free.indexOfFirst { anchoredMatch(name, it.first, it.last + 1, word) != null }
            if (slot < 0) return whole
            val range = free[slot]
            val end = anchoredMatch(name, range.first, range.last + 1, word) ?: return whole
            marked.add(range.first until end)
            free.removeAt(slot)
        }
        return split(name, marked.sortedBy { it.first })
    }

    /**
     * Where `needle` ends when it matches `text` from `start` (case, accent and width insensitive), within `end`; null
     * when it does not. Swift's `range(of:options: [.anchored, .caseInsensitive, .diacriticInsensitive, .widthInsensitive])`.
     */
    private fun anchoredMatch(text: String, start: Int, end: Int, needle: String): Int? {
        val target = Catalog.fold(needle)
        if (target.isEmpty()) return null
        val seen = StringBuilder()
        var index = start
        while (index < end) {
            seen.append(Catalog.fold(text[index].toString()))
            index += 1
            if (!target.startsWith(seen)) return null
            if (seen.length == target.length) return index
        }
        return null
    }

    /** Runs of letters, digits and apostrophes. */
    private fun wordRanges(text: String): List<IntRange> {
        val ranges = ArrayList<IntRange>()
        var start: Int? = null
        for ((index, c) in text.withIndex()) {
            val inWord = c.isLetterOrDigit() || c == '\'' || c == '’'
            if (inWord && start == null) start = index
            if (!inWord && start != null) {
                ranges.add(start until index)
                start = null
            }
        }
        start?.let { ranges.add(it until text.length) }
        return ranges
    }

    private fun split(text: String, ranges: List<IntRange>): List<Segment> {
        val segments = ArrayList<Segment>()
        var cursor = 0
        for (range in ranges) {
            if (range.first < cursor) continue
            if (cursor < range.first) segments.add(Segment(text.substring(cursor, range.first), false))
            if (!range.isEmpty()) segments.add(Segment(text.substring(range.first, range.last + 1), true))
            cursor = range.last + 1
        }
        if (cursor < text.length) segments.add(Segment(text.substring(cursor), false))
        return segments
    }
}
