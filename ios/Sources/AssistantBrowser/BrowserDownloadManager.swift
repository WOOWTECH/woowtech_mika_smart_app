#if canImport(WebKit)
import Foundation
import WebKit

/// The browser's downloads, one for the app: the browser's tabs and a web
/// task's page while the person has it (我來處理) hand their WKDownloads here.
/// Each download first asks the person (`question`) with its file name, size
/// when known and site; only 下載 lets WebKit write the file, into the app's
/// own folder (PendingFileFolder). A finished file waits there for 存到檔案,
/// 分享, 附加到對話 or 移除, and is deleted after any of them. Callers decide
/// that a download is the person's own: a task never downloads.
@MainActor
public final class BrowserDownloadManager: NSObject, ObservableObject, WKDownloadDelegate {
    @Published public private(set) var items: [BrowserDownloadItem] = []
    /// The download waiting for the person's answer; one question at a time.
    @Published public private(set) var question: BrowserDownloadItem?
    /// A download that finished or failed while the list was closed, for a note that opens it.
    @Published public var notice: BrowserDownloadItem?
    public let limits: BrowserDownloadLimits
    private let partial: PendingFileFolder
    private let files: PendingFileFolder
    private let allowsURL: (URL) -> Bool
    private var transfers: [UUID: Transfer] = [:]
    private var polling: Task<Void, Never>?
    /// The list is on screen, so a finished download needs no note.
    public var listIsOpen = false

    private final class Transfer {
        let download: WKDownload
        var decide: ((URL?) -> Void)?
        var destination: URL?
        var redirects = 0
        init(download: WKDownload) { self.download = download }
    }

    /// `root` holds Partial (arriving) and Files (finished). At start, what an
    /// earlier run left arriving is deleted (WebKit cannot resume it), and so
    /// are finished files older than a day and shared files whose moment has
    /// passed; the rest are listed again, never a file already shared.
    public init(root: URL, limits: BrowserDownloadLimits = .init(), now: Date = Date(),
                allowsURL: @escaping (URL) -> Bool = BrowserManualNavigationPolicy.allows) {
        partial = PendingFileFolder(root: root.appendingPathComponent("Partial", isDirectory: true))
        files = PendingFileFolder(root: root.appendingPathComponent("Files", isDirectory: true))
        self.limits = limits
        self.allowsURL = allowsURL
        super.init()
        partial.purge(olderThan: -1, now: now)
        files.purge(now: now)
        let finished = files.items().filter { item in
            guard item.deleteAt != nil else { return true }
            self.files.deleteWhenDue(item.id, now: now)
            return false
        }
        items = finished.sorted { $0.modified > $1.modified }.prefix(limits.maximumListed).compactMap { item in
            guard let file = self.files.files(in: item.folder).first,
                  let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                self.files.remove(item.id)
                return nil
            }
            var restored = BrowserDownloadItem(id: item.id, fileName: file.lastPathComponent, host: "", phase: .finished)
            restored.receivedBytes = Int64(size); restored.expectedBytes = Int64(size); restored.fileURL = file
            return restored
        }
    }

    /// Library/Caches/Downloads of this app.
    public static func live() -> BrowserDownloadManager {
        BrowserDownloadManager(root: PendingFileFolder.live("Downloads").root)
    }

    /// Takes a download the caller already decided is the person's own. It
    /// asks once WebKit has the response; more than the limit are refused.
    public func accept(_ download: WKDownload, from url: URL?) {
        let item = BrowserDownloadItem(fileName: BrowserDownloadRules.fileName(url?.lastPathComponent ?? ""),
                                       host: BrowserDownloadRules.host(of: url))
        insert(item)
        guard url.map(allowsURL) == true else { download.cancel(nil); end(item.id, .failed(.unsafeAddress)); return }
        guard items.filter({ $0.phase.isActive }).count <= limits.maximumActive else {
            download.cancel(nil); end(item.id, .failed(.tooMany)); return
        }
        transfers[item.id] = Transfer(download: download)
        download.delegate = self
    }

    /// The person's answer to `question`.
    public func answer(_ id: UUID, allowed: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].phase == .asking,
              let transfer = transfers[id], let decide = transfer.decide else { return }
        transfer.decide = nil
        if question?.id == id { question = nil }
        guard items[index].answer(allowed, now: Date(), limits: limits) else {
            decide(nil)
            finish(id)
            // Declined: nothing was downloaded, so nothing is listed.
            if items[index].phase == .cancelled { items.remove(at: index) }
            nextQuestion()
            return
        }
        do {
            let folder = try partial.folder(for: id)
            let destination = folder.appendingPathComponent(items[index].fileName)
            transfer.destination = destination
            decide(destination)
            startPolling()
        } catch {
            decide(nil)
            end(id, .failed(.unavailable))
        }
        nextQuestion()
    }

    /// Stops a download still asking or arriving; its partial file is deleted.
    public func cancel(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }), item.phase.isActive else { return }
        if item.phase == .asking { answer(id, allowed: false); return }
        stop(id, .cancelled)
    }

    /// The finished file, while it is still in the app.
    public func file(_ id: UUID) -> URL? {
        guard let item = items.first(where: { $0.id == id }), item.phase == .finished, let url = item.fileURL,
              FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        return url
    }

    /// Saved, shared or attached: the app's copy is deleted, after a share a
    /// little later while the receiving app may still read it. That deletion
    /// is noted on disk, so a restart before then deletes the file and never
    /// lists it again.
    public func delivered(_ id: UUID, as delivery: BrowserDownloadItem.Delivery, deleteAfter delay: TimeInterval = 0) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].phase == .finished else { return }
        items[index].phase = .delivered(delivery)
        items[index].fileURL = nil
        files.remove(id, after: delay)
    }

    /// Takes the download off the list; a finished file is deleted with it.
    public func remove(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), !items[index].phase.isActive else { return }
        if items[index].phase == .finished { files.remove(id) }
        items.remove(at: index)
        if notice?.id == id { notice = nil }
    }

    /// Stops every download still asking or arriving (the website data is being removed).
    public func cancelAll() {
        for item in items where item.phase.isActive { cancel(item.id) }
    }

    // MARK: WKDownloadDelegate

    public func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                         suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard let (id, transfer) = transfer(of: download), let index = items.firstIndex(where: { $0.id == id }),
              items[index].phase == .starting else { completionHandler(nil); return }
        let expected = response.expectedContentLength >= 0 ? response.expectedContentLength : nil
        let failure: BrowserDownloadFailure?
        if response.url.map(allowsURL) != true { failure = .unsafeAddress }
        else if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { failure = .network }
        else {
            failure = BrowserDownloadRules.refusal(expectedBytes: expected, storedBytes: storedBytes(excluding: id),
                                                   active: items.filter { $0.phase.isActive && $0.id != id }.count, limits: limits)
        }
        if let failure { completionHandler(nil); end(id, .failed(failure)); return }
        items[index].ask(fileName: BrowserDownloadRules.fileName(suggestedFilename), expectedBytes: expected,
                         host: BrowserDownloadRules.host(of: response.url), now: Date())
        transfer.decide = completionHandler
        if question == nil { question = items[index] }
        // Unanswered in time, the download is dropped and its question closes.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.limits.answerTime ?? 120) * 1_000_000_000))
            guard let self, let index = self.items.firstIndex(where: { $0.id == id }),
                  self.items[index].expire(now: Date(), limits: self.limits) else { return }
            self.transfers[id]?.decide?(nil)
            self.transfers[id]?.decide = nil
            self.finish(id)
            self.nextQuestion()
        }
    }

    public func download(_ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse,
                         newRequest request: URLRequest, decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void) {
        guard let (id, transfer) = transfer(of: download) else { decisionHandler(.cancel); return }
        transfer.redirects += 1
        guard transfer.redirects <= limits.maximumRedirects, request.url.map(allowsURL) == true else {
            decisionHandler(.cancel)
            stop(id, .failed(.unsafeAddress))
            return
        }
        decisionHandler(.allow)
    }

    public func download(_ download: WKDownload, didReceive challenge: URLAuthenticationChallenge,
                         completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // The system's own trust evaluation, once; no bypass and no copied credentials.
        completionHandler(challenge.previousFailureCount == 0 ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }

    public func downloadDidFinish(_ download: WKDownload) {
        guard let (id, transfer) = transfer(of: download), let index = items.firstIndex(where: { $0.id == id }),
              items[index].phase == .downloading, let source = transfer.destination else { return }
        let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
        guard let size else { end(id, .failed(.unavailable)); return }
        if let failure = BrowserDownloadRules.refusal(receivedBytes: size, storedBytes: storedBytes(excluding: id), limits: limits) {
            end(id, .failed(failure)); return
        }
        do {
            let target = try files.folder(for: id).appendingPathComponent(source.lastPathComponent)
            try FileManager.default.moveItem(at: source, to: target)
            files.protect(target)
            items[index].receivedBytes = size
            items[index].fileURL = target
            items[index].phase = .finished
            finish(id)
            if !listIsOpen { notice = items[index] }
        } catch {
            files.remove(id)
            end(id, .failed(BrowserDownloadRules.isDeviceFull(error) ? .deviceFull : .unavailable))
        }
    }

    public func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        // Resume data and the error may hold signed URLs or session data: neither is kept.
        guard let (id, _) = transfer(of: download) else { return }
        guard let item = items.first(where: { $0.id == id }), item.phase.isActive else { finish(id); return }
        end(id, .failed(BrowserDownloadRules.isDeviceFull(error) ? .deviceFull : .network))
    }

    // MARK: Bookkeeping

    private func transfer(of download: WKDownload) -> (UUID, Transfer)? {
        transfers.first { $0.value.download === download }.map { ($0.key, $0.value) }
    }

    /// What waits in the app and what the downloads arriving have already brought or announced.
    private func storedBytes(excluding id: UUID) -> Int64 {
        files.storedBytes() + items.filter { $0.phase == .downloading && $0.id != id }
            .reduce(0) { $0 + max($1.receivedBytes, $1.expectedBytes ?? 0) }
    }

    private func insert(_ item: BrowserDownloadItem) {
        items.insert(item, at: 0)
        // The oldest ended entries leave the list; a finished file stays listed.
        while items.count > limits.maximumListed,
              let last = items.lastIndex(where: { !$0.phase.isActive && $0.phase != .finished }) {
            items.remove(at: last)
        }
    }

    private func stop(_ id: UUID, _ phase: BrowserDownloadItem.Phase) {
        guard let transfer = transfers[id] else { end(id, phase); return }
        set(id, phase)
        transfer.decide?(nil)
        transfer.decide = nil
        // Wait for WebKit before deleting the partial file, or it could write it again.
        transfer.download.cancel { [weak self] _ in
            Task { @MainActor in self?.finish(id) }
        }
    }

    /// The download ended with `phase`; its partial file is deleted.
    private func end(_ id: UUID, _ phase: BrowserDownloadItem.Phase) {
        set(id, phase)
        finish(id)
        nextQuestion()
    }

    private func set(_ id: UUID, _ phase: BrowserDownloadItem.Phase) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].phase = phase
        if question?.id == id { question = nil }
        if case .failed = phase, !listIsOpen { notice = items[index] }
    }

    private func finish(_ id: UUID) {
        if let transfer = transfers.removeValue(forKey: id) { transfer.download.delegate = nil }
        partial.remove(id)
        if question?.id == id { question = nil }
        if transfers.values.allSatisfy({ $0.destination == nil }) { polling?.cancel(); polling = nil }
    }

    private func nextQuestion() {
        guard question == nil else { return }
        question = items.last { $0.phase == .asking }
    }

    /// Progress four times a second; a file that passes a limit while it arrives is stopped.
    private func startPolling() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, !Task.isCancelled else { return }
                self.poll()
            }
        }
    }

    private func poll() {
        for (id, transfer) in transfers where transfer.destination != nil {
            guard let index = items.firstIndex(where: { $0.id == id }), items[index].phase == .downloading else { continue }
            let progress = transfer.download.progress
            let received = max(0, progress.completedUnitCount)
            items[index].receivedBytes = received
            if progress.totalUnitCount > 0 { items[index].expectedBytes = progress.totalUnitCount }
            if let failure = BrowserDownloadRules.refusal(receivedBytes: max(received, items[index].expectedBytes ?? 0),
                                                          storedBytes: storedBytes(excluding: id), limits: limits) {
                stop(id, .failed(failure))
            }
        }
    }
}
#endif
