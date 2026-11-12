#if os(iOS) && canImport(Speech) && canImport(AVFoundation)
import Foundation
import Speech
import AVFoundation
import UIKit

/// iOS 17 system recognizer adapter, connected through the mixed-audio candidate.
/// No provider fallback: if on-device recognition is unavailable, fail closed.
/// The host must cancel when its chat is hidden or scene becomes inactive.
@MainActor
final class AppleVoiceInputDriver: VoiceInputDriver {
    private var id: UUID?
    private var emit: ((UUID, VoiceInputEvent) -> Void)?
    private var mayContinue: (() -> Bool)?
    private var engine: AVAudioEngine?
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var deadline: DispatchWorkItem?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var mediaResetObserver: NSObjectProtocol?
    private let audioLease: VoiceAudioLeaseSlot
    private var finishing = false
    private let locale: Locale

    /// The default denies access; the chat explicitly injects its mixed coordinator.
    init(locale: Locale = .current) {
        self.locale = locale
        self.audioLease = VoiceAudioLeaseSlot(coordinator: UnavailableVoiceAudioCoordinator())
    }

    init(locale: Locale = .current, audioCoordinator: any VoiceAudioCoordinating) {
        self.locale = locale
        self.audioLease = VoiceAudioLeaseSlot(coordinator: audioCoordinator)
    }

    func start(id: UUID, mayContinue: @escaping () -> Bool, emit: @escaping (UUID, VoiceInputEvent) -> Void) {
        if let old = self.id { cancel(id: old) }
        self.id = id
        self.emit = emit
        self.mayContinue = mayContinue
        finishing = false
        guard permittedToStart(id: id) else { return }
        // No permissions, recording, or shared audio changes without a lease.
        guard audioLease.acquire(onRevoked: { [weak self] in self?.fail(.audio, id: id) }) else {
            fail(.unavailable, id: id)
            return
        }
        guard permittedToStart(id: id) else { return }
        // This deadline includes permission prompts, so a forgotten gesture
        // cannot start or continue recording indefinitely.
        scheduleDeadline(id: id, seconds: 60)
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async { self?.speechAuthorization(status, id: id) }
        }
    }

    private func speechAuthorization(_ status: SFSpeechRecognizerAuthorizationStatus, id: UUID) {
        guard permittedToStart(id: id) else { return }
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
        guard permittedToStart(id: id) else { return }
        guard granted else { fail(.microphoneDenied, id: id); return }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else { fail(.unavailable, id: id); return }
        self.recognizer = recognizer
        guard permittedToStart(id: id) else { return }
        guard audioLease.activateForRecording() else { fail(.audio, id: id); return }
        guard permittedToStart(id: id) else { return }
        let audio = AVAudioSession.sharedInstance()
        do {
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
            routeObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.routeChangeNotification, object: audio, queue: .main
            ) { [weak self] notification in
                guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                      reason == .oldDeviceUnavailable || reason == .newDeviceAvailable else { return }
                DispatchQueue.main.async { self?.fail(.audio, id: id) }
            }
            mediaResetObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.mediaServicesWereResetNotification, object: audio, queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async { self?.fail(.audio, id: id) }
            }
            guard permittedToStart(id: id) else { return }
            task = recognizer.recognitionTask(with: newRequest) { [weak self] result, error in
                let text = result?.bestTranscription.formattedString
                let final = result?.isFinal == true
                DispatchQueue.main.async { self?.recognitionResult(text, final: final, failed: error != nil, id: id) }
            }
            guard permittedToStart(id: id) else { return }
            newEngine.prepare()
            guard permittedToStart(id: id) else { return }
            try newEngine.start()
        } catch {
            fail(.audio, id: id)
        }
    }

    /// Re-check the live settings snapshot and the state-machine session after
    /// each asynchronous permission and immediately before capture starts.
    private func permittedToStart(id: UUID) -> Bool {
        guard self.id == id else { return false }
        guard !finishing, UIApplication.shared.applicationState == .active,
              mayContinue?() == true else { deliver(.cancelled, id: id); return false }
        guard self.id == id else { return false }
        guard !finishing, UIApplication.shared.applicationState == .active else {
            deliver(.cancelled, id: id); return false
        }
        return true
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
        audioLease.release()
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
        mayContinue = nil
        deadline?.cancel(); deadline = nil
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        if let routeObserver { NotificationCenter.default.removeObserver(routeObserver) }
        if let mediaResetObserver { NotificationCenter.default.removeObserver(mediaResetObserver) }
        interruptionObserver = nil; routeObserver = nil; mediaResetObserver = nil
        if let engine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        engine = nil
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
        recognizer = nil
        finishing = false
        // Only the shared coordinator may modify or restore global audio state.
        audioLease.release()
    }
}
#endif
