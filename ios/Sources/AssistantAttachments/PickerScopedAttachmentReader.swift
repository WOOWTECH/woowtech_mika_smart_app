import Foundation

/// Access is begun synchronously in the picker callback and balanced exactly
/// once. A false start is permitted for already-accessible local URLs; actual
/// access is still checked by the coordinated reader.
protocol PickerSecurityScope: Sendable {
    func start(_ url: URL) -> Bool
    func stop(_ url: URL)
}
struct URLPickerSecurityScope: PickerSecurityScope {
    func start(_ url: URL) -> Bool { url.startAccessingSecurityScopedResource() }
    func stop(_ url: URL) { url.stopAccessingSecurityScopedResource() }
}

/// One instance per selection. If cancellation precedes read, release the
/// lease immediately and refuse a late read. If a provider is already reading,
/// keep the lease until that read actually returns, even after session timeout.
final class PickerScopedAttachmentReader: ChatAttachmentFileReading, @unchecked Sendable {
    private enum Phase { case pending, reading, closed }
    private let lock = NSLock()
    private let selectedURL: URL
    private let scope: any PickerSecurityScope
    private let delegate: any ChatAttachmentFileReading
    private let started: Bool
    private var phase: Phase = .pending

    init(url: URL, scope: any PickerSecurityScope, delegate: any ChatAttachmentFileReading) {
        selectedURL = url; self.scope = scope; self.delegate = delegate
        started = scope.start(url)
    }
    deinit { closePendingOrFinished() }

    func read(url: URL, maximumBytes: Int, isCancelled: @escaping @Sendable () -> Bool) throws -> Data {
        lock.lock()
        guard phase == .pending, url == selectedURL, !isCancelled() else {
            let close = phase == .pending
            if close { phase = .closed }
            lock.unlock()
            if close && started { scope.stop(selectedURL) }
            throw ChatAttachmentImportError.cancelled
        }
        phase = .reading; lock.unlock()
        defer { closePendingOrFinished() }
        return try delegate.read(url: url, maximumBytes: maximumBytes, isCancelled: isCancelled)
    }

    func cancel() {
        lock.lock()
        let close = phase == .pending
        if close { phase = .closed }
        lock.unlock()
        if close && started { scope.stop(selectedURL) }
        delegate.cancel()
    }

    private func closePendingOrFinished() {
        lock.lock()
        let close = phase != .closed
        if close { phase = .closed }
        lock.unlock()
        if close && started { scope.stop(selectedURL) }
    }
}
