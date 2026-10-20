import Foundation

// Code checks every task against the words that were actually said (SPEC 3.10). The on-device model is small: it can
// split one action into two tasks ("Reach toothbrushes" and "Order toothbrushes" from "order Reach toothbrushes on
// Amazon"), or add one nobody said. So every task carries `spoken`, the words of the note it came from (generated
// before its title), and these rules give each word of the note one owner before titles are cleaned and dates checked.
// The idea is source grounding: an extraction is kept only where it lines up with the source text, and extractions
// never overlap. Pure and deterministic, so CI tests it with canned answers (TodoGroundingTests).

enum TodoGrounding {
    /// A rebuilt title keeps at most this many words: a to-do list has no paragraphs.
    static let maxTitleWords = 8
    /// A note this short with no separator in it is one thought, however many tasks the model made of it (G4).
    static let shortNoteWords = 8

    /// The model's tasks with each word of the transcript owned by one task:
    /// - G1 each task is placed on the words it came from: its `spoken` words as a run, first after the previous task,
    ///   then anywhere, then fuzzily (80% of them in order, one miss allowed in two to four words); failing that, or
    ///   with no `spoken`, by its title's content words (60%). A task with `spoken` that places neither way was
    ///   invented and is dropped. A task with only a title that cannot be placed passes through untouched.
    /// - G2 two tasks on overlapping words are one task, and so are two whose titles share a content word said only
    ///   once, unless a separator sits between them and neither title leads with the other's action.
    /// - G3 a one-word task, or a shop or website said after its action ("on Amazon"), joins the task it touches,
    ///   unless a comma or "and" sits between them or the two carry different due dates.
    /// - G4 a short note with no separator in it is one task, unless its tasks carry different due dates.
    /// - G5 a merged title, or one that is empty, adds a word never said, drops a name it covers or drops a word from
    ///   the middle of what it kept, is rebuilt from the speaker's own words.
    /// - G6 a merged task keeps the first due date said.
    static func reconcile(_ raw: [RawTodo], transcript: String) -> [RawTodo] {
        let note = SpokenNote(transcript)
        guard !note.words.isEmpty, !raw.isEmpty else { return raw }

        // G1: place. A `spoken` copied a little off ("I have got to" for "I've gotta", "e-mail" for "email") still
        // places by its title, so a task that was said is never dropped while the rest of its note is kept (the
        // whole-note fallback only runs when nothing is left).
        var spans: [WordSpan?] = Array(repeating: nil, count: raw.count)
        var dropped = Set<Int>()
        var previousEnd = -1
        for (index, task) in raw.enumerated() {
            let spoken = note.aligned(SpokenNote.tokens(of: task.spoken ?? ""))
            var span = spoken.isEmpty ? nil : note.place(spoken: spoken, after: previousEnd)
            if span == nil { span = note.place(title: task.title, after: previousEnd) }
            if span == nil && !spoken.isEmpty { dropped.insert(index) }
            if let span {
                let trimmed = note.withoutEdgeSeparators(span)
                spans[index] = trimmed
                previousEnd = trimmed.end
            }
        }
        let placed = raw.indices.filter { spans[$0] != nil }
        guard !placed.isEmpty else { return raw.indices.filter { !dropped.contains($0) }.map { raw[$0] } }

        var owners = TaskOwners(count: raw.count)

        // G2: one owner per word. A shared title word links only neighbours, so a merge never swallows the task said
        // between them. Across a pause or a separator it links only a list split into things, where one title leads
        // with the action said in the other's words ("buy milk", "eggs" titled "Buy eggs"); a word carried over as
        // context ("call a plumber" titled "Call a plumber about the boiler") leaves two actions apart.
        let titleWords = raw.map { Set(SpokenNote.tokens(of: $0.title).filter(SpokenNote.isContent)) }
        for (n, a) in placed.enumerated() {
            for b in placed[(n + 1)...] {
                guard let spanA = spans[a], let spanB = spans[b] else { continue }
                if spanA.overlaps(spanB) {
                    owners.join(a, b)
                    continue
                }
                let shared = titleWords[a].intersection(titleWords[b]).filter { note.counts[$0] == 1 }
                guard !shared.isEmpty else { continue }
                let (left, right) = spanA.start < spanB.start ? (spanA, spanB) : (spanB, spanA)
                let between = placed.contains { other in
                    guard other != a, other != b, let span = spans[other] else { return false }
                    return span.start > left.end && span.end < right.start
                }
                guard !between else { continue }
                if note.breakBetween(left.end, right.start) != .none,
                   !note.leadsWithCarriedWord(raw[a].title, span: spanA, shared: shared),
                   !note.leadsWithCarriedWord(raw[b].title, span: spanB, shared: shared) { continue }
                owners.join(a, b)
            }
        }
        owners.joinOverlapping(placed: placed, spans: spans)

        // G3: a fragment joins the task it touches: one word, or a shop or website said after its action ("on Amazon",
        // "from Boots"), which joins the task before it. A full stop or question mark between them is only a pause (the
        // transcriber may finalise "Order." on its own); a comma, "and", "then", "also", "plus" or ";" is not. Two
        // tasks the model gave different due dates are two timed things, and stay apart.
        var changed = true
        while changed {
            changed = false
            let groups = owners.groups(placed: placed, spans: spans)
            guard groups.count > 1 else { break }
            for (k, group) in groups.enumerated() {
                let lone = group.span.start == group.span.end
                guard lone || note.isAttachment(group.span) else { continue }
                let previous = k > 0 ? groups[k - 1] : nil
                let next = lone && k + 1 < groups.count ? groups[k + 1] : nil
                let toPrevious = previous.flatMap { other in
                    duesAgree(other.members + group.members, raw: raw) ? note.link(from: other.span, to: group.span) : nil
                }
                let toNext = next.flatMap { other in
                    duesAgree(group.members + other.members, raw: raw) ? note.link(from: group.span, to: other.span) : nil
                }
                // Prefer the side with no pause at all; a lone word otherwise goes with what follows it ("Order. Reach
                // toothbrushes").
                let target: GroundedTask?
                switch (toPrevious, toNext) {
                case (.some(let back), .some(let ahead)): target = back < ahead ? previous : next
                case (.some, nil): target = previous
                case (nil, .some): target = next
                case (nil, nil): target = nil
                }
                guard let target else { continue }
                owners.join(group.members[0], target.members[0])
                owners.joinOverlapping(placed: placed, spans: spans)
                changed = true
                break
            }
        }

        // G4: a short note with no separator is one thought, unless the model heard two times in it ("gym at 6 call
        // mum at 8").
        if placed.count == raw.count - dropped.count, note.words.count <= shortNoteWords, note.isOneThought,
           duesAgree(placed, raw: raw) {
            for index in placed.dropFirst() { owners.join(placed[0], index) }
        }

        // G5 and G6: one task per group, where its first member was in the model's answer.
        let groups = owners.groups(placed: placed, spans: spans)
        var result: [RawTodo] = []
        var emitted = Set<Int>()
        for index in raw.indices where !dropped.contains(index) {
            guard spans[index] != nil else {
                result.append(raw[index])
                continue
            }
            guard let group = groups.first(where: { $0.members.contains(index) }), emitted.insert(group.root).inserted
            else { continue }
            let nextStart = groups.map(\.span.start).filter { $0 > group.span.end }.min()
            result.append(task(for: group, raw: raw, spans: spans, note: note, nextStart: nextStart))
        }
        return result
    }

    /// One group's task. A lone task keeps the model's title unless it adds a word never said, drops a name its words
    /// cover, or drops a word from the middle of what it kept; a merged one is always rebuilt from the transcript, and
    /// keeps the due date of its earliest words.
    private static func task(for group: GroundedTask, raw: [RawTodo], spans: [WordSpan?], note: SpokenNote,
                             nextStart: Int?) -> RawTodo {
        let byPlace = group.members.sorted { a, b in
            let (sa, sb) = (spans[a]?.start ?? 0, spans[b]?.start ?? 0)
            return sa != sb ? sa < sb : a < b
        }
        let first = raw[group.members.min() ?? byPlace[0]]
        let merged = group.members.count > 1
        var due = first.dueISO8601
        var hasTime = first.hasTime
        if merged {
            let source = byPlace.first { !(raw[$0].dueISO8601 ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
            due = source.flatMap { raw[$0].dueISO8601 }
            hasTime = source.map { raw[$0].hasTime } ?? false
        }
        var title = merged ? raw[byPlace[0]].title : first.title
        if merged || SpokenNote.tokens(of: title).isEmpty || note.addsUnsaidWord(title)
            || note.dropsName(in: group.span, title: title) || note.dropsInnerWord(in: group.span, title: title),
           let rebuilt = note.title(for: group.span, nextStart: nextStart, hasDue: due != nil,
                                    members: byPlace.compactMap { spans[$0] }) {
            title = rebuilt
        }
        return RawTodo(spoken: note.text(group.span), title: title, dueISO8601: due, hasTime: hasTime)
    }

    /// The tasks carry one due date at most: none, or the same one (to the minute). Two different ones are two timed
    /// things the model heard ("Gym at 6. Call mum at 8."), so G3 and G4 never make them one.
    static func duesAgree(_ members: [Int], raw: [RawTodo]) -> Bool {
        let dues = Set(members.compactMap { index -> String? in
            let due = (raw[index].dueISO8601 ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return due.isEmpty ? nil : String(due.prefix(16))
        })
        return dues.count <= 1
    }
}

// MARK: - Spans and groups

/// Words `start...end` of the transcript.
struct WordSpan: Hashable, Sendable {
    var start: Int
    var end: Int

    func overlaps(_ other: WordSpan) -> Bool { start <= other.end && other.start <= end }

    func union(_ other: WordSpan) -> WordSpan { WordSpan(start: min(start, other.start), end: max(end, other.end)) }
}

/// Tasks that became one, and the words they cover.
struct GroundedTask {
    var root: Int
    var members: [Int]
    var span: WordSpan
}

/// Which tasks are one (union-find over the model's answer).
struct TaskOwners {
    private var parent: [Int]

    init(count: Int) {
        parent = Array(0..<count)
    }

    mutating func root(_ index: Int) -> Int {
        var current = index
        while parent[current] != current {
            parent[current] = parent[parent[current]]
            current = parent[current]
        }
        return current
    }

    mutating func join(_ a: Int, _ b: Int) {
        let (ra, rb) = (root(a), root(b))
        if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
    }

    /// The placed tasks' groups in the order their words were said.
    mutating func groups(placed: [Int], spans: [WordSpan?]) -> [GroundedTask] {
        var byRoot: [Int: GroundedTask] = [:]
        for index in placed {
            guard let span = spans[index] else { continue }
            let key = root(index)
            if var group = byRoot[key] {
                group.members.append(index)
                group.span = group.span.union(span)
                byRoot[key] = group
            } else {
                byRoot[key] = GroundedTask(root: key, members: [index], span: span)
            }
        }
        return byRoot.values.sorted { $0.span.start != $1.span.start ? $0.span.start < $1.span.start : $0.root < $1.root }
    }

    /// Joins groups whose words overlap until none do.
    mutating func joinOverlapping(placed: [Int], spans: [WordSpan?]) {
        var changed = true
        while changed {
            changed = false
            let all = groups(placed: placed, spans: spans)
            outer: for (n, a) in all.enumerated() {
                for b in all[(n + 1)...] where a.span.overlaps(b.span) {
                    join(a.root, b.root)
                    changed = true
                    break outer
                }
            }
        }
    }
}

// MARK: - The note, word by word

/// How strongly the speaker moved on before a word.
enum SpeechBreak: Int, Comparable, Sendable {
    case none
    /// A full stop, question mark or exclamation mark: the transcriber's guess at a pause, which can fall inside one
    /// task ("Order. Reach toothbrushes on Amazon.").
    case weak
    /// A comma or semicolon, or "and", "then", "also", "plus", "after that": the speaker listing or moving on.
    case strong

    static func < (lhs: SpeechBreak, rhs: SpeechBreak) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A transcript as words: each word's text as said, its normalised tokens (lowercase, no punctuation) and the break
/// before it.
struct SpokenNote {
    struct Word {
        /// As said, without the punctuation around it: "L-Theanine", "don't", "Amazon".
        var surface: String
        /// Lowercase, apostrophes gone, split at other punctuation: ["l", "theanine"], ["dont"].
        var tokens: [String]
        var breakBefore: SpeechBreak
        /// A comma or semicolon right after it, kept when a title is rebuilt ("Buy milk, eggs and bread").
        var commaAfter: Bool
        /// The first word, or the first after a full stop: its capital says nothing about a name.
        var startsSentence: Bool

        var key: String { tokens.joined() }
        /// Only day, time and number words: "Friday", "4", "pm", "tonight".
        var isDayOrTime: Bool { !tokens.isEmpty && tokens.allSatisfy(SpokenNote.isDayOrTime) }
    }

    let words: [Word]
    /// Every token in order, and the word it belongs to.
    let tokens: [String]
    let tokenWord: [Int]
    /// How often each token was said.
    let counts: [String: Int]

    init(_ text: String) {
        var words: [Word] = []
        var pending = SpeechBreak.none
        var sentenceEnded = true
        for chunk in text.split(whereSeparator: { $0.isWhitespace }) {
            let characters = Array(chunk)
            guard let first = characters.firstIndex(where: SpokenNote.isWordCharacter),
                  let last = characters.lastIndex(where: SpokenNote.isWordCharacter) else {
                // Punctuation on its own: " - ", " & ", " ... ".
                let mark = String(characters)
                if mark.allSatisfy({ "-\u{2013}\u{2014}&+".contains($0) }) {
                    pending = .strong
                } else {
                    pending = max(pending, SpokenNote.breakOf(mark))
                }
                if SpokenNote.endsSentence(mark) { sentenceEnded = true }
                continue
            }
            let lead = String(characters[..<first])
            let core = String(characters[first...last])
            let trail = String(characters[(last + 1)...])
            let tokens = SpokenNote.coreTokens(core)
            guard !tokens.isEmpty else { continue }
            words.append(Word(surface: core, tokens: tokens,
                              breakBefore: words.isEmpty ? .none : max(pending, SpokenNote.breakOf(lead)),
                              commaAfter: trail.contains(",") || trail.contains(";"),
                              startsSentence: sentenceEnded || SpokenNote.endsSentence(lead)))
            pending = SpokenNote.breakOf(trail)
            sentenceEnded = SpokenNote.endsSentence(trail)
        }
        var tokens: [String] = []
        var tokenWord: [Int] = []
        var counts: [String: Int] = [:]
        for (index, word) in words.enumerated() {
            for token in word.tokens {
                tokens.append(token)
                tokenWord.append(index)
                counts[token, default: 0] += 1
            }
        }
        self.words = words
        self.tokens = tokens
        self.tokenWord = tokenWord
        self.counts = counts
    }

    /// The normalised tokens of any text (a `spoken` value, a title).
    static func tokens(of text: String) -> [String] { SpokenNote(text).tokens }

    // MARK: G1 placement

    /// `spoken` in the note's own spelling of a word written two ways: "e-mail" copied for "email", or "email" for
    /// "e-mail", is the same word.
    func aligned(_ spoken: [String]) -> [String] {
        // The note's hyphenated words, joined: "e-mail" is ["e", "mail"] under "email".
        var split: [String: [String]] = [:]
        for index in tokens.indices.dropLast() where tokenWord[index] == tokenWord[index + 1] {
            split[tokens[index] + tokens[index + 1]] = [tokens[index], tokens[index + 1]]
        }
        var out: [String] = []
        var index = 0
        while index < spoken.count {
            let token = spoken[index]
            if index + 1 < spoken.count, counts[token + spoken[index + 1]] != nil,
               counts[token] == nil || counts[spoken[index + 1]] == nil {
                out.append(token + spoken[index + 1])
                index += 2
                continue
            }
            if counts[token] == nil, let pieces = split[token] {
                out += pieces
            } else {
                out.append(token)
            }
            index += 1
        }
        return out
    }

    /// Where `spoken` was said: as a run after `previousEnd`, then anywhere, then fuzzily (at least 80% of its tokens in
    /// order, skipping at most two of the note's tokens between them). Nil when it was not said.
    func place(spoken: [String], after previousEnd: Int) -> WordSpan? {
        let start = tokenWord.firstIndex { $0 > previousEnd } ?? tokens.count
        if let index = run(spoken, from: start) ?? run(spoken, from: 0) {
            return WordSpan(start: tokenWord[index], end: tokenWord[index + spoken.count - 1])
        }
        return fuzzy(spoken, after: previousEnd)
    }

    private func run(_ wanted: [String], from start: Int) -> Int? {
        let n = wanted.count
        guard n > 0, n <= tokens.count, start <= tokens.count - n else { return nil }
        for index in start...(tokens.count - n) where tokens[index] == wanted[0] {
            if (1..<n).allSatisfy({ tokens[index + $0] == wanted[$0] }) { return index }
        }
        return nil
    }

    private func fuzzy(_ wanted: [String], after previousEnd: Int) -> WordSpan? {
        let n = wanted.count
        // 80% of the tokens (rounded up), which for two to four tokens would mean all of them: there one may be missed
        // ("call mom" for "call mum"), as long as a content word is among those found.
        let needed = n < 2 ? n : n - max(1, n / 5)
        let maxSkip = 2
        var best: Candidate?
        for start in tokens.indices {
            for first in wanted.indices where wanted[first] == tokens[start] {
                var matched = 1
                var foundContent = SpokenNote.isContent(wanted[first])
                var cursor = start + 1
                var last = start
                for next in wanted.indices where next > first {
                    let limit = min(tokens.count, cursor + maxSkip + 1)
                    guard cursor < limit, let hit = (cursor..<limit).first(where: { tokens[$0] == wanted[next] }) else {
                        continue
                    }
                    matched += 1
                    foundContent = foundContent || SpokenNote.isContent(wanted[next])
                    last = hit
                    cursor = hit + 1
                }
                guard matched >= needed, matched == n || foundContent else { continue }
                let candidate = Candidate(found: matched, afterPrevious: tokenWord[start] > previousEnd,
                                          span: WordSpan(start: tokenWord[start], end: tokenWord[last]))
                if candidate.isBetter(than: best) { best = candidate }
            }
        }
        return best?.span
    }

    /// Where a title with no `spoken` came from: the tightest stretch holding at least 60% of its content words (in
    /// any order, the model may reorder them), at most three words per content word plus two.
    func place(title: String, after previousEnd: Int) -> WordSpan? {
        var wanted: [String] = []
        for token in SpokenNote.tokens(of: title) where SpokenNote.isContent(token) && !wanted.contains(token) {
            wanted.append(token)
        }
        guard !wanted.isEmpty else { return nil }
        let needed = Int((Double(wanted.count) * 0.6).rounded(.up))
        let widest = 3 * wanted.count + 2
        var hits: [(word: Int, key: Int)] = []
        for (index, token) in tokens.enumerated() {
            if let key = wanted.firstIndex(of: token) { hits.append((tokenWord[index], key)) }
        }
        var best: Candidate?
        for a in hits.indices {
            var seen = Set<Int>()
            for b in a..<hits.count {
                guard hits[b].word - hits[a].word + 1 <= widest else { break }
                seen.insert(hits[b].key)
                let candidate = Candidate(found: seen.count, afterPrevious: hits[a].word > previousEnd,
                                          span: WordSpan(start: hits[a].word, end: hits[b].word))
                if candidate.isBetter(than: best) { best = candidate }
            }
        }
        guard let best, best.found >= needed else { return nil }
        return best.span
    }

    /// A possible place: the most words found, then after the previous task, then the tightest, then the earliest.
    private struct Candidate {
        var found: Int
        var afterPrevious: Bool
        var span: WordSpan

        func isBetter(than other: Candidate?) -> Bool {
            guard let other else { return true }
            if found != other.found { return found > other.found }
            if afterPrevious != other.afterPrevious { return afterPrevious }
            let (width, otherWidth) = (span.end - span.start, other.span.end - other.span.start)
            if width != otherWidth { return width < otherWidth }
            return span.start < other.span.start
        }
    }

    // MARK: Separators

    /// "and", "then", "also", "plus" and "after that" move on to the next thing.
    func isSeparatorWord(_ index: Int) -> Bool {
        guard words.indices.contains(index) else { return false }
        switch words[index].key {
        case "and", "then", "also", "plus": return true
        case "after": return index + 1 < words.count && words[index + 1].key == "that"
        case "that": return index > 0 && words[index - 1].key == "after"
        default: return false
        }
    }

    /// A span without an "and" or "then" at either end: the word between two tasks belongs to neither, so a model that
    /// copies "call mum and" and "and buy milk" has not made them overlap.
    func withoutEdgeSeparators(_ span: WordSpan) -> WordSpan {
        var span = span
        while span.start < span.end, isSeparatorWord(span.start) { span.start += 1 }
        while span.end > span.start, isSeparatorWord(span.end) { span.end -= 1 }
        return span
    }

    /// The strongest break between the end of one span and the start of the next.
    func breakBetween(_ leftEnd: Int, _ rightStart: Int) -> SpeechBreak {
        guard leftEnd < rightStart else { return .none }
        var level = SpeechBreak.none
        for index in (leftEnd + 1)...rightStart {
            if isSeparatorWord(index) { return .strong }
            level = max(level, words[index].breakBefore)
        }
        return level
    }

    /// The break between two spans that touch (at most two words apart), or nil when they do not touch or a strong
    /// separator sits between them (G3).
    func link(from left: WordSpan, to right: WordSpan) -> SpeechBreak? {
        let gap = right.start - left.end - 1
        guard gap >= 0, gap <= 2 else { return nil }
        let level = breakBetween(left.end, right.start)
        return level == .strong ? nil : level
    }

    /// No comma, "and" or other strong separator anywhere, and no full stop between two pieces that each stand alone
    /// (G4): two or more content words, or one with its own day or time ("Dentist tomorrow", "Gym at 6"). "Order. Reach
    /// toothbrushes on Amazon" and "Order Reach toothbrushes. On Amazon" are one thought; "Call mum. Buy milk" and
    /// "Gym at 6. Call mum at 8" are two.
    var isOneThought: Bool {
        for index in words.indices where words[index].breakBefore == .strong || isSeparatorWord(index) { return false }
        let cuts = words.indices.filter { $0 > 0 && words[$0].breakBefore == .weak }
        let bounds = [0] + cuts + [words.count]
        guard bounds.count > 2 else { return true }
        for cut in 1..<(bounds.count - 1) {
            if standsAlone(bounds[cut - 1]..<bounds[cut]) && standsAlone(bounds[cut]..<bounds[cut + 1]) { return false }
        }
        return true
    }

    private func standsAlone(_ range: Range<Int>) -> Bool {
        let content = contentWords(range)
        return content >= 2 || (content == 1 && range.contains { words[$0].tokens.contains(where: SpokenNote.isDayOrTime) })
    }

    private func contentWords(_ range: Range<Int>) -> Int {
        range.filter { words[$0].tokens.contains(where: SpokenNote.isContent) }.count
    }

    /// A shop, website or place said after its action, the model's task of its own: "on Amazon", "from Boots", "at
    /// Tesco". It leads with one of `attachingWords` and holds at most one content word (G3).
    func isAttachment(_ span: WordSpan) -> Bool {
        guard span.start < span.end, SpokenNote.attachingWords.contains(words[span.start].key) else { return false }
        return contentWords(span.start..<(span.end + 1)) <= 1
    }

    /// The title's first content word is not in its own words but in the other task's, said once: the action carried
    /// over to the next thing in a list ("eggs" titled "Buy eggs" after "buy milk"). G2.
    func leadsWithCarriedWord(_ title: String, span: WordSpan, shared: Set<String>) -> Bool {
        guard let lead = SpokenNote.tokens(of: title).first(where: SpokenNote.isContent), shared.contains(lead) else {
            return false
        }
        return !(span.start...span.end).contains { words[$0].tokens.contains(lead) }
    }

    // MARK: G5 titles

    /// A content word in the title that was never said, past its first word (the model may add a leading verb).
    func addsUnsaidWord(_ title: String) -> Bool {
        for (index, token) in SpokenNote.tokens(of: title).enumerated()
        where index > 0 && SpokenNote.isContent(token) && counts[token] == nil {
            return true
        }
        return false
    }

    /// A capitalised word inside the span (a name, mid-sentence) that the title leaves out: "Order toothbrushes on
    /// Amazon" from "order Reach toothbrushes on Amazon". Days and months are left out of titles on purpose.
    func dropsName(in span: WordSpan, title: String) -> Bool {
        let kept = Set(SpokenNote.tokens(of: title))
        for index in span.start...span.end {
            let word = words[index]
            guard let first = word.surface.first, first.isUppercase, !word.startsSentence, !word.isDayOrTime,
                  word.surface != "I", !word.surface.hasPrefix("I'"), !word.surface.hasPrefix("I\u{2019}") else { continue }
            if word.tokens.contains(where: { !kept.contains($0) }) { return true }
        }
        return false
    }

    /// A content word the title leaves out from between two words it kept: "Order toothbrushes on amazon" from "order
    /// reach toothbrushes on amazon", where no capital marks the brand. Words before the first kept word or after the
    /// last (chat, the day) may go.
    func dropsInnerWord(in span: WordSpan, title: String) -> Bool {
        let kept = Set(SpokenNote.tokens(of: title))
        let keptWords = (span.start...span.end).filter { index in
            words[index].tokens.contains { SpokenNote.isContent($0) && kept.contains($0) }
        }
        guard let first = keptWords.first, let last = keptWords.last, last - first > 1 else { return false }
        for index in (first + 1)..<last {
            let word = words[index]
            if word.tokens.contains(where: { SpokenNote.isContent($0) && !kept.contains($0) }) { return true }
        }
        return false
    }

    /// The speaker's own words over the span, carried on to the next separator or the next task, without leading filler,
    /// without the day and time when a due date carries them, at most `maxWords`, never ending on a function word.
    /// When the cut falls inside a member said after a separator, that member goes whole: "Email the landlord about the
    /// boiler", never "... and call". Nil when nothing is left.
    func title(for span: WordSpan, nextStart: Int?, hasDue: Bool, maxWords: Int = TodoGrounding.maxTitleWords,
               members: [WordSpan] = []) -> String? {
        var end = span.end
        let limit = min(nextStart ?? words.count, words.count)
        while end + 1 < limit, words[end + 1].breakBefore == .none, !isSeparatorWord(end + 1) { end += 1 }
        var picked = Array(span.start...end)
        picked = withoutFiller(picked)
        if hasDue { picked = withoutFiller(withoutDayAndTime(picked)) }
        if picked.count > maxWords {
            picked = Array(picked.prefix(maxWords))
            if let last = picked.last,
               let cut = members.first(where: { $0.start > picked[0] && $0.start <= last && $0.end > last }),
               let before = picked.last(where: { $0 < cut.start && !isSeparatorWord($0) }),
               breakBetween(before, cut.start) == .strong {
                picked = picked.filter { $0 < cut.start }
            }
        }
        while picked.count > 1, let last = picked.last,
              SpokenNote.trailingFunctionWords.contains(words[last].key) || isSeparatorWord(last) {
            picked.removeLast()
        }
        guard !picked.isEmpty else { return nil }
        var parts: [String] = []
        for (n, index) in picked.enumerated() {
            let word = words[index]
            var surface = word.surface
            // "Order Reach toothbrushes. On Amazon": a pause inside one task is not the start of a new sentence.
            if n > 0, word.startsSentence, word.surface != "I", SpokenNote.stopwords.contains(word.key) {
                surface = surface.lowercased()
            }
            if word.commaAfter && n < picked.count - 1 { surface += "," }
            parts.append(surface)
        }
        let text = parts.joined(separator: " ")
        guard let first = text.first else { return nil }
        return first.uppercased() + text.dropFirst()
    }

    /// The words of a span as said, for the record.
    func text(_ span: WordSpan) -> String {
        (span.start...span.end).map { words[$0].surface }.joined(separator: " ")
    }

    private func withoutFiller(_ picked: [Int]) -> [Int] {
        var picked = picked
        var trimmed = true
        while trimmed {
            trimmed = false
            for phrase in SpokenNote.leadingFiller where picked.count > phrase.count {
                if zip(picked, phrase).allSatisfy({ words[$0.0].key == $0.1 }) {
                    picked.removeFirst(phrase.count)
                    trimmed = true
                    break
                }
            }
        }
        return picked
    }

    /// Drops a leading or trailing day or time phrase ("today by 4 pm", "at 8 tonight", "by Thursday").
    private func withoutDayAndTime(_ picked: [Int]) -> [Int] {
        func isDayOrTimePart(_ index: Int) -> Bool {
            words[index].isDayOrTime || SpokenNote.dayAndTimeConnectors.contains(words[index].key)
        }
        var picked = picked
        var cut = picked.count
        while cut > 0, isDayOrTimePart(picked[cut - 1]) { cut -= 1 }
        if cut > 0, picked[cut...].contains(where: { words[$0].isDayOrTime }) { picked = Array(picked[..<cut]) }
        var lead = 0
        while lead < picked.count, isDayOrTimePart(picked[lead]) { lead += 1 }
        if lead < picked.count, picked[..<lead].contains(where: { words[$0].isDayOrTime }) {
            picked = Array(picked[lead...])
        }
        return picked
    }

    // MARK: Words

    static func isWordCharacter(_ character: Character) -> Bool { character.isLetter || character.isNumber }

    static func breakOf(_ marks: String) -> SpeechBreak {
        if marks.contains(",") || marks.contains(";") { return .strong }
        if endsSentence(marks) { return .weak }
        return .none
    }

    static func endsSentence(_ marks: String) -> Bool {
        marks.contains(where: { ".?!\u{2026}".contains($0) })
    }

    /// One word's tokens: lowercase, apostrophes dropped ("don't" is "dont"), "p.m." as "pm", "4:00" as "4", "4pm" as
    /// "4" and "pm", split at any other punctuation ("L-Theanine" is "l" and "theanine").
    static func coreTokens(_ core: String) -> [String] {
        var text = core.lowercased()
        for mark in ["'", "\u{2019}", "\u{2018}", "\u{02BC}", "`"] {
            text = text.replacingOccurrences(of: mark, with: "")
        }
        text = text.replacingOccurrences(of: #"(?<![a-z])([ap])\.m(?![a-z])"#, with: "$1m", options: .regularExpression)
        text = text.replacingOccurrences(of: #"(\d):00(?!\d)"#, with: "$1", options: .regularExpression)
        var tokens: [String] = []
        var current = ""
        var previousIsDigit = false
        for character in text {
            guard isWordCharacter(character) else {
                if !current.isEmpty { tokens.append(current) }
                current = ""
                previousIsDigit = false
                continue
            }
            if character.isLetter && previousIsDigit && !current.isEmpty {
                tokens.append(current)
                current = ""
            }
            current.append(character)
            previousIsDigit = character.isNumber
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// A word that carries meaning: not a function word, filler, day, time or number.
    static func isContent(_ token: String) -> Bool { !stopwords.contains(token) && !isDayOrTime(token) }

    static func isDayOrTime(_ token: String) -> Bool {
        dayAndTimeWords.contains(token) || token.allSatisfy { $0.isNumber }
    }

    static let leadingFiller: [[String]] = [
        ["i", "need", "to"], ["i", "have", "to"], ["remember", "to"], ["dont", "forget", "to"],
        ["um"], ["uh"], ["so"], ["also"], ["and"], ["then"], ["plus"],
    ]

    /// What a shop, website or place said after its action starts with (G3).
    static let attachingWords: Set<String> = ["on", "from", "at", "in", "for", "with", "via", "off"]

    static let trailingFunctionWords: Set<String> = [
        "a", "an", "the", "to", "of", "for", "from", "with", "at", "by", "on", "in", "into", "onto", "and", "or", "but",
        "so", "then", "also", "plus", "if", "as", "my", "your", "our", "their", "his", "her", "its", "this", "that",
        "these", "those", "some", "any", "i", "me", "we", "you", "is", "are", "was", "be", "about", "um", "uh", "like",
        "just",
    ]

    static let dayAndTimeConnectors: Set<String> = [
        "at", "by", "on", "before", "this", "next", "in", "the", "until", "till", "around", "from", "latest",
    ]

    static let stopwords: Set<String> = [
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
    ]

    /// Days, times and numbers: shared by every task in "today by 4 pm I need to X, Y and Z", so never a reason to
    /// merge, and never a name.
    static let dayAndTimeWords: Set<String> = [
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
    ]
}

// MARK: - Keep as one

/// Keep as one: what a split note reads as once it is put back together. Pure, so the tests pin it. It reads the note
/// word by word as the grounding rules do, so it lives in the app beside them.
enum TodoMerge {
    /// A note this short reads best in the words said.
    static let maxSpokenWords = 12

    /// For a note of 12 words or fewer, the words said, rebuilt as G5 rebuilds a title: leading filler ("um", "so", "I
    /// need to") and pauses dropped, and the day and time left to the due date when there is one ("Tomorrow at 9 call
    /// the dentist and buy milk" reads "Call the dentist and buy milk" beside "Tomorrow 09:00"). Longer, the tasks'
    /// titles in the order said, joined with commas. Cleaned like every title, so at most `TodoText.maxTitleLength`
    /// characters: the list stays short lines, never paragraphs.
    static func title(transcript: String, titles: [String], hasDue: Bool) -> String? {
        let note = SpokenNote(transcript)
        if !note.words.isEmpty, note.words.count <= maxSpokenWords,
           let spoken = note.title(for: WordSpan(start: 0, end: note.words.count - 1), nextStart: nil, hasDue: hasDue,
                                   maxWords: maxSpokenWords).flatMap(TodoText.clean) {
            return spoken
        }
        return TodoText.clean(titles.joined(separator: ", "))
    }

    /// The soonest of the due dates, ordered as the list orders them (a day alone is due by its end), or nil.
    static func earliestDue(_ dues: [TodoDue?], clock: DayClock) -> TodoDue? {
        dues.compactMap { $0 }.min { a, b in
            (TodoOrdering.sortDate(a, clock: clock) ?? .distantFuture) < (TodoOrdering.sortDate(b, clock: clock) ?? .distantFuture)
        }
    }
}
