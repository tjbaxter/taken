import Foundation

// A long voice note in parts (SPEC 3.10). One on-device model session holds 4,096 tokens with its instructions, schema
// and answer, and the phone writes about 30 tokens a second, so a note of more than about 7 tasks cannot be sorted in
// one go inside the time a person waits. Apple's answer for input larger than the window is to split it into steps,
// each in a new session (TN3193), so a note is cut into parts of 40 to 80 words, at sentence ends, and each part is
// sorted on its own (NoteSorter). Text mode only: the cuts read the finished transcript, never the words still being
// heard, and never pause timings (how SpeechTranscriber's result ranges treat silence is not documented). Pure, so CI
// tests it.

/// One part of a note.
struct TodoChunk: Hashable, Codable, Sendable {
    enum Cut: String, Codable, Sendable {
        /// At a sentence end, after at least 40 words.
        case sentence
        /// At 80 words with no sentence end to cut at: the latest comma or "and", else the latest full stop.
        case forced
        /// The rest of the note, at the stop.
        case end
        /// Half of a part the model had no room for (`TodoChunker.split`).
        case split
    }

    var index: Int
    var text: String
    /// Its words in `SpokenNote(note).words`. The parts of a note are contiguous and cover it once.
    var wordRange: Range<Int>
    /// The day or time a forced cut left in the part before ("today by 4" from "Today by 4 I need to email Sam, ... |
    /// call the bank"), given to the model with this part and to G7.
    var carried: String?
    var cut: Cut

    var wordCount: Int { wordRange.count }
}

enum TodoChunker {
    /// A part is closed at the first sentence end after this many words.
    static let minimumWords = 40
    /// A part never runs past this many words.
    static let maximumWords = 80
    /// A forced cut looks for a comma or "and" in this many words before the 80th.
    static let forcedLookback = 25
    /// The rest of a note, shorter than this, joins the part before when that part was not sent yet.
    static let shortestTail = 15
    /// No part starts on one of these: what follows belongs to what came before ("Order Reach toothbrushes. On
    /// Amazon.", "Call the bank. And the dentist.").
    static let noCutBefore: Set<String> = [
        "and", "then", "also", "plus", "or", "but", "on", "from", "at", "in", "for", "with", "via", "off", "to", "by",
    ]

    /// The parts of a note. With `final` false only the parts already closed (the word after each cut is known), for
    /// sorting while the person is still talking; the parts closed so far never change as more words come. With
    /// `final` true the rest is the last part, joined to the part before when it is under `shortestTail` words and that
    /// part is not one of the `sent` already sorted.
    static func chunks(text: String, final: Bool, sent: Int = 0) -> [TodoChunk] {
        chunks(note: SpokenNote(text), final: final, sent: sent)
    }

    static func chunks(note: SpokenNote, final: Bool, sent: Int = 0) -> [TodoChunk] {
        let count = note.words.count
        var chunks: [TodoChunk] = []
        var start = 0
        var carried: String?
        while start < count {
            var cut: (at: Int, reason: TodoChunk.Cut)?
            var next = start + minimumWords
            while next < count && next - start <= maximumWords {
                if isSentenceCut(note, before: next) {
                    cut = (next, .sentence)
                    break
                }
                next += 1
            }
            if cut == nil && count - start > maximumWords {
                cut = (forcedCut(note, from: start), .forced)
            }
            guard let found = cut else { break }
            chunks.append(chunk(note, index: chunks.count, words: start..<found.at, carried: carried, cut: found.reason))
            carried = found.reason == .forced ? carriedPhrase(note, cutBefore: found.at) : nil
            start = found.at
        }
        guard final, start < count else { return chunks }
        if count - start < shortestTail, let last = chunks.last, last.index >= sent {
            chunks[chunks.count - 1] = chunk(note, index: last.index, words: last.wordRange.lowerBound..<count,
                                             carried: last.carried, cut: .end)
        } else {
            chunks.append(chunk(note, index: chunks.count, words: start..<count, carried: carried, cut: .end))
        }
        return chunks
    }

    /// A part the model had no room for, in two: at the sentence end nearest its middle, else the comma or "and"
    /// nearest it, else the middle word. Nil for a part too short to halve.
    static func split(_ chunk: TodoChunk, note: SpokenNote) -> [TodoChunk]? {
        let range = chunk.wordRange
        guard range.count >= 2, range.upperBound <= note.words.count else { return nil }
        let middle = range.lowerBound + range.count / 2
        let inside = Array((range.lowerBound + 1)..<range.upperBound)
        func nearest(_ candidates: [Int]) -> Int? {
            candidates.min { abs($0 - middle) < abs($1 - middle) }
        }
        let at = nearest(inside.filter { note.words[$0].startsSentence })
            ?? nearest(inside.filter { isStrongSeparator(note, before: $0) })
            ?? middle
        return [
            Self.chunk(note, index: chunk.index, words: range.lowerBound..<at, carried: chunk.carried, cut: .split),
            Self.chunk(note, index: chunk.index, words: at..<range.upperBound,
                       carried: chunk.carried ?? carriedPhrase(note, cutBefore: at), cut: .split),
        ]
    }

    /// The words as written, for the prompt and for lines saved as said.
    static func text(_ note: SpokenNote, _ words: Range<Int>) -> String {
        words.map { note.words[$0].raw }.joined(separator: " ")
    }

    // MARK: Rules

    private static func chunk(_ note: SpokenNote, index: Int, words: Range<Int>, carried: String?,
                              cut: TodoChunk.Cut) -> TodoChunk {
        TodoChunk(index: index, text: text(note, words), wordRange: words, carried: carried, cut: cut)
    }

    /// A part may close before word `index`: a sentence ended there, the next word does not carry on what came before,
    /// and the sentence just ended is not a day or time header ("Tomorrow.") that belongs to what follows.
    static func isSentenceCut(_ note: SpokenNote, before index: Int) -> Bool {
        guard index > 0, index < note.words.count, note.words[index].startsSentence,
              !noCutBefore.contains(note.words[index].key) else { return false }
        return !note.isDayTimeHeader(note.sentenceStart(of: index - 1)..<index)
    }

    /// A comma or semicolon before the word, or "and", "then", "also", "plus" as the word.
    static func isStrongSeparator(_ note: SpokenNote, before index: Int) -> Bool {
        guard index > 0, index < note.words.count else { return false }
        return note.words[index].breakBefore == .strong || note.isSeparatorWord(index)
    }

    /// Where an 80-word part with no sentence end to close at is cut: the latest comma, semicolon, "and", "then",
    /// "also" or "plus" in its last 25 words, else its latest sentence end, else after its 80th word.
    static func forcedCut(_ note: SpokenNote, from start: Int) -> Int {
        let end = start + maximumWords
        let late = (end - forcedLookback + 1)...end
        if let at = late.reversed().first(where: { $0 > start && isStrongSeparator(note, before: $0) }) { return at }
        if let at = ((start + 1)...end).reversed().first(where: { note.words[$0].startsSentence }) { return at }
        return end
    }

    /// The day or time a sentence cut in two starts with, for the part after the cut: "Today by 4 pm" from "Today by 4
    /// pm I need to email Sam, call the bank". Nil when the cut falls on a sentence end, or the sentence does not start
    /// with a day or time.
    static func carriedPhrase(_ note: SpokenNote, cutBefore index: Int) -> String? {
        guard index > 0, index < note.words.count, !note.words[index].startsSentence else { return nil }
        var start = note.sentenceStart(of: index - 1)
        var end = start
        while end < index, note.words[end].tokens.allSatisfy(SpokenDayTime.isHeaderWord) { end += 1 }
        // Without the filler before it or a connector after it: "Today by 4 pm", from "So today by 4 pm I need to".
        while start < end, leadingFiller.contains(note.words[start].key) { start += 1 }
        while end > start, trailingConnectors.contains(note.words[end - 1].key) { end -= 1 }
        let tokens = (start..<end).flatMap { note.words[$0].tokens }
        guard end > start, SpokenDayTime.said(in: tokens) else { return nil }
        return (start..<end).map { note.words[$0].surface }.joined(separator: " ")
    }

    private static let leadingFiller: Set<String> = ["um", "uh", "so", "okay", "ok", "oh", "right", "and", "then", "well"]
    private static let trailingConnectors: Set<String> = [
        "at", "by", "on", "before", "this", "next", "in", "the", "until", "till", "around", "from", "for", "of", "to",
        "every", "end", "um", "uh", "so", "okay", "ok", "oh", "right", "and", "then", "well",
    ]
}
