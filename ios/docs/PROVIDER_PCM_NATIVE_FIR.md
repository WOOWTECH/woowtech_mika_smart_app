# Isolated native PCM source and anti-aliasing candidate

This candidate starts from `6dc7d87de70710bf6b1c9f8a8ea68972194766db`. It
keeps provider speech inaccessible from the app. No real microphone or
service is used by the included tests.

`AppleProviderPCMSource` now delegates source ownership to
`CoordinatedProviderPCMSource`, whose platform and engine are injectable. The
source creates an engine only after the driver obtains the shared voice lease
and permission, observes interruptions/routes/media reset, installs the tap,
and rechecks the live start permission and collector before and after setup.
Cleanup detaches observers and synchronously stops the engine before the driver
releases the lease. Generation checks reject old errors, including an observer
returned after synchronous cancellation. A detected malformed tap buffer or
relevant notification closes the PCM collector before queuing the main-actor
failure callback; if release occurs in that interval, earlier partial samples
cannot be sent. As before, the future host must actively cancel on scene,
settings, conversation and gesture changes. Notifications not yet delivered
cannot be detected retroactively.

The observer is registered after lease activation, leaving an unobserved gap
before registration. A notification can also arrive between the final check
and engine start: the closed collector and post-start check prevent delivering
the captured data and stop the engine, but cannot rule out a brief start. These
timing limits require native investigation before exposing this source.

The native adapter's extracted AVAudioPCMBuffer conversion and notification
handling have iOS-hosted XCTest cases using synthetic buffers and an isolated
NotificationCenter. The test uses `AVAudioSession.sharedInstance()` only as a
notification identity; it does not activate the session, create an engine or
ask for permission. The portable `check_provider_pcm.sh` uses injected fake
permission, engine, observation and mixed-audio session; it covers permission
races, system-change/error paths, synchronous reentrancy, lease handoff, late
callbacks, stop, cancellation and synthetic release. Native AVAudioEngine,
actual permission, observer delivery, audio routes and background behavior have
not been SDK-typechecked or run on this host. The iOS cases are in the hosted
`AssistantSkillsTests` target, which still needs to run with the iOS SDK. The
portable fixture is also invoked by `scripts/test_provider_pcm.py` during
macOS unittest discovery.

## Anti-aliasing

The earlier box averaging was weak above the 8 kHz output Nyquist frequency.
For input rates above 16 kHz, the collector now applies a causal 7.2 kHz
Blackman-windowed sinc before decimation. It uses at most 505 taps and 17
nearest fractional-phase banks (at most 8,585 Double coefficients) and at most
16,000 convolutions per second. The filter is continuous across chunks and
emits exactly `floor(inputFrames * 16000 / inputRate)` samples; its start is
zero-padded and its tail is not flushed. The roughly 1.3 ms group delay means a
short initial transient and a corresponding tail loss. The transition band
near 7 kHz attenuates content; this is not bit-equivalent to Android's native
16 kHz microphone input. Rates at or below 16 kHz retain the prior simple
sample expansion, rather than claiming reconstruction of missing high bands.

The synthetic measurements below are numerical signal tests, not device audio
quality or performance tests. A 0.25-second sine of peak 0.8 was converted;
RMS was measured after removing the first 128 output samples to exclude the
causal startup. Expected unattenuated RMS is approximately 0.565685:

| Input → output | Tone | Output RMS |
| --- | --- | ---: |
| 48 kHz → 16 kHz | 1 kHz passband | 0.565682 |
| 48 kHz → 16 kHz | 6 kHz passband | 0.565612 |
| 48 kHz → 16 kHz | 10 kHz stopband | 0.000022 |
| 44.1 kHz → 16 kHz | 10 kHz stopband | 0.000016 |
| 192 kHz → 16 kHz | 10 kHz stopband | 0.000022 |

For 6 kHz, the measured fundamental RMS at 22.05 kHz and 44.1 kHz input was
0.563231 and 0.565540 respectively. Tests require the 1 kHz passband within 1%,
the 6 kHz passband and measured fundamental within 2%, and the tested 10 kHz
stopbands below 1% of the input RMS. Seven input rates (8, 16, 22.05, 44.1, 48,
96 and 192 kHz) are also checked for exact output length and chunk invariance.

Popper's unmodified 0.1-second, peak-1.0, 48 kHz/10 kHz review fixture was
reproduced at output RMS 0.358 on `6dc7d87`. On this candidate, the same input
including the startup transient measured 0.006695 (about 34.6 dB below the
old output). The steady-state table and this full-window replay have different
amplitude and window conventions and should not be compared as the same test.

A physical device must still validate the native adapter, signal quality,
real-time CPU/power cost, permissions and shared audio behavior. The collector
is bounded and prepares coefficient banks before the native tap is installed,
but performs convolution on the audio callback; its suitability on slower
iPhones or at 192 kHz has not been established. Real provider inventory,
model selection, consent disclosure and production capture/transport wiring
remain separate work. In-flight bytes handed to URLSession cannot be recalled.
