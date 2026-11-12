import SwiftUI
import UIKit

@MainActor
final class ChatVoiceViewModel: ObservableObject {
    @Published private(set) var state: VoiceInputState = .idle
    @Published private(set) var wasInterrupted = false
    private var controller: ChatVoiceController?
    private var preferenceBinding: ChatVoicePreferenceBinding?
    private let makeDriver: @MainActor () -> any VoiceInputDriver
    private let preferences = VoicePreferences.shared

    init(makeDriver: @escaping @MainActor () -> any VoiceInputDriver = {
        #if DEBUG
        if let fixture = VoiceUITestFixture.selected() { return fixture }
        #endif
        return AppleMixedVoiceRuntime.makeDriver()
    }) {
        self.makeDriver = makeDriver
    }

    func attach(session: ChatSession) {
        guard controller == nil else { return }
        let controller = ChatVoiceController(driver: makeDriver(), conversation: { [weak session] in
            session?.conversationID ?? ""
        }, readDraft: { [weak session] in session?.draft ?? "" }, writeDraft: { [weak session] in
            session?.draft = $0
        }, voiceAuthorization: { [weak preferences] in preferences?.authorization })
        controller.onStateChange = { [weak self] in self?.state = $0 }
        self.controller = controller
        preferenceBinding = ChatVoicePreferenceBinding(preferences: preferences, controller: controller)
    }
    func begin(startedAt: TimeInterval) {
        preferences.refresh()
        wasInterrupted = false; controller?.begin(gestureStartedAt: startedAt)
    }
    func drag(_ distance: Double) { controller?.drag(upwardDistance: distance) }
    func release() { controller?.release() }
    func cancel(interrupted: Bool = false) {
        let wasActive = isActive
        controller?.cancel()
        wasInterrupted = interrupted ? (wasInterrupted || wasActive) : false
    }
    func tick() { preferences.refresh(); controller?.tick() }
    var isActive: Bool {
        switch state { case .listening, .finishing: return true; default: return false }
    }
}

/// UIKit reports cancelled recognizers as well as successful lifts, so an
/// interrupted gesture cannot accidentally be interpreted as a release.
@MainActor
struct ChatVoicePressControl: UIViewRepresentable {
    @ObservedObject private var voicePreferences = VoicePreferences.shared
    @Environment(\.appLocalizer) private var localizer
    let label: String
    let hint: String
    let cancelLabel: String
    let active: Bool
    let enabled: Bool
    let begin: (TimeInterval) -> Void
    let drag: (Double) -> Void
    let release: () -> Void
    let cancel: () -> Void

    init(label: String, hint: String, cancelLabel: String, active: Bool, enabled: Bool,
         begin: @escaping (TimeInterval) -> Void, drag: @escaping (Double) -> Void,
         release: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.label = label; self.hint = hint; self.cancelLabel = cancelLabel
        self.active = active; self.enabled = enabled
        self.begin = begin; self.drag = drag; self.release = release; self.cancel = cancel
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> VoicePressButton {
        let button = VoicePressButton(type: .system)
        button.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        button.accessibilityIdentifier = "chat.voice"
        button.accessibilityTraits = .button
        button.accessibilityToggle = { [weak coordinator = context.coordinator] in coordinator?.accessibilityToggle() }
        button.accessibilityCancel = { [weak coordinator = context.coordinator] in coordinator?.accessibilityCancel() }
        #if DEBUG
        if let fixture = VoiceUITestFixture.selected() {
            fixture.activateAccessibility = { [weak button] in button?.accessibilityActivate() ?? false }
            fixture.cancelAccessibility = { [weak button] in
                guard let button, let action = button.accessibilityCustomActions?.first,
                      button.cancelVoice(action) else { return nil }
                return action.name
            }
        }
        #endif
        let gesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handle(_:)))
        gesture.minimumPressDuration = 0.3
        button.addGestureRecognizer(gesture)
        return button
    }
    func updateUIView(_ button: VoicePressButton, context: Context) {
        context.coordinator.parent = self
        button.accessibilityLabel = label
        button.accessibilityHint = voicePreferences.choice.allowsDeviceRecognition
            ? hint : localizer.text(.voiceChoiceDisabledHint)
        button.accessibilityCustomActions = active
            ? [UIAccessibilityCustomAction(name: cancelLabel, target: button, selector: #selector(VoicePressButton.cancelVoice(_:)))]
            : nil
        button.isEnabled = enabled && voicePreferences.choice.allowsDeviceRecognition
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
        func accessibilityCancel() {
            gestureActive = false
            accessibilityRecording = false
            parent.cancel()
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
    var accessibilityCancel: (() -> Void)?
    override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        accessibilityToggle?()
        return true
    }
    @objc func cancelVoice(_ action: UIAccessibilityCustomAction) -> Bool {
        guard isEnabled, let accessibilityCancel else { return false }
        accessibilityCancel()
        return true
    }
}
