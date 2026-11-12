#if os(iOS) && canImport(AVFoundation)
import AVFoundation
import Foundation

/// Native adapter. No app entry constructs it or requests permission yet.
@MainActor
final class AppleProviderPCMSource: ProviderPCMSource {
    private let source = CoordinatedProviderPCMSource(platform: AppleProviderPCMPlatform())
    func requestPermission(_ completion: @escaping @MainActor (Bool) -> Void) {
        source.requestPermission(completion)
    }
    func start(buffer: ProviderPCMBuffer, mayStart: @escaping @MainActor () -> Bool,
               onFailure: @escaping @MainActor () -> Void) throws {
        try source.start(buffer: buffer, mayStart: mayStart, onFailure: onFailure)
    }
    func stop() { source.stop() }
}

/// Only the real engine adapter touches AVAudioEngine. The pure source owns
/// creation, teardown, interruption handling and generation fences.
@MainActor
final class AppleProviderPCMPlatform: ProviderPCMPlatform {
    private let center: NotificationCenter
    private let session: AVAudioSession
    init(center: NotificationCenter = .default, session: AVAudioSession = .sharedInstance()) {
        self.center = center
        self.session = session
    }
    func requestPermission(_ completion: @escaping @MainActor (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }
    func makeEngine() throws -> any ProviderPCMEngine { AppleProviderPCMEngine() }
    func observeSystemChanges(buffer: ProviderPCMBuffer,
                              onFailure: @escaping @MainActor () -> Void) -> any ProviderPCMObservation {
        let center = self.center
        let session = self.session
        var tokens: [NSObjectProtocol] = []
        tokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: nil) { note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            buffer.discard()
            DispatchQueue.main.async { onFailure() }
        })
        tokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: nil) { note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                  reason == .oldDeviceUnavailable || reason == .newDeviceAvailable else { return }
            buffer.discard()
            DispatchQueue.main.async { onFailure() }
        })
        tokens.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: nil) { _ in
            buffer.discard()
            DispatchQueue.main.async { onFailure() }
        })
        return AppleProviderPCMObservation(center: center, tokens: tokens)
    }
}

@MainActor
private final class AppleProviderPCMObservation: ProviderPCMObservation {
    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol]
    init(center: NotificationCenter, tokens: [NSObjectProtocol]) { self.center = center; self.tokens = tokens }
    func cancel() {
        let previous = tokens
        tokens.removeAll()
        for token in previous { center.removeObserver(token) }
    }
}

@MainActor
private final class AppleProviderPCMEngine: ProviderPCMEngine {
    private let engine = AVAudioEngine()
    private var installedTap = false

    func install(buffer: ProviderPCMBuffer, onFailure: @escaping @MainActor () -> Void) throws {
        guard !installedTap else { throw CaptureError.invalidFormat }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let rate = format.sampleRate
        let count = Int(format.channelCount)
        guard format.commonFormat == .pcmFormatFloat32, rate.isFinite,
              rate.rounded() == rate, rate >= 8_000, rate <= 192_000,
              (1...8).contains(count) else { throw CaptureError.invalidFormat }
        guard buffer.prepare(sampleRate: Int(rate), channels: count) else { throw CaptureError.invalidFormat }
        let interleaved = format.isInterleaved
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { audio, _ in
            switch AppleProviderPCMFrames.append(audio, expectedRate: rate, expectedChannels: count,
                                                  expectedInterleaved: interleaved, to: buffer) {
            case .accepted, .closed: break
            case .invalid, .limit: DispatchQueue.main.async { onFailure() }
            }
        }
        installedTap = true
    }
    func prepare() { engine.prepare() }
    func start() throws { try engine.start() }
    func stop() {
        engine.stop()
        if installedTap { engine.inputNode.removeTap(onBus: 0); installedTap = false }
    }
    private enum CaptureError: Error { case invalidFormat }
}

/// Kept separate so iOS tests can pass synthetic AVAudioPCMBuffer values
/// without constructing an engine, requesting permission or using a microphone.
enum AppleProviderPCMFrames {
    static func append(_ audio: AVAudioPCMBuffer, expectedRate: Double, expectedChannels: Int,
                       expectedInterleaved: Bool, to buffer: ProviderPCMBuffer) -> ProviderPCMBuffer.AppendResult {
        let frames = Int(audio.frameLength)
        guard frames > 0, frames <= 8192, frames <= Int(audio.frameCapacity),
              expectedRate.isFinite, expectedRate.rounded() == expectedRate,
              expectedRate >= 8_000, expectedRate <= 192_000, (1...8).contains(expectedChannels),
              audio.format.commonFormat == .pcmFormatFloat32,
              audio.format.sampleRate == expectedRate, Int(audio.format.channelCount) == expectedChannels,
              audio.format.isInterleaved == expectedInterleaved,
              let channels = audio.floatChannelData else {
            // Fail the collector synchronously: release may happen before the
            // audio thread's error notification reaches the main actor.
            buffer.discard()
            return .invalid
        }
        var samples = [Float]()
        samples.reserveCapacity(frames * expectedChannels)
        for frame in 0..<frames {
            for channel in 0..<expectedChannels {
                samples.append(expectedInterleaved ? channels[0][frame * expectedChannels + channel] : channels[channel][frame])
            }
        }
        return buffer.append(samples, sampleRate: Int(expectedRate), channels: expectedChannels)
    }
}
#endif
