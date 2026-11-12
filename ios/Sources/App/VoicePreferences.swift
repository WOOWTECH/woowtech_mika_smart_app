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
    private let store: VoiceChoiceStore
    private var observer: VoicePreferenceObserver?
    var authorization: String? { store.snapshot().authorization }

    init(store: VoiceChoiceStore) {
        self.store = store
        choice = store.load()
        observer = VoicePreferenceObserver(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refresh() }
            })
    }
    func refresh() {
        let value = store.load()
        if value != choice { choice = value }
    }
    func select(_ value: VoiceChoice) {
        store.select(value)
        refresh()
    }
}
