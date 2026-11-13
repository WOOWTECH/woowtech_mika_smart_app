import SwiftUI
import UIKit
import Combine

@MainActor
final class ChatVoiceViewModel: ObservableObject {
    @Published private(set) var state: VoiceInputState = .idle
    @Published private(set) var wasInterrupted = false
    private var controller: ChatVoiceController?
    private var preferenceBinding: ChatVoicePreferenceBinding?
    private var modelSettingsBinding: AnyCancellable?
    private var candidateRouter: CandidateSpeechRouter?
    private let makeDriver: (@MainActor () -> any VoiceInputDriver)?
    private let preferences = VoicePreferences.shared

    init(makeDriver: (@MainActor () -> any VoiceInputDriver)? = nil) {
        self.makeDriver = makeDriver
    }

    func attach(session: ChatSession) {
        guard controller == nil else { return }
        #if DEBUG
        let selectedDriver: (any VoiceInputDriver)? = makeDriver?() ?? VoiceUITestFixture.selected()
        #else
        let selectedDriver = makeDriver?()
        #endif
        let driver: any VoiceInputDriver
        if let selectedDriver { driver = selectedDriver }
        else {
            let router = CandidateSpeechRouterFactory.make(repository: session.voiceModelRepository,
                                                            defaults: preferences.routingDefaults)
            candidateRouter = router
            driver = router
        }
        let controller = ChatVoiceController(driver: driver, conversation: { [weak session] in
            session?.conversationID ?? ""
        }, readDraft: { [weak session] in session?.draft ?? "" }, writeDraft: { [weak session] in
            session?.draft = $0
        }, voiceAuthorization: { [weak preferences, weak session] in
            guard let authorization = preferences?.authorization, let session else { return nil }
            return authorization + ":" + session.voiceModelRepository.revision
        })
        controller.onStateChange = { [weak self] in self?.state = $0 }
        self.controller = controller
        preferenceBinding = ChatVoicePreferenceBinding(preferences: preferences, controller: controller,
                                                       onChange: { [weak self] in self?.candidateRouter?.reloadChoice() })
        modelSettingsBinding = session.$savedSettings.dropFirst().sink { [weak self] _ in
            self?.cancel(interrupted: true)
        }
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
        candidateRouter?.invalidate()
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
    /// The input bar gives the microphone a fixed 40 pt slot, like Play's 40 dp
    /// IconButton. At the largest accessibility text size UIKit sized this button
    /// 67 × 83 pt and SwiftUI let it spill out of the slot: over the end of the
    /// draft, and below the bottom of an iPhone SE. Take exactly the offered size.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: VoicePressButton, context: Context) -> CGSize? {
        func side(_ offered: CGFloat?) -> CGFloat {
            guard let offered, offered.isFinite else { return 40 }
            return offered
        }
        return CGSize(width: side(proposal.width), height: side(proposal.height))
    }
    func makeUIView(context: Context) -> VoicePressButton {
        let button = VoicePressButton(type: .system)
        button.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        button.accessibilityIdentifier = "chat.voice"
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
        let accepts = enabled && voicePreferences.choice.allowsDeviceRecognition
        button.isEnabled = accepts
        // Traits set by the app replace UIKit's own, so a disabled microphone
        // must say so itself; otherwise VoiceOver and UI tests see it as usable.
        button.accessibilityTraits = accepts ? .button : [.button, .notEnabled]
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
