import AssistantModels
import AssistantPersistence
import CryptoKit
import Darwin
import Foundation

/// Explicit local reproduction only. Never writes the personal archive, uses a
/// live model credential, or invokes a model/MCP service. Relaunch resets only the
/// named diagnostic directory to the same source prefix and actual file bytes.
@MainActor enum ChatLayoutReplay {
    struct Configuration {
        let source: UUID
        let namespace: UUID
        let turns: Int

        static func resolve(_ arguments: [String]) throws -> Configuration? {
            let prefix = "-WoowLayoutReplay"
            guard arguments.contains(where: { $0.hasPrefix(prefix) }) else { return nil }
            let flags = [prefix + "Source", prefix + "Namespace", prefix + "Turns"]
            guard arguments.filter({ $0 == "-WoowLayoutDiagnostics" }).count == 1,
                  flags.allSatisfy({ flag in arguments.filter { $0 == flag }.count == 1 }),
                  !arguments.contains(where: { $0.hasPrefix(prefix) && !flags.contains($0) }),
                  !arguments.contains(where: { $0.hasPrefix("-UITest") || $0.hasPrefix("-Live") })
            else { throw Failure.invalidArguments }
            func value(_ flag: String) throws -> String {
                guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
                    throw Failure.invalidArguments
                }
                return arguments[index + 1]
            }
            guard let source = UUID(uuidString: try value(flags[0])),
                  let namespace = UUID(uuidString: try value(flags[1])), source != namespace,
                  let count = Int(try value(flags[2])), (1...25).contains(count)
            else { throw Failure.invalidArguments }
            return Configuration(source: source, namespace: namespace, turns: count)
        }
    }

    enum Failure: Error { case invalidArguments, missingSource, unsafeFile, tooLarge, copyMismatch, setup }
    static var requested: Bool {
        ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("-WoowLayoutReplay") }
    }

    static func makeSession() -> ChatSession {
        do {
            guard let configuration = try Configuration.resolve(ProcessInfo.processInfo.arguments) else {
                return ChatSession()
            }
            let location = try ConversationArchiveStore.location(arguments: [])
            let sourceFile = EncryptedLearningFile(url: location.url,
                keys: LearningKeychainStore(service: location.service))
            // load only: no save/rotation, no personal defaults or credential sweep.
            let source = try sourceFile.load(ConversationArchive.self)
            guard let record = source?.conversations.first(where: { $0.id == configuration.source }),
                  record.turns.count >= configuration.turns else { throw Failure.missingSource }
            return try makeIsolatedSession(configuration, record: record,
                sourceAttachments: ChatAttachmentStore.live(arguments: []).root)
        } catch {
            // Invalid explicit diagnostic setup must never silently select live storage/network.
            preconditionFailure("Local layout reproduction could not initialize; live mode was not opened.")
        }
    }

    static func makeIsolatedSession(_ configuration: Configuration, record: ArchivedConversation,
                                   sourceAttachments: URL,
                                   base: URL = FileManager.default.temporaryDirectory) throws -> ChatSession {
            guard record.id == configuration.source, (1...25).contains(configuration.turns),
                  record.turns.count >= configuration.turns else { throw Failure.missingSource }
            let root = try resetDirectory(configuration.namespace, base: base)
            let store = ChatAttachmentStore(root: root.appendingPathComponent("attachments", isDirectory: true))
            let prefix = Array(record.turns.prefix(configuration.turns))
            let fingerprint = try copyAttachments(prefix, from: sourceAttachments, to: store.root)
            try verifyBaseline(fingerprint, namespace: configuration.namespace, parent: root.deletingLastPathComponent())

            // Ephemeral keys/credentials exist only in RAM; no personal Keychain writes.
            let archiveFile = EncryptedLearningFile(url: root.appendingPathComponent("archive.vault"), keys: Keys())
            let archive = ConversationArchiveStore(vault: archiveFile)
            let duplicate = try ArchivedConversation(id: record.id, destination: record.destination,
                updatedAt: record.updatedAt, turns: prefix)
            try archive.save(duplicate, expected: nil)
            let suite = "io.woowtech.assistant.layout-replay." + configuration.namespace.uuidString
            guard let defaults = UserDefaults(suiteName: suite) else { throw Failure.setup }
            defaults.removePersistentDomain(forName: suite)
            let repository = ModelSettingsRepository(defaults: defaults, credentials: Credentials())
            _ = try repository.save(baseURL: "https://layout-replay.invalid/v1", model: "local-layout-replay",
                                    newKey: "local-diagnostic-placeholder")
            try repository.recordConsentForMain()
            let learning = LearningStore(vault: EncryptedLearningFile(
                url: root.appendingPathComponent("learning.vault"), keys: Keys()))
            let session = ChatSession(learning: learning, repository: repository, client: LocalFailure(),
                                      archive: archive, attachmentStore: store)
            guard session.openConversation(id: record.id), session.entries.count == configuration.turns * 2 else {
                throw Failure.setup
            }
            return session
    }

    static func resetDirectory(_ namespace: UUID, base: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let manager = FileManager.default
        let parent = base.resolvingSymlinksInPath().appendingPathComponent("ChatLayoutReplay", isDirectory: true)
        let root = parent.appendingPathComponent(namespace.uuidString, isDirectory: true)
        guard parent.standardizedFileURL.path == parent.resolvingSymlinksInPath().standardizedFileURL.path,
              root.standardizedFileURL.path == root.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw Failure.unsafeFile
        }
        if manager.fileExists(atPath: root.path) { try manager.removeItem(at: root) }
        try manager.createDirectory(at: root, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        return root
    }

    @discardableResult
    static func copyAttachments(_ turns: [ArchivedConversationTurn], from source: URL, to destination: URL) throws -> String {
        let manager = FileManager.default
        if let kind = try? manager.attributesOfItem(atPath: source.path)[.type] as? FileAttributeType,
           kind == .typeSymbolicLink { throw Failure.unsafeFile }
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        let destination = destination.standardizedFileURL
        guard destination.path == destination.resolvingSymlinksInPath().standardizedFileURL.path else { throw Failure.unsafeFile }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var digest = SHA256()
        digest.update(data: try encoder.encode(turns))
        var bytes = 0
        var copied = Set<String>()
        for attachment in turns.flatMap(\.attachments) where copied.insert(attachment.relativePath).inserted {
            let input = source.appendingPathComponent(attachment.relativePath).standardizedFileURL
            let output = destination.appendingPathComponent(attachment.relativePath).standardizedFileURL
            guard input.path.hasPrefix(source.path + "/"), output.path.hasPrefix(destination.path + "/"),
                  input.path == input.resolvingSymlinksInPath().standardizedFileURL.path,
                  output.path == output.resolvingSymlinksInPath().standardizedFileURL.path else { throw Failure.unsafeFile }
            let attributes = try manager.attributesOfItem(atPath: input.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber, size.int64Value == attachment.byteCount,
                  size.int64Value >= 0, size.int64Value <= 16 * 1024 * 1024 - Int64(bytes) else {
                throw Failure.tooLarge
            }
            let data = try boundedRead(input, limit: 16 * 1024 * 1024 - bytes)
            guard data.count == size.intValue else { throw Failure.copyMismatch }
            bytes += data.count
            try manager.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: output, options: .atomic)
            guard try boundedRead(output, limit: data.count) == data else { throw Failure.copyMismatch }
            digest.update(data: data)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func boundedRead(_ url: URL, limit: Int) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw Failure.unsafeFile }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var state = stat()
        guard fstat(descriptor, &state) == 0, state.st_mode & S_IFMT == S_IFREG else { throw Failure.unsafeFile }
        var data = Data()
        while true {
            let chunk = try handle.read(upToCount: min(65_536, limit + 1 - data.count)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
            guard data.count <= limit else { throw Failure.tooLarge }
        }
        return data
    }

    /// Hash only; survives namespace reset so changed source text/images fail closed.
    private static func verifyBaseline(_ fingerprint: String, namespace: UUID, parent: URL) throws {
        let path = parent.appendingPathComponent(namespace.uuidString + ".sha256")
        let expected = Data(fingerprint.utf8)
        if FileManager.default.fileExists(atPath: path.path) {
            guard try boundedRead(path, limit: 64) == expected else { throw Failure.copyMismatch }
        } else {
            try expected.write(to: path, options: .withoutOverwriting)
        }
    }

    private final class Keys: LearningKeyStore {
        private var values: [String: Data] = [:]
        func read(id: String) throws -> Data? { values[id] }
        func insert(_ key: Data, id: String) throws { values[id] = key }
        func remove(id: String) throws { values[id] = nil }
        func removeAll(except id: String) throws { values = values.filter { $0.key == id } }
    }

    private final class Credentials: ModelCredentialStoring {
        private var values: [String: String] = [:]
        func read(account: String) throws -> String? { values[account] }
        func insert(_ key: String, account: String) throws { values[account] = key }
        func remove(account: String) throws { values[account] = nil }
        func removeAll() throws { values.removeAll() }
        func allAccounts() throws -> Set<String>? { Set(values.keys) }
    }

    struct LocalFailure: ChatModelClient {
        func complete(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> String {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            throw HTTPChatModelError.httpStatus(429)
        }
    }
}
