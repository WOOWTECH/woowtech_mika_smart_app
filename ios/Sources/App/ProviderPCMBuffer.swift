import Foundation

/// Thread-safe, bounded capture storage. Input is interleaved normalized Float
/// PCM. Each output sample is a time-weighted box average; integer phase avoids
/// drift at rates such as 44.1 kHz and makes chunk boundaries irrelevant.
final class ProviderPCMBuffer: @unchecked Sendable {
    enum AppendResult: Equatable { case accepted, closed, invalid, limit }
    private let lock = NSLock()
    private let maxSamples: Int
    private var samples: [Int16] = []
    private var rate: Int?
    private var channels: Int?
    private var weight = 0
    private var sum: Double = 0
    private var closed = false
    private var failed = false

    init(maxSamples: Int = 16_000 * 60) {
        precondition((1...16_000 * 60).contains(maxSamples))
        self.maxSamples = maxSamples
    }

    func append(_ input: [Float], sampleRate: Int, channels: Int) -> AppendResult {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return .closed }
        guard (8_000...192_000).contains(sampleRate), (1...8).contains(channels),
              !input.isEmpty, input.count % channels == 0, input.count / channels <= 8192,
              rate == nil || rate == sampleRate, self.channels == nil || self.channels == channels,
              input.allSatisfy({ $0.isFinite }) else {
            closed = true; failed = true; samples.removeAll(); return .invalid
        }
        rate = sampleRate; self.channels = channels
        for frame in stride(from: 0, to: input.count, by: channels) {
            var mono = 0.0
            for c in 0..<channels { mono += Double(max(-1, min(1, input[frame + c]))) }
            mono /= Double(channels)
            var remaining = 16_000
            while remaining > 0 {
                let part = min(remaining, sampleRate - weight)
                sum += mono * Double(part)
                weight += part; remaining -= part
                if weight == sampleRate {
                    let value = max(-1.0, min(1.0, sum / Double(sampleRate)))
                    let scaled = value < 0 ? value * 32768.0 : value * 32767.0
                    samples.append(Int16(scaled.rounded()))
                    sum = 0; weight = 0
                    if samples.count == maxSamples {
                        // Reaching the deadline is not a user release. Discard.
                        closed = true; failed = true; samples.removeAll(); return .limit
                    }
                }
            }
        }
        return .accepted
    }

    /// Closes before returning, so a concurrent late callback cannot append.
    func finish() -> [Int16]? {
        lock.lock(); defer { lock.unlock() }
        guard !closed, !failed else { return nil }
        closed = true
        let result = samples
        samples = []
        return result
    }

    func discard() {
        lock.lock(); defer { lock.unlock() }
        closed = true; failed = true; samples.removeAll()
        sum = 0; weight = 0
    }
}
