import Foundation

/// Composer semantics, independent of SwiftUI and the platform speech driver.
@MainActor
final class ChatVoiceController {
    private let machine: VoiceInputStateMachine
    private let conversation: () -> String
    private let readDraft: () -> String
    private let writeDraft: (String) -> Void
    private var origin: String?
    var onStateChange: ((VoiceInputState) -> Void)?

    var state: VoiceInputState { machine.state }

    init(driver: VoiceInputDriver, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         conversation: @escaping () -> String, readDraft: @escaping () -> String,
         writeDraft: @escaping (String) -> Void) {
        self.conversation = conversation
        self.readDraft = readDraft
        self.writeDraft = writeDraft
        self.machine = VoiceInputStateMachine(driver: driver, now: now)
        machine.onStateChange = { [weak self] state in self?.onStateChange?(state) }
        machine.onFinal = { [weak self] text in
            guard let self = self, let origin = self.origin, origin == self.conversation() else { return }
            self.origin = nil
            self.writeDraft(VoiceDraftJoin.join(self.readDraft(), text))
        }
    }

    func begin(gestureStartedAt: TimeInterval) {
        origin = conversation()
        machine.begin(gestureStartedAt: gestureStartedAt)
    }
    func drag(upwardDistance: Double) { machine.drag(upwardDistance: upwardDistance, cancelThreshold: 70) }
    func release() { machine.release() }
    func tick() { machine.tick() }
    func cancel() {
        origin = nil
        machine.cancel()
    }
}
