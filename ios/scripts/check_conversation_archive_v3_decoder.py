#!/usr/bin/env python3
"""Compare current archive bytes with exact historical v3 and v4 decoders.

The unmodified source fixtures keep these checks usable in shallow checkouts.
"""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile


OLD_SHA256 = "e65e62b6f0c0ab4f5a9e0c5295588f7741c73295bed374ab9c7d2ebe0ddc065a"
V4_SHA256 = "8793560d0738f8aa758bbb834c00c4f119f37b46ba21374bb78b85750fd2d664"
PDF_SHA256 = "0a16c0cc7a8028c22386159ce6dcab83d8d6e08580a07d27d485cebbd2d6b70e"
ROOT = Path(__file__).resolve().parents[1]

WRITER = r'''
import AssistantPersistence
import Foundation

@main enum WriteFixtures {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let destination = try ConversationDestination(baseURL: "https://fixture.invalid",
            model: "fixture", credentialAccount: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let record = try ArchivedConversation(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            destination: destination, updatedAt: Date(timeIntervalSince1970: 100),
            turns: [.init(userText: "synthetic request", assistantText: "synthetic answer")])
        var archive = ConversationArchive()
        func save(_ name: String) throws {
            try JSONEncoder().encode(archive).write(to: root.appendingPathComponent(name + ".json"))
        }
        try archive.save(record)
        try save("v2")
        try archive.rename(id: record.id, expectedTitle: nil, to: "synthetic title")
        try save("v3")
        let pinTime = Date(timeIntervalSince1970: 200)
        try archive.setPinned(id: record.id, expectedPinnedAt: nil, pinned: true, at: pinTime)
        try save("v4-pinned")
        try archive.setPinned(id: record.id, expectedPinnedAt: pinTime, pinned: false)
        try save("v4-unpinned")
        let current = archive.conversations[0]
        let plan = try ConversationBranchPlan.prepare(in: archive, source: current,
            assistantID: current.turns[0].assistantID, targetID: UUID(), title: "branch",
            at: Date(timeIntervalSince1970: 300), isBusy: false, hasUnfinishedOrUnsavedTurn: false)
        let branched = try plan.applying(to: archive, isBusy: false, hasUnfinishedOrUnsavedTurn: false)
        try JSONEncoder().encode(branched).write(to: root.appendingPathComponent("v5-branch.json"))
        try archive.delete(id: record.id)
        try save("v4-empty")
    }
}
'''

OLD_READER = r'''
import Foundation
import LegacyPersistence

@main enum ReadFixtures {
    enum Failure: Error { case result }
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        func data(_ name: String) throws -> Data {
            try Data(contentsOf: root.appendingPathComponent(name + ".json"))
        }
        func decode(_ bytes: Data) throws -> ConversationArchive {
            try JSONDecoder().decode(ConversationArchive.self, from: bytes)
        }
        let v2 = try decode(data("v2"))
        let v3 = try decode(data("v3"))
        guard v2.conversations.count == 1, v2.conversations[0].turns[0].assistantText == "synthetic answer",
              v3.conversations.count == 1, v3.conversations[0].customTitle == "synthetic title",
              v3.conversations[0].turns == v2.conversations[0].turns else { throw Failure.result }
        let v3Written = try JSONSerialization.jsonObject(with: JSONEncoder().encode(v3)) as! [String: Any]
        guard v3Written["version"] as? Int == 3,
              (v3Written["conversations"] as! [[String: Any]])[0]["customTitle"] as? String == "synthetic title"
        else { throw Failure.result }
        var oldAuthored = v2
        try oldAuthored.rename(id: v2.conversations[0].id, expectedTitle: nil, to: "legacy title")
        try JSONEncoder().encode(oldAuthored).write(to: root.appendingPathComponent("old-v3.json"))
        for name in ["v4-pinned", "v4-unpinned", "v4-empty"] {
            do { _ = try decode(data(name)); throw Failure.result }
            catch ConversationArchiveError.invalidData { }
        }
        // Demonstrate the real old decoder's unsafe behavior if a pin is
        // incorrectly written under v3. It accepts that row, then omits pin.
        var forged = try JSONSerialization.jsonObject(with: data("v4-pinned")) as! [String: Any]
        forged["version"] = 3
        let wronglyVersioned = try JSONSerialization.data(withJSONObject: forged)
        let oldAccepted = try decode(wronglyVersioned)
        let oldReencoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(oldAccepted)) as! [String: Any]
        let oldRow = (oldReencoded["conversations"] as! [[String: Any]])[0]
        guard oldRow["pinnedAt"] == nil, oldRow["customTitle"] as? String == "synthetic title"
        else { throw Failure.result }
        print("old_source_v2_v3_read=PASS old_source_v4_pin_unpin_empty_reject=PASS wrong_v3_drops_pin=CONFIRMED")
    }
}
'''

CURRENT_READER = r'''
import AssistantPersistence
import Foundation

@main enum ReadOldV3 {
    enum Failure: Error { case result }
    static func version(_ archive: ConversationArchive) throws -> Int {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as! [String: Any]
        return object["version"] as! Int
    }
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let oldBytes = try Data(contentsOf: root.appendingPathComponent("old-v3.json"))
        var archive = try JSONDecoder().decode(ConversationArchive.self, from: oldBytes)
        guard try version(archive) == 3, archive.conversations.count == 1,
              archive.conversations[0].customTitle == "legacy title",
              archive.conversations[0].pinnedAt == nil,
              archive.conversations[0].turns[0].assistantText == "synthetic answer"
        else { throw Failure.result }
        let row = archive.conversations[0]
        let appended = try ArchivedConversation(id: row.id, destination: row.destination,
            updatedAt: Date(timeIntervalSince1970: 150),
            turns: row.turns + [.init(userText: "later", assistantText: "continued")])
        try archive.save(appended)
        try archive.rename(id: row.id, expectedTitle: "legacy title", to: "new title")
        guard try version(archive) == 3, archive.conversations[0].turns.count == 2,
              archive.conversations[0].customTitle == "new title" else { throw Failure.result }
        let pinTime = Date(timeIntervalSince1970: 200)
        try archive.setPinned(id: row.id, expectedPinnedAt: nil, pinned: true, at: pinTime)
        guard try version(archive) == 4, archive.conversations[0].turns.count == 2,
              archive.conversations[0].customTitle == "new title" else { throw Failure.result }
        try archive.setPinned(id: row.id, expectedPinnedAt: pinTime, pinned: false)
        guard try version(archive) == 4, archive.conversations[0].pinnedAt == nil
        else { throw Failure.result }
        print("new_reader_old_authored_v3=PASS title_only_rewrite_v3=PASS first_pin_v4_no_downgrade=PASS")
    }
}
'''


V4_READER = r'''
import Foundation
import LegacyV4Persistence

@main enum ReadWithV4 {
    enum Failure: Error { case result }
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        func data(_ name: String) throws -> Data {
            try Data(contentsOf: root.appendingPathComponent(name + ".json"))
        }
        for name in ["v2", "v3", "v4-pinned", "v4-unpinned", "v4-empty"] {
            let decoded = try JSONDecoder().decode(ConversationArchive.self, from: data(name))
            let before = try JSONSerialization.jsonObject(with: data(name)) as! [String: Any]
            let after = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as! [String: Any]
            guard before["version"] as? Int == after["version"] as? Int else { throw Failure.result }
        }
        do {
            _ = try JSONDecoder().decode(ConversationArchive.self, from: data("v5-branch"))
            throw Failure.result
        } catch ConversationArchiveError.invalidData { }
        // Demonstrate why falsely claiming v4 would silently drop provenance.
        var forged = try JSONSerialization.jsonObject(with: data("v5-branch")) as! [String: Any]
        forged["version"] = 4
        let decoded = try JSONDecoder().decode(ConversationArchive.self, from: JSONSerialization.data(withJSONObject: forged))
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as! [String: Any]
        let rows = encoded["conversations"] as! [[String: Any]]
        guard rows.count == 2 && rows.allSatisfy({ $0["branchOrigin"] == nil }) else { throw Failure.result }
        print("actual_v4_reads_v2_v3_v4=PASS actual_v4_rejects_v5=PASS forged_v4_drops_origin=CONFIRMED")
    }
}
'''


def run(command, *, cwd, env):
    subprocess.run(command, cwd=cwd, env=env, check=True, timeout=120,
                   stdout=subprocess.DEVNULL if command[0] == "swiftc" else None)


def main():
    old_file = ROOT / "Tests/Fixtures/ConversationArchive_0c9827e.txt"
    v4_file = ROOT / "Tests/Fixtures/ConversationArchive_v4_c3f0cf5.txt"
    pdf_file = ROOT / "Sources/AssistantPersistence/ArchivedPDFAnswer.swift"
    if hashlib.sha256(old_file.read_bytes()).hexdigest() != OLD_SHA256:
        raise RuntimeError("old decoder fixture changed")
    if hashlib.sha256(v4_file.read_bytes()).hexdigest() != V4_SHA256:
        raise RuntimeError("v4 decoder fixture changed")
    if hashlib.sha256(pdf_file.read_bytes()).hexdigest() != PDF_SHA256:
        raise RuntimeError("shared PDF value decoder changed; recheck historic equivalence")
    env = {key: os.environ[key] for key in ("PATH", "DEVELOPER_DIR", "SDKROOT", "TMPDIR") if key in os.environ}
    with tempfile.TemporaryDirectory(prefix="woow-archive-v3-decoder-") as directory:
        out = Path(directory)
        legacy_source = out / "ConversationArchive_0c9827e.swift"
        legacy_source.write_bytes(old_file.read_bytes())
        v4_source = out / "ConversationArchive_v4.swift"
        v4_source.write_bytes(v4_file.read_bytes())
        writer_source = out / "WriteFixtures.swift"
        reader_source = out / "ReadFixtures.swift"
        current_source = out / "ReadOldV3.swift"
        writer_source.write_text(WRITER)
        reader_source.write_text(OLD_READER)
        current_source.write_text(CURRENT_READER)
        v4_reader_source = out / "ReadWithV4.swift"
        v4_reader_source.write_text(V4_READER)
        module_options = ["-swift-version", "5", "-parse-as-library", "-emit-module", "-emit-library"]
        run(["swiftc", *module_options, "-module-name", "AssistantPersistence",
             str(ROOT / "Sources/AssistantPersistence/ConversationArchive.swift"), str(pdf_file),
             str(ROOT / "Sources/AssistantPersistence/ConversationMessageActions.swift"),
             "-o", str(out / "libAssistantPersistence.dylib")], cwd=out, env=env)
        run(["swiftc", *module_options, "-module-name", "LegacyPersistence",
             str(legacy_source), str(pdf_file), "-o", str(out / "libLegacyPersistence.dylib")], cwd=out, env=env)
        run(["swiftc", *module_options, "-module-name", "LegacyV4Persistence",
             str(v4_source), str(pdf_file), "-o", str(out / "libLegacyV4Persistence.dylib")], cwd=out, env=env)
        link = ["-I", str(out), "-L", str(out), "-Xlinker", "-rpath", "-Xlinker", str(out)]
        run(["swiftc", "-parse-as-library", *link, "-lAssistantPersistence", str(writer_source),
             "-o", str(out / "write-fixtures")], cwd=out, env=env)
        run(["swiftc", "-parse-as-library", *link, "-lLegacyPersistence", str(reader_source),
             "-o", str(out / "read-fixtures")], cwd=out, env=env)
        run(["swiftc", "-parse-as-library", *link, "-lAssistantPersistence", str(current_source),
             "-o", str(out / "read-old-v3")], cwd=out, env=env)
        run(["swiftc", "-parse-as-library", *link, "-lLegacyV4Persistence", str(v4_reader_source),
             "-o", str(out / "read-v4")], cwd=out, env=env)
        run([str(out / "write-fixtures"), str(out)], cwd=out, env=env)
        run([str(out / "read-fixtures"), str(out)], cwd=out, env=env)
        run([str(out / "read-old-v3"), str(out)], cwd=out, env=env)
        run([str(out / "read-v4"), str(out)], cwd=out, env=env)


if __name__ == "__main__":
    main()
