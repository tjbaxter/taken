package com.tombaxter.taken.core.todo

// A long voice note in parts (SPEC 3.10), ported from Taken/Todo/TodoChunking.swift. A note is cut into parts of 40 to
// 80 words at sentence ends, and each part is sorted on its own (NoteSorter). Pure, so CI tests it.

/** One part of a note. */
data class TodoChunk(
    val index: Int,
    val text: String,
    /** Its words in `SpokenNote(note).words`, half-open. The parts of a note are contiguous and cover it once. */
    val wordRange: IntRange,
    /** The day or time a forced cut left in the part before, given to the model with this part and to G7. */
    val carried: String? = null,
    val cut: Cut,
) {
    enum class Cut {
        /** At a sentence end, after at least 40 words. */
        SENTENCE,

        /** At 80 words with no sentence end to cut at: the latest comma or "and", else the latest full stop. */
        FORCED,

        /** The rest of the note, at the stop. */
        END,

        /** Half of a part the model had no room for ([TodoChunker.split]). */
        SPLIT,
    }

    val wordCount: Int get() = wordRange.size
}

object TodoChunker {
    /** A part is closed at the first sentence end after this many words. */
    const val MINIMUM_WORDS = 40

    /** A part never runs past this many words. */
    const val MAXIMUM_WORDS = 80

    /** A forced cut looks for a comma or "and" in this many words before the 80th. */
    const val FORCED_LOOKBACK = 25

    /** The rest of a note, shorter than this, joins the part before when that part was not sent yet. */
    const val SHORTEST_TAIL = 15

    /** No part starts on one of these: what follows belongs to what came before. */
    val noCutBefore: Set<String> = setOf(
        "and", "then", "also", "plus", "or", "but", "on", "from", "at", "in", "for", "with", "via", "off", "to", "by",
    )

    /**
     * The parts of a note. With `final` false only the parts already closed, for sorting while the person is still
     * talking; the parts closed so far never change as more words come. With `final` true the rest is the last part,
     * joined to the part before when it is under [SHORTEST_TAIL] words and that part is not one of the `sent` already.
     */
    fun chunks(text: String, final: Boolean, sent: Int = 0): List<TodoChunk> = chunks(SpokenNote(text), final, sent)

    fun chunks(note: SpokenNote, final: Boolean, sent: Int = 0): List<TodoChunk> {
        val count = note.words.size
        val chunks = ArrayList<TodoChunk>()
        var start = 0
        var carried: String? = null
        while (start < count) {
            var cutAt: Int? = null
            var reason: TodoChunk.Cut? = null
            var next = start + MINIMUM_WORDS
            while (next < count && next - start <= MAXIMUM_WORDS) {
                if (isSentenceCut(note, next)) {
                    cutAt = next
                    reason = TodoChunk.Cut.SENTENCE
                    break
                }
                next += 1
            }
            if (cutAt == null && count - start > MAXIMUM_WORDS) {
                cutAt = forcedCut(note, start)
                reason = TodoChunk.Cut.FORCED
            }
            if (cutAt == null || reason == null) break
            chunks.add(chunk(note, chunks.size, start until cutAt, carried, reason))
            carried = if (reason == TodoChunk.Cut.FORCED) carriedPhrase(note, cutAt) else null
            start = cutAt
        }
        if (!final || start >= count) return chunks
        val last = chunks.lastOrNull()
        if (count - start < SHORTEST_TAIL && last != null && last.index >= sent) {
            chunks[chunks.size - 1] = chunk(note, last.index, last.wordRange.lowerBound until count, last.carried, TodoChunk.Cut.END)
        } else {
            chunks.add(chunk(note, chunks.size, start until count, carried, TodoChunk.Cut.END))
        }
        return chunks
    }

    /**
     * A part the model had no room for, in two: at the sentence end nearest its middle, else the comma or "and" nearest
     * it, else the middle word. Null for a part too short to halve.
     */
    fun split(chunk: TodoChunk, note: SpokenNote): List<TodoChunk>? {
        val range = chunk.wordRange
        if (range.size < 2 || range.upperBound > note.words.size) return null
        val middle = range.lowerBound + range.size / 2
        val inside = ((range.lowerBound + 1) until range.upperBound).toList()
        fun nearest(candidates: List<Int>): Int? = candidates.minByOrNull { Math.abs(it - middle) }
        val at = nearest(inside.filter { note.words[it].startsSentence })
            ?: nearest(inside.filter { isStrongSeparator(note, it) })
            ?: middle
        return listOf(
            chunk(note, chunk.index, range.lowerBound until at, chunk.carried, TodoChunk.Cut.SPLIT),
            chunk(note, chunk.index, at until range.upperBound, chunk.carried ?: carriedPhrase(note, at), TodoChunk.Cut.SPLIT),
        )
    }

    /** The words as written, for the prompt and for lines saved as said. */
    fun text(note: SpokenNote, words: IntRange): String = words.joinToString(" ") { note.words[it].raw }

    private fun chunk(note: SpokenNote, index: Int, words: IntRange, carried: String?, cut: TodoChunk.Cut): TodoChunk =
        TodoChunk(index, text(note, words), words, carried, cut)

    /** A part may close before word `index`: a sentence ended there, the next word carries nothing on, no header before. */
    fun isSentenceCut(note: SpokenNote, index: Int): Boolean {
        if (index <= 0 || index >= note.words.size || !note.words[index].startsSentence || note.words[index].key in noCutBefore) {
            return false
        }
        return !note.isDayTimeHeader(note.sentenceStart(index - 1) until index)
    }

    /** A comma or semicolon before the word, or "and", "then", "also", "plus" as the word. */
    fun isStrongSeparator(note: SpokenNote, index: Int): Boolean {
        if (index <= 0 || index >= note.words.size) return false
        return note.words[index].breakBefore == SpeechBreak.STRONG || note.isSeparatorWord(index)
    }

    /**
     * Where an 80-word part with no sentence end to close at is cut: the latest strong separator in its last 25 words,
     * else its latest sentence end, else after its 80th word.
     */
    fun forcedCut(note: SpokenNote, start: Int): Int {
        val end = start + MAXIMUM_WORDS
        for (at in end downTo (end - FORCED_LOOKBACK + 1)) {
            if (at > start && isStrongSeparator(note, at)) return at
        }
        for (at in end downTo (start + 1)) {
            if (note.words[at].startsSentence) return at
        }
        return end
    }

    /**
     * The day or time a sentence cut in two starts with, for the part after the cut: "Today by 4 pm" from "Today by 4 pm
     * I need to email Sam, call the bank". Null when the cut falls on a sentence end, or the sentence starts otherwise.
     */
    fun carriedPhrase(note: SpokenNote, cutBefore: Int): String? {
        val index = cutBefore
        if (index <= 0 || index >= note.words.size || note.words[index].startsSentence) return null
        var start = note.sentenceStart(index - 1)
        var end = start
        while (end < index && note.words[end].tokens.all { SpokenDayTime.isHeaderWord(it) }) end += 1
        while (start < end && note.words[start].key in leadingFiller) start += 1
        while (end > start && note.words[end - 1].key in trailingConnectors) end -= 1
        val tokens = (start until end).flatMap { note.words[it].tokens }
        if (end <= start || !SpokenDayTime.said(tokens)) return null
        return (start until end).joinToString(" ") { note.words[it].surface }
    }

    private val leadingFiller = setOf("um", "uh", "so", "okay", "ok", "oh", "right", "and", "then", "well")
    private val trailingConnectors = setOf(
        "at", "by", "on", "before", "this", "next", "in", "the", "until", "till", "around", "from", "for", "of", "to",
        "every", "end", "um", "uh", "so", "okay", "ok", "oh", "right", "and", "then", "well",
    )
}
