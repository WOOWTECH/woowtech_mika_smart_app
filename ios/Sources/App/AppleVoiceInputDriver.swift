#if os(iOS) && canImport(Speech) && canImport(AVFoundation)
import Foundation
import Speech
import AVFoundation

/// iOS 17 system recognizer adapter. Intentionally not connected to the UI.
/// No provider fallback: if on-device recognition is unavailable, fail closed.
/// The host must cancel when its chat is hidden or scene becomes inactive.
@MainActor
final class AppleVoiceInputDriver: VoiceInputDriver {
    private var id: UUID?
    private var emit: ((UUID, VoiceInputEvent) -> Void)?
    private var engine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var deadline: DispatchWorkItem?
    private var interruptionObserver: NSObjectProtocol?
    private var audioSessionStarted = false
    private var previousAudio: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
    private var finishing = false
    private let locale: Locale

    init(locale: Locale = .current) { self.locale = locale }

    func start(id: UUID, emit: @escaping (UUID, VoiceInputEvent) -> Void) {
        if let old = self.id { cancel(id: old) }
        self.id = id
        self.emit = emit
        finishing = false
        // This deadline includes permission prompts, so a forgotten gesture
        // cannot start or continue recording indefinitely.
        scheduleDeadline(id: id, seconds: 60)
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async { self?.speechAuthorization(status, id: id) }
        }
    }

    private func speechAuthorization(_ status: SFSpeechRecognizerAuthorizationStatus, id: UUID) {
        guard self.id == id, !finishing else { return }
        switch status {
        case .authorized:
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async { self?.microphoneAuthorization(granted, id: id) }
            }
        case .denied: fail(.speechDenied, id: id)
        case .restricted: fail(.speechRestricted, id: id)
        case .notDetermined: fail(.unavailable, id: id)
        @unknown default: fail(.unavailable, id: id)
        }
    }

    private func microphoneAuthorization(_ granted: Bool, id: UUID) {
        guard self.id == id, !finishing else { return }
        guard granted else { fail(.microphoneDenied, id: id); return }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else { fail(.unavailable, id: id); return }
        self.recognizer = recognizer
        let audio = AVAudioSession.sharedInstance()
        previousAudio = (audio.category, audio.mode, audio.categoryOptions)
        do {
            try audio.setCategory(.record, mode: .measurement, options: [])
            try audio.setActive(true)
            audioSessionStarted = true
            let newEngine = AVAudioEngine()
            let input = newEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                fail(.audio, id: id); return
            }
            let newRequest = SFSpeechAudioBufferRecognitionRequest()
            newRequest.requiresOnDeviceRecognition = true
            newRequest.shouldReportPartialResults = true
            engine = newEngine
            request = newRequest
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                newRequest.append(buffer)
            }
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification, object: audio, queue: .main
            ) { [weak self] notification in
                guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      raw == AVAudioSession.InterruptionType.began.rawValue else { return }
                DispatchQueue.main.async { self?.fail(.audio, id: id) }
            }
            task = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal == true
                DispatchQueue.main.async { self?.recognitionResult(text, final: final, failed: error != nil, id: id) }
            }
            newEngine.prepare()
            try newEngine.start()
        } catch {
            fail(.audio, id: id)
        }
    }

    private func recognitionResult(_ text: String?, final: Bool, failed: Bool, id: UUID) {
        guard self.id == id else { return }
        if final {
            deliver(.final(text ?? ""), id: id)
        } else if failed {
            fail(.recognition, id: id)
        } else if let text, !finishing {
            emit?(id, .partial(text))
        }
    }

    func finish(id: UUID) {
        guard self.id == id, !finishing else { return }
        finishing = true
        guard let engine, let request else {
            // Permission prompt still open: it must never start recording later.
            deliver(.final(""), id: id)
            return
        }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        self.engine = nil
        request.endAudio()
        self.request = nil
        scheduleDeadline(id: id, seconds: 5)
    }

    func cancel(id: UUID) {
        guard self.id == id else { return }
        cleanup()
    }

    private func scheduleDeadline(id: UUID, seconds: TimeInterval) {
        deadline?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.fail(.timeout, id: id) }
        deadline = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func fail(_ error: VoiceInputFailure, id: UUID) { deliver(.failed(error), id: id) }

    private func deliver(_ event: VoiceInputEvent, id: UUID) {
        guard self.id == id else { return }
        let callback = emit
        cleanup()
        callback?(id, event)
    }

    private func cleanup() {
        id = nil
        emit = nil
        deadline?.cancel(); deadline = nil
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
        recognizer = nil
        let audio = AVAudioSession.sharedInstance()
        if audioSessionStarted { try? audio.setActive(false, options: .notifyOthersOnDeactivation) }
        audioSessionStarted = false
        if let previousAudio {
            try? audio.setCategory(previousAudio.0, mode: previousAudio.1, options: previousAudio.2)
        }
        previousAudio = nil
        finishing = false
    }
}
#endif
