import Foundation

/// Composer semantics, independent of SwiftUI and the platform speech driver.
@MainActor
final class ChatVoiceController {
    private let machine: VoiceInputStateMachine
    private let conversation: () -> String
    private let voiceAuthorization: () -> String?
    private var voiceRevision: String?
    private let readDraft: () -> String
    private let writeDraft: (String) -> Void
    private var origin: String?
    var onStateChange: ((VoiceInputState) -> Void)?

    var state: VoiceInputState { machine.state }

    init(driver: VoiceInputDriver, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         conversation: @escaping () -> String, readDraft: @escaping () -> String,
         writeDraft: @escaping (String) -> Void, voiceAuthorization: @escaping () -> String? = { "device" }) {
        self.conversation = conversation
        self.voiceAuthorization = voiceAuthorization
        self.readDraft = readDraft
        self.writeDraft = writeDraft
        self.machine = VoiceInputStateMachine(driver: driver, now: now)
        machine.mayContinue = { [weak self] in
            guard let self, let revision = self.voiceRevision else { return false }
            return revision == self.voiceAuthorization()
        }
        machine.onStateChange = { [weak self] state in
            guard let self else { return }
            self.onStateChange?(state)
            if case .listening = state,
               self.voiceRevision == nil || self.voiceRevision != self.voiceAuthorization() {
                self.cancel()
            }
        }
        machine.onFinal = { [weak self] text in
            guard let self = self, self.voiceRevision != nil, self.voiceRevision == self.voiceAuthorization(), let origin = self.origin, origin == self.conversation() else { return }
            self.origin = nil
            self.writeDraft(VoiceDraftJoin.join(self.readDraft(), text))
        }
    }

    func begin(gestureStartedAt: TimeInterval) {
        guard let revision = voiceAuthorization() else { cancel(); return }
        voiceRevision = revision
        origin = conversation()
        machine.begin(gestureStartedAt: gestureStartedAt)
    }
    func authorizationChanged() {
        if let revision = voiceRevision, revision != voiceAuthorization() { cancel() }
    }
    func drag(upwardDistance: Double) { machine.drag(upwardDistance: upwardDistance, cancelThreshold: 70) }
    func release() { if voiceRevision != nil && voiceRevision == voiceAuthorization() { machine.release() } else { cancel() } }
    func tick() { if voiceRevision != nil && voiceRevision == voiceAuthorization() { machine.tick() } else { cancel() } }
    func cancel() {
        origin = nil
        voiceRevision = nil
        machine.cancel()
    }
}
