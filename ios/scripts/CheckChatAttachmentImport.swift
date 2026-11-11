import AssistantAttachments
import AssistantModels
import CoreGraphics
import Darwin
import Foundation
import ImageIO

private struct Failure: Error { let detail: String }
private var checks = 0
private func check(_ value: @autoclosure () -> Bool, _ detail: String) throws {
    checks += 1
    if !value() { throw Failure(detail: detail) }
}
private func expect(_ reason: ChatAttachmentImportError, _ operation: () async throws -> Void) async throws {
    do { try await operation(); throw Failure(detail: "Expected \(reason)") }
    catch let actual as ChatAttachmentImportError { try check(actual == reason, "Expected \(reason), got \(actual)") }
}
private func select(_ url: URL) throws -> ChatAttachmentSelection { try ChatAttachmentSelection(userSelectedURL: url) }
private func makeImage(_ type: CFString, width: Int = 4, height: Int = 3) throws -> Data {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw Failure(detail: "Cannot create fixture context")
    }
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage() else { throw Failure(detail: "Cannot create fixture image") }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, type, 1, nil) else { throw Failure(detail: "Cannot create fixture destination") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw Failure(detail: "Cannot encode fixture") }
    return output as Data
}
private final class HeldReader: ChatAttachmentFileReading, @unchecked Sendable {
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var cancelledValue = false
    let data: Data
    let blockCancellation: Bool
    let allowCancellation = DispatchSemaphore(value: 0)
    init(_ data: Data, blockCancellation: Bool = false) { self.data = data; self.blockCancellation = blockCancellation }
    func read(url: URL, maximumBytes: Int, isCancelled: @escaping @Sendable () -> Bool) throws -> Data {
        started.signal(); release.wait(); defer { finished.signal() }
        // Deliberately ignores cancellation to simulate a misbehaving provider.
        return data
    }
    func cancel() {
        lock.lock(); cancelledValue = true; lock.unlock()
        if blockCancellation { allowCancellation.wait() }
    }
    var wasCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelledValue }
}
private final class HeldDecoder: ChatAttachmentImageValidating, @unchecked Sendable {
    let started = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let finished = DispatchSemaphore(value: 0)
    func validate(data: Data, mimeType: String) throws { started.signal(); release.wait(); finished.signal() }
}
private struct OversizedReader: ChatAttachmentFileReading {
    func read(url: URL, maximumBytes: Int, isCancelled: @escaping @Sendable () -> Bool) throws -> Data {
        Data(repeating: 0x61, count: maximumBytes + 1)
    }
    func cancel() {}
}
private final class MutationDuringRead: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var changedValue = false
    private let url: URL
    init(url: URL) { self.url = url }
    func poll() -> Bool {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        if calls == 4 {
            do { try Data("changed-size".utf8).write(to: url); changedValue = true }
            catch { changedValue = false }
        }
        return false
    }
    var changed: Bool { lock.lock(); defer { lock.unlock() }; return changedValue }
}
private func wait(_ predicate: @escaping () -> Bool) async throws {
    for _ in 0..<1000 {
        if predicate() { return }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    throw Failure(detail: "Fixture timeout")
}

@main struct CheckChatAttachmentImport {
    static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        func file(_ name: String, _ data: Data) throws -> URL {
            let url = directory.appendingPathComponent(name)
            try data.write(to: url); return url
        }
        let textData = Data("你好\n檔案".utf8)
        let textURL = try file("memo.txt", textData)
        let selection = try select(textURL)
        try check(selection.filename == "memo.txt" && selection.kind == .text, "Selection metadata")
        let initialFiles = try Set(FileManager.default.contentsOfDirectory(atPath: directory.path))
        let session = ChatAttachmentImportSession(selection: selection)
        let info = try await session.load()
        try check(info.filename == "memo.txt" && info.byteCount == textData.count && info.kind == .text, "Actual filename and bytes")
        let ready = await session.state
        try check(ready == .ready(info), "Ready after completed load")
        let first = try await session.take(), expectedText = try ModelAttachment.text(utf8: textData)
        try check(first == expectedText, "Transferred model attachment is exact")
        try await expect(.invalidState) { _ = try await session.take() }
        try await expect(.invalidState) { _ = try await session.load() }
        let consumed = await session.state
        try check(consumed == .consumed, "Take is one-shot")
        let finalFiles = try Set(FileManager.default.contentsOfDirectory(atPath: directory.path))
        try check(finalFiles == initialFiles, "No attachment copy persisted")

        let maxText = try file("max.txt", Data(repeating: 0x61, count: ModelAttachment.maximumTextBytes))
        let maxSession = ChatAttachmentImportSession(selection: try select(maxText))
        let maxInfo = try await maxSession.load()
        try check(maxInfo.byteCount == ModelAttachment.maximumTextBytes, "Exact byte limit accepted")
        await maxSession.discard()
        try await expect(.invalidState) { _ = try await maxSession.take() }
        let oversize = try file("over.txt", Data(repeating: 0x61, count: ModelAttachment.maximumTextBytes + 1))
        let overSession = ChatAttachmentImportSession(selection: try select(oversize))
        try await expect(.tooLarge) { _ = try await overSession.load() }
        let oversizedResult = ChatAttachmentImportSession(selection: selection, reader: OversizedReader())
        try await expect(.tooLarge) { _ = try await oversizedResult.load() }
        try await expect(.invalidState) { _ = try await oversizedResult.take() }
        let badText = try file("bad.txt", Data([0xff]))
        let badTextSession = ChatAttachmentImportSession(selection: try select(badText))
        try await expect(.invalidFormat) { _ = try await badTextSession.load() }
        let empty = try file("empty.txt", Data())
        let emptySession = ChatAttachmentImportSession(selection: try select(empty))
        try await expect(.empty) { _ = try await emptySession.load() }
        let nul = try file("nul.txt", Data([0x61, 0, 0x62]))
        let nulSession = ChatAttachmentImportSession(selection: try select(nul))
        try await expect(.invalidFormat) { _ = try await nulSession.load() }

        let png = try makeImage("public.png" as CFString), jpeg = try makeImage("public.jpeg" as CFString)
        for (name, bytes, kind) in [("photo.png", png, ChatAttachmentKind.png), ("photo.jpg", jpeg, .jpeg)] {
            let url = try file(name, bytes), imageSession = ChatAttachmentImportSession(selection: try select(url))
            let result = try await imageSession.load()
            try check(result.filename == name && result.byteCount == bytes.count && result.kind == kind, "Real image decoded with actual metadata")
            let attachment = try await imageSession.take()
            let expected = try ModelAttachment.image(data: bytes, mimeType: kind == .png ? "image/png" : "image/jpeg")
            try check(attachment == expected, "Decoded image preserves exact bytes")
        }
        let forged = try file("forged.png", Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x01]))
        let forgedSession = ChatAttachmentImportSession(selection: try select(forged))
        try await expect(.invalidFormat) { _ = try await forgedSession.load() }
        let truncated = try file("truncated.png", png.prefix(png.count / 2))
        let truncatedSession = ChatAttachmentImportSession(selection: try select(truncated))
        try await expect(.invalidFormat) { _ = try await truncatedSession.load() }
        guard let chunk = png.range(of: Data("IDAT".utf8)), chunk.upperBound < png.endIndex else {
            throw Failure(detail: "Fixture PNG has no image data")
        }
        var corrupted = png
        corrupted[chunk.upperBound] ^= 0xff
        let corruptURL = try file("corrupt.png", corrupted)
        let corruptSession = ChatAttachmentImportSession(selection: try select(corruptURL))
        try await expect(.invalidFormat) { _ = try await corruptSession.load() }
        let wrong = try file("wrong.jpg", png)
        let wrongSession = ChatAttachmentImportSession(selection: try select(wrong))
        try await expect(.invalidFormat) { _ = try await wrongSession.load() }
        let shortJPEG = try file("short.jpg", jpeg.dropLast(2))
        let shortJPEGSession = ChatAttachmentImportSession(selection: try select(shortJPEG))
        try await expect(.invalidFormat) { _ = try await shortJPEGSession.load() }
        let extraJPEG = try file("extra.jpg", jpeg + Data([0]))
        let extraJPEGSession = ChatAttachmentImportSession(selection: try select(extraJPEG))
        try await expect(.invalidFormat) { _ = try await extraJPEGSession.load() }
        let hugeImage = try file("huge.png", Data(repeating: 0, count: ModelAttachment.maximumImageBytes + 1))
        let hugeSession = ChatAttachmentImportSession(selection: try select(hugeImage))
        try await expect(.tooLarge) { _ = try await hugeSession.load() }
        let wide = try file("wide.png", try makeImage("public.png" as CFString, width: ImageIOAttachmentValidator.maximumDimension + 1, height: 1))
        let wideSession = ChatAttachmentImportSession(selection: try select(wide))
        try await expect(.imageTooLarge) { _ = try await wideSession.load() }

        let link = directory.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: textURL)
        let linkSession = ChatAttachmentImportSession(selection: try select(link))
        try await expect(.unreadable) { _ = try await linkSession.load() }
        let fifo = directory.appendingPathComponent("pipe.txt")
        guard mkfifo(fifo.path, 0o600) == 0 else { throw Failure(detail: "Cannot create FIFO") }
        let fifoSession = ChatAttachmentImportSession(selection: try select(fifo))
        try await expect(.unreadable) { _ = try await fifoSession.load() }
        let dirURL = directory.appendingPathComponent("directory.txt", isDirectory: true)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: false)
        let dirSession = ChatAttachmentImportSession(selection: try select(dirURL))
        try await expect(.unreadable) { _ = try await dirSession.load() }
        let mutationURL = try file("changing.txt", Data("original".utf8))
        let mutation = MutationDuringRead(url: mutationURL)
        try await expect(.unreadable) {
            _ = try CoordinatedAttachmentReader().read(url: mutationURL, maximumBytes: 1024, isCancelled: { mutation.poll() })
        }
        try check(mutation.changed, "Test changed the actual open file during read")
        try await expect(.unsupportedType) { _ = try select(directory.appendingPathComponent("paper.pdf")) }
        try await expect(.invalidSelection) { _ = try select(URL(string: "https://example.invalid/file.txt")!) }
        try await expect(.invalidSelection) { _ = try select(directory.appendingPathComponent("bad\u{202e}.txt")) }
        let abandoned = ChatAttachmentImportSession(selection: selection)
        await abandoned.discard()
        try await expect(.invalidState) { _ = try await abandoned.load() }

        let heldReader = HeldReader(textData)
        let heldSession = ChatAttachmentImportSession(selection: try select(textURL), reader: heldReader)
        let load = Task { try await heldSession.load() }
        defer { heldReader.release.signal(); load.cancel() }
        try await wait { heldReader.started.wait(timeout: .now()) == .success }
        await heldSession.discard()
        try await expect(.cancelled) { _ = try await load.value }
        try await wait { heldReader.wasCancelled }
        try check(heldReader.wasCancelled, "Discard calls reader cancellation")
        heldReader.release.signal()
        try await wait { heldReader.finished.wait(timeout: .now()) == .success }
        try await expect(.invalidState) { _ = try await heldSession.take() }
        let discardedState = await heldSession.state
        try check(discardedState == .discarded, "Late provider completion cannot republish")

        let stuckCancel = HeldReader(textData, blockCancellation: true)
        let stuckSession = ChatAttachmentImportSession(selection: try select(textURL), reader: stuckCancel)
        let stuckLoad = Task { try await stuckSession.load() }
        let discardReturned = DispatchSemaphore(value: 0)
        defer { stuckCancel.release.signal(); stuckCancel.allowCancellation.signal(); stuckLoad.cancel() }
        try await wait { stuckCancel.started.wait(timeout: .now()) == .success }
        let discardTask = Task { await stuckSession.discard(); discardReturned.signal() }
        defer { discardTask.cancel() }
        try await wait { stuckCancel.wasCancelled }
        try await wait { discardReturned.wait(timeout: .now()) == .success }
        try await expect(.cancelled) { _ = try await stuckLoad.value }
        try check(stuckCancel.wasCancelled, "Blocked reader cancellation cannot block discard")
        stuckCancel.allowCancellation.signal(); stuckCancel.release.signal()
        try await wait { stuckCancel.finished.wait(timeout: .now()) == .success }

        let timeoutReader = HeldReader(textData)
        let timeoutSession = ChatAttachmentImportSession(selection: try select(textURL), reader: timeoutReader, timeout: 0.05)
        let timed = Task { try await timeoutSession.load() }
        defer { timeoutReader.release.signal(); timed.cancel() }
        try await wait { timeoutReader.started.wait(timeout: .now()) == .success }
        try await expect(.timedOut) { _ = try await timed.value }
        try await wait { timeoutReader.wasCancelled }
        try check(timeoutReader.wasCancelled, "Deadline cancels reader")
        timeoutReader.release.signal()
        try await wait { timeoutReader.finished.wait(timeout: .now()) == .success }
        let timedState = await timeoutSession.state
        try check(timedState == .failed(.timedOut), "Late result cannot replace timeout")
        try await expect(.invalidState) { _ = try await timeoutSession.take() }

        let decoder = HeldDecoder(), decodeSession = ChatAttachmentImportSession(selection: try select(directory.appendingPathComponent("photo.png")), decoder: decoder)
        let decoding = Task { try await decodeSession.load() }
        defer { decoder.release.signal(); decoding.cancel() }
        try await wait { decoder.started.wait(timeout: .now()) == .success }
        decoding.cancel()
        try await expect(.cancelled) { _ = try await decoding.value }
        decoder.release.signal()
        try await wait { decoder.finished.wait(timeout: .now()) == .success }
        let decodeState = await decodeSession.state
        try check(decodeState == .discarded, "Cancelled decode cannot republish")
        try await expect(.invalidState) { _ = try await decodeSession.take() }
        print("Chat attachment import checks passed: \(checks)")
    }
}
