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
    func start(buffer: ProviderPCMBuffer, activate: @escaping @MainActor () -> Bool,
               mayStart: @escaping @MainActor () -> Bool,
               onFailure: @escaping @MainActor () -> Void) throws {
        beforeStartCheck?()
        guard mayStart() else { return }
        guard activate(), mayStart() else { return }
        starts += 1; sinks.append(buffer); failures.append(onFailure)
    }
    func stop() { stops += 1; onStop?() }
}
@MainActor private final class FakeMixedSession: MixedVoiceAudioSession {
    var current = VoiceAudioSettings(category: "original", mode: "default", options: 0)
    var onActivate: (() -> Void)?
    var activations = 0
    func settings() -> VoiceAudioSettings? { current }
    func configureMixedRecording() -> Bool { current = VoiceAudioSettings(category: "mixed", mode: "default", options: 1); return true }
    func isMixedRecording(_ settings: VoiceAudioSettings) -> Bool { settings.category == "mixed" }
    func activate() -> Bool { activations += 1; onActivate?(); return true }
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

@MainActor private final class FixtureEngine: ProviderPCMEngine {
    enum Failure: Error { case install, start }
    var log: [String] = []
    var sink: ProviderPCMBuffer?
    var failure: (@MainActor () -> Void)?
    var failInstall = false, failStart = false
    var duringInstall: (() -> Void)?, duringPrepare: (() -> Void)?, duringStart: (() -> Void)?
    func install(buffer: ProviderPCMBuffer, onFailure: @escaping @MainActor () -> Void) throws {
        log.append("install"); sink = buffer; failure = onFailure
        duringInstall?()
        if failInstall { throw Failure.install }
    }
    func prepare() { log.append("prepare"); duringPrepare?() }
    func start() throws { log.append("start"); duringStart?(); if failStart { throw Failure.start } }
    func stop() { log.append("stop"); sink = nil }
}
@MainActor private final class FixtureObservation: ProviderPCMObservation {
    var cancelCount = 0
    func cancel() { cancelCount += 1 }
}
@MainActor private final class FixturePlatform: ProviderPCMPlatform {
    enum Failure: Error { case make }
    var permissions: [@MainActor (Bool) -> Void] = []
    var engines: [FixtureEngine] = []
    var observations: [FixtureObservation] = []
    var failures: [@MainActor () -> Void] = []
    var buffers: [ProviderPCMBuffer] = []
    var makeHook: (() -> Void)?, observeHook: ((@MainActor () -> Void) -> Void)?
    var configure: ((FixtureEngine) -> Void)?
    var failMake = false
    func requestPermission(_ completion: @escaping @MainActor (Bool) -> Void) { permissions.append(completion) }
    func makeEngine() throws -> any ProviderPCMEngine {
        if failMake { throw Failure.make }
        let engine = FixtureEngine(); configure?(engine); engines.append(engine); makeHook?(); return engine
    }
    func observeSystemChanges(buffer: ProviderPCMBuffer,
                              onFailure: @escaping @MainActor () -> Void) -> any ProviderPCMObservation {
        buffers.append(buffer)
        let failure: @MainActor () -> Void = { buffer.discard(); onFailure() }
        failures.append(failure)
        let token = FixtureObservation(); observations.append(token)
        observeHook?(failure)
        return token
    }
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
        let down = capture([Float](repeating: 1, count: 4_800), rate: 48_000, channels: 1, pieces: 301)
        check(down.count == 1_600 && down.dropFirst(128).allSatisfy { $0 >= 32766 }, "48k filtered downsample retains DC and length")
        let up = capture([-1, 1], rate: 8_000, channels: 1, pieces: 1)
        check(up == [-32768, -32768, 32767, 32767], "8k upsample")
        let wave = (0..<44_100).map { Float(($0 % 100) - 50) / 50 }
        let whole = capture(wave, rate: 44_100, channels: 1, pieces: 8000)
        let split = capture(wave, rate: 44_100, channels: 1, pieces: 137)
        check(whole.count == 16_000 && split == whole, "44.1k rate and chunk independence")
        let reviewFrames = 7_999
        let reviewInput = (0..<reviewFrames).map { Float(($0 % 71) - 35) / 35 }
        for sampleRate in [8_000, 16_000, 22_050, 44_100, 48_000, 96_000, 192_000] {
            let one = capture(reviewInput, rate: sampleRate, channels: 1, pieces: reviewFrames)
            let many = capture(reviewInput, rate: sampleRate, channels: 1, pieces: 73)
            check(one == many && one.count == reviewFrames * 16_000 / sampleRate,
                  "review sample rates preserve length and chunk independence")
        }
        let reviewTone = (0..<4_800).map { Float(sin(2 * .pi * 10_000 * Double($0) / 48_000)) }
        let reviewOutput = capture(reviewTone, rate: 48_000, channels: 1, pieces: 400)
        let reviewRMS = sqrt(reviewOutput.reduce(0.0) { $0 + pow(Double($1) / 32768.0, 2) } / Double(reviewOutput.count))
        check(reviewOutput.count == 1_600 && reviewRMS < 0.01, "review 10k tone including startup transient")
        func toneRMS(rate: Int, frequency: Double) -> Double {
            let frames = rate / 4
            let tone = (0..<frames).map { Float(0.8 * sin(2 * .pi * frequency * Double($0) / Double(rate))) }
            let output = capture(tone, rate: rate, channels: 1, pieces: 317).dropFirst(128)
            return sqrt(output.reduce(0.0) { $0 + pow(Double($1) / 32768.0, 2) } / Double(output.count))
        }
        func fundamentalRMS(rate: Int, frequency: Double) -> Double {
            let tone = (0..<(rate / 4)).map { Float(0.8 * sin(2 * .pi * frequency * Double($0) / Double(rate))) }
            let output = Array(capture(tone, rate: rate, channels: 1, pieces: 317).dropFirst(128))
            var sine = 0.0, cosine = 0.0
            for (index, sample) in output.enumerated() {
                let angle = 2 * .pi * frequency * Double(index) / 16_000
                let value = Double(sample) / 32768.0
                sine += value * sin(angle); cosine += value * cos(angle)
            }
            return sqrt(2) * hypot(sine, cosine) / Double(output.count)
        }
        let pass1k = toneRMS(rate: 48_000, frequency: 1_000)
        let pass6k = toneRMS(rate: 48_000, frequency: 6_000)
        let stop10k = toneRMS(rate: 48_000, frequency: 10_000)
        let stop12k = toneRMS(rate: 48_000, frequency: 12_000)
        let stop44k = toneRMS(rate: 44_100, frequency: 10_000)
        let pass44k = toneRMS(rate: 44_100, frequency: 6_000)
        let pass22k = toneRMS(rate: 22_050, frequency: 6_000)
        let pass192k = toneRMS(rate: 192_000, frequency: 6_000)
        let stop192k = toneRMS(rate: 192_000, frequency: 10_000)
        let fundamental22k = fundamentalRMS(rate: 22_050, frequency: 6_000)
        let fundamental44k = fundamentalRMS(rate: 44_100, frequency: 6_000)
        let expectedRMS = 0.8 / sqrt(2.0)
        check(abs(pass1k / expectedRMS - 1) < 0.01, "1k passband retained within 1%")
        check(abs(pass6k / expectedRMS - 1) < 0.02, "6k passband retained within 2%")
        check(stop10k / expectedRMS < 0.01, "10k alias suppressed by at least 40 dB")
        check(stop12k / expectedRMS < 0.01, "12k alias suppressed by at least 40 dB")
        check(stop44k / expectedRMS < 0.01, "44.1k input rejects 10k by at least 40 dB")
        check(abs(pass44k / expectedRMS - 1) < 0.02, "44.1k input preserves 6k RMS")
        check(abs(pass22k / expectedRMS - 1) < 0.02, "22.05k input preserves 6k RMS")
        check(abs(fundamental22k / expectedRMS - 1) < 0.02, "22.05k input preserves 6k fundamental")
        check(abs(fundamental44k / expectedRMS - 1) < 0.02, "44.1k input preserves 6k fundamental")
        check(abs(pass192k / expectedRMS - 1) < 0.02, "192k input preserves 6k passband")
        check(stop192k / expectedRMS < 0.01, "192k input rejects 10k by at least 40 dB")
        print(String(format: "Synthetic 48k->16k RMS (input peak 0.8): 1k=%.6f 6k=%.6f 10k=%.6f 12k=%.6f", pass1k, pass6k, stop10k, stop12k))
        print(String(format: "Synthetic 10k stopband RMS: 44.1k=%.6f 192k=%.6f; 192k 6k passband RMS=%.6f", stop44k, stop192k, pass192k))
        print(String(format: "Synthetic 6k passband RMS: 22.05k=%.6f 44.1k=%.6f", pass22k, pass44k))
        print(String(format: "Synthetic 6k fundamental RMS: 22.05k=%.6f 44.1k=%.6f", fundamental22k, fundamental44k))
        print(String(format: "Review 10k tone output RMS, including startup: %.6f", reviewRMS))
        let invalid = ProviderPCMBuffer()
        check(invalid.append([.nan], sampleRate: 16_000, channels: 1) == .invalid, "nonfinite rejected")
        check(invalid.finish() == nil, "invalid audio discarded")
        let mismatch = ProviderPCMBuffer()
        check(mismatch.append([0], sampleRate: 16_000, channels: 1) == .accepted, "initial format")
        check(mismatch.append([0], sampleRate: 48_000, channels: 1) == .invalid, "format change rejected")
        let prepared = ProviderPCMBuffer()
        check(prepared.prepare(sampleRate: 48_000, channels: 2), "native format prepares filter before tap")
        check(!prepared.prepare(sampleRate: 44_100, channels: 2), "prepared format cannot silently change")
        check(prepared.append([0, 0, 0, 0, 0, 0], sampleRate: 48_000, channels: 2) == .accepted,
              "prepared filter accepts matching frames")
        prepared.discard()
        check(!prepared.prepare(sampleRate: 48_000, channels: 2), "discarded collector cannot be prepared again")
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

        // Test the source's real orchestration, with only its platform and
        // engine substituted. No native engine or microphone is constructed.
        let platform = FixturePlatform(), coordinated = CoordinatedProviderPCMSource(platform: platform)
        let audioSession = FakeMixedSession(), shared = MixedVoiceAudioCoordinator(session: audioSession)
        let device = VoiceAudioLeaseSlot(coordinator: shared)
        var sourceAllowed = true
        var sourceEvents: [(UUID, VoiceInputEvent)] = []
        var sourceEnded: [UUID] = []
        let sourceDriver = ProviderPCMVoiceDriver(source: coordinated, coordinator: shared,
            mayFinish: { sourceAllowed }, onEnd: { sourceEnded.append($0) }, transcribe: { _, _ in "fixture" })
        func sourceBegin() -> UUID {
            let id = UUID()
            sourceDriver.start(id: id, mayContinue: { sourceAllowed }, emit: { sourceEvents.append(($0, $1)) })
            return id
        }
        let permissionPending = sourceBegin()
        check(platform.engines.isEmpty && platform.permissions.count == 1, "permission prompt does not create an engine")
        sourceDriver.cancel(id: permissionPending)
        platform.permissions[0](true)
        check(platform.engines.isEmpty && sourceEnded.contains(permissionPending), "late permission after cancellation cannot create engine")
        let active = sourceBegin()
        platform.permissions[1](true)
        let firstEngine = platform.engines[0]
        let firstObservation = platform.observations[0]
        check(firstEngine.log == ["install", "prepare", "start"], "source installs, prepares and starts in order")
        check(!device.acquire(onRevoked: {}), "device speech cannot acquire the provider lease")
        let sinkBeforeInterrupt = firstEngine.sink!
        _ = sinkBeforeInterrupt.append([Float](repeating: 0.25, count: 8_000), sampleRate: 16_000, channels: 1)
        platform.failures[0]()
        check(sourceEvents.last?.0 == active && sourceEvents.last?.1 == .failed(.audio), "interruption fails active capture")
        check(firstEngine.log.last == "stop" && firstObservation.cancelCount == 1 && sinkBeforeInterrupt.finish() == nil,
              "interruption stops engine, removes observers and discards audio")
        check(device.acquire(onRevoked: {}), "audio lease is available after interruption cleanup")
        device.release()
        let replacementCapture = sourceBegin()
        platform.permissions[2](true)
        let replacementEngine = platform.engines[1]
        platform.failures[0]()
        firstEngine.failure?()
        check(replacementEngine.log == ["install", "prepare", "start"], "old system and tap errors cannot stop new engine")
        check(!device.acquire(onRevoked: {}), "stale error cannot release the replacement lease")
        sourceDriver.cancel(id: replacementCapture)
        check(replacementEngine.log.last == "stop" && platform.observations[1].cancelCount == 1,
              "cancellation stops replacement and removes observers")

        let revokedDuringObserve = sourceBegin()
        platform.observeHook = { failure in failure() }
        platform.permissions[3](true)
        platform.observeHook = nil
        check(sourceEvents.last?.0 == revokedDuringObserve && sourceEvents.last?.1 == .failed(.audio),
              "synchronous interruption during observer setup fails once")
        check(platform.engines[2].log == ["stop"] && platform.observations[2].cancelCount == 1,
              "observer returned after cancellation is still removed")
        let revokedDuringPrepare = sourceBegin()
        platform.configure = { engine in engine.duringPrepare = { sourceAllowed = false } }
        platform.permissions[4](true)
        platform.configure = nil
        check(sourceEvents.last?.0 == revokedDuringPrepare && sourceEvents.last?.1 == .cancelled,
              "authorization change during prepare cancels capture")
        check(platform.engines[3].log == ["install", "prepare", "stop"] && platform.observations[3].cancelCount == 1,
              "authorization rechecked immediately before engine start")
        sourceAllowed = true
        let installFailure = sourceBegin()
        platform.configure = { $0.failInstall = true }
        platform.permissions[5](true)
        platform.configure = nil
        check(sourceEvents.last?.0 == installFailure && sourceEvents.last?.1 == .failed(.audio) &&
              platform.engines[4].log == ["install", "stop"] && platform.observations[4].cancelCount == 1,
              "failed install tears down engine, observer and lease")
        let startFailure = sourceBegin()
        platform.configure = { $0.failStart = true }
        platform.permissions[6](true)
        platform.configure = nil
        check(sourceEvents.last?.0 == startFailure && sourceEvents.last?.1 == .failed(.audio) &&
              platform.engines[5].log == ["install", "prepare", "start", "stop"] && platform.observations[5].cancelCount == 1,
              "failed start removes observer and stops engine")
        let canceledDuringMake = sourceBegin()
        platform.makeHook = { sourceDriver.cancel(id: canceledDuringMake) }
        platform.permissions[7](true)
        platform.makeHook = nil
        check(platform.engines[6].log == ["stop"] && sourceEnded.contains(canceledDuringMake),
              "engine returned after cancellation is stopped without install")
        check(device.acquire(onRevoked: {}), "all synthetic source error paths release the shared lease")
        device.release()
        let successfulCapture = sourceBegin()
        platform.permissions[8](true)
        let successfulEngine = platform.engines[7]
        let successfulSink = successfulEngine.sink!
        _ = successfulSink.append([Float](repeating: 0.25, count: 8_000), sampleRate: 16_000, channels: 1)
        sourceDriver.finish(id: successfulCapture)
        check(successfulEngine.log.last == "stop" && platform.observations[6].cancelCount == 1 &&
              successfulSink.append([1], sampleRate: 16_000, channels: 1) == .closed,
              "release synchronously closes source before transcription")
        for _ in 0..<1_000 where sourceEvents.last?.0 != successfulCapture { await Task.yield() }
        check(sourceEvents.last?.0 == successfulCapture && sourceEvents.last?.1 == .final("fixture"),
              "coordinated source delivers synthetic recorded data on release")
        let invalidBeforeRelease = sourceBegin()
        platform.permissions[9](true)
        let invalidEngine = platform.engines[8]
        let invalidNativeSink = invalidEngine.sink!
        _ = invalidNativeSink.append([Float](repeating: 0.25, count: 8_000), sampleRate: 16_000, channels: 1)
        // A tap or observer has detected an error on its callback thread,
        // but the main-actor error delivery has not run yet.
        invalidNativeSink.discard()
        sourceDriver.finish(id: invalidBeforeRelease)
        platform.failures[7]()
        check(sourceEvents.last?.0 == invalidBeforeRelease && sourceEvents.last?.1 == .failed(.audio),
              "release after detected error never transcribes earlier PCM")
        check(invalidEngine.log.last == "stop" && device.acquire(onRevoked: {}), "error-before-release still frees audio lease")
        device.release()
        let beforeDeniedCount = platform.engines.count
        let deniedPermission = sourceBegin()
        platform.permissions.last!(false)
        check(platform.engines.count == beforeDeniedCount && sourceEvents.last?.0 == deniedPermission &&
              sourceEvents.last?.1 == .failed(.microphoneDenied), "denied permission never constructs engine")
        let changedBeforePermission = sourceBegin()
        sourceAllowed = false
        platform.permissions.last!(true)
        check(platform.engines.count == beforeDeniedCount && sourceEvents.last?.0 == changedBeforePermission &&
              sourceEvents.last?.1 == .cancelled, "settings or background change before permission cannot create engine")
        sourceAllowed = true
        check(device.acquire(onRevoked: {}), "denied and revoked permission release the audio lease")
        device.release()
        let failureDuringInstall = sourceBegin()
        let observerCount = platform.observations.count
        platform.configure = { engine in engine.duringInstall = { [weak engine] in engine?.failure?() } }
        platform.permissions.last!(true)
        platform.configure = nil
        check(sourceEvents.last?.0 == failureDuringInstall && sourceEvents.last?.1 == .failed(.audio) &&
              platform.engines.last?.log == ["install", "stop"] && platform.observations.count == observerCount + 1 &&
              platform.observations.last?.cancelCount == 1,
              "synchronous tap error during install stops and removes observer")
        let failureDuringStart = sourceBegin()
        platform.configure = { engine in engine.duringStart = { [weak engine] in engine?.failure?() } }
        platform.permissions.last!(true)
        platform.configure = nil
        check(sourceEvents.last?.0 == failureDuringStart && sourceEvents.last?.1 == .failed(.audio) &&
              platform.engines.last?.log == ["install", "prepare", "start", "stop"] &&
              platform.observations.last?.cancelCount == 1,
              "synchronous error during start stops engine and removes observer")
        let discardedDuringInstall = sourceBegin()
        platform.configure = { engine in engine.duringInstall = { [weak engine] in engine?.sink?.discard() } }
        platform.permissions.last!(true)
        platform.configure = nil
        check(sourceEvents.last?.0 == discardedDuringInstall && sourceEvents.last?.1 == .failed(.audio) &&
              platform.engines.last?.log == ["install", "stop"] && platform.observations.last?.cancelCount == 1,
              "buffer closed during install stops before prepare without waiting for callback")
        let discardedDuringStart = sourceBegin()
        platform.configure = { engine in engine.duringStart = { [weak engine] in engine?.sink?.discard() } }
        platform.permissions.last!(true)
        platform.configure = nil
        check(sourceEvents.last?.0 == discardedDuringStart && sourceEvents.last?.1 == .failed(.audio) &&
              platform.engines.last?.log == ["install", "prepare", "start", "stop"] &&
              platform.observations.last?.cancelCount == 1,
              "buffer closed during start stops before capture can finish")
        check(device.acquire(onRevoked: {}), "synchronous setup failures return the voice lease")
        device.release()
        let makeFailure = sourceBegin()
        let beforeMakeFailure = platform.engines.count
        platform.failMake = true
        platform.permissions.last!(true)
        platform.failMake = false
        check(platform.engines.count == beforeMakeFailure && sourceEvents.last?.0 == makeFailure &&
              sourceEvents.last?.1 == .failed(.audio), "engine creation failure is reported")
        check(device.acquire(onRevoked: {}), "engine creation failure returns the voice lease")
        device.release()
        let activationInterrupted = sourceBegin()
        let beforeActivation = audioSession.activations
        audioSession.onActivate = { platform.failures.last?() }
        platform.permissions.last!(true)
        audioSession.onActivate = nil
        check(audioSession.activations == beforeActivation + 1 && sourceEvents.last?.0 == activationInterrupted &&
              sourceEvents.last?.1 == .failed(.audio) && platform.engines.last?.log == ["stop"] &&
              platform.observations.last?.cancelCount == 1,
              "observer catches synchronous interruption during audio session activation before engine install")
        check(device.acquire(onRevoked: {}), "interrupted activation releases lease after reentrant cleanup")
        device.release()
        let delayedActivationFailure = sourceBegin()
        audioSession.onActivate = { platform.buffers.last?.discard() }
        platform.permissions.last!(true)
        audioSession.onActivate = nil
        let activationCallback = platform.failures.last!
        check(sourceEvents.last?.0 == delayedActivationFailure && sourceEvents.last?.1 == .failed(.audio) &&
              platform.engines.last?.log == ["stop"] && platform.observations.last?.cancelCount == 1,
              "notification detected during activation closes collector before queued failure and engine install")
        let afterActivationFailure = sourceBegin()
        platform.permissions.last!(true)
        let afterActivationEngine = platform.engines.last!
        activationCallback()
        check(afterActivationEngine.log == ["install", "prepare", "start"],
              "late activation notification cannot stop the next capture")
        sourceDriver.cancel(id: afterActivationFailure)
        check(device.acquire(onRevoked: {}), "late activation notification and cancellation return lease")
        device.release()
        let backgroundDuringActivation = sourceBegin()
        audioSession.onActivate = { sourceAllowed = false }
        platform.permissions.last!(true)
        audioSession.onActivate = nil
        check(sourceEvents.last?.0 == backgroundDuringActivation && sourceEvents.last?.1 == .cancelled &&
              platform.engines.last?.log == ["stop"] && platform.observations.last?.cancelCount == 1,
              "background or setting change during activation cancels before engine install")
        sourceAllowed = true
        let cancelledDuringActivation = sourceBegin()
        audioSession.onActivate = { sourceDriver.cancel(id: cancelledDuringActivation) }
        platform.permissions.last!(true)
        audioSession.onActivate = nil
        check(sourceEnded.contains(cancelledDuringActivation) && platform.engines.last?.log == ["stop"] &&
              platform.observations.last?.cancelCount == 1 && device.acquire(onRevoked: {}),
              "explicit cancellation during activation removes observer and releases lease")
        device.release()
        let standalonePlatform = FixturePlatform()
        let standaloneSource = CoordinatedProviderPCMSource(platform: standalonePlatform)
        let standaloneBuffer = ProviderPCMBuffer()
        try standaloneSource.start(buffer: standaloneBuffer, activate: { true }, mayStart: { true }, onFailure: {})
        _ = standaloneBuffer.append([1], sampleRate: 16_000, channels: 1)
        standaloneSource.stop()
        standaloneSource.stop()
        check(standaloneBuffer.finish() == nil && standalonePlatform.engines[0].log == ["install", "prepare", "start", "stop"] &&
              standalonePlatform.observations[0].cancelCount == 1, "source stop discards its buffer and is idempotent")
        print("PASS provider PCM: \(checks) checks; injected source and transcriber, no microphone or network")
    }
}
