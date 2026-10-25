package com.tombaxter.taken.core.todo

// A transcript word by word, and the day and time words in it (Taken/Todo/TodoGrounding.swift `SpokenNote`,
// `SpeechBreak`, `SaidWhen`, `SpokenDayTime`), ported line for line. Swift's half-open `Range<Int>` is a Kotlin
// `IntRange` made with `until`; [lowerBound] and [upperBound] read it the Swift way.

/** Swift's `range.lowerBound` for a half-open range made with `until`. */
val IntRange.lowerBound: Int get() = first

/** Swift's `range.upperBound` for a half-open range made with `until`. */
val IntRange.upperBound: Int get() = last + 1

/** Swift's `range.count`. */
val IntRange.size: Int get() = if (isEmpty()) 0 else last - first + 1

/** Swift's `range.clamped(to:)` for two half-open ranges. */
fun IntRange.clampedTo(bounds: IntRange): IntRange {
    val lower = maxOf(lowerBound, bounds.lowerBound)
    val upper = minOf(upperBound, bounds.upperBound)
    return if (lower >= upper) lower until lower else lower until upper
}

/** How strongly the speaker moved on before a word. Ordered: NONE < WEAK < STRONG. */
enum class SpeechBreak {
    NONE,

    /** A full stop, question mark or exclamation mark: the transcriber's guess at a pause, which can fall inside one task. */
    WEAK,

    /** A comma or semicolon, or "and", "then", "also", "plus", "after that": the speaker listing or moving on. */
    STRONG,
}

/** Words `start...end` of the transcript (closed). */
data class WordSpan(var start: Int, var end: Int) {
    fun overlaps(other: WordSpan): Boolean = start <= other.end && other.start <= end
    fun union(other: WordSpan): WordSpan = WordSpan(minOf(start, other.start), maxOf(end, other.end))
}

/** What was said for a task (G7): a day, a clock time, both or neither. */
data class SaidWhen(var day: Boolean, var time: Boolean, var ownTime: Boolean)

/** A transcript as words: each word's text as said, its normalised tokens and the break before it. */
class SpokenNote(text: String) {
    data class Word(
        /** As said, without the punctuation around it: "L-Theanine", "don't", "Amazon". */
        val surface: String,
        /** Lowercase, apostrophes gone, split at other punctuation: ["l", "theanine"], ["dont"]. */
        val tokens: List<String>,
        val breakBefore: SpeechBreak,
        /** A comma or semicolon right after it, kept when a title is rebuilt. */
        val commaAfter: Boolean,
        /** The first word, or the first after a full stop: its capital says nothing about a name. */
        val startsSentence: Boolean,
        /** As written, punctuation and all, with any punctuation said on its own after it. */
        var raw: String = "",
    ) {
        val key: String get() = tokens.joinToString("")

        /** Only day, time and number words: "Friday", "4", "pm", "tonight". */
        val isDayOrTime: Boolean get() = tokens.isNotEmpty() && tokens.all { SpokenNote.isDayOrTime(it) }
    }

    val words: List<Word>

    /** Every token in order, and the word it belongs to. */
    val tokens: List<String>
    val tokenWord: List<Int>

    /** How often each token was said. */
    val counts: Map<String, Int>

    init {
        val built = ArrayList<Word>()
        var pending = SpeechBreak.NONE
        var sentenceEnded = true
        var leading = ""
        for (chunk in Words.split(text)) {
            val first = chunk.indexOfFirst{ SpokenNote.isWordCharacter(it) }
            val last = chunk.indexOfLast{ SpokenNote.isWordCharacter(it) }
            if (first < 0 || last < 0) {
                // Punctuation on its own: " - ", " & ", " ... ".
                val mark = chunk
                pending = if (mark.all { it in "-–—&+" }) SpeechBreak.STRONG else maxOf(pending, breakOf(mark))
                if (endsSentence(mark)) sentenceEnded = true
                if (built.isEmpty()) {
                    leading += "$mark "
                } else {
                    built[built.size - 1].raw += " $mark"
                }
                continue
            }
            val lead = chunk.substring(0, first)
            val core = chunk.substring(first, last + 1)
            val trail = chunk.substring(last + 1)
            val tokens = coreTokens(core)
            if (tokens.isEmpty()) continue
            built.add(
                Word(
                    surface = core,
                    tokens = tokens,
                    breakBefore = if (built.isEmpty()) SpeechBreak.NONE else maxOf(pending, breakOf(lead)),
                    commaAfter = trail.contains(",") || trail.contains(";"),
                    startsSentence = sentenceEnded || endsSentence(lead),
                    raw = (if (built.isEmpty()) leading else "") + chunk,
                ),
            )
            pending = breakOf(trail)
            sentenceEnded = endsSentence(trail)
        }
        val allTokens = ArrayList<String>()
        val owners = ArrayList<Int>()
        val tally = HashMap<String, Int>()
        for ((index, word) in built.withIndex()) {
            for (token in word.tokens) {
                allTokens.add(token)
                owners.add(index)
                tally[token] = (tally[token] ?: 0) + 1
            }
        }
        words = built
        tokens = allTokens
        tokenWord = owners
        counts = tally
    }

    // MARK: G1 placement

    /** `spoken` in the note's own spelling of a word written two ways: "e-mail" copied for "email" is the same word. */
    fun aligned(spoken: List<String>): List<String> {
        val split = HashMap<String, List<String>>()
        for (index in 0 until tokens.size - 1) {
            if (tokenWord[index] == tokenWord[index + 1]) {
                split[tokens[index] + tokens[index + 1]] = listOf(tokens[index], tokens[index + 1])
            }
        }
        val out = ArrayList<String>()
        var index = 0
        while (index < spoken.size) {
            val token = spoken[index]
            if (index + 1 < spoken.size && counts[token + spoken[index + 1]] != null &&
                (counts[token] == null || counts[spoken[index + 1]] == null)
            ) {
                out.add(token + spoken[index + 1])
                index += 2
                continue
            }
            val pieces = split[token]
            if (counts[token] == null && pieces != null) out.addAll(pieces) else out.add(token)
            index += 1
        }
        return out
    }

    /** The token indices of the words in `window` (every token without one). */
    fun tokenBounds(window: IntRange?): IntRange {
        if (window == null) return tokens.indices
        val lower = tokenWord.indexOfFirst { it >= window.lowerBound }.let { if (it < 0) tokens.size else it }
        val upper = tokenWord.indexOfFirst { it >= window.upperBound }.let { if (it < 0) tokens.size else it }
        return lower until maxOf(lower, upper)
    }

    /**
     * Where `spoken` was said: as a run after `previousEnd`, then anywhere, then fuzzily (at least 80% of its tokens in
     * order, skipping at most two of the note's tokens between them), inside `window` when there is one.
     */
    fun place(spoken: List<String>, after: Int, within: IntRange? = null): WordSpan? {
        val bounds = tokenBounds(within)
        val firstAfter = tokenWord.indexOfFirst { it > after }.let { if (it < 0) tokens.size else it }
        val start = maxOf(bounds.lowerBound, firstAfter)
        val index = runAt(spoken, start, bounds) ?: runAt(spoken, bounds.lowerBound, bounds)
        if (index != null) return WordSpan(tokenWord[index], tokenWord[index + spoken.size - 1])
        return fuzzy(spoken, after, bounds)
    }

    private fun runAt(wanted: List<String>, start: Int, bounds: IntRange): Int? {
        val n = wanted.size
        if (n <= 0 || n > bounds.size || start > bounds.upperBound - n) return null
        for (index in start..(bounds.upperBound - n)) {
            if (tokens[index] != wanted[0]) continue
            if ((1 until n).all { tokens[index + it] == wanted[it] }) return index
        }
        return null
    }

    private fun fuzzy(wanted: List<String>, previousEnd: Int, bounds: IntRange): WordSpan? {
        val n = wanted.size
        val needed = if (n < 2) n else n - maxOf(1, n / 5)
        val maxSkip = 2
        var best: Candidate? = null
        for (start in bounds) {
            for (first in wanted.indices) {
                if (wanted[first] != tokens[start]) continue
                var matched = 1
                var foundContent = isContent(wanted[first])
                var cursor = start + 1
                var last = start
                for (next in wanted.indices) {
                    if (next <= first) continue
                    val limit = minOf(bounds.upperBound, cursor + maxSkip + 1)
                    if (cursor >= limit) continue
                    val hit = (cursor until limit).firstOrNull { tokens[it] == wanted[next] } ?: continue
                    matched += 1
                    foundContent = foundContent || isContent(wanted[next])
                    last = hit
                    cursor = hit + 1
                }
                if (matched < needed || !(matched == n || foundContent)) continue
                val candidate = Candidate(matched, tokenWord[start] > previousEnd, WordSpan(tokenWord[start], tokenWord[last]))
                if (candidate.isBetter(best)) best = candidate
            }
        }
        return best?.span
    }

    /**
     * Where a title with no `spoken` came from: the tightest stretch holding at least `share` of its content words (in any
     * order; singular or plural alike), at most three words per content word plus two.
     */
    fun place(title: String, after: Int, within: IntRange? = null, share: Double = 0.6): WordSpan? {
        val wanted = ArrayList<String>()
        for (token in SpokenNote.tokens(title)) if (isContent(token) && token !in wanted) wanted.add(token)
        if (wanted.isEmpty()) return null
        val needed = maxOf(1, Math.ceil(wanted.size * share).toInt())
        val widest = 3 * wanted.size + 2
        val hits = ArrayList<Pair<Int, Int>>()
        for (index in tokenBounds(within)) {
            val key = wanted.indexOfFirst { sameWord(it, tokens[index]) }
            if (key >= 0) hits.add(tokenWord[index] to key)
        }
        var best: Candidate? = null
        for (a in hits.indices) {
            val seen = HashSet<Int>()
            for (b in a until hits.size) {
                if (hits[b].first - hits[a].first + 1 > widest) break
                seen.add(hits[b].second)
                val candidate = Candidate(seen.size, hits[a].first > after, WordSpan(hits[a].first, hits[b].first))
                if (candidate.isBetter(best)) best = candidate
            }
        }
        if (best == null || best.found < needed) return null
        return best.span
    }

    /** A possible place: the most words found, then after the previous task, then the tightest, then the earliest. */
    private data class Candidate(val found: Int, val afterPrevious: Boolean, val span: WordSpan) {
        fun isBetter(other: Candidate?): Boolean {
            if (other == null) return true
            if (found != other.found) return found > other.found
            if (afterPrevious != other.afterPrevious) return afterPrevious
            val width = span.end - span.start
            val otherWidth = other.span.end - other.span.start
            if (width != otherWidth) return width < otherWidth
            return span.start < other.span.start
        }
    }

    // MARK: Separators

    /** "and", "then", "also", "plus" and "after that" move on to the next thing. */
    fun isSeparatorWord(index: Int): Boolean {
        if (index !in words.indices) return false
        return when (words[index].key) {
            "and", "then", "also", "plus" -> true
            "after" -> index + 1 < words.size && words[index + 1].key == "that"
            "that" -> index > 0 && words[index - 1].key == "after"
            else -> false
        }
    }

    /** A span without an "and" or "then" at either end: the word between two tasks belongs to neither. */
    fun withoutEdgeSeparators(span: WordSpan): WordSpan {
        val out = span.copy()
        while (out.start < out.end && isSeparatorWord(out.start)) out.start += 1
        while (out.end > out.start && isSeparatorWord(out.end)) out.end -= 1
        return out
    }

    /** The strongest break between the end of one span and the start of the next. */
    fun breakBetween(leftEnd: Int, rightStart: Int): SpeechBreak {
        if (leftEnd >= rightStart) return SpeechBreak.NONE
        var level = SpeechBreak.NONE
        for (index in (leftEnd + 1)..rightStart) {
            if (isSeparatorWord(index)) return SpeechBreak.STRONG
            level = maxOf(level, words[index].breakBefore)
        }
        return level
    }

    /** The break between two spans that touch (at most two words apart), or null when they do not or a strong one is between. */
    fun link(from: WordSpan, to: WordSpan): SpeechBreak? {
        val gap = to.start - from.end - 1
        if (gap < 0 || gap > 2) return null
        val level = breakBetween(from.end, to.start)
        return if (level == SpeechBreak.STRONG) null else level
    }

    /**
     * No comma, "and" or other strong separator anywhere, and no full stop between two pieces that each stand alone (G4):
     * two or more content words, or one with its own day or time.
     */
    val isOneThought: Boolean
        get() {
            for (index in words.indices) if (words[index].breakBefore == SpeechBreak.STRONG || isSeparatorWord(index)) return false
            val cuts = words.indices.filter { it > 0 && words[it].breakBefore == SpeechBreak.WEAK }
            val bounds = listOf(0) + cuts + listOf(words.size)
            if (bounds.size <= 2) return true
            for (cut in 1 until bounds.size - 1) {
                if (standsAlone(bounds[cut - 1] until bounds[cut]) && standsAlone(bounds[cut] until bounds[cut + 1])) return false
            }
            return true
        }

    private fun standsAlone(range: IntRange): Boolean {
        val content = contentWords(range)
        return content >= 2 || (content == 1 && range.any { words[it].tokens.any { SpokenNote.isDayOrTime(it) } })
    }

    private fun contentWords(range: IntRange): Int = range.count { words[it].tokens.any{ SpokenNote.isContent(it) } }

    /** A shop, website or place said after its action, the model's task of its own: "on Amazon", "from Boots" (G3). */
    fun isAttachment(span: WordSpan): Boolean {
        if (span.start >= span.end || words[span.start].key !in attachingWords) return false
        return contentWords(span.start until span.end + 1) <= 1
    }

    /** The title's first content word is not in its own words but in the other task's, said once (G2). */
    fun leadsWithCarriedWord(title: String, span: WordSpan, shared: Set<String>): Boolean {
        val lead = SpokenNote.tokens(title).firstOrNull{ SpokenNote.isContent(it) } ?: return false
        if (lead !in shared) return false
        return !(span.start..span.end).any { lead in words[it].tokens }
    }

    // MARK: G5 titles

    /** A content word in the title that was never said, past its first word. */
    fun addsUnsaidWord(title: String): Boolean {
        for ((index, token) in SpokenNote.tokens(title).withIndex()) {
            if (index > 0 && isContent(token) && !wasSaid(token)) return true
        }
        return false
    }

    /** The token, or the same word with or without a trailing s or es, is in the note. */
    fun wasSaid(token: String): Boolean = counts[token] != null || variants(token).any { counts[it] != null }

    /** A capitalised word inside the span (a name, mid-sentence) that the title leaves out. */
    fun dropsName(span: WordSpan, title: String): Boolean {
        val kept = TitleWords(title)
        for (index in span.start..span.end) {
            val word = words[index]
            val first = word.surface.firstOrNull() ?: continue
            if (!first.isUpperCase() || word.startsSentence || word.isDayOrTime || word.surface == "I" ||
                word.surface.startsWith("I'") || word.surface.startsWith("I’")
            ) {
                continue
            }
            if (word.tokens.any { !kept.contains(it) }) return true
        }
        return false
    }

    /** A content word the title leaves out from between two words it kept. */
    fun dropsInnerWord(span: WordSpan, title: String): Boolean {
        val kept = TitleWords(title)
        val keptWords = (span.start..span.end).filter { index ->
            words[index].tokens.any { isContent(it) && kept.contains(it) }
        }
        val first = keptWords.firstOrNull() ?: return false
        val last = keptWords.lastOrNull() ?: return false
        if (last - first <= 1) return false
        for (index in (first + 1) until last) {
            if (words[index].tokens.any { isContent(it) && !kept.contains(it) }) return true
        }
        return false
    }

    /**
     * G5 keeps the action: a title that starts on a word said but past the action of its clause. Returns where the action
     * starts, or null for a title that keeps its action.
     */
    fun actionStart(span: WordSpan, title: String, after: Int): Int? {
        val titleTokens = SpokenNote.tokens(title)
        val lead = titleTokens.firstOrNull() ?: return null
        if (!wasSaid(lead)) return null
        val kept = TitleWords(title)
        val first = (span.start..span.end).firstOrNull { index ->
            words[index].tokens.any { isContent(it) && kept.contains(it) }
        } ?: return null
        var index = first
        var crossed = 0
        var leftOut = false
        while (index > 0 && index - 1 > after && words[index].breakBefore == SpeechBreak.NONE) {
            val left = index - 1
            val key = words[left].key
            if (isSeparatorWord(left) || key in clauseWords) break
            if (key in objectWords) {
                crossed += 1
                index = left
                continue
            }
            leftOut = crossed > 0 && !words[left].isDayOrTime &&
                words[left].tokens.any { isContent(it) && !kept.contains(it) }
            break
        }
        if (!leftOut) return null
        var clauseStart = first
        while (clauseStart > 0 && clauseStart - 1 > after && words[clauseStart].breakBefore == SpeechBreak.NONE &&
            !isSeparatorWord(clauseStart - 1) && words[clauseStart - 1].key !in clauseWords
        ) {
            clauseStart -= 1
        }
        val start = withoutFiller((clauseStart until first).toList()).firstOrNull() ?: first
        return maxOf(start, first - MAX_ACTION_REACH)
    }

    /** A kept title in the spelling said: a word the model wrote singular or plural takes the speaker's form. */
    fun respelled(title: String): String = title.split(" ").joinToString(" ") { piece ->
        val first = piece.indexOfFirst{ SpokenNote.isWordCharacter(it) }
        val last = piece.indexOfLast{ SpokenNote.isWordCharacter(it) }
        if (first < 0 || last < 0) return@joinToString piece
        val core = piece.substring(first, last + 1)
        val coreTokens = coreTokens(core)
        if (coreTokens.size != 1 || counts[coreTokens[0]] != null) return@joinToString piece
        val said = words.firstOrNull { word -> word.tokens.size == 1 && word.tokens[0] in variants(coreTokens[0]) }
            ?: return@joinToString piece
        piece.substring(0, first) + said.surface + piece.substring(last + 1)
    }

    // MARK: G7 days and times

    /** The first word of the sentence holding `index`. */
    fun sentenceStart(index: Int): Int {
        var start = minOf(index, words.size - 1)
        while (start > 0 && !words[start].startsSentence) start -= 1
        return start
    }

    /** What was said for the words of `span` (G7), a day and a clock time apart, given the spans of the tasks said before. */
    fun saidWhen(around: WordSpan, nextStart: Int?, earlier: List<WordSpan> = emptyList(), carried: List<String> = emptyList()): SaidWhen {
        if (words.isEmpty()) return SaidWhen(day = false, time = false, ownTime = false)
        val span = around
        val start = sentenceStart(span.start)
        val first = minOf(span.start, words.size - 1)
        val end = trailingEnd(span, nextStart)
        val previous = earlier.filter { it.end < first }.maxOfOrNull { it.end }
        val lead = maxOf(start, previous?.let { trailingEnd(WordSpan(it, it), first) + 1 } ?: start)
        val own = minOf(lead, first) until (end + 1)
        var opening = start
        while (opening < first) {
            val inTask = earlier.any { it.start <= opening && opening <= it.end }
            if (inTask && !words[opening].tokens.all { SpokenDayTime.isHeaderWord(it) }) break
            opening += 1
        }
        var header: IntRange? = null
        if (start > 0) {
            val headerStart = sentenceStart(start - 1)
            if (isDayTimeHeader(headerStart until start)) header = headerStart until start
        }
        val phrases = carried.map { SpokenNote(it) }
        val headerTime = header?.let { saysTime(it) } ?: false
        val ownTime = saysTime(own) || headerTime || phrases.any { it.saysTime(it.words.indices) }
        val day = saysDay(start until end + 1) || (header?.let { saysDay(it) } ?: false) ||
            phrases.any { it.saysDay(it.words.indices) }
        return SaidWhen(day = day, time = ownTime || saysTime(start until opening), ownTime = ownTime)
    }

    /** The last word a span carries on to: the words after it up to the next break, separator or `limit`. */
    private fun trailingEnd(span: WordSpan, limit: Int?): Int {
        var end = minOf(span.end, words.size - 1)
        val bound = minOf(limit ?: words.size, words.size)
        while (end + 1 < bound && words[end + 1].breakBefore == SpeechBreak.NONE && !isSeparatorWord(end + 1)) end += 1
        return end
    }

    /** A clock time was said in words `range`. */
    fun saysTime(range: IntRange): Boolean {
        val clamped = range.clampedTo(words.indices)
        if (clamped.isEmpty()) return false
        return clamped.any { SpokenDayTime.isClockTime(words[it]) } ||
            SpokenDayTime.saysTime(clamped.flatMap { words[it].tokens })
    }

    /** A day was said in words `range`. */
    fun saysDay(range: IntRange): Boolean {
        val clamped = range.clampedTo(words.indices)
        if (clamped.isEmpty()) return false
        return SpokenDayTime.saysDay(clamped.flatMap { words[it].tokens })
    }

    /** A sentence that only says when: four words or fewer, every one a day or time word, a connector or filler. */
    fun isDayTimeHeader(range: IntRange): Boolean {
        if (range.isEmpty() || range.size > 4 || range.lowerBound < 0 || range.upperBound > words.size) return false
        val said = range.flatMap { words[it].tokens }
        return said.all { SpokenDayTime.isHeaderWord(it) } && SpokenDayTime.said(said)
    }

    /**
     * The speaker's own words over the span, carried on to the next separator or the next task, without leading filler,
     * without the day and time when a due date carries them, at most `maxWords`, never ending on a function word.
     */
    fun title(span: WordSpan, nextStart: Int?, hasDue: Boolean, maxWords: Int = TodoGrounding.MAX_TITLE_WORDS, members: List<WordSpan> = emptyList()): String? {
        var end = span.end
        val limit = minOf(nextStart ?: words.size, words.size)
        while (end + 1 < limit && words[end + 1].breakBefore == SpeechBreak.NONE && !isSeparatorWord(end + 1)) end += 1
        var picked = (span.start..end).toList()
        picked = withoutFiller(picked)
        if (hasDue) picked = withoutFiller(withoutDayAndTime(picked))
        if (picked.size > maxWords) {
            picked = picked.take(maxWords)
            val last = picked.lastOrNull()
            if (last != null) {
                val cut = members.firstOrNull { it.start > picked[0] && it.start <= last && it.end > last }
                if (cut != null) {
                    val before = picked.lastOrNull { it < cut.start && !isSeparatorWord(it) }
                    if (before != null && breakBetween(before, cut.start) == SpeechBreak.STRONG) {
                        picked = picked.filter { it < cut.start }
                    }
                }
            }
        }
        while (picked.size > 1) {
            val last = picked.last()
            if (words[last].key in trailingFunctionWords || isSeparatorWord(last)) picked = picked.dropLast(1) else break
        }
        if (picked.isEmpty()) return null
        val parts = ArrayList<String>()
        for ((n, index) in picked.withIndex()) {
            val word = words[index]
            var surface = word.surface
            if (n > 0 && word.startsSentence && word.surface != "I" && word.key in stopwords) surface = surface.lowercase()
            if (word.commaAfter && n < picked.size - 1) surface += ","
            parts.add(surface)
        }
        val text = parts.joinToString(" ")
        if (text.isEmpty()) return null
        return text.first().uppercase() + text.drop(1)
    }

    /** The words of a span as said, for the record. */
    fun text(span: WordSpan): String = (span.start..span.end).joinToString(" ") { words[it].surface }

    /** The words without the filler they start with ("um so I need to"). */
    fun withoutFiller(picked: List<Int>): List<Int> {
        var out = picked
        var trimmed = true
        while (trimmed) {
            trimmed = false
            for (phrase in leadingFiller) {
                if (out.size <= phrase.size) continue
                if (out.zip(phrase).all { (index, word) -> words[index].key == word }) {
                    out = out.drop(phrase.size)
                    trimmed = true
                    break
                }
            }
        }
        return out
    }

    /** Drops a leading or trailing day or time phrase ("today by 4 pm", "at 8 tonight", "by Thursday"). */
    private fun withoutDayAndTime(picked: List<Int>): List<Int> {
        fun isDayOrTimePart(index: Int): Boolean = words[index].isDayOrTime || words[index].key in dayAndTimeConnectors
        var out = picked
        var cut = out.size
        while (cut > 0 && isDayOrTimePart(out[cut - 1])) cut -= 1
        if (cut > 0 && out.subList(cut, out.size).any { words[it].isDayOrTime }) out = out.subList(0, cut)
        var lead = 0
        while (lead < out.size && isDayOrTimePart(out[lead])) lead += 1
        if (lead < out.size && out.subList(0, lead).any { words[it].isDayOrTime }) out = out.subList(lead, out.size)
        return out
    }

    /** A title's tokens, looked up singular or plural alike. */
    class TitleWords(title: String) {
        val tokens: Set<String> = SpokenNote.tokens(title).toSet()
        fun contains(token: String): Boolean = token in tokens || SpokenNote.variants(token).any { it in tokens }
    }

    companion object {
        fun isWordCharacter(c: Char): Boolean = c.isLetter() || Words.isNumber(c)

        fun breakOf(marks: String): SpeechBreak {
            if (marks.contains(",") || marks.contains(";")) return SpeechBreak.STRONG
            if (endsSentence(marks)) return SpeechBreak.WEAK
            return SpeechBreak.NONE
        }

        fun endsSentence(marks: String): Boolean = marks.any { it in ".?!…" }

        /** The normalised tokens of any text (a `spoken` value, a title). */
        fun tokens(text: String): List<String> = SpokenNote(text).tokens

        private val ampm = Regex("(?<![a-z])([ap])\\.m(?![a-z])")
        private val oclock = Regex("(\\d):00(?!\\d)")

        /** One word's tokens: lowercase, apostrophes dropped, "p.m." as "pm", "4:00" as "4", "4pm" as "4" and "pm". */
        fun coreTokens(core: String): List<String> {
            var text = core.lowercase()
            for (mark in listOf("'", "’", "‘", "ʼ", "`")) text = text.replace(mark, "")
            text = ampm.replace(text, "$1m")
            text = oclock.replace(text, "$1")
            val out = ArrayList<String>()
            val current = StringBuilder()
            var previousIsDigit = false
            for (c in text) {
                if (!isWordCharacter(c)) {
                    if (current.isNotEmpty()) out.add(current.toString())
                    current.setLength(0)
                    previousIsDigit = false
                    continue
                }
                if (c.isLetter() && previousIsDigit && current.isNotEmpty()) {
                    out.add(current.toString())
                    current.setLength(0)
                }
                current.append(c)
                previousIsDigit = Words.isNumber(c)
            }
            if (current.isNotEmpty()) out.add(current.toString())
            return out
        }

        /** A word that carries meaning: not a function word, filler, day, time or number. */
        fun isContent(token: String): Boolean = token !in stopwords && !isDayOrTime(token)

        fun isDayOrTime(token: String): Boolean = token in dayAndTimeWords || token.all { Words.isNumber(it) }

        /** The same word with a trailing s or es, or without one. Only for words of three letters or more. */
        fun variants(token: String): List<String> {
            val forms = ArrayList<String>()
            if (token.length >= 3) forms += listOf(token + "s", token + "es")
            if (token.endsWith("es") && token.length - 2 >= 3) forms.add(token.dropLast(2))
            if (token.endsWith("s") && token.length - 1 >= 3) forms.add(token.dropLast(1))
            return forms
        }

        /** One word, singular or plural alike. */
        fun sameWord(a: String, b: String): Boolean = a == b || b in variants(a)

        /** Words that tie an object to its verb, crossed when looking for the action a title left out (G5). */
        val objectWords: Set<String> = setOf(
            "a", "an", "the", "to", "my", "your", "our", "his", "her", "their", "this", "that", "these", "those", "some",
            "for", "with", "of", "on", "at", "in", "from", "about", "into", "onto",
        )

        /** A copula ends the clause an action is looked for in. */
        val clauseWords: Set<String> = setOf("is", "was", "are", "were", "im", "its", "thats", "theres", "whats")

        /** How far back a title rebuilt for its action reaches, in words before its first kept word. */
        const val MAX_ACTION_REACH = 6

        val leadingFiller: List<List<String>> = listOf(
            listOf("i", "need", "to"), listOf("i", "have", "to"), listOf("remember", "to"), listOf("dont", "forget", "to"),
            listOf("i", "have", "got", "to"), listOf("ive", "got", "to"), listOf("i", "want", "to"),
            listOf("i", "ought", "to"), listOf("id", "like", "to"), listOf("im", "going", "to"), listOf("im", "gonna"),
            listOf("i", "should"), listOf("i", "must"), listOf("i", "wanna"), listOf("i", "gotta"),
            listOf("we", "need", "to"), listOf("we", "should"), listOf("need", "to"), listOf("got", "to"),
            listOf("um"), listOf("uh"), listOf("so"), listOf("also"), listOf("and"), listOf("then"), listOf("plus"),
        )

        /** What a shop, website or place said after its action starts with (G3). */
        val attachingWords: Set<String> = setOf("on", "from", "at", "in", "for", "with", "via", "off")

        val trailingFunctionWords: Set<String> = setOf(
            "a", "an", "the", "to", "of", "for", "from", "with", "at", "by", "on", "in", "into", "onto", "and", "or", "but",
            "so", "then", "also", "plus", "if", "as", "my", "your", "our", "their", "his", "her", "its", "this", "that",
            "these", "those", "some", "any", "i", "me", "we", "you", "is", "are", "was", "be", "about", "um", "uh", "like",
            "just",
        )

        val dayAndTimeConnectors: Set<String> = setOf(
            "at", "by", "on", "before", "this", "next", "in", "the", "until", "till", "around", "from", "latest",
        )

        val stopwords: Set<String> = setOf(
            "a", "an", "the", "and", "or", "but", "nor", "so", "then", "also", "plus", "if", "as", "than", "of", "to",
            "for", "from", "with", "without", "at", "by", "on", "in", "into", "onto", "off", "out", "up", "down", "over",
            "under", "about", "after", "before", "around", "through", "again", "back", "away", "i", "im", "ive", "ill",
            "id", "me", "my", "mine", "myself", "you", "your", "youre", "we", "our", "us", "he", "him", "his", "she",
            "her", "it", "its", "they", "them", "their", "this", "that", "thats", "these", "those", "there", "here", "is",
            "are", "was", "were", "be", "been", "being", "do", "does", "did", "doing", "dont", "have", "has", "had",
            "having", "will", "would", "should", "could", "can", "cant", "must", "may", "might", "shall", "need", "needs",
            "gotta", "gonna", "wanna", "got", "um", "uh", "erm", "er", "oh", "ok", "okay", "like", "just", "really",
            "actually", "maybe", "please", "yeah", "yes", "no", "not", "well", "anyway", "very", "some", "any", "all",
            "what", "which", "who", "when", "where", "why", "how", "remember", "remind", "forget", "thing", "things",
            "lets", "let",
        )

        /** Days, times and numbers: shared by every task in a list said with one time, so never a reason to merge. */
        val dayAndTimeWords: Set<String> = setOf(
            "today", "todays", "tomorrow", "tomorrows", "tonight", "yesterday", "morning", "afternoon", "evening", "night",
            "noon", "midday", "midnight", "week", "weeks", "weekend", "weekday", "fortnight", "month", "months", "year",
            "now", "later", "soon", "asap", "early", "earlier", "late", "next", "last", "ago", "am", "pm", "oclock",
            "clock", "hour", "hours", "hr", "hrs", "minute", "minutes", "min", "mins", "half", "quarter", "past", "daily",
            "weekly",
            "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "mon", "tue", "tues", "wed",
            "weds", "thu", "thur", "thurs", "fri", "sat", "sun", "mondays", "tuesdays", "wednesdays", "thursdays",
            "fridays", "saturdays", "sundays",
            "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november",
            "december", "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
            "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
            "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "thirty", "forty",
            "fifty", "sixty", "hundred", "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth",
            "ninth", "tenth", "eleventh", "twelfth", "st", "nd", "rd", "th",
        )
    }
}

/**
 * The words that let a due date stand (G7), narrower than [SpokenNote.dayAndTimeWords]. Weekday short forms count only
 * before a time or after a day word, numbers only beside a time word, so "Buy 6 eggs" never keeps a 06:00. A day word
 * alone keeps a day, never a clock time. The rules follow Duckling's (https://github.com/facebook/duckling).
 */
object SpokenDayTime {
    /** A day, never a clock time: "tonight" or "this evening" says when, not what time. */
    val dayWords: Set<String> = setOf(
        "today", "todays", "tonight", "tonights", "tomorrow", "tomorrows", "yesterday", "morning", "mornings",
        "afternoon", "evening", "weekend", "eod",
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "mondays", "tuesdays",
        "wednesdays", "thursdays", "fridays", "saturdays", "sundays",
        "january", "february", "april", "june", "july", "august", "september", "october", "november", "december",
    )

    /** A clock time on its own. */
    val timeWords: Set<String> = setOf("noon", "midday", "midnight")
    val shortDays: Set<String> = setOf("mon", "tue", "tues", "wed", "weds", "thu", "thur", "thurs", "fri", "sat", "sun")
    val numberWords: Set<String> = setOf(
        "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "fifteen",
        "twenty", "thirty", "forty", "fifty",
    )

    /** A number right after one of these is a time: "at 6", "by 4", "until 3", "half past 3". */
    val beforeTime: Set<String> = setOf("at", "by", "around", "before", "until", "till", "from", "past")

    /** And right before one of these: "4 pm", "8 o'clock". */
    val afterTime: Set<String> = setOf("am", "pm", "oclock")

    /** A weekday short form after one of these is a day: "on Fri", "by Thu". */
    val dayLead: Set<String> = setOf("on", "by", "until", "till", "this", "next", "before", "from", "every")
    val durations: Set<String> = setOf("minute", "minutes", "min", "mins", "hour", "hours", "hr", "hrs")

    /** After a number, a date: "the 23rd", "1st". */
    val ordinalSuffixes: Set<String> = setOf("st", "nd", "rd", "th")

    /** What else a header sentence ("For Friday,", "Tomorrow at 9.") may hold. */
    val headerExtras: Set<String> = setOf(
        "at", "by", "on", "before", "this", "next", "in", "the", "until", "till", "around", "from", "for", "of", "end",
        "day", "week", "am", "pm", "oclock", "half", "quarter", "past", "to", "um", "uh", "so", "okay", "ok", "oh",
        "right", "and", "then", "well", "every", "st", "nd", "rd", "th",
    )

    /** The parts of a day an hour may be said before: "8 tonight", "7 this evening". */
    val partsOfDay: Set<String> = setOf("tonight", "morning", "afternoon", "evening")

    private val hourWords = setOf("one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve")

    fun isNumber(token: String): Boolean = (token.isNotEmpty() && token.all { Words.isNumber(it) }) || token in numberWords

    fun isHeaderWord(token: String): Boolean =
        token in dayWords || token in timeWords || token in shortDays || isNumber(token) || token in headerExtras

    /** Whether the tokens, in the order said, name a day or a time. */
    fun said(tokens: List<String>): Boolean = saysDay(tokens) || saysTime(tokens)

    /** A clock time: "at 6", "4 pm", "quarter to 4", "half three", "8 tonight", "noon", "in 20 minutes", "in an hour". */
    fun saysTime(tokens: List<String>): Boolean {
        fun peek(index: Int): String? = tokens.getOrNull(index)
        for ((index, token) in tokens.withIndex()) {
            val previous = peek(index - 1)
            val next = peek(index + 1)
            if (token in timeWords) return true
            if (token == "in") {
                if (next != null && (next == "a" || next == "an")) {
                    val unit = peek(index + 2)
                    if (unit != null && unit in durations) return true
                }
                if (next == "half") {
                    val article = peek(index + 2)
                    val unit = peek(index + 3)
                    if (article != null && (article == "a" || article == "an") && unit != null && unit in durations) return true
                }
            }
            if (!isNumber(token)) continue
            if (previous != null && previous in beforeTime) return true
            if (previous == "to" && index >= 2 && tokens[index - 2] == "quarter") return true
            if (next != null && next in afterTime) return true
            if (previous == "in" && next != null && next in durations) return true
            if (isHour(token)) {
                if (previous == "half") return true
                var part = index + 1
                val lead = peek(part)
                if (lead != null && (lead == "this" || lead == "tomorrow")) {
                    part += 1
                } else if (peek(part) == "in" && peek(part + 1) == "the") {
                    part += 2
                }
                val word = peek(part)
                if (word != null && word in partsOfDay) return true
            }
        }
        return false
    }

    /** An hour on a 12-hour clock, as said: 1 to 12, or one to twelve. */
    fun isHour(token: String): Boolean {
        if (token.isNotEmpty() && token.all { Words.isNumber(it) }) {
            val value = Words.asciiInt(token) ?: return false
            return value in 1..12
        }
        return token in hourWords
    }

    private val clockPattern = Regex("^([01]?\\d|2[0-3])[:.][0-5]\\d$")

    /** A word written as a clock time, hours and minutes: "9:30", "4:00", "19.30", never a price ("£9.50"). */
    fun isClockTime(word: SpokenNote.Word): Boolean {
        if (!clockPattern.matches(word.surface)) return false
        return !word.raw.any { it in "£$€¥" }
    }

    /** A day: today, tonight, tomorrow, a weekday, a month, "next week", "end of day", a date ("the 23rd"). */
    fun saysDay(tokens: List<String>): Boolean {
        for ((index, token) in tokens.withIndex()) {
            val previous = if (index > 0) tokens[index - 1] else null
            val next = tokens.getOrNull(index + 1)
            if (token in dayWords) return true
            if (token in shortDays) {
                if (next != null && (isNumber(next) || next in afterTime)) return true
                if (previous != null && previous in dayLead) return true
            }
            if (token == "week" && previous != null && (previous == "next" || previous == "this")) return true
            if (token == "day" && previous == "of" && index >= 2 && tokens[index - 2] == "end") return true
            if (token.isNotEmpty() && token.all { Words.isNumber(it) } && next != null && next in ordinalSuffixes) return true
        }
        return false
    }
}
