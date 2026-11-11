import SwiftUI
import UIKit

@MainActor
final class ChatVoiceViewModel: ObservableObject {
    @Published private(set) var state: VoiceInputState = .idle
    @Published private(set) var wasInterrupted = false
    private var controller: ChatVoiceController?
    private let makeDriver: @MainActor () -> any VoiceInputDriver

    init(makeDriver: @escaping @MainActor () -> any VoiceInputDriver = { AppleMixedVoiceRuntime.makeDriver() }) {
        self.makeDriver = makeDriver
    }

    func attach(session: ChatSession) {
        guard controller == nil else { return }
        let controller = ChatVoiceController(driver: makeDriver(), conversation: { [weak session] in
            session?.conversationID ?? ""
        }, readDraft: { [weak session] in session?.draft ?? "" }, writeDraft: { [weak session] in
            session?.draft = $0
        })
        controller.onStateChange = { [weak self] in self?.state = $0 }
        self.controller = controller
    }
    func begin(startedAt: TimeInterval) { wasInterrupted = false; controller?.begin(gestureStartedAt: startedAt) }
    func drag(_ distance: Double) { controller?.drag(upwardDistance: distance) }
    func release() { controller?.release() }
    func cancel(interrupted: Bool = false) {
        let wasActive = isActive
        controller?.cancel()
        wasInterrupted = interrupted ? (wasInterrupted || wasActive) : false
    }
    func tick() { controller?.tick() }
    var isActive: Bool {
        switch state { case .listening, .finishing: return true; default: return false }
    }
}

/// UIKit reports cancelled recognizers as well as successful lifts, so an
/// interrupted gesture cannot accidentally be interpreted as a release.
@MainActor
struct ChatVoicePressControl: UIViewRepresentable {
    let label: String
    let hint: String
    let active: Bool
    let enabled: Bool
    let begin: (TimeInterval) -> Void
    let drag: (Double) -> Void
    let release: () -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> VoicePressButton {
        let button = VoicePressButton(type: .system)
        button.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        button.accessibilityIdentifier = "chat.voice"
        button.accessibilityTraits = .button
        button.accessibilityToggle = { [weak coordinator = context.coordinator] in coordinator?.accessibilityToggle() }
        let gesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        gesture.minimumPressDuration = 0.3
        button.addGestureRecognizer(gesture)
        return button
    }
    func updateUIView(_ button: VoicePressButton, context: Context) {
        context.coordinator.parent = self
        button.accessibilityLabel = label
        button.accessibilityHint = hint
        button.isEnabled = enabled
        button.tintColor = active ? .systemRed : .label
    }
    static func dismantleUIView(_ button: VoicePressButton, coordinator: Coordinator) {
        coordinator.cancelIfNeeded()
    }

    @MainActor final class Coordinator: NSObject {
        var parent: ChatVoicePressControl
        var startY: CGFloat = 0
        var gestureActive = false
        var accessibilityRecording = false
        init(parent: ChatVoicePressControl) { self.parent = parent }
        @objc func handle(_ recognizer: UILongPressGestureRecognizer) {
            guard let view = recognizer.view else { return }
            switch recognizer.state {
            case .began:
                guard parent.enabled else { return }
                gestureActive = true
                startY = recognizer.location(in: view).y
                parent.begin(ProcessInfo.processInfo.systemUptime - 0.3)
            case .changed:
                if gestureActive { parent.drag(Double(startY - recognizer.location(in: view).y)) }
            case .ended:
                guard gestureActive else { return }
                gestureActive = false
                parent.drag(Double(startY - recognizer.location(in: view).y))
                parent.release()
            case .cancelled, .failed: cancelIfNeeded()
            default: break
            }
        }
        func accessibilityToggle() {
            guard parent.enabled else { return }
            if parent.active {
                accessibilityRecording = false
                parent.release()
            } else {
                accessibilityRecording = true
                parent.begin(ProcessInfo.processInfo.systemUptime - 0.5)
            }
        }
        func cancelIfNeeded() {
            if gestureActive || accessibilityRecording { parent.cancel() }
            gestureActive = false
            accessibilityRecording = false
        }
    }
}

final class VoicePressButton: UIButton {
    var accessibilityToggle: (() -> Void)?
    override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        accessibilityToggle?()
        return true
    }
}
