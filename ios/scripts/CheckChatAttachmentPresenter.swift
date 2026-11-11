import AssistantModels
@testable import AssistantAttachments
import CoreGraphics
import Foundation
import ImageIO

private struct Failure: Error { let detail: String }
@MainActor private var checks = 0
@MainActor private func check(_ value: @autoclosure () -> Bool, _ detail: String) throws {
    checks += 1
    if !value() { throw Failure(detail: detail) }
}
@MainActor private func expect(_ reason: ChatAttachmentPresentationError, _ operation: () async throws -> Void) async throws {
    do { try await operation(); throw Failure(detail: "Expected \(reason)") }
    catch let actual as ChatAttachmentPresentationError { try check(actual == reason, "Wrong presentation error") }
}
private final class Scope: PickerSecurityScope, @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0, stops = 0
    let grant: Bool
    init(grant: Bool = true) { self.grant = grant }
    func start(_ url: URL) -> Bool { lock.lock(); starts += 1; lock.unlock(); return grant }
    func stop(_ url: URL) { lock.lock(); stops += 1; lock.unlock() }
    var counts: (Int, Int) { lock.lock(); defer { lock.unlock() }; return (starts, stops) }
}
private final class HeldReader: ChatAttachmentFileReading, @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), finished = DispatchSemaphore(value: 0)
    let bytes: Data
    private let lock = NSLock()
    private var cancelled = false
    init(_ bytes: Data) { self.bytes = bytes }
    func read(url: URL, maximumBytes: Int, isCancelled: @escaping @Sendable () -> Bool) throws -> Data {
        entered.signal(); release.wait(); defer { finished.signal() }
        // Simulates a provider that ignores cancellation.
        return bytes
    }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    var wasCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
}
private struct NoopReader: ChatAttachmentFileReading {
    let bytes: Data
    func read(url: URL, maximumBytes: Int, isCancelled: @escaping @Sendable () -> Bool) throws -> Data { bytes }
    func cancel() {}
}
private final class CountingReader: ChatAttachmentFileReading, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let bytes: Data
    init(_ bytes: Data) { self.bytes = bytes }
    func read(url: URL, maximumBytes: Int, isCancelled: @escaping @Sendable () -> Bool) throws -> Data {
        lock.lock(); count += 1; lock.unlock()
        return bytes
    }
    func cancel() {}
    var reads: Int { lock.lock(); defer { lock.unlock() }; return count }
}
private struct AcceptDecoder: ChatAttachmentImageValidating {
    func validate(data: Data, mimeType: String) throws {}
}
@MainActor private func wait(line: Int = #line, _ predicate: () -> Bool) async throws {
    for _ in 0..<1000 {
        if predicate() { return }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    throw Failure(detail: "Timed out waiting for synthetic state at line \(line)")
}
@MainActor private func isReady(_ presenter: ChatAttachmentPresenter) -> Bool {
    if case .ready = presenter.state.phase { return true }; return false
}
@MainActor private func context(input: UUID = UUID(), credential: UUID = UUID(),
                                vision: ModelVisionCapability = .unknown) throws -> ChatAttachmentReviewContext {
    try .init(baseURL: URL(string: "https://fixture.invalid/v1")!, model: "fixture", credentialRevision: credential,
              inputRevision: input, additionalData: [.currentQuestion], vision: vision)
}

// The scheduler probe runs synchronously at task creation, before the main
// actor can run either the task or the asynchronous discard. It observes the
// race itself, rather than hoping a background reader happens to win it.
@MainActor private func synchronousDiscardProbe(_ url: URL, bytes: Data) async throws {
    let scope = Scope(), reader = CountingReader(bytes)
    var scheduled = 0
    let presenter = ChatAttachmentPresenter(scope: scope, makeReader: { reader }, decoder: AcceptDecoder(),
        schedulePreparation: { operation in scheduled += 1; return Task { await operation() } })
    presenter.onChange = { [weak presenter] state in
        if case .loading = state.phase { presenter?.discard() }
    }
    presenter.picked(url)
    try check(scheduled == 0, "STALE_DISCARD_TASK_SCHEDULED")
    try await wait { scope.counts.1 == 1 }
    try check(scope.counts.0 == 1 && scope.counts.1 == 1 && reader.reads == 0 && presenter.state.phase == .empty,
              "Synchronous discard never starts a reader and balances scope")
}

@MainActor private func synchronousReplaceProbe(_ first: URL, second: URL, bytes: Data) async throws {
    let scope = Scope(), rejected = CountingReader(bytes), accepted = CountingReader(bytes)
    var made = 0, scheduled = 0, didReplace = false
    let presenter = ChatAttachmentPresenter(scope: scope, makeReader: {
        made += 1; return made == 1 ? rejected : accepted
    }, decoder: AcceptDecoder(), schedulePreparation: { operation in
        scheduled += 1; return Task { await operation() }
    })
    presenter.onChange = { [weak presenter] state in
        if case .loading = state.phase, !didReplace { didReplace = true; presenter?.picked(second) }
    }
    presenter.picked(first)
    try check(scheduled == 1, "STALE_REPLACEMENT_TASK_SCHEDULED")
    try await wait { isReady(presenter) && scope.counts.1 == 2 }
    guard case .ready(let metadata) = presenter.state.phase else { throw Failure(detail: "Replacement not ready") }
    try check(metadata.filename == second.lastPathComponent && rejected.reads == 0 && accepted.reads == 1,
              "Synchronous replacement starts only the winning reader")
    try check(scope.counts.0 == 2 && scope.counts.1 == 2, "Synchronous replacement balances scopes")
    presenter.discard()
}

@main struct CheckChatAttachmentPresenter {
    @MainActor static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let url = directory.appendingPathComponent("text.txt"), bytes = Data("測試附件".utf8)
        try bytes.write(to: url)
        let jpegURL = directory.appendingPathComponent("image.jpg")
        let jpeg = Data([0xff, 0xd8, 0xff, 0xe0, 0x01])
        try jpeg.write(to: jpegURL)
        let probeSecond = directory.appendingPathComponent("probe-other.txt")
        try bytes.write(to: probeSecond)
        let probe = ProcessInfo.processInfo.environment["WOOW_ATTACHMENT_REENTRANCY_PROBE"]
        if let probe, probe != "discard" && probe != "replace" { throw Failure(detail: "Unknown reentrancy probe") }
        if probe == nil || probe == "discard" { try await synchronousDiscardProbe(url, bytes: bytes) }
        if probe == nil || probe == "replace" { try await synchronousReplaceProbe(url, second: probeSecond, bytes: bytes) }
        if probe != nil { return }
        let scope = Scope()
        let presenter = ChatAttachmentPresenter(scope: scope, makeReader: { CoordinatedAttachmentReader() }, decoder: ImageIOAttachmentValidator())
        let originalContext = try context()
        presenter.updateContext(originalContext)
        var observed: [ChatAttachmentPresentationPhase] = []
        presenter.onChange = { observed.append($0.phase) }
        presenter.picked(url)
        try check(scope.counts.0 == 1, "Scope begins synchronously in picker callback")
        try await wait { isReady(presenter) && scope.counts.1 == 1 }
        guard case .ready(let metadata) = presenter.state.phase else { throw Failure(detail: "Not ready") }
        try check(metadata.filename == "text.txt" && metadata.byteCount == bytes.count && metadata.kind == .text, "Shows actual imported metadata")
        try check(observed.contains(.loading(filename: "text.txt")) && observed.contains(.ready(metadata)), "Publishes real import states")
        try check(scope.counts.0 == 1 && scope.counts.1 == 1, "One matching security scope stop")
        try presenter.confirm()
        try check(presenter.state.phase == .confirmed(metadata), "Confirmation stages only")
        try check(!String(describing: presenter.state).contains("測試附件"), "Display state excludes attachment contents")
        let referencesChanged = try ChatAttachmentReviewContext(baseURL: originalContext.baseURL, model: originalContext.model,
            credentialRevision: originalContext.credentialRevision, inputRevision: originalContext.inputRevision,
            additionalData: [.currentQuestion, .memory], vision: .unknown)
        try check(referencesChanged.additionalData == [.currentQuestion, .memory], "Review retains typed disclosure categories")
        presenter.updateContext(referencesChanged)
        try check(presenter.state.phase == .ready(metadata), "Changed disclosure categories revoke confirmation")
        presenter.updateContext(originalContext)
        try presenter.confirm()
        let wrongContext = try context()
        try await expect(.confirmationRequired) { _ = try await presenter.takeConfirmed(context: wrongContext) }
        try check(presenter.state.phase == .confirmed(metadata), "Wrong context cannot consume selected data")
        presenter.updateContext(wrongContext)
        try check(presenter.state.phase == .ready(metadata), "Changed input or credentials revokes confirmation")
        try await expect(.confirmationRequired) { _ = try await presenter.takeConfirmed(context: originalContext) }
        try presenter.confirm()
        let actual = try await presenter.takeConfirmed(context: wrongContext)
        let expected = try ModelAttachment.text(utf8: bytes)
        try check(actual == expected && presenter.state.phase == .consumed, "One-shot handoff preserves selected bytes")
        try await expect(.confirmationRequired) { _ = try await presenter.takeConfirmed(context: wrongContext) }

        let heldScope = Scope(), held = HeldReader(bytes)
        let replacement = ChatAttachmentPresenter(scope: heldScope, makeReader: { held }, decoder: AcceptDecoder())
        replacement.picked(url)
        defer { held.release.signal() }
        try await wait { held.entered.wait(timeout: .now()) == .success }
        replacement.discard()
        try await wait { held.wasCancelled }
        try check(heldScope.counts.0 == 1 && heldScope.counts.1 == 0, "Active provider retains scope after discard")
        held.release.signal()
        try await wait { held.finished.wait(timeout: .now()) == .success }
        try await wait { heldScope.counts.1 == 1 }
        try check(replacement.state.phase == .empty, "Late provider result cannot restore removed attachment")
        try check(heldScope.counts.1 == 1, "Scope stops once after actual read ends")

        let notStartedScope = Scope(), preCancelled = PickerScopedAttachmentReader(url: url, scope: notStartedScope, delegate: NoopReader(bytes: bytes))
        preCancelled.cancel()
        do { _ = try preCancelled.read(url: url, maximumBytes: 100, isCancelled: { false }); throw Failure(detail: "Read after cancel") }
        catch ChatAttachmentImportError.cancelled { try check(notStartedScope.counts.0 == 1 && notStartedScope.counts.1 == 1, "Pre-read cancel prevents read and releases scope once") }
        let unscoped = Scope(grant: false), unscopedReader = PickerScopedAttachmentReader(url: url, scope: unscoped, delegate: NoopReader(bytes: bytes))
        let localBytes = try unscopedReader.read(url: url, maximumBytes: 100, isCancelled: { false })
        try check(localBytes == bytes && unscoped.counts.0 == 1 && unscoped.counts.1 == 0, "False scope start does not trigger unmatched stop")

        let invalidSelectionScope = Scope()
        let errors = ChatAttachmentPresenter(scope: invalidSelectionScope, makeReader: { NoopReader(bytes: bytes) }, decoder: AcceptDecoder())
        errors.picked(directory.appendingPathComponent("report.pdf"))
        try check(errors.state.error == .importing(.unsupportedType) && invalidSelectionScope.counts.0 == 0, "PDF rejected before opening scope")
        errors.pickerCancelled()
        try check(errors.state.error == .importing(.unsupportedType), "Picker cancellation preserves prior state")
        errors.pickerFailed()
        try check(errors.state.error == .pickerFailed && errors.state.error?.errorDescription?.contains("PRIVATE") == false, "Picker failure is sanitized")
        let revokedScope = Scope()
        let revoked = ChatAttachmentPresenter(scope: revokedScope, makeReader: { NoopReader(bytes: bytes) }, decoder: AcceptDecoder())
        revoked.updateContext(originalContext); revoked.picked(url)
        try await wait { isReady(revoked) && revokedScope.counts.1 == 1 }
        try revoked.confirm(); revoked.pickerFailed()
        try check(revoked.state.phase == .empty && revoked.state.error == .pickerFailed,
                  "Failed picker replacement revokes the previously confirmed item")
        revoked.updateContext(wrongContext)
        do { try revoked.confirm(); throw Failure(detail: "Failed replacement could be reconfirmed") }
        catch ChatAttachmentPresentationError.pickerFailed { try check(true, "Failed replacement requires explicit decision") }
        try await expect(.confirmationRequired) { _ = try await revoked.takeConfirmed(context: wrongContext) }
        revoked.discard()
        try check(revoked.state.error == nil && revoked.state.phase == .empty, "Explicit discard clears selection error")
        try check(revokedScope.counts.0 == 1 && revokedScope.counts.1 == 1, "Revoking confirmed attachment balances scope")

        let failedScope = Scope(), failedReader = HeldReader(bytes)
        let failedWhileLoading = ChatAttachmentPresenter(scope: failedScope, makeReader: { failedReader }, decoder: AcceptDecoder())
        failedWhileLoading.picked(url)
        defer { failedReader.release.signal() }
        try await wait { failedReader.entered.wait(timeout: .now()) == .success }
        failedWhileLoading.picked(directory.appendingPathComponent("unsupported.pdf"))
        try await wait { failedReader.wasCancelled }
        try check(failedScope.counts.0 == 1 && failedScope.counts.1 == 0, "Failed replacement keeps live reader's scope")
        failedReader.release.signal()
        try await wait { failedReader.finished.wait(timeout: .now()) == .success }
        try await wait { failedScope.counts.1 == 1 }
        try check(failedWhileLoading.state.phase == .empty && failedWhileLoading.state.error == .importing(.unsupportedType),
                  "Late old reader cannot clear replacement failure")
        try check(failedScope.counts.1 == 1, "Failed replacement stops its scope exactly once")

        let invalidBytesScope = Scope()
        let invalidBytes = ChatAttachmentPresenter(scope: invalidBytesScope, makeReader: { NoopReader(bytes: Data([0xff])) }, decoder: AcceptDecoder())
        invalidBytes.picked(url)
        try await wait { invalidBytes.state.error == .importing(.invalidFormat) && invalidBytesScope.counts.1 == 1 }
        try check(invalidBytes.state.phase == .empty, "Invalid imported file reports a bounded error and releases scope")
        try await expect(.confirmationRequired) { _ = try await invalidBytes.takeConfirmed(context: originalContext) }
        do {
            _ = try ChatAttachmentReviewContext(baseURL: URL(string: "http://fixture.invalid")!, model: "fixture",
                credentialRevision: UUID(), inputRevision: UUID(), additionalData: [.currentQuestion], vision: .unknown)
            throw Failure(detail: "Insecure review context accepted")
        } catch ChatAttachmentPresentationError.invalidContext { try check(true, "Invalid endpoint cannot be confirmed") }

        let imagePresenter = ChatAttachmentPresenter(scope: Scope(), makeReader: { NoopReader(bytes: jpeg) }, decoder: AcceptDecoder())
        imagePresenter.updateContext(originalContext)
        imagePresenter.picked(jpegURL)
        try await wait { isReady(imagePresenter) }
        do { try imagePresenter.confirm(); throw Failure(detail: "Unknown vision was accepted") }
        catch ChatAttachmentPresentationError.visionUnknown { try check(imagePresenter.state.error == .visionUnknown, "Unknown vision is visible and blocks confirmation") }
        let unsupported = try context(vision: .unsupported)
        imagePresenter.updateContext(unsupported)
        do { try imagePresenter.confirm(); throw Failure(detail: "Unsupported vision was accepted") }
        catch ChatAttachmentPresentationError.visionUnsupported { try check(imagePresenter.state.error == .visionUnsupported, "Unsupported vision blocks confirmation") }
        let supported = try context(vision: .supported)
        imagePresenter.updateContext(supported)
        try imagePresenter.confirm()
        let imageData = try await imagePresenter.takeConfirmed(context: supported)
        let expectedImage = try ModelAttachment.image(data: jpeg, mimeType: "image/jpeg")
        try check(imageData == expectedImage, "Supported image can be handed off")

        let invalidation = ChatAttachmentPresenter(scope: Scope(), makeReader: { NoopReader(bytes: bytes) }, decoder: AcceptDecoder())
        invalidation.updateContext(originalContext)
        invalidation.picked(url)
        try await wait { isReady(invalidation) }
        try invalidation.confirm()
        invalidation.onChange = { state in
            if case .taking = state.phase { invalidation.updateContext(wrongContext) }
        }
        try await expect(.contextChanged) { _ = try await invalidation.takeConfirmed(context: originalContext) }
        try check(invalidation.state.phase == .empty && invalidation.state.error == .contextChanged, "Context change during handoff cannot return attachment")

        let heldOld = HeldReader(bytes), scopeOld = Scope()
        var readerCount = 0
        let replacing = ChatAttachmentPresenter(scope: scopeOld, makeReader: {
            readerCount += 1
            return readerCount == 1 ? heldOld : NoopReader(bytes: bytes)
        }, decoder: AcceptDecoder())
        defer { heldOld.release.signal() }
        replacing.picked(url)
        try await wait { heldOld.entered.wait(timeout: .now()) == .success }
        let secondURL = directory.appendingPathComponent("other.txt"); try bytes.write(to: secondURL)
        replacing.picked(secondURL)
        try await wait { isReady(replacing) && heldOld.wasCancelled }
        guard case .ready(let selected) = replacing.state.phase else { throw Failure(detail: "Replacement missing") }
        try check(selected.filename == "other.txt", "New selection wins while old provider is blocked")
        heldOld.release.signal()
        try await wait { heldOld.finished.wait(timeout: .now()) == .success }
        try await wait { scopeOld.counts.1 == 2 }
        try check(replacing.state.phase == .ready(selected) && scopeOld.counts.0 == 2, "Late replaced result cannot overwrite new selection")
        replacing.pickerCancelled()
        try check(replacing.state.phase == .ready(selected), "Picker cancellation keeps staged selection")
        replacing.discard()

        let contextScope = Scope(), contextReader = CountingReader(bytes)
        let synchronousContext = ChatAttachmentPresenter(scope: contextScope, makeReader: { contextReader }, decoder: AcceptDecoder())
        var didUpdateContext = false
        synchronousContext.onChange = { [weak synchronousContext] state in
            if case .loading = state.phase, !didUpdateContext {
                didUpdateContext = true; synchronousContext?.updateContext(originalContext)
            }
        }
        synchronousContext.picked(url)
        try await wait { isReady(synchronousContext) && contextScope.counts.1 == 1 }
        try check(contextReader.reads == 1 && synchronousContext.state.context == originalContext,
                  "Synchronous context update preserves the current selection")
        synchronousContext.discard()
        print("Chat attachment presenter checks passed: \(checks)")
    }
}
