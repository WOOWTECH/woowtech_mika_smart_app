import AssistantModels
import Darwin
import Foundation

/// Reads only the exact picker-selected URL within its security scope. Uses
/// descriptor-based checks and a hard streaming cap; never creates a copy.
public final class CoordinatedAttachmentReader: ChatAttachmentFileReading, @unchecked Sendable {
    private let coordinator = NSFileCoordinator(filePresenter: nil)
    public init() {}
    public func cancel() { coordinator.cancel() }

    public func read(url: URL, maximumBytes: Int, isCancelled: @escaping @Sendable () -> Bool) throws -> Data {
        guard maximumBytes > 0, maximumBytes <= ModelAttachment.maximumImageBytes else {
            throw ChatAttachmentImportError.tooLarge
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard !isCancelled() else { throw ChatAttachmentImportError.cancelled }
        var selected = stat()
        guard url.withUnsafeFileSystemRepresentation({ $0.map { lstat($0, &selected) } ?? -1 }) == 0,
              selected.st_mode & S_IFMT == S_IFREG else { throw ChatAttachmentImportError.unreadable }
        var coordinationError: NSError?
        var outcome: Result<Data, Error>?
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            outcome = Result {
                guard !isCancelled() else { throw ChatAttachmentImportError.cancelled }
                let fd = coordinatedURL.withUnsafeFileSystemRepresentation {
                    $0.map { Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) } ?? -1
                }
                guard fd >= 0 else { throw ChatAttachmentImportError.unreadable }
                defer { Darwin.close(fd) }
                var before = stat()
                guard fstat(fd, &before) == 0, (before.st_mode & S_IFMT) == S_IFREG, before.st_size >= 0 else {
                    throw ChatAttachmentImportError.unreadable
                }
                // Refuse replacement or a coordinator resolving a selected
                // symlink to another object. A provider that substitutes a
                // different inode must be selected again after materialization.
                var named = stat()
                guard url.withUnsafeFileSystemRepresentation({ $0.map { lstat($0, &named) } ?? -1 }) == 0,
                      named.st_mode & S_IFMT == S_IFREG,
                      selected.st_dev == before.st_dev, selected.st_ino == before.st_ino,
                      named.st_dev == before.st_dev, named.st_ino == before.st_ino else {
                    throw ChatAttachmentImportError.unreadable
                }
                guard before.st_size <= maximumBytes else { throw ChatAttachmentImportError.tooLarge }
                var data = Data(), buffer = [UInt8](repeating: 0, count: 8192)
                while true {
                    guard !isCancelled() else { throw ChatAttachmentImportError.cancelled }
                    let available = min(buffer.count, maximumBytes + 1 - data.count)
                    let count = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, available) }
                    if count < 0 { if errno == EINTR { continue }; throw ChatAttachmentImportError.unreadable }
                    if count == 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                    guard data.count <= maximumBytes else { throw ChatAttachmentImportError.tooLarge }
                }
                var after = stat()
                guard !isCancelled() else { throw ChatAttachmentImportError.cancelled }
                guard url.withUnsafeFileSystemRepresentation({ $0.map { lstat($0, &named) } ?? -1 }) == 0,
                      named.st_mode & S_IFMT == S_IFREG, named.st_dev == before.st_dev, named.st_ino == before.st_ino,
                      fstat(fd, &after) == 0, before.st_dev == after.st_dev, before.st_ino == after.st_ino,
                      before.st_size == after.st_size, after.st_size == data.count,
                      before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
                      before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
                      before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
                      before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else {
                    throw ChatAttachmentImportError.unreadable
                }
                return data
            }
        }
        guard !isCancelled() else { throw ChatAttachmentImportError.cancelled }
        guard coordinationError == nil, let outcome else { throw ChatAttachmentImportError.unreadable }
        return try outcome.get()
    }
}
