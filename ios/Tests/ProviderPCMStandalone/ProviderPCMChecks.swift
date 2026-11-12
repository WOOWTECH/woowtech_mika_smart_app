import Foundation

@MainActor private final class FakeSource: ProviderPCMSource {
    var permissions: [@MainActor (Bool) -> Void] = []
    var sinks: [ProviderPCMBuffer] = []
    var failures: [@MainActor () -> Void] = []
    var starts = 0
    var stops = 0
    var onStop: (() -> Void)?
    var beforeStartCheck: (() -> Void)?
    func requestPermission(_ completion: @escaping @MainActor (Bool) -> Void) { permissions.append(completion) }
    func start(buffer: ProviderPCMBuffer, mayStart: @escaping @MainActor () -> Bool,
               onFailure: @escaping @MainActor () -> Void) throws {
        beforeStartCheck?()
        guard mayStart() else { return }
        starts += 1; sinks.append(buffer); failures.append(onFailure)
    }
    func stop() { stops += 1; onStop?() }
}
@MainActor private final class FakeMixedSession: MixedVoiceAudioSession {
    var current = VoiceAudioSettings(category: "original", mode: "default", options: 0)
    var onActivate: (() -> Void)?
    func settings() -> VoiceAudioSettings? { current }
    func configureMixedRecording() -> Bool { current = VoiceAudioSettings(category: "mixed", mode: "default", options: 1); return true }
    func isMixedRecording(_ settings: VoiceAudioSettings) -> Bool { settings.category == "mixed" }
    func activate() -> Bool { onActivate?(); return true }
    func restore(_ settings: VoiceAudioSettings) -> Bool { current = settings; return true }
}
@MainActor private final class FakeTranscriber {
    var calls: [(UUID, [Int16])] = []
    var continuation: CheckedContinuation<String, Error>?
    func run(_ id: UUID, _ samples: [Int16]) async throws -> String {
        calls.append((id, samples))
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func resolve(_ text: String) { continuation?.resume(returning: text); continuation = nil }
}

@main private enum Checks {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            checks += 1; precondition(value(), label)
        }
        func capture(_ data: [Float], rate: Int, channels: Int, pieces: Int) -> [Int16] {
            let buffer = ProviderPCMBuffer()
            var start = 0
            while start < data.count {
                let end = min(data.count, start + pieces * channels)
                precondition(buffer.append(Array(data[start..<end]), sampleRate: rate, channels: channels) == .accepted)
                start = end
            }
            return buffer.finish()!
        }
        let basic = capture([-1, 0, 1, 2, -2], rate: 16_000, channels: 1, pieces: 5)
        check(basic == [-32768, 0, 32767, 32767, -32768], "clipping and signed encoding")
        let stereo = capture([1, -1, 1, 1], rate: 16_000, channels: 2, pieces: 2)
        check(stereo == [0, 32767], "stereo downmix")
        let down = capture([1, 0, -1, 1, 1, 1], rate: 48_000, channels: 1, pieces: 6)
        check(down == [0, 32767], "48k weighted downsample")
        let up = capture([-1, 1], rate: 8_000, channels: 1, pieces: 1)
        check(up == [-32768, -32768, 32767, 32767], "8k upsample")
        let wave = (0..<44_100).map { Float(($0 % 100) - 50) / 50 }
        let whole = capture(wave, rate: 44_100, channels: 1, pieces: 8000)
        let split = capture(wave, rate: 44_100, channels: 1, pieces: 137)
        check(whole.count == 16_000 && split == whole, "44.1k rate and chunk independence")
        let invalid = ProviderPCMBuffer()
        check(invalid.append([.nan], sampleRate: 16_000, channels: 1) == .invalid, "nonfinite rejected")
        check(invalid.finish() == nil, "invalid audio discarded")
        let mismatch = ProviderPCMBuffer()
        check(mismatch.append([0], sampleRate: 16_000, channels: 1) == .accepted, "initial format")
        check(mismatch.append([0], sampleRate: 48_000, channels: 1) == .invalid, "format change rejected")
        let limit = ProviderPCMBuffer(maxSamples: 3)
        check(limit.append([0, 0, 0], sampleRate: 16_000, channels: 1) == .limit, "limit fails closed")
        check(limit.finish() == nil, "limit never releases audio")
        let ended = ProviderPCMBuffer()
        check(ended.finish() == [], "empty finish")
        check(ended.append([1], sampleRate: 16_000, channels: 1) == .closed, "late callback ignored")
        let discarded = ProviderPCMBuffer()
        _ = discarded.append([1], sampleRate: 16_000, channels: 1)
        discarded.discard()
        check(discarded.finish() == nil, "discard never returns captured data")
        let concurrent = ProviderPCMBuffer()
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            precondition(concurrent.append([0.5], sampleRate: 16_000, channels: 1) == .accepted)
        }
        check(concurrent.finish()?.count == 100, "concurrent callback serialization")
        check(concurrent.append([1], sampleRate: 16_000, channels: 1) == .closed, "concurrent sink stays closed")

        let session = FakeMixedSession(), coordinator = MixedVoiceAudioCoordinator(session: session)
        let source = FakeSource(), transcriber = FakeTranscriber()
        var allowed = true, listening = true
        var events: [(UUID, VoiceInputEvent)] = []
        var endedIDs: [UUID] = []
        let driver = ProviderPCMVoiceDriver(source: source, coordinator: coordinator,
                                            mayFinish: { allowed }, onEnd: { endedIDs.append($0) },
                                            transcribe: { try await transcriber.run($0, $1) })
        func begin() -> UUID {
            let id = UUID()
            driver.start(id: id, mayContinue: { listening }, emit: { events.append(($0, $1)) })
            return id
        }
        let pending = begin()
        check(source.permissions.count == 1, "permission requested after lease")
        allowed = false
        source.permissions[0](true)
        check(source.starts == 0 && events.last?.1 == .cancelled, "closed settings before permission blocks engine")
        allowed = true
        let cancelled = begin()
        driver.cancel(id: cancelled)
        source.permissions[1](true)
        check(source.starts == 0, "cancelled permission cannot start")
        check(endedIDs.filter { $0 == cancelled }.count == 1, "cancel ends the recording exactly once")
        let deviceSlot = VoiceAudioLeaseSlot(coordinator: coordinator)
        check(deviceSlot.acquire(onRevoked: {}), "device speech can acquire after cancellation")
        _ = begin()
        check(events.last?.1 == .failed(.unavailable) && source.permissions.count == 2, "provider cannot compete with device lease")
        deviceSlot.release()
        let recording = begin()
        source.permissions[2](true)
        check(source.starts == 1, "authorized source started")
        check(!deviceSlot.acquire(onRevoked: {}), "device cannot compete with provider lease")
        let sink = source.sinks.last!
        check(sink.append([Float](repeating: 0.25, count: 8000), sampleRate: 16_000, channels: 1) == .accepted, "audio fed")
        driver.finish(id: recording)
        check(source.stops == 1 && deviceSlot.acquire(onRevoked: {}), "release stops source before lease handoff")
        deviceSlot.release()
        source.failures[0]()
        check(!events.contains { $0.0 == recording }, "late source failure cannot cancel finishing")
        for _ in 0..<1000 where transcriber.calls.isEmpty { await Task.yield() }
        check(transcriber.calls.count == 1 && transcriber.calls[0].1.count == 8000, "only released audio reaches transcriber")
        driver.cancel(id: recording)
        transcriber.resolve("late")
        for _ in 0..<20 { await Task.yield() }
        check(!events.contains { $0.0 == recording && $0.1 == .final("late") }, "late transcription discarded")
        check(sink.append([1], sampleRate: 16_000, channels: 1) == .closed, "post-stop audio ignored")
        let background = begin()
        source.permissions[3](true)
        let bgSink = source.sinks.last!
        _ = bgSink.append([Float](repeating: 0, count: 8000), sampleRate: 16_000, channels: 1)
        allowed = false
        driver.finish(id: background)
        for _ in 0..<10 { await Task.yield() }
        check(events.last?.1 == .cancelled && transcriber.calls.count == 1, "background before release prevents transcription")
        allowed = true
        let revoked = begin()
        source.permissions[4](true)
        let revokedSink = source.sinks.last!
        coordinator.revokeForSystemChange()
        check(events.last?.0 == revoked && events.last?.1 == .failed(.audio), "revocation delivers failure")
        check(revokedSink.append([1], sampleRate: 16_000, channels: 1) == .closed, "revocation synchronously closes sink")
        check(deviceSlot.acquire(onRevoked: {}), "lease released after revocation stops capture")
        deviceSlot.release()
        let short = begin()
        source.permissions[5](true)
        _ = source.sinks.last!.append([1], sampleRate: 16_000, channels: 1)
        driver.finish(id: short)
        check(events.last?.1 == .final("") && transcriber.calls.count == 1, "short audio discarded without transcription")
        let waiting = begin()
        driver.finish(id: waiting)
        source.permissions[6](true)
        check(source.starts == 4 && events.last?.1 == .final(""), "release during permission cannot later start")
        let timeout = begin()
        source.permissions[7](true)
        let timedSink = source.sinks.last!
        driver.timeout(id: timeout)
        check(events.last?.1 == .failed(.timeout) && timedSink.finish() == nil, "deadline discards audio")
        let next = begin()
        source.permissions[8](true)
        source.failures[0]()
        check(deviceSlot.acquire(onRevoked: {}) == false, "late old failure cannot stop new recording")
        driver.cancel(id: next)
        check(deviceSlot.acquire(onRevoked: {}), "cancel releases new lease")
        deviceSlot.release()
        _ = pending
        listening = false
        let blocked = begin()
        check(events.last?.0 == blocked && events.last?.1 == .cancelled, "disabled session denies permission")
        listening = true
        let activation = begin()
        let previousStarts = source.starts
        session.onActivate = { coordinator.revokeForSystemChange() }
        source.permissions.last!(true)
        session.onActivate = nil
        check(source.starts == previousStarts && events.last?.0 == activation && events.last?.1 == .failed(.audio),
              "synchronous revocation during activation never starts capture")
        let beforeTask = begin()
        source.permissions.last!(true)
        _ = source.sinks.last!.append([Float](repeating: 0, count: 8_000), sampleRate: 16_000, channels: 1)
        driver.finish(id: beforeTask)
        driver.cancel(id: beforeTask)
        for _ in 0..<20 { await Task.yield() }
        check(transcriber.calls.count == 1, "cancel before next task turn prevents transcription")
        let finishTimeout = begin()
        source.permissions.last!(true)
        _ = source.sinks.last!.append([Float](repeating: 0, count: 8_000), sampleRate: 16_000, channels: 1)
        driver.finish(id: finishTimeout)
        for _ in 0..<1000 where transcriber.calls.count == 1 { await Task.yield() }
        check(transcriber.calls.count == 2, "second transcription started")
        driver.timeout(id: finishTimeout)
        transcriber.resolve("too late")
        for _ in 0..<20 { await Task.yield() }
        check(events.last?.0 == finishTimeout && events.last?.1 == .failed(.timeout), "transcription deadline rejects late result")
        let preStart = begin()
        let startsBeforeCheck = source.starts
        source.beforeStartCheck = { allowed = false }
        source.permissions.last!(true)
        source.beforeStartCheck = nil
        check(source.starts == startsBeforeCheck && events.last?.0 == preStart && events.last?.1 == .cancelled,
              "settings closure immediately before engine start prevents capture")
        allowed = true
        let reentrantOld = begin()
        source.permissions.last!(true)
        _ = source.sinks.last!.append([Float](repeating: 0, count: 8_000), sampleRate: 16_000, channels: 1)
        var replacement: UUID?
        source.onStop = { source.onStop = nil; replacement = begin() }
        let callsBeforeReentry = transcriber.calls.count
        driver.finish(id: reentrantOld)
        check(replacement != nil && transcriber.calls.count == callsBeforeReentry, "reentrant replacement discards old capture")
        source.permissions.last!(true)
        check(!deviceSlot.acquire(onRevoked: {}), "old finish cannot release replacement lease")
        driver.cancel(id: replacement!)
        let cancelReentry = begin()
        source.permissions.last!(true)
        let permissionsBeforeReentry = source.permissions.count
        source.onStop = { source.onStop = nil; _ = begin() }
        driver.cancel(id: cancelReentry)
        check(source.permissions.count == permissionsBeforeReentry && events.last?.1 == .failed(.unavailable),
              "reentrant start during cleanup cannot take a live lease")
        check(deviceSlot.acquire(onRevoked: {}), "lease available after reentrant cleanup")
        deviceSlot.release()
        let invalidAudio = begin()
        source.permissions.last!(true)
        let invalidSink = source.sinks.last!
        check(invalidSink.append([.nan], sampleRate: 16_000, channels: 1) == .invalid, "source rejects invalid samples")
        source.failures.last!()
        check(events.last?.0 == invalidAudio && events.last?.1 == .failed(.audio), "source error stops capture")
        check(deviceSlot.acquire(onRevoked: {}), "source failure releases voice lease")
        deviceSlot.release()
        let changedDuringUpload = begin()
        source.permissions.last!(true)
        _ = source.sinks.last!.append([Float](repeating: 0, count: 8_000), sampleRate: 16_000, channels: 1)
        driver.finish(id: changedDuringUpload)
        let expectedCalls = callsBeforeReentry + 1
        for _ in 0..<1000 where transcriber.calls.count < expectedCalls { await Task.yield() }
        check(transcriber.calls.count == expectedCalls, "transcription fixture started")
        allowed = false
        transcriber.resolve("stale setting")
        for _ in 0..<1000 where events.last?.0 != changedDuringUpload { await Task.yield() }
        check(events.last?.0 == changedDuringUpload && events.last?.1 == .cancelled,
              "changed authorization rejects result even without notification")
        allowed = true
        let composerSource = FakeSource(), composerTranscriber = FakeTranscriber()
        let composerDriver = ProviderPCMVoiceDriver(source: composerSource, coordinator: coordinator,
                                                    mayFinish: { allowed }, onEnd: { _ in },
                                                    transcribe: { try await composerTranscriber.run($0, $1) })
        var now = 0.0, draft = "prefix "
        let controller = ChatVoiceController(driver: composerDriver, now: { now }, conversation: { "fixture" },
                                             readDraft: { draft }, writeDraft: { draft = $0 }, finishTimeout: 30)
        controller.begin(gestureStartedAt: 0)
        composerSource.permissions.last!(true)
        _ = composerSource.sinks.last!.append([Float](repeating: 0, count: 8_000), sampleRate: 16_000, channels: 1)
        now = 1
        controller.release()
        for _ in 0..<1000 where composerTranscriber.calls.isEmpty { await Task.yield() }
        now = 10
        controller.tick()
        check(controller.state == .finishing && draft == "prefix ", "provider finishing can exceed device five-second limit")
        composerTranscriber.resolve("result")
        for _ in 0..<1000 where draft == "prefix " { await Task.yield() }
        check(draft == "prefix result", "real composer state machine accepts released fake transcription")
        print("PASS provider PCM: \(checks) checks; injected source and transcriber, no microphone or network")
    }
}
