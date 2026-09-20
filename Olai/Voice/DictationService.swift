import AVFoundation
import Foundation
import Observation
import Speech

/// Dictation using the system's own speech recognition, kept on-device.
///
/// `requiresOnDeviceRecognition` is set and not relaxed: if a locale has no on-device
/// model, dictation says so rather than quietly sending the audio to a server.
@MainActor
@Observable
final class DictationService {
    enum State: Equatable {
        case idle
        case starting
        case listening
        case failed(String)

        var isRunning: Bool { self == .starting || self == .listening }
    }

    private(set) var state: State = .idle

    /// Called with each new piece of recognised text, ready to insert.
    var onText: ((String) -> Void)?

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: .current)
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    /// What has already been inserted for this utterance, so only the new tail goes in.
    @ObservationIgnored private var inserted = ""

    func toggle() async {
        state.isRunning ? stop() : await start()
    }

    func start() async {
        guard !state.isRunning else { return }
        state = .starting
        inserted = ""

        guard let recognizer, recognizer.isAvailable else {
            state = .failed("Speech recognition is not available on this device.")
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            state = .failed("No on-device speech model for \(recognizer.locale.identifier). Add the language in System Settings › Keyboard › Dictation.")
            return
        }
        guard await authorize() else { return }

        do {
            try beginListening(with: recognizer)
            state = .listening
        } catch {
            stop()
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if state.isRunning { state = .idle }
    }

    // MARK: Plumbing

    private func authorize() async -> Bool {
        guard await Self.speechAuthorization() == .authorized else {
            state = .failed("Olai needs permission to use speech recognition. Grant it in System Settings › Privacy & Security › Speech Recognition.")
            return false
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            state = .failed("Olai needs permission to use the microphone.")
            return false
        }
        return true
    }

    /// Deliberately outside the main actor.
    ///
    /// These callbacks arrive on the system's own queues -- TCC's reply queue here, the
    /// audio thread for the tap, a recognition queue for results. A closure written
    /// inside a `@MainActor` type is isolated to the main actor, and Swift 6 asserts
    /// that at the point it runs: the app trapped the instant the permission sheet was
    /// answered. Everything that the system calls back on is `nonisolated` or
    /// `@Sendable`, and hops to the main actor itself.
    private nonisolated static func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }

    private func beginListening(with recognizer: SFSpeechRecognizer) throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        try Self.startCapturing(with: engine, into: request)
        task = Self.startRecognizing(with: recognizer, request: request, reporting: self)
    }

    /// Installs the microphone tap. Written here, outside the actor, because the tap
    /// block runs on the audio thread: a block written inside this `@MainActor` class is
    /// isolated to the main actor and traps as soon as audio arrives.
    private nonisolated static func startCapturing(
        with engine: AVAudioEngine,
        into request: SFSpeechAudioBufferRecognitionRequest
    ) throws {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    /// Likewise: results arrive on the recogniser's own queue. Only plain values cross
    /// back to the main actor.
    private nonisolated static func startRecognizing(
        with recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        reporting service: DictationService
    ) -> SFSpeechRecognitionTask {
        nonisolated(unsafe) let target = service
        return recognizer.recognitionTask(with: request) { result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil

            Task { @MainActor in
                target.receive(transcript: transcript, isFinal: isFinal, failed: failed)
            }
        }
    }

    private func receive(transcript: String?, isFinal: Bool, failed: Bool) {
        if let transcript {
            emit(transcript)
            if isFinal { inserted = "" }
        }
        // A recognition error ends the utterance; the user can start again.
        if failed { stop() }
    }

    /// Results arrive as the whole utterance so far, so only what is new is inserted.
    private func emit(_ transcript: String) {
        guard transcript != inserted else { return }

        if transcript.hasPrefix(inserted) {
            let tail = String(transcript.dropFirst(inserted.count))
            inserted = transcript
            if !tail.isEmpty { onText?(tail) }
        } else {
            // The recogniser revised what it heard; start a fresh run rather than
            // trying to retract text the user may already have edited.
            inserted = transcript
            onText?(" " + transcript)
        }
    }
}
