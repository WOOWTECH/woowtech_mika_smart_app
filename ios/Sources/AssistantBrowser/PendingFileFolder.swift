import Foundation

/// Files that wait in the app for the person: browser downloads and files the
/// assistant made. Each item has a folder named by its UUID under `root`, in
/// Caches, excluded from backup and readable only by the app; its file is
/// protected until the device is first unlocked. Nothing here reaches Files,
/// another app or anyone else until the person taps 存到檔案 or 分享, and an item
/// is deleted once it was saved, shared or dismissed. Leftovers older than a
/// day are deleted when the app starts.
public struct PendingFileFolder: Sendable {
    public static let retention: TimeInterval = 24 * 60 * 60
    public let root: URL

    public init(root: URL) { self.root = root.standardizedFileURL }

    /// Library/Caches/<name> of this app.
    public static func live(_ name: String) -> PendingFileFolder {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return PendingFileFolder(root: caches.appendingPathComponent(name, isDirectory: true))
    }

    /// The item's own folder, made empty for its one file.
    public func folder(for id: UUID) throws -> URL {
        try make(root)
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: folder.path) else { throw CocoaError(.fileWriteFileExists) }
        try make(folder)
        return folder
    }

    /// Writes one file into a new item folder; nothing is left on failure.
    public func write(_ data: Data, named name: String, id: UUID) throws -> URL {
        let folder = try folder(for: id)
        let file = folder.appendingPathComponent(name)
        do {
            try data.write(to: file, options: [.withoutOverwriting, .completeFileProtectionUntilFirstUserAuthentication])
            return file
        } catch {
            remove(id)
            throw error
        }
    }

    /// For a file written by someone else (WebKit's download), once it is complete.
    public func protect(_ file: URL) {
        #if os(iOS)
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                               ofItemAtPath: file.path)
        #endif
    }

    public func remove(_ id: UUID) {
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        // removeItem removes a link itself, never what it points to.
        try? FileManager.default.removeItem(at: folder)
    }

    /// The item folders and the time each last changed; other names are not the app's and are left alone.
    public func items() -> [(id: UUID, folder: URL, modified: Date)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey, .isSymbolicLinkKey]
        guard let contents = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: keys) else { return [] }
        return contents.compactMap { url in
            guard let id = UUID(uuidString: url.lastPathComponent), id.uuidString == url.lastPathComponent,
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            return (id, url, values.contentModificationDate ?? .distantPast)
        }
    }

    /// The regular files in an item's folder, not counting the app's own notes (names starting with ".").
    public func files(in folder: URL) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        return contents.filter { url in
            guard !url.lastPathComponent.hasPrefix("."), let values = try? url.resourceValues(forKeys: Set(keys)) else { return false }
            return values.isRegularFile == true && values.isSymbolicLink != true
        }
    }

    /// Bytes of every item's files, so a new one can be refused before it fills the device.
    public func storedBytes() -> Int64 {
        items().reduce(0) { total, item in
            total + files(in: item.folder).reduce(0) { sum, file in
                sum + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
        }
    }

    /// Deletes item folders that last changed more than `age` before `now`,
    /// except `keeping`; returns what it deleted. Links and other names stay.
    @discardableResult
    public func purge(olderThan age: TimeInterval = PendingFileFolder.retention, now: Date = Date(),
                      keeping: Set<UUID> = []) -> [UUID] {
        var removed: [UUID] = []
        for item in items() where !keeping.contains(item.id) && now.timeIntervalSince(item.modified) > age {
            remove(item.id)
            removed.append(item.id)
        }
        return removed
    }

    private func make(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var url = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}
