import Foundation

/// Thread-safe, bounded capture storage. Input is interleaved normalized Float
/// PCM. Rates above 16 kHz use a bounded causal low-pass FIR before decimation;
/// integer phase keeps exact sample counts and independent chunk boundaries.
final class ProviderPCMBuffer: @unchecked Sendable {
    enum AppendResult: Equatable { case accepted, closed, invalid, limit }
    private let lock = NSLock()
    private let maxSamples: Int
    private var samples: [Int16] = []
    private var rate: Int?
    private var channels: Int?
    private var weight = 0
    private var sum: Double = 0
    private var phase = 0
    private var coefficientBanks: [[Double]] = []
    private var history: [Double] = []
    private var historyIndex = 0
    private var closed = false
    private var failed = false

    init(maxSamples: Int = 16_000 * 60) {
        precondition((1...16_000 * 60).contains(maxSamples))
        self.maxSamples = maxSamples
    }

    var isOpen: Bool {
        lock.lock(); defer { lock.unlock() }
        return !closed && !failed
    }

    /// A Blackman-windowed sinc with a 7.2 kHz cutoff. Scale its length by the
    /// source rate, so transition width and delay stay approximately constant.
    /// Seventeen fractional phases limit timing error at nonintegral ratios.
    /// At most 17*505 coefficients and 16k convolutions/s bound memory/work.
    private func configureFilter(rate: Int) {
        guard rate > 16_000 else { return }
        let taps = min(505, max(43, Int(ceil(Double(rate) * 0.002625)) | 1))
        let center = Double(taps - 1) / 2
        let cutoff = 7_200.0 / Double(rate)
        coefficientBanks = (0...16).map { fractionalPhase in
            let fraction = Double(fractionalPhase) / 16
            let values = (0..<taps).map { index in
                let offset = Double(index) - center - fraction
                let sinc = offset == 0 ? 2 * cutoff : sin(2 * .pi * cutoff * offset) / (.pi * offset)
                let angle = 2 * .pi * Double(index) / Double(taps - 1)
                return sinc * (0.42 - 0.5 * cos(angle) + 0.08 * cos(2 * angle))
            }
            let gain = values.reduce(0, +)
            return values.map { $0 / gain }
        }
        history = [Double](repeating: 0, count: taps)
    }

    private func filteredSample(phaseIndex: Int) -> Double {
        var result = 0.0
        var index = historyIndex == 0 ? history.count - 1 : historyIndex - 1
        for coefficient in coefficientBanks[phaseIndex] {
            result += coefficient * history[index]
            index = index == 0 ? history.count - 1 : index - 1
        }
        return result
    }

    private func appendSample(_ value: Double) -> Bool {
        let value = max(-1.0, min(1.0, value))
        let scaled = value < 0 ? value * 32768.0 : value * 32767.0
        samples.append(Int16(scaled.rounded()))
        if samples.count == maxSamples {
            // A deadline is not a user release. Discard instead of uploading.
            closed = true; failed = true; samples.removeAll(); history.removeAll()
            return false
        }
        return true
    }

    /// The native source calls this after reading the engine format and before
    /// installing its tap, so coefficient construction is not on the audio
    /// callback. Synthetic sources may still configure lazily on first append.
    func prepare(sampleRate: Int, channels: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !closed, (8_000...192_000).contains(sampleRate), (1...8).contains(channels),
              rate == nil || rate == sampleRate, self.channels == nil || self.channels == channels else { return false }
        if rate == nil { configureFilter(rate: sampleRate) }
        rate = sampleRate; self.channels = channels
        return true
    }

    func append(_ input: [Float], sampleRate: Int, channels: Int) -> AppendResult {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return .closed }
        guard (8_000...192_000).contains(sampleRate), (1...8).contains(channels),
              !input.isEmpty, input.count % channels == 0, input.count / channels <= 8192,
              rate == nil || rate == sampleRate, self.channels == nil || self.channels == channels,
              input.allSatisfy({ $0.isFinite }) else {
            closed = true; failed = true; samples.removeAll(); history.removeAll(); return .invalid
        }
        if rate == nil { configureFilter(rate: sampleRate) }
        rate = sampleRate; self.channels = channels
        for frame in stride(from: 0, to: input.count, by: channels) {
            var mono = 0.0
            for c in 0..<channels { mono += Double(max(-1, min(1, input[frame + c]))) }
            mono /= Double(channels)
            if sampleRate > 16_000 {
                history[historyIndex] = mono
                historyIndex += 1
                if historyIndex == history.count { historyIndex = 0 }
                phase += 16_000
                if phase >= sampleRate {
                    phase -= sampleRate
                    let phaseIndex = (phase * 16 + 8_000) / 16_000
                    if !appendSample(filteredSample(phaseIndex: phaseIndex)) { return .limit }
                }
            } else {
                var remaining = 16_000
                while remaining > 0 {
                    let part = min(remaining, sampleRate - weight)
                    sum += mono * Double(part)
                    weight += part; remaining -= part
                    if weight == sampleRate {
                        if !appendSample(sum / Double(sampleRate)) { return .limit }
                        sum = 0; weight = 0
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
        samples = []; history.removeAll()
        return result
    }

    func discard() {
        lock.lock(); defer { lock.unlock() }
        closed = true; failed = true; samples.removeAll(); history.removeAll()
        sum = 0; weight = 0; phase = 0
    }
}
