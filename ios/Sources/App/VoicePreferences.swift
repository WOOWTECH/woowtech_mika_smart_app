import Combine
import Foundation

private final class VoicePreferenceObserver: @unchecked Sendable {
    let token: NSObjectProtocol
    init(_ token: NSObjectProtocol) { self.token = token }
    deinit { NotificationCenter.default.removeObserver(token) }
}

@MainActor
final class VoicePreferences: ObservableObject {
    static let shared = VoicePreferences(store: .application())
    @Published private(set) var choice: VoiceChoice
    @Published private(set) var observedAuthorization: String?
    @Published private(set) var saveFailed = false
    private let store: VoiceChoiceStore
    private var observers: [VoicePreferenceObserver] = []
    private var choiceChanges: AnyCancellable?
    var authorization: String? { store.snapshot().authorization }
    var routingDefaults: UserDefaults { store.routingDefaults }

    init(store: VoiceChoiceStore) {
        self.store = store
        let snapshot = store.snapshot()
        choice = snapshot.choice
        observedAuthorization = snapshot.authorization
        observers.append(VoicePreferenceObserver(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            }))
        // The store publishes only from MainActor, after its lock is released.
        // Cancel active captures in this same turn, before another permission
        // completion can start an engine in a different window.
        choiceChanges = VoiceChoiceChanges.subject.sink { [weak self] _ in self?.refresh() }
    }
    func refresh() {
        let value = store.snapshot()
        if value.authorization != observedAuthorization { observedAuthorization = value.authorization }
        if value.choice != choice { choice = value.choice }
    }
    func select(_ value: VoiceChoice) {
        saveFailed = !store.select(value)
        refresh()
    }
}
