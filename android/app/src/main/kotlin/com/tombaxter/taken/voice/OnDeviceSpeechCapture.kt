package com.tombaxter.taken.voice

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import com.tombaxter.taken.core.todo.RecognizerTranscript
import com.tombaxter.taken.core.todo.SpeechLanguage
import com.tombaxter.taken.core.todo.TranscriptJoin
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.resume

/**
 * A voice note heard by Android's on-device recognizer, and only that one (SPEC-ANDROID 11): never the default
 * recognizer, which "is likely to stream audio to remote servers", so nothing said leaves the phone
 * (https://developer.android.com/reference/android/speech/SpeechRecognizer). Android 12 (API 31) and later:
 * `createOnDeviceSpeechRecognizer` after `isOnDeviceRecognitionAvailable`. Every call runs on the main thread, as the
 * class requires ("This class's methods must be invoked only from the main application thread").
 *
 * - Android 13 and later: `checkRecognitionSupport` first. The phone's language installed: listen. Being downloaded:
 *   type it for now. Supported but not on the phone: `triggerModelDownload` for next time, type it for now. Not
 *   supported: type it instead (https://developer.android.com/reference/android/speech/RecognitionSupport).
 * - The request (https://developer.android.com/reference/android/speech/RecognizerIntent): free form in the phone's
 *   language, partial results, `EXTRA_PREFER_OFFLINE`; on Android 13 and later `EXTRA_ENABLE_FORMATTING` (full stops,
 *   which the one-line-per-sentence save reads), the names to expect as `EXTRA_BIASING_STRINGS`, and a segmented
 *   session of at least five minutes (`EXTRA_SEGMENTED_SESSION` set to `EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS`, "The
 *   recognizer will not stop recognizing speech before this amount of time"), so a long note stays one session and
 *   comes back in segments (`onSegmentResults`, `onEndOfSegmentedSession`).
 * - Every recognizer may ignore those extras ("Depending on the recognizer implementation, this value may have no
 *   effect"), and Android 12 has no segmented sessions, so a session that ends on a pause before Taken's own stop rules
 *   (30 s of quiet, 5 minutes, a tap) is followed by a new one, and the words carry on through the ported
 *   `RecognizerTranscript` (the iPhone's fix for the same start-over shape on iOS 17 to 25,
 *   Taken/Todo/TodoSpeech.swift `RecognizerBackend`, with its numbers: at most 200 restarts, a session that ended at once
 *   waits 0.3 s, the last words are waited for at most 2 s). [Own choice: the iPhone's safety net, unchanged]
 */
@RequiresApi(31)
class OnDeviceSpeechCapture(context: Context) : VoiceCapture {
    private val context: Context = context.applicationContext
    private val main = Handler(Looper.getMainLooper())
    private val transcript = RecognizerTranscript()
    private var recognizer: SpeechRecognizer? = null
    private var request: Intent? = null
    private var listener: VoiceCapture.Listener? = null

    /** Answered by the first callback of the first session. */
    private var starting: CompletableDeferred<VoiceCapture.Start>? = null

    /** Answered when the last session ends after [finish] asked it to. */
    private var ending: CompletableDeferred<Unit>? = null

    /** A session is running: its end has not been reported yet. */
    private var sessionOpen = false
    private var sessionStartedAt = 0L
    private var restarts = 0
    private var finishing = false

    /** The words of this session's finished segments (Android 13 and later), so a result that repeats them is caught. */
    private var segments = ""

    override suspend fun start(languageTag: String, vocabulary: List<String>, listener: VoiceCapture.Listener): VoiceCapture.Start {
        val available = try {
            SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
        } catch (e: RuntimeException) {
            false
        }
        if (!available) return VoiceCapture.Start.UNAVAILABLE
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            return VoiceCapture.Start.NO_PERMISSION
        }
        val recognizer = try {
            SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
        } catch (e: UnsupportedOperationException) {
            return VoiceCapture.Start.UNAVAILABLE
        }
        this.recognizer = recognizer
        this.listener = listener
        // "setRecognitionListener(RecognitionListener) should be called before dispatching any command".
        recognizer.setRecognitionListener(callbacks)
        var tag = languageTag
        if (Build.VERSION.SDK_INT >= 33) {
            when (val language = language(recognizer, tag)) {
                is Language.Listen -> tag = language.tag
                is Language.Blocked -> {
                    release()
                    return language.start
                }
                null -> Unit // The service could not say: try listening, and an error says the rest.
            }
        }
        request = listeningIntent(tag, vocabulary)
        val answer = CompletableDeferred<VoiceCapture.Start>()
        starting = answer
        listen()
        val outcome = withTimeoutOrNull(START_TIMEOUT_MS) { answer.await() } ?: VoiceCapture.Start.BUSY
        starting = null
        if (outcome != VoiceCapture.Start.LISTENING) release()
        return outcome
    }

    override suspend fun finish(): String {
        val recognizer = recognizer ?: return transcript.text
        finishing = true
        // A restart waiting to run never runs now.
        main.removeCallbacksAndMessages(null)
        if (sessionOpen) {
            val end = CompletableDeferred<Unit>()
            ending = end
            // "Speech captured so far will be recognized as if the user had stopped speaking at this point."
            recognizer.stopListening()
            withTimeoutOrNull(FINISH_TIMEOUT_MS) { end.await() }
        }
        transcript.commit()
        release()
        return transcript.text
    }

    override fun cancel() {
        finishing = true
        main.removeCallbacksAndMessages(null)
        recognizer?.cancel()
        release()
    }

    // MARK: Sessions

    private fun listen() {
        val recognizer = recognizer ?: return
        val request = request ?: return
        sessionOpen = true
        sessionStartedAt = SystemClock.elapsedRealtime()
        segments = ""
        recognizer.startListening(request)
    }

    /** A session ended (a final result, the end of a segmented session, a pause, an error). */
    private fun sessionEnded() {
        if (!sessionOpen) return
        sessionOpen = false
        transcript.commit()
        emit()
        if (finishing) {
            ending?.complete(Unit)
            return
        }
        if (restarts >= MAX_RESTARTS) {
            listener?.onInterrupted()
            return
        }
        restarts += 1
        // A session that ended at once (an error on every start) waits a moment, so it never spins.
        if (SystemClock.elapsedRealtime() - sessionStartedAt < QUICK_SESSION_MS) {
            main.postDelayed({ if (!finishing) listen() }, RESTART_DELAY_MS)
        } else {
            listen()
        }
    }

    private fun heard(results: Bundle?, segment: Boolean = false) {
        // With formatting on, "Each result list will contain two hypotheses in the order of 1) formatted text 2) raw
        // text": the first is the one shown and saved.
        val raw = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: return
        // A recognizer that reports a segmented session's results from the session's start would repeat its finished
        // segments: only the words after them are new (TranscriptJoin.afterRepeat, SPEC-ANDROID 11).
        val text = TranscriptJoin.afterRepeat(raw, segments)
        if (text.isBlank()) return
        transcript.apply(text)
        if (segment) segments = TranscriptJoin.join(segments, text)
        emit()
    }

    private fun emit() {
        val text = transcript.text
        if (text.isNotEmpty()) listener?.onText(text)
    }

    private fun failed(error: Int) {
        val answer = starting
        if (answer != null && !answer.isCompleted) {
            when (error) {
                // A pause before the first word: the session is open for the note, and starts again.
                SpeechRecognizer.ERROR_NO_MATCH, SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> {
                    answer.complete(VoiceCapture.Start.LISTENING)
                    sessionEnded()
                }
                else -> {
                    sessionOpen = false
                    answer.complete(startFailure(error))
                }
            }
            return
        }
        if (finishing) {
            sessionOpen = false
            ending?.complete(Unit)
            return
        }
        when (error) {
            // The microphone or the language went away mid-note: keep the words, stop listening.
            SpeechRecognizer.ERROR_AUDIO,
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS,
            SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED,
            SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> {
                sessionOpen = false
                transcript.commit()
                emit()
                listener?.onInterrupted()
            }
            // A pause ended the session, the service was busy for a moment, or it restarted: listen again.
            else -> sessionEnded()
        }
    }

    private fun startFailure(error: Int): VoiceCapture.Start = when (error) {
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> VoiceCapture.Start.NO_PERMISSION
        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> VoiceCapture.Start.UNAVAILABLE
        // "Requested language is supported, but not available currently (e.g. not downloaded yet)."
        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE ->
            if (Build.VERSION.SDK_INT >= 33) {
                request?.let { download(it) }
                VoiceCapture.Start.DOWNLOADING
            } else {
                VoiceCapture.Start.UNAVAILABLE
            }
        else -> VoiceCapture.Start.BUSY
    }

    private fun release() {
        sessionOpen = false
        main.removeCallbacksAndMessages(null)
        recognizer?.let {
            try {
                // "the caller MUST invoke destroy() on a SpeechRecognizer object when it is no longer needed."
                it.destroy()
            } catch (e: RuntimeException) {
                // Already gone with its service.
            }
        }
        recognizer = null
        listener = null
    }

    private val callbacks = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {
            starting?.complete(VoiceCapture.Start.LISTENING)
        }

        override fun onBeginningOfSpeech() {
            starting?.complete(VoiceCapture.Start.LISTENING)
        }

        override fun onRmsChanged(rmsdB: Float) {
            if (!finishing) listener?.onLevel(rmsdB)
        }

        override fun onBufferReceived(buffer: ByteArray?) = Unit

        override fun onEndOfSpeech() = Unit

        override fun onPartialResults(partialResults: Bundle?) = heard(partialResults)

        override fun onResults(results: Bundle?) {
            heard(results)
            sessionEnded()
        }

        /** Android 13 and later, a segmented session: one finished segment. Its words stay; the next ones follow. */
        override fun onSegmentResults(segmentResults: Bundle) {
            heard(segmentResults, segment = true)
            transcript.commit()
        }

        override fun onEndOfSegmentedSession() = sessionEnded()

        override fun onError(error: Int) = failed(error)

        override fun onEvent(eventType: Int, params: Bundle?) = Unit
    }

    // MARK: The phone's language (Android 13 and later)

    private sealed class Language {
        data class Listen(val tag: String) : Language()
        data class Blocked(val start: VoiceCapture.Start) : Language()
    }

    /** Whether the phone's language can be heard on the phone now; null when the service cannot say. */
    @RequiresApi(33)
    private suspend fun language(recognizer: SpeechRecognizer, tag: String): Language? {
        val support = support(recognizer, tag) ?: return null
        val installed = support.installedOnDeviceLanguages
        val pending = support.pendingOnDeviceLanguages
        val supported = support.supportedOnDeviceLanguages
        return when (SpeechLanguage.availability(tag, installed, pending, supported)) {
            SpeechLanguage.Availability.INSTALLED -> Language.Listen(SpeechLanguage.bestTag(tag, installed))
            SpeechLanguage.Availability.DOWNLOADING -> Language.Blocked(VoiceCapture.Start.DOWNLOADING)
            SpeechLanguage.Availability.DOWNLOADABLE -> {
                download(baseIntent(SpeechLanguage.bestTag(tag, supported)))
                Language.Blocked(VoiceCapture.Start.DOWNLOADING)
            }
            SpeechLanguage.Availability.UNSUPPORTED -> Language.Blocked(VoiceCapture.Start.UNAVAILABLE)
        }
    }

    @RequiresApi(33)
    private suspend fun support(recognizer: SpeechRecognizer, tag: String): RecognitionSupport? =
        withTimeoutOrNull(SUPPORT_TIMEOUT_MS) {
            suspendCancellableCoroutine<RecognitionSupport?> { continuation ->
                recognizer.checkRecognitionSupport(
                    baseIntent(tag),
                    ContextCompat.getMainExecutor(context),
                    object : RecognitionSupportCallback {
                        override fun onSupportResult(recognitionSupport: RecognitionSupport) {
                            if (continuation.isActive) continuation.resume(recognitionSupport)
                        }

                        override fun onError(error: Int) {
                            if (continuation.isActive) continuation.resume(null)
                        }
                    },
                )
            }
        }

    /**
     * Asks the service to download the language "for next time": "This might trigger user interaction to approve the
     * download" (https://developer.android.com/reference/android/speech/SpeechRecognizer#triggerModelDownload(android.content.Intent)).
     */
    @RequiresApi(33)
    private fun download(intent: Intent) {
        try {
            recognizer?.triggerModelDownload(intent)
        } catch (e: RuntimeException) {
            // The service may not support downloads: the blocker still offers typing.
        }
    }

    private fun baseIntent(tag: String): Intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
        .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        .putExtra(RecognizerIntent.EXTRA_LANGUAGE, tag)

    private fun listeningIntent(tag: String, vocabulary: List<String>): Intent {
        val intent = baseIntent(tag)
            .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        if (Build.VERSION.SDK_INT >= 33) android13Extras(intent, vocabulary)
        return intent
    }

    @RequiresApi(33)
    private fun android13Extras(intent: Intent, vocabulary: List<String>) {
        // Quality over latency: the full stops decide the lines a note is saved as. [Own choice]
        intent.putExtra(RecognizerIntent.EXTRA_ENABLE_FORMATTING, RecognizerIntent.FORMATTING_OPTIMIZE_QUALITY)
        intent.putExtra(RecognizerIntent.EXTRA_SEGMENTED_SESSION, RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS)
        // "Optional integer to indicate the minimum length of the recognition session."
        intent.putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, LONGEST_NOTE_MS)
        if (vocabulary.isNotEmpty()) intent.putStringArrayListExtra(RecognizerIntent.EXTRA_BIASING_STRINGS, ArrayList(vocabulary))
    }

    companion object {
        /** The first callback of the first session must come within this; otherwise the microphone is taken. */
        const val START_TIMEOUT_MS = 5_000L

        /** `checkRecognitionSupport` may take a moment; past this Taken tries listening and lets an error say the rest. */
        const val SUPPORT_TIMEOUT_MS = 3_000L

        /** The last words follow the stop within a moment; never wait more than 2 s for them (the iPhone's number). */
        const val FINISH_TIMEOUT_MS = 2_000L

        /** A session shorter than this ended at once: the next waits [RESTART_DELAY_MS]. */
        const val QUICK_SESSION_MS = 500L
        const val RESTART_DELAY_MS = 300L

        /** A safety net: a recognizer that keeps ending at once is not restarted for ever (the iPhone's 200). */
        const val MAX_RESTARTS = 200

        /** One note is at most 5 minutes (TodoCapture.LONGEST_NOTE). */
        const val LONGEST_NOTE_MS = 300_000
    }
}
