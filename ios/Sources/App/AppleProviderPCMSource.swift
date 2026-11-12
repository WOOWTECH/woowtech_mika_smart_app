#if os(iOS) && canImport(AVFoundation)
import AVFoundation
import Foundation

/// Native adapter for the injectable PCM source. It is not constructed by the
/// app yet; microphone access requires a future explicit user gesture.
@MainActor
final class AppleProviderPCMSource: ProviderPCMSource {
    private var engine: AVAudioEngine?
    private var installedTap = false
    private var observers: [NSObjectProtocol] = []

    func requestPermission(_ completion: @escaping @MainActor (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    func start(buffer: ProviderPCMBuffer, mayStart: @escaping @MainActor () -> Bool,
               onFailure: @escaping @MainActor () -> Void) throws {
        guard engine == nil else { throw CaptureError.invalidFormat }
        let newEngine = AVAudioEngine()
        let input = newEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        let rate = format.sampleRate
        let count = Int(format.channelCount)
        guard format.commonFormat == .pcmFormatFloat32, rate.isFinite,
              rate.rounded() == rate, rate >= 8_000, rate <= 192_000,
              (1...8).contains(count) else { throw CaptureError.invalidFormat }
        let integerRate = Int(rate)
        let interleaved = format.isInterleaved
        engine = newEngine
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { audio, _ in
            let frames = Int(audio.frameLength)
            guard frames > 0, frames <= 8192, frames <= Int(audio.frameCapacity),
                  audio.format.commonFormat == .pcmFormatFloat32,
                  audio.format.sampleRate == rate, Int(audio.format.channelCount) == count,
                  audio.format.isInterleaved == interleaved,
                  let channels = audio.floatChannelData else {
                DispatchQueue.main.async { onFailure() }; return
            }
            var inputSamples = [Float]()
            inputSamples.reserveCapacity(frames * count)
            for frame in 0..<frames {
                for channel in 0..<count {
                    inputSamples.append(interleaved ? channels[0][frame * count + channel] : channels[channel][frame])
                }
            }
            switch buffer.append(inputSamples, sampleRate: integerRate, channels: count) {
            case .accepted, .closed: break
            case .invalid, .limit: DispatchQueue.main.async { onFailure() }
            }
        }
        installedTap = true
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            DispatchQueue.main.async { onFailure() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                  reason == .oldDeviceUnavailable || reason == .newDeviceAvailable else { return }
            DispatchQueue.main.async { onFailure() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { _ in
            DispatchQueue.main.async { onFailure() }
        })
        guard mayStart() else { return }
        newEngine.prepare()
        guard mayStart() else { return }
        try newEngine.start()
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        if let engine {
            engine.stop()
            if installedTap { engine.inputNode.removeTap(onBus: 0) }
        }
        engine = nil
        installedTap = false
    }

    private enum CaptureError: Error { case invalidFormat }
}
#endif
