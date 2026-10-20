import AVFoundation
import CoreMedia
import Foundation
import Speech

// Speech to text on the iPhone (REDESIGN.md: audio is never stored or uploaded).
// iOS 26: SpeechAnalyzer with a SpeechTranscriber module. iOS 17 to 25 (or when the iOS 26 model for the language is
// not on the phone yet): SFSpeechRecognizer with requiresOnDeviceRecognition. No path sends audio anywhere: with
// neither on-device engine available, voice capture says so and offers typing instead.
//
// Threading: the microphone tap runs on a real-time audio thread, so everything it touches lives in the nonisolated,
// lock-guarded types below and reaches the main actor only as Sendable values through one AsyncStream of events.

enum SpeechCaptureError: Error, Equatable, Sendable {
    /// No input device (the simulator in CI) or the engine would not start.
    case noMicrophone
    /// Neither on-device engine can transcribe this language on this iPhone.
    case unavailable
}

/// What a running capture reports, in order, on the main actor. The stream keeps only the newest events, so nothing
/// that must not be lost travels here: the finished words a long note is cut from stay in the capture's lock-guarded
/// transcript (`SpeechCapture.finishedText()`).
enum SpeechCaptureEvent: Sendable {
    /// Everything heard so far.
    case text(String)
    /// The latest input level in dBFS (about -80 quiet to 0 loud).
    case level(Float)
    /// A call, Siri or a route change stopped the microphone.
    case interrupted
}

/// Which transcriber heard a note.
enum SpeechEngine: String, Codable, Sendable {
    /// iOS 26: SpeechAnalyzer with SpeechTranscriber. Its finished phrases come while the person talks, so a long
    /// note is sorted part by part as it is said.
    case analyzer = "SpeechAnalyzer"
    /// iOS 17 to 25, or iOS 26 before its model is on the phone.
    case recognizer = "SFSpeechRecognizer"
}

/// A finished phrase and the audio it came from, in seconds from the start (SpeechTranscriber's result range).
struct TimedPhrase: Codable, Hashable, Sendable {
    var text: String
    var start: Double
    var end: Double
}

/// SFSpeechRecognizer starting over mid-note: what the text was, and the shorter result that did not continue it.
struct TranscriptReset: Codable, Hashable, Sendable {
    /// Seconds from the start.
    var at: Double
    var before: String
    var after: String
}

/// What the internal voice note log records about the transcriber. Never audio.
struct SpeechDiagnostics: Sendable {
    var engine: SpeechEngine
    /// Why not SpeechAnalyzer, when it was not.
    var why: String?
    var phrases: [TimedPhrase] = []
    var resets: [TranscriptReset] = []
    /// SFSpeechRecognizer tasks that ended by themselves mid-note and were started again.
    var restarts = 0
    var vocabulary = 0
}

// MARK: - Permissions

enum VoicePermission: Equatable, Sendable {
    case granted
    case microphoneDenied
    case speechDenied
}

/// Microphone and speech recognition permission. Nonisolated on purpose: the system calls the speech authorization
/// handler on a background queue, and a main-actor closure there would trap.
enum VoicePermissions {
    nonisolated static func current() -> VoicePermission? {
        switch AVAudioApplication.shared.recordPermission {
        case .denied: return .microphoneDenied
        case .undetermined: return nil
        default: break
        }
        switch SFSpeechRecognizer.authorizationStatus() {
        case .denied, .restricted: return .speechDenied
        case .authorized: return .granted
        default: return nil
        }
    }

    /// Asks for whatever has not been answered yet: the microphone first, then speech recognition.
    nonisolated static func request() async -> VoicePermission {
        var microphone = AVAudioApplication.shared.recordPermission
        if microphone == .undetermined {
            microphone = await AVAudioApplication.requestRecordPermission() ? .granted : .denied
        }
        guard microphone == .granted else { return .microphoneDenied }
        var speech = SFSpeechRecognizer.authorizationStatus()
        if speech == .notDetermined {
            speech = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
                SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status) }
            }
        }
        return speech == .authorized ? .granted : .speechDenied
    }
}

// MARK: - Capture

/// One voice note: the microphone, an on-device transcriber, and the events the To-do tab draws from. Its work runs
/// off the main actor; the To-do tab only calls it and reads `events`.
final class SpeechCapture: @unchecked Sendable {
    let events: AsyncStream<SpeechCaptureEvent>
    private let continuation: AsyncStream<SpeechCaptureEvent>.Continuation
    private let audio = AudioInput()
    private let relay = BufferRelay()
    private let lock = NSLock()
    private var backend: (any SpeechBackend)?
    private var finalDiagnostics: SpeechDiagnostics?

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: SpeechCaptureEvent.self,
                                                            bufferingPolicy: .bufferingNewest(64))
        events = stream
        self.continuation = continuation
    }

    /// Starts the microphone at once (nothing said while the transcriber loads is lost: the relay holds it), then the
    /// best on-device transcriber for the language.
    func start(locale: Locale) async throws {
        let continuation = self.continuation
        let format = try audio.prepare()
        try audio.start(relay: relay,
                        onLevel: { continuation.yield(.level($0)) },
                        onInterruption: { continuation.yield(.interrupted) })
        let onText: @Sendable (String) -> Void = { continuation.yield(.text($0)) }
        // The names this person is likely to say, read now that the microphone is on and the relay holds what is said.
        let vocabulary = TranscriptionVocabulary.current()
        do {
            let backend = try await Self.makeBackend(locale: locale, inputFormat: format, vocabulary: vocabulary,
                                                     onText: onText)
            lock.withLock { self.backend = backend }
            relay.attach { buffer in backend.append(buffer) }
        } catch {
            audio.stop()
            relay.detach()
            continuation.finish()
            throw error
        }
    }

    /// The transcriber in use, once started.
    var engine: SpeechEngine? { lock.withLock { backend?.diagnostics.engine } }

    /// The words finished so far (SpeechAnalyzer's finalized phrases; nothing on SFSpeechRecognizer, whose notes are
    /// cut at the stop). Read from the lock-guarded transcript, so no event the stream dropped can cost a word.
    func finishedText() -> String {
        lock.withLock { backend }?.finishedText ?? ""
    }

    /// The transcriber's record of this note, for the internal voice note log: kept after `finish`.
    func diagnostics() -> SpeechDiagnostics? {
        lock.withLock { backend?.diagnostics ?? finalDiagnostics }
    }

    /// Stops the microphone and returns the whole transcript once the transcriber has finished it.
    func finish() async -> String {
        audio.stop()
        relay.detach()
        let backend = lock.withLock { () -> (any SpeechBackend)? in
            defer { self.backend = nil }
            return self.backend
        }
        let text = await backend?.finish() ?? ""
        if let diagnostics = backend?.diagnostics { lock.withLock { finalDiagnostics = diagnostics } }
        continuation.finish()
        return text
    }

    /// Stops without a result.
    func cancel() {
        audio.stop()
        relay.detach()
        let backend = lock.withLock { () -> (any SpeechBackend)? in
            defer { self.backend = nil }
            return self.backend
        }
        backend?.cancel()
        continuation.finish()
    }

    private static func makeBackend(locale: Locale, inputFormat: AVAudioFormat, vocabulary: [String],
                                    onText: @escaping @Sendable (String) -> Void) async throws -> any SpeechBackend {
        var why = "iOS 17 to 25"
        if #available(iOS 26.0, *) {
            do {
                return try await AnalyzerBackend.make(locale: locale, inputFormat: inputFormat, vocabulary: vocabulary,
                                                      onText: onText)
            } catch let reason as AnalyzerUnavailable {
                why = reason.rawValue
            } catch {
                why = AnalyzerUnavailable.startFailed.rawValue
            }
        }
        if let recognizer = RecognizerBackend(locale: locale, vocabulary: vocabulary, why: why, onText: onText) {
            return recognizer
        }
        throw SpeechCaptureError.unavailable
    }
}

/// Why a note on iOS 26 used SFSpeechRecognizer instead of SpeechAnalyzer, in words for the log.
enum AnalyzerUnavailable: String, Error, Sendable {
    case notAvailable = "SpeechTranscriber is not available on this iPhone"
    case language = "SpeechTranscriber does not support this language"
    case modelMissing = "the iOS 26 speech model is not on this iPhone yet"
    case noFormat = "no audio format for SpeechAnalyzer"
    case startFailed = "SpeechAnalyzer would not start"
}

// MARK: - Microphone

/// AVAudioEngine's input with a tap. Its methods run off the main actor's isolation, so the tap block is never
/// treated as main-actor code.
final class AudioInput: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var observers: [any NSObjectProtocol] = []
    private var running = false

    /// Activates a recording session and returns the microphone's format.
    func prepare() throws -> AVAudioFormat {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        // The tap on the mic and the stop still get their haptics while recording.
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(true)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            throw SpeechCaptureError.noMicrophone
        }
        return format
    }

    func start(relay: BufferRelay, onLevel: @escaping @Sendable (Float) -> Void,
               onInterruption: @escaping @Sendable () -> Void) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            relay.push(buffer)
            onLevel(AudioInput.level(of: buffer))
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            throw SpeechCaptureError.noMicrophone
        }
        let center = NotificationCenter.default
        let interruption = center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { note in
            // Only a call or Siri taking the microphone; the end of someone else's interruption is not ours to act on.
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            onInterruption()
        }
        let change = center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { _ in
            onInterruption()
        }
        lock.withLock {
            observers = [interruption, change]
            running = true
        }
    }

    func stop() {
        let (wasRunning, observers) = lock.withLock { () -> (Bool, [any NSObjectProtocol]) in
            let snapshot = (running, self.observers)
            running = false
            self.observers = []
            return snapshot
        }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        guard wasRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // Music or a podcast that was ducked comes back.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// RMS level of the first channel in dBFS.
    static func level(of buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return -160 }
        var sum: Float = 0
        if let channel = buffer.floatChannelData?[0] {
            for index in 0..<frames { sum += channel[index] * channel[index] }
        } else if let channel = buffer.int16ChannelData?[0] {
            for index in 0..<frames {
                let sample = Float(channel[index]) / Float(Int16.max)
                sum += sample * sample
            }
        } else {
            return -160
        }
        let rms = (sum / Float(frames)).squareRoot()
        return rms > 0 ? 20 * log10(rms) : -160
    }
}

/// A value handed to another task that only that task uses afterwards.
final class UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// Carries microphone buffers to the transcriber. Until the transcriber is ready it keeps copies (a few seconds at
/// most), then hands them over in order.
final class BufferRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [AVAudioPCMBuffer] = []
    private var sink: (@Sendable (AVAudioPCMBuffer) -> Void)?
    private var closed = false
    /// About 10 s of 1024-frame buffers at 48 kHz.
    private let maxPending = 480

    func push(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        if closed {
            lock.unlock()
            return
        }
        if let sink {
            lock.unlock()
            sink(buffer)
            return
        }
        if pending.count < maxPending, let copy = BufferRelay.copy(buffer) { pending.append(copy) }
        lock.unlock()
    }

    func attach(_ sink: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
        lock.lock()
        let held = pending
        pending = []
        for buffer in held { sink(buffer) }
        self.sink = closed ? nil : sink
        lock.unlock()
    }

    func detach() {
        lock.withLock {
            closed = true
            sink = nil
            pending = []
        }
    }

    /// The tap's buffer may be reused once the tap returns, so held buffers are copies.
    static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let target = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (from, to) in zip(source, target) {
            guard let fromData = from.mData, let toData = to.mData else { continue }
            let bytes = Int(min(from.mDataByteSize, to.mDataByteSize))
            toData.copyMemory(from: fromData, byteCount: bytes)
        }
        return copy
    }
}

// MARK: - Transcribers

protocol SpeechBackend: AnyObject, Sendable {
    /// Every microphone buffer, on the audio thread.
    func append(_ buffer: AVAudioPCMBuffer)
    /// No more audio: finish the transcript and return all of it.
    func finish() async -> String
    func cancel()
    /// The words finished so far, which a long note's parts are cut from while it is said.
    var finishedText: String { get }
    var diagnostics: SpeechDiagnostics { get }
}

/// The words so far: finished phrases plus the phrase still being heard. Finished phrases are only ever added to, so
/// the parts of a long note cut from them never change under it.
final class TranscriptBuffer: @unchecked Sendable {
    /// The log keeps at most this many timed phrases.
    static let maxPhrases = 300

    private let lock = NSLock()
    private var finished = ""
    private var volatile = ""
    private var phrases: [TimedPhrase] = []

    var text: String {
        lock.withLock { TranscriptBuffer.join(finished, volatile) }
    }

    var finishedText: String {
        lock.withLock { finished }
    }

    var timedPhrases: [TimedPhrase] {
        lock.withLock { phrases }
    }

    /// A finished phrase replaces whatever was still being heard. Returns the whole text so far.
    func commit(_ phrase: String, start: Double? = nil, end: Double? = nil) -> String {
        lock.withLock {
            finished = TranscriptBuffer.join(finished, phrase)
            volatile = ""
            if let start, let end, phrases.count < TranscriptBuffer.maxPhrases {
                phrases.append(TimedPhrase(text: phrase, start: start, end: end))
            }
            return finished
        }
    }

    func setVolatile(_ phrase: String) -> String {
        lock.withLock {
            volatile = phrase
            return TranscriptBuffer.join(finished, volatile)
        }
    }

    static func join(_ head: String, _ tail: String) -> String {
        let a = head.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = tail.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }
}

/// iOS 26: SpeechAnalyzer and SpeechTranscriber, fully on the iPhone.
@available(iOS 26.0, *)
final class AnalyzerBackend: SpeechBackend, @unchecked Sendable {
    private let analyzer: SpeechAnalyzer
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let converter: FormatConverter
    private let transcript = TranscriptBuffer()
    private let vocabularyCount: Int
    private let lock = NSLock()
    private var results: Task<Void, Never>?

    private init(analyzer: SpeechAnalyzer, input: AsyncStream<AnalyzerInput>.Continuation, converter: FormatConverter,
                 vocabularyCount: Int) {
        self.analyzer = analyzer
        self.input = input
        self.converter = converter
        self.vocabularyCount = vocabularyCount
    }

    /// Nil-free or throws why not: the language must be supported and its model already on the phone. A missing
    /// model starts downloading for next time and this note uses SFSpeechRecognizer.
    static func make(locale: Locale, inputFormat: AVAudioFormat, vocabulary: [String] = [],
                     onText: @escaping @Sendable (String) -> Void) async throws -> AnalyzerBackend {
        guard SpeechTranscriber.isAvailable else { throw AnalyzerUnavailable.notAvailable }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw AnalyzerUnavailable.language
        }
        let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [],
                                            reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            let pending = UncheckedSendable(request)
            Task.detached(priority: .utility) { try? await pending.value.downloadAndInstall() }
            throw AnalyzerUnavailable.modelMissing
        }
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]),
              let converter = FormatConverter(from: inputFormat, to: analyzerFormat) else {
            throw AnalyzerUnavailable.noFormat
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        await expect(vocabulary, on: analyzer)
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let backend = AnalyzerBackend(analyzer: analyzer, input: continuation, converter: converter,
                                      vocabularyCount: vocabulary.count)
        let transcript = backend.transcript
        backend.results = Task.detached(priority: .userInitiated) {
            do {
                for try await result in transcriber.results {
                    let phrase = String(result.text.characters)
                    guard result.isFinal else {
                        onText(transcript.setVolatile(phrase))
                        continue
                    }
                    // A finalized result covers its own stretch of audio (WWDC25 277); its range is kept for the log.
                    let start = CMTimeGetSeconds(result.range.start)
                    let end = CMTimeGetSeconds(CMTimeRangeGetEnd(result.range))
                    onText(transcript.commit(phrase, start: start.isFinite ? start : nil, end: end.isFinite ? end : nil))
                }
            } catch {
                // The analyzer finished with an error: what was heard stays.
            }
        }
        do {
            try await analyzer.start(inputSequence: stream)
        } catch {
            continuation.finish()
            backend.results?.cancel()
            throw AnalyzerUnavailable.startFailed
        }
        return backend
    }

    var finishedText: String { transcript.finishedText }

    var diagnostics: SpeechDiagnostics {
        SpeechDiagnostics(engine: .analyzer, why: nil, phrases: transcript.timedPhrases, vocabulary: vocabularyCount)
    }

    /// The names to expect, as the analyzer's contextual strings (AnalysisContext, iOS 26). Apple's forum answer says
    /// SpeechTranscriber does not read contextual strings yet (DictationTranscriber does), so this may change nothing
    /// today; it costs nothing, waits at most 0.3 s, and a failure is ignored.
    private static func expect(_ vocabulary: [String], on analyzer: SpeechAnalyzer) async {
        guard !vocabulary.isEmpty else { return }
        let context = AnalysisContext()
        context.contextualStrings[.general] = vocabulary
        _ = await firstResult(of: { (try? await analyzer.setContext(context)) != nil }, orAfter: .milliseconds(300),
                              fallback: false)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let converted = converter.convert(buffer) else { return }
        input.yield(AnalyzerInput(buffer: converted))
    }

    func finish() async -> String {
        input.finish()
        let analyzer = self.analyzer
        let results = lock.withLock { self.results }
        // Finalize what is left, but never keep the person waiting more than a couple of seconds.
        _ = await firstResult(of: { try? await analyzer.finalizeAndFinishThroughEndOfInput(); return true },
                              orAfter: .seconds(2.5), fallback: false)
        _ = await firstResult(of: { _ = await results?.value; return true }, orAfter: .seconds(0.5), fallback: false)
        results?.cancel()
        return transcript.text
    }

    func cancel() {
        input.finish()
        let analyzer = self.analyzer
        lock.withLock { results?.cancel() }
        Task.detached { await analyzer.cancelAndFinishNow() }
    }
}

/// Converts microphone buffers to the transcriber's format, keeping state across buffers (resampling).
final class FormatConverter: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let output: AVAudioFormat

    init?(from input: AVAudioFormat, to output: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: input, to: output) else { return nil }
        self.converter = converter
        self.output = output
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if buffer.format == output { return buffer }
        let ratio = output.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return nil }
        let source = SourceOnce(buffer)
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if let next = source.take() {
                inputStatus.pointee = .haveData
                return next
            }
            inputStatus.pointee = .noDataNow
            return nil
        }
        guard status != .error, error == nil, out.frameLength > 0 else { return nil }
        return out
    }

    /// Hands one buffer to the converter, once.
    private final class SourceOnce: @unchecked Sendable {
        private var buffer: AVAudioPCMBuffer?

        init(_ buffer: AVAudioPCMBuffer) {
            self.buffer = buffer
        }

        func take() -> AVAudioPCMBuffer? {
            defer { buffer = nil }
            return buffer
        }
    }
}

/// iOS 17 to 25 (and iOS 26 before its model is on the phone): SFSpeechRecognizer, on the device only. Two things keep
/// every word of a long note: the text survives the recogniser starting over after a pause (`RecognizerTranscript`),
/// and a recognition task that ends by itself mid-note (a final result or an error) is followed by a new one with the
/// same settings, which the next buffers go to.
final class RecognizerBackend: SpeechBackend, @unchecked Sendable {
    /// A safety net: a task that keeps ending at once (an error on every start) is not restarted for ever.
    static let maxRestarts = 200

    private let recognizer: SFSpeechRecognizer
    private let vocabulary: [String]
    private let why: String
    private let onText: @Sendable (String) -> Void
    private let started = Date()
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest
    private var task: SFSpeechRecognitionTask?
    private var taskStarted = Date()
    /// Which request the results are for: a late result from an ended task never lands in the new one's text.
    private var generation = 0
    private var transcript = RecognizerTranscript()
    private var resets: [TranscriptReset] = []
    private var restarts = 0
    private var finishing = false
    private var done = false

    /// Nil when this iPhone cannot recognise the language on the device: audio is never sent to a server.
    init?(locale: Locale, vocabulary: [String] = [], why: String = "iOS 17 to 25",
          onText: @escaping @Sendable (String) -> Void) {
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { return nil }
        self.recognizer = recognizer
        self.vocabulary = vocabulary
        self.why = why
        self.onText = onText
        self.request = Self.makeRequest(vocabulary: vocabulary)
        startTask()
    }

    /// On the device only, partial results, punctuation, dictation, and the names this person is likely to say (at
    /// most 100 short phrases, as Apple asks).
    private static func makeRequest(vocabulary: [String]) -> SFSpeechAudioBufferRecognitionRequest {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        request.contextualStrings = vocabulary
        return request
    }

    private func startTask() {
        let (request, generation) = lock.withLock { () -> (SFSpeechAudioBufferRecognitionRequest, Int) in
            taskStarted = Date()
            return (self.request, self.generation)
        }
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            self?.handle(result, ended: error != nil || result?.isFinal == true, generation: generation)
        }
        lock.withLock { if self.generation == generation { self.task = task } }
    }

    private func handle(_ result: SFSpeechRecognitionResult?, ended: Bool, generation: Int) {
        let (text, restartAfter) = lock.withLock { () -> (String?, Double?) in
            guard generation == self.generation else { return (nil, nil) }
            var text: String?
            if let result {
                let before = transcript.text
                let heard = result.bestTranscription.formattedString
                if transcript.apply(heard), resets.count < RecognizerTranscript.maxResets {
                    resets.append(TranscriptReset(at: Date().timeIntervalSince(started), before: before, after: heard))
                }
                text = transcript.text
            }
            guard ended else { return (text, nil) }
            transcript.commit()
            text = transcript.text
            guard !finishing, restarts < Self.maxRestarts else {
                done = true
                return (text, nil)
            }
            restarts += 1
            self.generation += 1
            request = Self.makeRequest(vocabulary: vocabulary)
            // A task that ended at once (an error on start) waits a moment, so it never spins.
            return (text, Date().timeIntervalSince(taskStarted) < 0.5 ? 0.3 : 0)
        }
        if let text { onText(text) }
        guard let restartAfter else { return }
        if restartAfter > 0 {
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + restartAfter) { [weak self] in
                self?.startTask()
            }
        } else {
            startTask()
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { request }.append(buffer)
    }

    func finish() async -> String {
        let request = lock.withLock { () -> SFSpeechAudioBufferRecognitionRequest in
            finishing = true
            return self.request
        }
        request.endAudio()
        // The final result follows the end of the audio within a moment; never wait more than 2 s for it.
        for _ in 0..<20 {
            if lock.withLock({ done }) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return lock.withLock { () -> String in
            task?.cancel()
            transcript.commit()
            return transcript.text
        }
    }

    func cancel() {
        let request = lock.withLock { () -> SFSpeechAudioBufferRecognitionRequest in
            finishing = true
            return self.request
        }
        request.endAudio()
        lock.withLock { task?.cancel() }
    }

    var finishedText: String { "" }

    var diagnostics: SpeechDiagnostics {
        lock.withLock {
            SpeechDiagnostics(engine: .recognizer, why: why, resets: resets, restarts: restarts,
                              vocabulary: vocabulary.count)
        }
    }
}

/// One note's words on SFSpeechRecognizer, kept when the recogniser starts over. On iOS 17 to 25 the on-device
/// recogniser can begin again after a pause of a second or two and report only the words since (Apple staff reproduced
/// it on iOS 17, forum 765609); the text so far stays, and the new words follow it. A start-over is told from the
/// text, not from partial results' timestamps, which Apple says are not accurate (forum 785389): a result no longer
/// than the longest text since the last start-over that does not continue it (its opening words are not that text's
/// opening words, compared in order), from a text of two words or more. Pure, so CI tests it.
/// https://developer.apple.com/forums/thread/765609
/// https://developer.apple.com/forums/thread/785389
struct RecognizerTranscript: Hashable, Sendable {
    /// The log keeps at most this many start-overs.
    static let maxResets = 50
    /// How many opening words are compared.
    static let compared = 8

    /// What earlier tasks and start-overs left.
    private(set) var committed = ""
    /// The longest text since the last start-over, and the latest result.
    private(set) var peak = ""
    private(set) var current = ""

    /// Everything heard, in order.
    var text: String { TranscriptBuffer.join(committed, tail) }

    /// Takes the latest result. True when it started over.
    @discardableResult
    mutating func apply(_ result: String) -> Bool {
        let next = Self.words(result)
        guard !next.isEmpty else { return false }
        let longest = Self.words(peak)
        // A start-over begins again with the new words, so it is never longer than the text before it. A longer result
        // that does not carry on the opening words is a revision of the whole result (iOS 18.1 and later report one
        // growing result: "Book a table" and then "Look at the table for six"), and replaces it.
        if longest.count >= 2, next.count <= longest.count, !Self.continues(longest, next) {
            committed = TranscriptBuffer.join(committed, peak)
            peak = result
            current = result
            return true
        }
        current = result
        if next.count >= longest.count { peak = result }
        return false
    }

    /// The task ended (a final result, an error, the stop): its words are kept, and the next task starts clean.
    mutating func commit() {
        committed = TranscriptBuffer.join(committed, tail)
        peak = ""
        current = ""
    }

    /// The words since the last start-over: the latest result, unless it is shorter than the longest and only
    /// matches its opening words loosely, which may be a start-over not seen yet ("I need milk" after "I need to call
    /// the dentist"): then both, so no word is lost.
    private var tail: String {
        let latest = Self.words(current)
        let longest = Self.words(peak)
        guard latest.count < longest.count else { return current }
        // The same opening words, revised at the end ("call the dentist to" and then "call the dentist").
        if Array(longest.prefix(latest.count)) == latest { return peak }
        if latest.count >= 4, Self.matched(latest, Array(longest.prefix(latest.count + 1))) >= latest.count - 1 {
            return current
        }
        return TranscriptBuffer.join(peak, current)
    }

    /// The new result carries on the text: at least half of the shorter one's opening words come, in order, in the
    /// longer one's opening words (two to spare for a word put in).
    static func continues(_ previous: [String], _ next: [String]) -> Bool {
        let (short, long) = next.count <= previous.count ? (next, previous) : (previous, next)
        let opening = Array(short.prefix(compared))
        let against = Array(long.prefix(opening.count + 2))
        return matched(opening, against) * 2 >= opening.count
    }

    /// The most words of `a` found in `b` in the same order (longest common subsequence).
    static func matched(_ a: [String], _ b: [String]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var row = Array(repeating: 0, count: b.count + 1)
        for x in a {
            var diagonal = 0
            for (j, y) in b.enumerated() {
                let above = row[j + 1]
                row[j + 1] = x == y ? diagonal + 1 : max(row[j], above)
                diagonal = above
            }
        }
        return row[b.count]
    }

    /// Lowercase words without punctuation.
    static func words(_ text: String) -> [String] {
        text.lowercased().split(whereSeparator: { $0.isWhitespace }).compactMap { word in
            let kept = word.filter { $0.isLetter || $0.isNumber }
            return kept.isEmpty ? nil : kept
        }
    }
}
