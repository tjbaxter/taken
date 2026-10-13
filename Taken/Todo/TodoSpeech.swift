import AVFoundation
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

/// What a running capture reports, in order, on the main actor.
enum SpeechCaptureEvent: Sendable {
    /// Everything heard so far.
    case text(String)
    /// The latest input level in dBFS (about -80 quiet to 0 loud).
    case level(Float)
    /// A call, Siri or a route change stopped the microphone.
    case interrupted
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
        do {
            let backend = try await Self.makeBackend(locale: locale, inputFormat: format, onText: onText)
            lock.withLock { self.backend = backend }
            relay.attach { buffer in backend.append(buffer) }
        } catch {
            audio.stop()
            relay.detach()
            continuation.finish()
            throw error
        }
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

    private static func makeBackend(locale: Locale, inputFormat: AVAudioFormat,
                                    onText: @escaping @Sendable (String) -> Void) async throws -> any SpeechBackend {
        if #available(iOS 26.0, *) {
            if let analyzer = try? await AnalyzerBackend.make(locale: locale, inputFormat: inputFormat, onText: onText) {
                return analyzer
            }
        }
        if let recognizer = RecognizerBackend(locale: locale, onText: onText) {
            return recognizer
        }
        throw SpeechCaptureError.unavailable
    }
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
}

/// The words so far: finished phrases plus the phrase still being heard.
final class TranscriptBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = ""
    private var volatile = ""

    var text: String {
        lock.withLock { TranscriptBuffer.join(finished, volatile) }
    }

    /// A finished phrase replaces whatever was still being heard.
    func commit(_ phrase: String) -> String {
        lock.withLock {
            finished = TranscriptBuffer.join(finished, phrase)
            volatile = ""
            return finished
        }
    }

    func setVolatile(_ phrase: String) -> String {
        lock.withLock {
            volatile = phrase
            return TranscriptBuffer.join(finished, volatile)
        }
    }

    /// The whole transcript at once (SFSpeechRecognizer reports it whole).
    func replace(_ whole: String) -> String {
        lock.withLock {
            finished = whole
            volatile = ""
            return finished
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
    private let lock = NSLock()
    private var results: Task<Void, Never>?

    private init(analyzer: SpeechAnalyzer, input: AsyncStream<AnalyzerInput>.Continuation, converter: FormatConverter) {
        self.analyzer = analyzer
        self.input = input
        self.converter = converter
    }

    /// Nil-free or throws: the language must be supported and its model already on the phone. A missing model starts
    /// downloading for next time and this note uses SFSpeechRecognizer.
    static func make(locale: Locale, inputFormat: AVAudioFormat,
                     onText: @escaping @Sendable (String) -> Void) async throws -> AnalyzerBackend {
        guard SpeechTranscriber.isAvailable,
              let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw SpeechCaptureError.unavailable
        }
        let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [],
                                            reportingOptions: [.volatileResults, .fastResults], attributeOptions: [])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            let pending = UncheckedSendable(request)
            Task.detached(priority: .utility) { try? await pending.value.downloadAndInstall() }
            throw SpeechCaptureError.unavailable
        }
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]),
              let converter = FormatConverter(from: inputFormat, to: analyzerFormat) else {
            throw SpeechCaptureError.unavailable
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (stream, continuation) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let backend = AnalyzerBackend(analyzer: analyzer, input: continuation, converter: converter)
        let transcript = backend.transcript
        backend.results = Task.detached(priority: .userInitiated) {
            do {
                for try await result in transcriber.results {
                    let phrase = String(result.text.characters)
                    onText(result.isFinal ? transcript.commit(phrase) : transcript.setVolatile(phrase))
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
            throw SpeechCaptureError.unavailable
        }
        return backend
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

/// iOS 17 to 25 (and iOS 26 before its model is on the phone): SFSpeechRecognizer, on the device only.
final class RecognizerBackend: SpeechBackend, @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let transcript = TranscriptBuffer()
    private let lock = NSLock()
    private var task: SFSpeechRecognitionTask?
    private var done = false

    /// Nil when this iPhone cannot recognise the language on the device: audio is never sent to a server.
    init?(locale: Locale, onText: @escaping @Sendable (String) -> Void) {
        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(),
              recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { return nil }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        self.recognizer = recognizer
        self.request = request
        let transcript = self.transcript
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                onText(transcript.replace(result.bestTranscription.formattedString))
            }
            if error != nil || result?.isFinal == true {
                self?.markDone()
            }
        }
        lock.withLock { self.task = task }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
    }

    func finish() async -> String {
        request.endAudio()
        // The final result follows the end of the audio within a moment; never wait more than 2 s for it.
        for _ in 0..<20 {
            if lock.withLock({ done }) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        lock.withLock { task?.cancel() }
        return transcript.text
    }

    func cancel() {
        request.endAudio()
        lock.withLock { task?.cancel() }
    }

    private func markDone() {
        lock.withLock { done = true }
    }
}
