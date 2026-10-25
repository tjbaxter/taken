package com.tombaxter.taken.core

import com.tombaxter.taken.core.todo.RecognizerTranscript
import com.tombaxter.taken.core.todo.SpeechLanguage
import com.tombaxter.taken.core.todo.TranscriptJoin
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Ported from TakenTests/RecognizerTranscriptTests.swift: every word kept when a recognizer session starts over after a
 * pause or ends by itself. On Android this joins the sessions of one long note on Android 12 and on any recognizer that
 * ends a session on a pause (SPEC-ANDROID 11). Plus Android's language check against the on-device recognizer's lists.
 */
class RecognizerTranscriptTests {
    private fun heard(results: List<String>): RecognizerTranscript {
        val transcript = RecognizerTranscript()
        for (result in results) transcript.apply(result)
        return transcript
    }

    @Test
    fun testCumulativeResultsGiveTheLastText() {
        assertEquals("Call the dentist tomorrow", heard(listOf("Call", "Call the", "Call the dentist", "Call the dentist tomorrow")).text)
        assertEquals(
            "I need to call the dentist. And buy",
            heard(listOf("I need to call", "I need to call the dentist.", "I need to call the dentist. And buy")).text,
            "one growing result",
        )
    }

    @Test
    fun testAStartOverAfterAPauseKeepsBothPartsInOrder() {
        val transcript = RecognizerTranscript()
        for (result in listOf("Call", "Call the", "Call the dentist.")) transcript.apply(result)
        assertTrue(transcript.apply("Buy"), "a shorter result that does not continue the text started over")
        transcript.apply("Buy milk")
        transcript.apply("Buy milk and eggs")
        assertEquals("Call the dentist. Buy milk and eggs", transcript.text)
    }

    @Test
    fun testAStartOverWithTheSameOpeningWordsIsCaughtOnceItGoesItsOwnWay() {
        val transcript = heard(listOf("I need to call the dentist", "I", "I need", "I need milk", "I need milk and eggs"))
        assertEquals("I need to call the dentist I need milk and eggs", transcript.text)
        assertEquals("Call the dentist Call mum", heard(listOf("Call the dentist", "Call", "Call mum")).text, "both are kept, never the shorter alone")
    }

    @Test
    fun testRevisionsAreNotStartOvers() {
        assertEquals("Call the dentist to", heard(listOf("Cold", "Call the", "Call the dentist to", "Call the dentist")).text, "the end revised away: the longer text stays")
        assertEquals("I need to call the dentist", heard(listOf("I need to call the dentists at", "I need to call the dentist")).text, "a word revised and one dropped: the latest")
        val transcript = RecognizerTranscript()
        assertFalse(transcript.apply("Call the"))
        assertFalse(transcript.apply("Paul the dentist"), "one word changed in three carries on")
    }

    @Test
    fun testALongerResultThatRewritesTheOpeningWordsIsARevision() {
        assertEquals("Look at the table for six", heard(listOf("Book", "Book a", "Book a table", "Look at the table for six")).text)
        assertEquals("Sent message is to my LinkedIn", heard(listOf("Send", "Send messages", "Sent message is to my LinkedIn")).text)
        assertEquals("Remember to call the dentist", heard(listOf("Remind", "Remind me", "Remember to call the dentist")).text)
        val transcript = RecognizerTranscript()
        transcript.apply("Remind me")
        assertFalse(transcript.apply("Remember to call the dentist"), "longer: a revision, not a start-over")
        assertEquals(
            "I need to call the dentist I need milk and eggs and bread",
            heard(listOf("I need to call the dentist", "I", "I need", "I need milk", "I need milk and eggs", "I need milk and eggs and bread")).text,
            "a start-over sharing the opening words is still caught while it is no longer",
        )
    }

    @Test
    fun testARestartAfterIsFinalAppendsTheNewTasksWords() {
        val transcript = RecognizerTranscript()
        transcript.apply("Call the dentist.")
        transcript.commit()
        transcript.apply("Buy")
        transcript.apply("Buy milk.")
        assertEquals("Call the dentist. Buy milk.", transcript.text)
        transcript.commit()
        assertEquals("Call the dentist. Buy milk.", transcript.text, "committing twice changes nothing")
    }

    @Test
    fun testJoinNeverDoublesASpaceOrDropsAWord() {
        assertEquals("Call the dentist. Buy milk", TranscriptJoin.join("Call the dentist. ", "  Buy milk"))
        assertEquals("Buy milk", TranscriptJoin.join("", "Buy milk"))
        assertEquals("Call the dentist", TranscriptJoin.join("Call the dentist", ""))
        val transcript = RecognizerTranscript()
        transcript.apply("   ")
        assertEquals("", transcript.text, "an empty result is nothing")
        assertEquals(listOf("call", "the", "dentist"), RecognizerTranscript.words("Call, the DENTIST."))
        assertEquals(2, RecognizerTranscript.matched(listOf("i", "need", "milk"), listOf("i", "need", "to", "call")))
    }

    // Android only: the phone's language against checkRecognitionSupport's lists (Android 13 and later).

    @Test
    fun testThePhonesLanguageIsMatchedExactlyThenByLanguage() {
        val installed = listOf("en-US")
        val pending = listOf("fr-FR")
        val supported = listOf("en-US", "en-GB", "fr-FR", "de-DE")
        assertEquals(SpeechLanguage.Availability.INSTALLED, SpeechLanguage.availability("en-US", installed, pending, supported))
        assertEquals(SpeechLanguage.Availability.DOWNLOADABLE, SpeechLanguage.availability("en-GB", installed, pending, supported), "British English is its own download")
        assertEquals(SpeechLanguage.Availability.INSTALLED, SpeechLanguage.availability("en-AU", installed, pending, supported), "unlisted: English is on the phone")
        assertEquals(SpeechLanguage.Availability.INSTALLED, SpeechLanguage.availability("en_us", installed, pending, supported), "any spelling of the tag")
        assertEquals(SpeechLanguage.Availability.DOWNLOADING, SpeechLanguage.availability("fr-CA", installed, pending, supported))
        assertEquals(SpeechLanguage.Availability.DOWNLOADABLE, SpeechLanguage.availability("de-AT", installed, pending, supported))
        assertEquals(SpeechLanguage.Availability.UNSUPPORTED, SpeechLanguage.availability("cy-GB", installed, pending, supported))
        assertEquals("en-GB", SpeechLanguage.bestTag("en-GB", supported))
        assertEquals("de-DE", SpeechLanguage.bestTag("de-AT", supported))
        assertEquals("cy-GB", SpeechLanguage.bestTag("cy-GB", supported))
    }
}
