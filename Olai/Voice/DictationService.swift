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
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            state = .failed("Olai needs permission to use speech recognition. Grant it in System Settings › Privacy & Security › Speech Recognition.")
            return false
        }

        let microphone = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
        }
        guard microphone else {
            state = .failed("Olai needs permission to use the microphone.")
            return false
        }
        return true
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

        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.emit(result.bestTranscription.formattedString)
                    if result.isFinal { self.inserted = "" }
                }
                if error != nil {
                    // A recognition error ends the utterance; the user can start again.
                    self.stop()
                }
            }
        }
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
