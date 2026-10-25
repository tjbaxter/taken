package com.tombaxter.taken.voice

/**
 * One voice note's words, heard on the phone (SPEC-ANDROID 11): the seam between the To-do tab and Android's on-device
 * recognizer ([OnDeviceSpeechCapture]), so the tab's rules run in tests with a fake. The iPhone's `SpeechCapture` with its
 * `SpeechCaptureEvent`s, in Android's shape: events come to a [Listener] on the main thread.
 */
interface VoiceCapture {
    /** What a running capture reports, in order, on the main thread. */
    interface Listener {
        /** Everything heard so far in this note. */
        fun onText(text: String)

        /** The latest level from `RecognitionListener.onRmsChanged`, on the recognizer's own scale. */
        fun onLevel(rms: Float)

        /** The microphone went away mid-note (a call, another app, the recognizer failed): the words so far are kept. */
        fun onInterrupted()
    }

    /** How starting went. */
    enum class Start {
        /** Listening. */
        LISTENING,

        /** No on-device recognition for the phone's language, or below Android 12: type it instead. */
        UNAVAILABLE,

        /** The phone's language is being downloaded for on-device recognition (Android 13 and later): type it for now. */
        DOWNLOADING,

        /** Another app has the microphone or the recognizer. */
        BUSY,

        /** RECORD_AUDIO is not granted. */
        NO_PERMISSION,
    }

    /**
     * Starts listening in `languageTag` (BCP 47), with `vocabulary` as the names to expect. Never sends audio anywhere:
     * on-device recognition only.
     */
    suspend fun start(languageTag: String, vocabulary: List<String>, listener: Listener): Start

    /** Stops the microphone and returns everything heard, once the recognizer has finished the last words. */
    suspend fun finish(): String

    /** Stops without a result (Erase all data mid-note, a failed start). */
    fun cancel()
}

/**
 * What the To-do tab asks of Android for the microphone (SPEC-ANDROID 11): the RECORD_AUDIO state, Android's prompt, the
 * app's settings page, and a capture. [com.tombaxter.taken.MainActivity] is the real one; tests and captures fake it.
 */
interface VoiceHost {
    /** RECORD_AUDIO is granted. */
    val microphoneGranted: Boolean

    /**
     * Android says a rationale is due before asking again (`shouldShowRequestPermissionRationale`,
     * https://developer.android.com/training/permissions/requesting): Taken shows its sentence with Continue and Not now.
     */
    val microphoneRationaleDue: Boolean

    /** Shows Android's microphone prompt. The answer comes back to `TodoModel.microphoneAnswered`. */
    fun requestMicrophone()

    /** The app's page in Settings, where the microphone is turned back on (SPEC-ANDROID 6.3). */
    fun openAppSettings()

    /** A new capture for one note. */
    fun newVoiceCapture(): VoiceCapture

    companion object {
        /** No microphone at all (tests, captures): every start says so. */
        val none: VoiceHost = object : VoiceHost {
            override val microphoneGranted = false
            override val microphoneRationaleDue = false
            override fun requestMicrophone() = Unit
            override fun openAppSettings() = Unit
            override fun newVoiceCapture(): VoiceCapture = object : VoiceCapture {
                override suspend fun start(languageTag: String, vocabulary: List<String>, listener: VoiceCapture.Listener) =
                    VoiceCapture.Start.UNAVAILABLE
                override suspend fun finish() = ""
                override fun cancel() = Unit
            }
        }
    }
}
