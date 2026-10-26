package com.tombaxter.taken.core.todo

import com.tombaxter.taken.core.catalog.Catalog
import com.tombaxter.taken.core.model.StackState
import com.tombaxter.taken.core.stack.orderedItems
import java.util.Locale

// The pure parts of speech capture: the names the recognizer should expect (Taken/Todo/TodoVocabulary.swift), the
// transcript kept when a recognizer starts over (Taken/Todo/TodoSpeech.swift `RecognizerTranscript`,
// `TranscriptBuffer.join`), and Android's check of the phone's language against what the on-device recognizer has.

/**
 * The names the on-device recognizer should expect, so "Ashwagandha" or the person's own "Reach" floss is heard as said:
 * the stack first, then the Add sheet's chips and the rest of the catalog, at most 100 short phrases. On Android 13 and
 * later they go to the recognizer as `RecognizerIntent.EXTRA_BIASING_STRINGS`
 * (https://developer.android.com/reference/android/speech/RecognizerIntent#EXTRA_BIASING_STRINGS). Never stored or sent.
 */
object TranscriptionVocabulary {
    /** Apple: "Limit the total number of phrases to no more than 100." Android documents no limit; the iPhone's stands. */
    const val LIMIT = 100

    /** Chips and catalog names together, so the person's own names always fit. */
    const val CATALOG_LIMIT = 80

    /** Longer phrases are "less likely to be recognized", so they are left out. */
    const val MAX_WORDS = 4

    fun strings(stack: List<String>, chips: List<String>, catalog: List<String>): List<String> {
        val result = ArrayList<String>()
        val seen = HashSet<String>()
        fun add(name: String): Boolean {
            val words = Words.split(name)
            if (words.isEmpty() || words.size > MAX_WORDS || result.size >= LIMIT) return false
            val phrase = words.joinToString(" ")
            if (!seen.add(phrase.lowercase())) return false
            result.add(phrase)
            return true
        }
        for (name in stack) add(name)
        var fromCatalog = 0
        for (name in chips + catalog) {
            if (fromCatalog >= CATALOG_LIMIT) break
            if (add(name)) fromCatalog += 1
        }
        return result
    }

    /** The bundled names that are not chips, most widely taken first, in listed order within a weight. */
    val catalogNames: List<String> by lazy {
        Catalog.entries.withIndex()
            .filter { !it.value.isChip }
            .sortedWith(compareByDescending<IndexedValue<com.tombaxter.taken.core.catalog.CatalogEntry>> { it.value.weight }.thenBy { it.index })
            .map { it.value.name }
    }

    /** This person's phrases now: the items they take (not archived, in stack order), the chips, then the catalog. */
    fun current(state: StackState): List<String> {
        val items = state.orderedItems.filter { !it.archived }
        return strings(items.map { it.name }, Catalog.presets.map { it.name }, catalogNames)
    }
}

/** Two pieces of a transcript joined with one space, neither doubled nor dropped. */
object TranscriptJoin {
    fun join(head: String, tail: String): String {
        val a = Words.trimAll(head)
        val b = Words.trimAll(tail)
        if (a.isEmpty()) return b
        if (b.isEmpty()) return a
        return "$a $b"
    }

    /** A finished segment shorter than this is never taken for a repeat: a person may well say three words twice. */
    const val REPEAT_WORDS = 4

    /**
     * [Own choice, SPEC-ANDROID 11] Android 13's segmented sessions report a segment's results through
     * `onSegmentResults`; the docs do not say whether the partial results that follow cover only the next segment or the
     * whole session (https://developer.android.com/reference/android/speech/RecognitionListener#onSegmentResults(android.os.Bundle)).
     * A result that starts with every word of the session's finished segments (at least [REPEAT_WORDS] of them, case
     * and punctuation aside) is taken to repeat them, and only the words after them are new; anything else is new as
     * it is. Nothing said is ever dropped: a result that is only the repeat gives "".
     */
    fun afterRepeat(result: String, finished: String): String {
        val wanted = RecognizerTranscript.words(finished)
        if (wanted.size < REPEAT_WORDS) return result
        val raw = Words.split(result)
        var matched = 0
        for ((index, token) in raw.withIndex()) {
            val word = RecognizerTranscript.words(token).firstOrNull() ?: continue
            if (word != wanted[matched]) return result
            matched += 1
            if (matched == wanted.size) return raw.drop(index + 1).joinToString(" ")
        }
        return result
    }
}

/**
 * One note's words when the recognizer starts over (Taken/Todo/TodoSpeech.swift `RecognizerTranscript`). The iPhone needs
 * it for iOS 17 to 25; Android needs it where a long note is several recognizer sessions: Android 12 (no segmented
 * sessions) and any recognizer that ends a session on a pause (SPEC-ANDROID 11). A start-over is told from the text: a
 * result no longer than the longest text since the last start-over that does not continue it.
 */
class RecognizerTranscript {
    /** What earlier sessions and start-overs left. */
    var committed: String = ""
        private set

    /** The longest text since the last start-over, and the latest result. */
    var peak: String = ""
        private set
    var current: String = ""
        private set

    /** Everything heard, in order. */
    val text: String get() = TranscriptJoin.join(committed, tail)

    /** Takes the latest result. True when it started over. */
    fun apply(result: String): Boolean {
        val next = words(result)
        if (next.isEmpty()) return false
        val longest = words(peak)
        if (longest.size >= 2 && next.size <= longest.size && !continues(longest, next)) {
            committed = TranscriptJoin.join(committed, peak)
            peak = result
            current = result
            return true
        }
        current = result
        if (next.size >= longest.size) peak = result
        return false
    }

    /** The session ended (a final result, an error, the stop): its words are kept, and the next session starts clean. */
    fun commit() {
        committed = TranscriptJoin.join(committed, tail)
        peak = ""
        current = ""
    }

    /** The words since the last start-over. */
    private val tail: String
        get() {
            val latest = words(current)
            val longest = words(peak)
            if (latest.size >= longest.size) return current
            if (longest.take(latest.size) == latest) return peak
            if (latest.size >= 4 && matched(latest, longest.take(latest.size + 1)) >= latest.size - 1) return current
            return TranscriptJoin.join(peak, current)
        }

    companion object {
        /** The log keeps at most this many start-overs. */
        const val MAX_RESETS = 50

        /** How many opening words are compared. */
        const val COMPARED = 8

        /** The new result carries on the text: at least half of the shorter one's opening words come, in order. */
        fun continues(previous: List<String>, next: List<String>): Boolean {
            val (short, long) = if (next.size <= previous.size) next to previous else previous to next
            val opening = short.take(COMPARED)
            val against = long.take(opening.size + 2)
            return matched(opening, against) * 2 >= opening.size
        }

        /** The most words of `a` found in `b` in the same order (longest common subsequence). */
        fun matched(a: List<String>, b: List<String>): Int {
            if (a.isEmpty() || b.isEmpty()) return 0
            val row = IntArray(b.size + 1)
            for (x in a) {
                var diagonal = 0
                for ((j, y) in b.withIndex()) {
                    val above = row[j + 1]
                    row[j + 1] = if (x == y) diagonal + 1 else maxOf(row[j], above)
                    diagonal = above
                }
            }
            return row[b.size]
        }

        /** Lowercase words without punctuation. */
        fun words(text: String): List<String> = Words.split(text.lowercase()).mapNotNull { word ->
            val kept = word.filter { it.isLetter() || Words.isNumber(it) }
            kept.ifEmpty { null }
        }
    }
}

/**
 * Whether the phone's language can be heard on the device now (Android 13 and later, SPEC-ANDROID 11), from
 * `SpeechRecognizer.checkRecognitionSupport`'s answer: installed, being downloaded, downloadable, or not supported
 * (https://developer.android.com/reference/android/speech/RecognitionSupport). Pure, so CI tests the matching.
 */
object SpeechLanguage {
    enum class Availability {
        /** On the phone: listen now. */
        INSTALLED,

        /** Being downloaded: type it for now. */
        DOWNLOADING,

        /** Supported but not on the phone: start the download for next time, type it for now. */
        DOWNLOADABLE,

        /** The on-device recognizer does not have this language. */
        UNSUPPORTED,
    }

    /**
     * The phone's language tag against the recognizer's lists: the exact tag wherever it is listed ("en-GB"), else the
     * same language ("en-US" serves "en-AU"), as BCP 47 lookup falls back from region to language
     * (https://www.rfc-editor.org/rfc/rfc4647#section-3.4). [Own choice: installed, then pending, then supported.]
     */
    fun availability(tag: String, installed: List<String>, pending: List<String>, supported: List<String>): Availability {
        val wanted = normalized(tag)
        fun exact(list: List<String>): Boolean = list.any { normalized(it) == wanted }
        fun sameLanguage(list: List<String>): Boolean = list.any { language(it) == language(tag) }
        val listed = exact(installed) || exact(pending) || exact(supported)
        val match: (List<String>) -> Boolean = if (listed) ::exact else ::sameLanguage
        return when {
            match(installed) -> Availability.INSTALLED
            match(pending) -> Availability.DOWNLOADING
            match(supported) -> Availability.DOWNLOADABLE
            else -> Availability.UNSUPPORTED
        }
    }

    /** The best tag in a list for the phone's language: exact, else the same language, else the tag itself. */
    fun bestTag(tag: String, lists: List<String>): String {
        val wanted = normalized(tag)
        lists.firstOrNull { normalized(it) == wanted }?.let { return it }
        val language = language(tag)
        return lists.firstOrNull { language(it) == language } ?: tag
    }

    private fun normalized(tag: String): String = tag.replace('_', '-').lowercase(Locale.ROOT)

    private fun language(tag: String): String = normalized(tag).substringBefore('-')
}
