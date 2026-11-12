#if os(iOS) && canImport(WoowAssistant)
import AVFoundation
import XCTest
@testable import WoowAssistant

/// Synthetic buffers and an isolated NotificationCenter only. These tests do
/// not construct an AVAudioEngine, request microphone permission or connect.
final class ProviderPCMNativeAdapterTests: XCTestCase {
    func testPlanarStereoFloatBufferConvertsToMonoPCM() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                                  channels: 2, interleaved: false))
        let audio = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2))
        audio.frameLength = 2
        let channels = try XCTUnwrap(audio.floatChannelData)
        channels[0][0] = -1; channels[1][0] = 1
        channels[0][1] = 1; channels[1][1] = 1
        let sink = ProviderPCMBuffer()
        XCTAssertEqual(AppleProviderPCMFrames.append(audio, expectedRate: 16_000, expectedChannels: 2,
                                                      expectedInterleaved: false, to: sink), .accepted)
        XCTAssertEqual(sink.finish(), [0, 32767])
    }

    func testInterleavedStereoAndDownsampling() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                                  channels: 2, interleaved: true))
        let audio = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3))
        audio.frameLength = 3
        let channels = try XCTUnwrap(audio.floatChannelData)
        for frame in 0..<3 { channels[0][frame * 2] = 1; channels[0][frame * 2 + 1] = -1 }
        let sink = ProviderPCMBuffer()
        XCTAssertEqual(AppleProviderPCMFrames.append(audio, expectedRate: 48_000, expectedChannels: 2,
                                                      expectedInterleaved: true, to: sink), .accepted)
        XCTAssertEqual(sink.finish(), [0])
    }

    func testFormatMismatchAndOversizedFramesDiscardPreviouslyCapturedAudio() throws {
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                                  channels: 1, interleaved: false))
        let audio = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
        audio.frameLength = 1
        let sink = ProviderPCMBuffer()
        XCTAssertEqual(sink.append([0.5], sampleRate: 16_000, channels: 1), .accepted)
        XCTAssertEqual(AppleProviderPCMFrames.append(audio, expectedRate: 48_000, expectedChannels: 1,
                                                      expectedInterleaved: false, to: sink), .invalid)
        XCTAssertNil(sink.finish(), "the delayed error callback must not allow release of earlier samples")
        let large = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8193))
        large.frameLength = 8193
        let second = ProviderPCMBuffer()
        XCTAssertEqual(AppleProviderPCMFrames.append(large, expectedRate: 16_000, expectedChannels: 1,
                                                      expectedInterleaved: false, to: second), .invalid)
        XCTAssertNil(second.finish())
    }

    @MainActor func testSyntheticInterruptionDiscardsBufferAndRemovesObserver() async throws {
        let center = NotificationCenter()
        // Merely uses the singleton as a notification identity; it never
        // changes the session category, activates it, or requests permission.
        let session = AVAudioSession.sharedInstance()
        let platform = AppleProviderPCMPlatform(center: center, session: session)
        let sink = ProviderPCMBuffer()
        XCTAssertEqual(sink.append([0.5], sampleRate: 16_000, channels: 1), .accepted)
        var callbacks = 0
        let token = platform.observeSystemChanges(buffer: sink) { callbacks += 1 }
        center.post(name: AVAudioSession.interruptionNotification, object: session,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        XCTAssertNil(sink.finish(), "the buffer closes synchronously before the main-actor callback")
        for _ in 0..<100 where callbacks == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(callbacks, 1)
        token.cancel()
        token.cancel()
        center.post(name: AVAudioSession.interruptionNotification, object: session,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(callbacks, 1, "removed observer does not deliver new notifications")
    }

    @MainActor func testSyntheticRouteAndMediaResetFailClosed() async throws {
        let center = NotificationCenter(), session = AVAudioSession.sharedInstance()
        let platform = AppleProviderPCMPlatform(center: center, session: session)
        let harmless = ProviderPCMBuffer()
        XCTAssertEqual(harmless.append([0.5], sampleRate: 16_000, channels: 1), .accepted)
        var harmlessCallbacks = 0
        let harmlessToken = platform.observeSystemChanges(buffer: harmless) { harmlessCallbacks += 1 }
        center.post(name: AVAudioSession.interruptionNotification, object: session,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        center.post(name: AVAudioSession.routeChangeNotification, object: session,
                    userInfo: [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.categoryChange.rawValue])
        XCTAssertNotNil(harmless.finish())
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(harmlessCallbacks, 0)
        harmlessToken.cancel()
        for (name, info) in [
            (AVAudioSession.routeChangeNotification,
             [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue]),
            (AVAudioSession.mediaServicesWereResetNotification, [:])
        ] {
            let sink = ProviderPCMBuffer()
            XCTAssertEqual(sink.append([0.5], sampleRate: 16_000, channels: 1), .accepted)
            var calls = 0
            let token = platform.observeSystemChanges(buffer: sink) { calls += 1 }
            center.post(name: name, object: session, userInfo: info)
            XCTAssertNil(sink.finish())
            for _ in 0..<100 where calls == 0 { try await Task.sleep(nanoseconds: 10_000_000) }
            XCTAssertEqual(calls, 1)
            token.cancel()
        }
    }
}
#endif
