package com.tombaxter.taken.core

import com.tombaxter.taken.core.todo.SpokenNote
import com.tombaxter.taken.core.todo.TodoChunk
import com.tombaxter.taken.core.todo.TodoChunker
import com.tombaxter.taken.core.todo.TodoPrompt
import com.tombaxter.taken.core.todo.lowerBound
import com.tombaxter.taken.core.todo.upperBound
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/TodoChunkingTests.swift: a long note in parts, cut at sentence ends after 40 words, never before
 * a word that carries on what came before or right after a day header, forced at 80 words at the latest comma or "and",
 * carrying the day a cut sentence started with, a short tail joined to the part before, every word in exactly one part.
 */
class TodoChunkingTests {
    /** `count` sentences of `words` distinct words each. */
    private fun sentences(count: Int, words: Int, prefix: String = "w"): String =
        (0 until count).joinToString(" ") { s -> (0 until words).joinToString(" ") { "$prefix${s}x$it" } + "." }

    @Test
    fun testNoCutBeforeFortyWordsThenAtTheFirstSentenceEnd() {
        assertTrue(TodoChunker.chunks(sentences(3, 10), final = false).isEmpty(), "30 words: nothing closed")
        assertEquals(listOf(30), TodoChunker.chunks(sentences(3, 10), final = true).map { it.wordCount }, "at the stop the rest is one part")
        val parts = TodoChunker.chunks(sentences(6, 10), final = true)
        assertEquals(listOf(40, 20), parts.map { it.wordCount })
        assertEquals(listOf(TodoChunk.Cut.SENTENCE, TodoChunk.Cut.END), parts.map { it.cut })
        assertEquals(listOf(0, 1), parts.map { it.index })
        assertTrue(parts[0].text.endsWith("w3x9."), "the part keeps its punctuation: ${parts[0].text}")
    }

    @Test
    fun testNeverACutBeforeAndOrAShopOrRightAfterADayHeader() {
        val andNote = sentences(4, 10) + " And then the rest of the note runs on for a good few words more here. " + "On Amazon. Buy milk tomorrow. Call mum."
        for (part in TodoChunker.chunks(andNote, final = true).drop(1)) {
            val first = SpokenNote(part.text).words.firstOrNull()?.key ?: ""
            assertFalse(first in TodoChunker.noCutBefore, "a part starts on $first: ${part.text}")
        }
        val header = sentences(3, 13) + " Tomorrow. Call the bank about the card and the loan. Then the rest of it."
        val parts = TodoChunker.chunks(header, final = true)
        assertFalse(parts.any { it.text.endsWith("Tomorrow.") }, "the header stays with its sentence")
        assertTrue(parts.any { it.text.contains("Tomorrow. Call the bank") })
    }

    @Test
    fun testAForcedCutFallsOnACommaThenASentenceEndThenWordEighty() {
        val commas = (0 until 10).joinToString(", ") { i -> (0 until 9).joinToString(" ") { "f${i}x$it" } } + "."
        val atComma = TodoChunker.chunks(commas, final = true)
        assertEquals(TodoChunk.Cut.FORCED, atComma.firstOrNull()?.cut)
        assertEquals(72, atComma.firstOrNull()?.wordCount, "the latest comma in the last 25 words")
        assertTrue(atComma.firstOrNull()?.text?.endsWith(",") ?: false)

        val early = sentences(1, 30) + " " + (0 until 70).joinToString(" ") { "e$it" }
        assertEquals(30, TodoChunker.chunks(early, final = true).firstOrNull()?.wordCount)
        assertEquals(TodoChunk.Cut.FORCED, TodoChunker.chunks(early, final = true).firstOrNull()?.cut)

        val plain = (0 until 120).joinToString(" ") { "p$it" }
        assertEquals(listOf(80, 40), TodoChunker.chunks(plain, final = true).map { it.wordCount }, "else after word 80")
    }

    @Test
    fun testAForcedCutInsideASentenceCarriesItsDayOrTime() {
        val note = "Today by 4 pm I need to " + (0 until 100).joinToString(" ") { "c$it" }
        val parts = TodoChunker.chunks(note, final = true)
        assertEquals(2, parts.size)
        assertNull(parts[0].carried)
        assertEquals("Today by 4 pm", parts[1].carried)
        val prompt = TodoPrompt.prompt(parts[1], parts.size, TodoEval.context)
        assertTrue(prompt.contains("Said just before, for the same list: \"Today by 4 pm\"."), prompt)
        assertTrue(prompt.contains("Voice note, part 2: \""), prompt)
        assertNull(TodoChunker.carriedPhrase(SpokenNote("Call the bank. Tomorrow I will"), 3), "a cut at a sentence end carries nothing")
    }

    @Test
    fun testAShortTailJoinsThePartBeforeUnlessThatWasSent() {
        val note = sentences(5, 10) + " Short tail here now."
        assertEquals(listOf(54), TodoChunker.chunks(note, final = true).map { it.wordCount }, "14 words join")
        assertEquals(listOf(40, 14), TodoChunker.chunks(note, final = true, sent = 1).map { it.wordCount }, "a part already sorted is never sent again")
    }

    @Test
    fun testTheWordRangesCoverANineHundredWordNoteOnceAndClosedPartsNeverChange() {
        val note = StringBuilder()
        for (i in 0 until 900) note.append("b$i").append(if (i % 23 == 22) ". " else if (i % 7 == 6) ", " else " ")
        val text = note.toString()
        val parts = TodoChunker.chunks(text, final = true)
        var covered = 0
        for (part in parts) {
            assertEquals(covered, part.wordRange.lowerBound, "contiguous")
            assertTrue(part.wordCount <= TodoChunker.MAXIMUM_WORDS)
            covered = part.wordRange.upperBound
        }
        assertEquals(SpokenNote(text).words.size, covered, "every word once")
        val words = parts.flatMap { SpokenNote(it.text).tokens }.toSet()
        assertTrue((0 until 900).all { "b$it" in words })

        val early = TodoChunker.chunks(text.take(2_000), final = false)
        val later = TodoChunker.chunks(text, final = false)
        assertFalse(early.isEmpty())
        assertEquals(early, later.take(early.size))
    }

    @Test
    fun testTextModeOnATypedParagraph() {
        val typed = "Call the dentist about the crown and ask whether they have anything next week. Then email Sam the deck, " +
            "the one with the new numbers. Pick up the parcel from the post office before it goes back. Book the car in " +
            "for its service and remember to ask about the noise from the brakes. Order more printer ink. Text Jo about " +
            "Saturday. Water the plants on the balcony and the ones in the kitchen. Renew the parking permit online " +
            "before Friday."
        val parts = TodoChunker.chunks(typed, final = true)
        assertEquals(listOf(54, 27), parts.map { it.wordCount }, "the first sentence end after 40 words")
        assertEquals(listOf(TodoChunk.Cut.SENTENCE, TodoChunk.Cut.END), parts.map { it.cut })
        assertTrue(parts.last().text.startsWith("Order more printer ink."), parts.last().text)
    }

    @Test
    fun testAPartTooBigForTheWindowSplitsAtItsMiddleSentenceEnd() {
        val note = SpokenNote(sentences(6, 10))
        val first = assertNotNull(TodoChunker.chunks(note, final = true).firstOrNull())
        val halves = assertNotNull(TodoChunker.split(first, note))
        assertEquals(listOf(20, 20), halves.map { it.wordCount })
        assertEquals(listOf(TodoChunk.Cut.SPLIT, TodoChunk.Cut.SPLIT), halves.map { it.cut })
        assertEquals(first.wordRange.lowerBound, halves[0].wordRange.lowerBound)
        assertEquals(first.wordRange.upperBound, halves[1].wordRange.upperBound)
    }
}
