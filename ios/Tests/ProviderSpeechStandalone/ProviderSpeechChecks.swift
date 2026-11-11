import Foundation

private struct FixtureTransport: SpeechProviderTransport {
    let inspect: @Sendable (URLRequest) throws -> (Data, Int)
    func send(_ request: URLRequest) async throws -> (Data, Int) { try inspect(request) }
}

private actor DelayedTransport: SpeechProviderTransport {
    private var waiting: CheckedContinuation<(Data, Int), Never>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        await withCheckedContinuation { waiting = $0 }
    }
    func started() -> Bool { waiting != nil }
    func release() { waiting?.resume(returning: (Data("{\"text\":\"late\"}".utf8), 200)); waiting = nil }
}

private final class SpeechURLProtocol: URLProtocol {
    // Intercept every destination, including any accidental redirect target.
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let redirect = url.path.contains("redirect")
        let status = redirect ? 302 : 200
        let headers = redirect ? ["Location": "https://elsewhere.invalid/"] : ["Content-Type": "application/json"]
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !redirect { client?.urlProtocol(self, didLoad: Data("{\"text\":\"mock session\"}".utf8)) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main struct ProviderSpeechChecks {
    static func main() async throws {
        var count = 0
        func check(_ ok: Bool, _ message: String) {
            precondition(ok, message); count += 1
        }
        func expect(_ expected: SpeechProviderError, _ action: () throws -> Void) {
            do { try action(); fatalError("expected \(expected)") }
            catch let error as SpeechProviderError { check(error == expected, "unexpected error: \(error)") }
            catch { fatalError("unexpected error") }
        }
        let pcm: [Int16] = [0, 1, -1, Int16.max, Int16.min]
        let wav = try SpeechWAV.encode(pcm)
        check(wav.count == 54, "WAV length")
        check(Array(wav.suffix(10)) == [0,0,1,0,255,255,255,127,0,128], "little endian PCM")
        expect(.invalidAudio) { _ = try SpeechWAV.encode([]) }
        expect(.invalidAudio) { _ = try SpeechWAV.encode(Array(repeating: 0, count: SpeechWAV.maxSamples + 1)) }
        let selection = try SpeechProviderSelection(providerID: "provider-1", model: "whisper-1", method: .audioTranscriptions)
        let choices: [SpeechModelChoice] = [.automatic, .system, .off, .provider(selection)]
        for choice in choices { check(try SpeechModelChoice.decode(choice.encoded()) == choice, "choice round trip") }
        let suiteName = "voice-test-" + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else { fatalError("no test suite") }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SpeechChoiceStore(defaults: defaults)
        check(try store.load() == .automatic, "unset defaults to automatic")
        try store.save(.provider(selection))
        check(try store.load() == .provider(selection), "choice persistence")
        let stored = defaults.data(forKey: "speech.choice.v1")!
        check(!String(decoding: stored, as: UTF8.self).contains("test-secret"), "secret absent from persisted choice")
        defaults.set(Data("{\"type\":\"provider\",\"method\":\"future\"}".utf8), forKey: "speech.choice.v1")
        expect(.invalidConfiguration) { _ = try store.load() }
        expect(.invalidConfiguration) { _ = try SpeechProviderSelection(providerID: "", model: "x", method: .audioTranscriptions) }
        expect(.invalidConfiguration) { _ = try SpeechProviderSelection(providerID: "p", model: "bad\r\ninjection", method: .audioTranscriptions) }
        let open = SpeechProviderEndpoint(providerID: "provider-1", kind: .openAICompatible, baseURL: URL(string: "https://example.invalid/v1/")!)
        let multipart = try SpeechProviderRequest.make(endpoint: open, selection: selection, apiKey: "test-secret", wav: wav, language: "zh")
        check(multipart.url?.absoluteString == "https://example.invalid/v1/audio/transcriptions", "multipart endpoint")
        // Test both explicit malformed authorities and valid boundary ports.
        // URL may itself reject an input on some Foundation versions; otherwise
        // request construction must reject it before any audio can be sent.
        let invalidAuthorities = [
            "https://site.invalid:/v1", "https://site.invalid:0/v1",
            "https://site.invalid:00/v1", "https://site.invalid:01/v1",
            "https://site.invalid:000443/v1", "https://site.invalid:00065535/v1",
            "https://site.invalid:65536/v1", "https://site.invalid:999999999999999999999999/v1",
            "https://site.invalid:12:34/v1", "https://[::1]:/v1", "https://[::1]:0/v1",
            "https://[::1]:01/v1", "https://[::1]:000443/v1", "https://[::1]:00065535/v1",
            "https://[::1]:65536/v1", "https://[::1]:999999999999999999999999/v1",
            "https://[::1]extra/v1", "https://[not-ipv6]/v1", "https://[::1%25en0]/v1",
            "https://user@site.invalid/v1", "https://site.invalid%3a443/v1"
        ]
        for raw in invalidAuthorities {
            guard let url = URL(string: raw) else { check(true, "Foundation rejects \(raw)"); continue }
            let endpoint = SpeechProviderEndpoint(providerID: "provider-1", kind: .openAICompatible, baseURL: url)
            expect(.invalidConfiguration) { _ = try SpeechProviderRequest.make(endpoint: endpoint, selection: selection, apiKey: "k", wav: wav) }
        }
        let validAuthorities = ["site.invalid", "site.invalid:1", "site.invalid:443", "site.invalid:65535",
                                "[::1]", "[2001:db8::1]:1", "[2001:db8::1]:65535"]
        for authority in validAuthorities {
            let endpoint = SpeechProviderEndpoint(providerID: "provider-1", kind: .openAICompatible,
                                                  baseURL: URL(string: "https://\(authority)/v1")!)
            let request = try SpeechProviderRequest.make(endpoint: endpoint, selection: selection, apiKey: "k", wav: wav)
            check(request.url?.absoluteString == "https://\(authority)/v1/audio/transcriptions", "final destination preserved: \(authority)")
        }
        check(multipart.value(forHTTPHeaderField: "Authorization") == "Bearer test-secret", "bearer header")
        let body = multipart.httpBody!
        let bodyText = String(decoding: body, as: UTF8.self)
        check(bodyText.contains("name=\"model\"\r\n\r\nwhisper-1"), "multipart model")
        check(bodyText.contains("name=\"language\"\r\n\r\nzh"), "multipart language")
        check(body.range(of: wav) != nil, "multipart WAV bytes")
        check(!bodyText.contains("test-secret"), "key absent from body")
        let base64 = wav.base64EncodedString()
        for method in [SpeechProviderMethod.chatInputAudio, .chatInputAudioURI, .chatInputAudioOnly] {
            let chosen = try SpeechProviderSelection(providerID: "provider-1", model: "audio-model", method: method)
            let req = try SpeechProviderRequest.make(endpoint: open, selection: chosen, apiKey: nil, wav: wav)
            check(req.url?.path == "/v1/chat/completions", "chat endpoint")
            let json = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
            let messages = json["messages"] as! [[String: Any]]
            let blocks = messages[0]["content"] as! [[String: Any]]
            let audio = blocks[0]["input_audio"] as! [String: String]
            check(audio["data"] == (method == .chatInputAudio ? base64 : "data:audio/wav;base64," + base64), "audio payload variant")
            check(blocks.count == (method == .chatInputAudioOnly ? 1 : 2), "audio-only excludes instruction")
        }
        let gemini = SpeechProviderEndpoint(providerID: "g", kind: .gemini, baseURL: URL(string: "https://gemini.example.invalid")!)
        let gm = try SpeechProviderSelection(providerID: "g", model: "gemini-test", method: .geminiInline)
        let gr = try SpeechProviderRequest.make(endpoint: gemini, selection: gm, apiKey: "test-secret", wav: wav)
        check(gr.url?.path == "/v1beta/models/gemini-test:generateContent", "Gemini endpoint")
        check(gr.value(forHTTPHeaderField: "x-goog-api-key") == "test-secret", "Gemini key header")
        let object = try JSONSerialization.jsonObject(with: gr.httpBody!) as! [String: Any]
        let contents = object["contents"] as! [[String: Any]]
        let parts = contents[0]["parts"] as! [[String: Any]]
        check((parts[0]["inline_data"] as? [String: String])?["data"] == base64, "Gemini inline audio")
        let unsafe = SpeechProviderEndpoint(providerID: "provider-1", kind: .openAICompatible, baseURL: URL(string: "http://example.invalid/v1")!)
        expect(.invalidConfiguration) { _ = try SpeechProviderRequest.make(endpoint: unsafe, selection: selection, apiKey: "k", wav: wav) }
        expect(.invalidConfiguration) { _ = try SpeechProviderRequest.make(endpoint: open, selection: selection, apiKey: "a\r\nb", wav: wav) }
        expect(.invalidConfiguration) { _ = try SpeechProviderRequest.make(endpoint: open, selection: gm, apiKey: nil, wav: wav) }
        let wrongProvider = try SpeechProviderSelection(providerID: "other", model: "x", method: .audioTranscriptions)
        expect(.invalidConfiguration) { _ = try SpeechProviderRequest.make(endpoint: open, selection: wrongProvider, apiKey: "k", wav: wav) }
        expect(.invalidAudio) { _ = try SpeechProviderRequest.make(endpoint: open, selection: selection, apiKey: nil, wav: Data([1,2])) }
        let badModel = try SpeechProviderSelection(providerID: "g", model: "../other", method: .geminiInline)
        expect(.invalidConfiguration) { _ = try SpeechProviderRequest.make(endpoint: gemini, selection: badModel, apiKey: nil, wav: wav) }
        let result = Data("{\"text\":\"  hello  \"}".utf8)
        check(try SpeechProviderRequest.parse(result, status: 200, method: .audioTranscriptions) == "hello", "parse text")
        check(try SpeechProviderRequest.parse(Data("{\"choices\":[{\"message\":{\"content\":[{\"text\":\"a\"},{\"text\":\"b\"}]}}]}".utf8), status: 200, method: .chatInputAudio) == "ab", "parse content blocks")
        check(try SpeechProviderRequest.parse(Data("{\"candidates\":[{}]}".utf8), status: 200, method: .geminiInline).isEmpty, "empty Gemini candidate")
        expect(.invalidResponse) { _ = try SpeechProviderRequest.parse(Data("{}".utf8), status: 200, method: .audioTranscriptions) }
        expect(.redirectRejected) { _ = try SpeechProviderRequest.parse(Data(), status: 302, method: .audioTranscriptions) }
        expect(.unauthorized) { _ = try SpeechProviderRequest.parse(Data(), status: 401, method: .audioTranscriptions) }
        expect(.rateLimited) { _ = try SpeechProviderRequest.parse(Data(), status: 429, method: .audioTranscriptions) }
        expect(.unsupported) { _ = try SpeechProviderRequest.parse(Data(), status: 404, method: .audioTranscriptions) }
        expect(.responseTooLarge) { _ = try SpeechProviderRequest.parse(Data(repeating: 0, count: 1_048_577), status: 200, method: .audioTranscriptions) }
        let fake = FixtureTransport { request in
            precondition(request.url?.host == "example.invalid")
            return (result, 200)
        }
        let client = ProviderSpeechClient(transport: fake)
        let transcript = try await client.transcribe(endpoint: open, selection: selection, apiKey: "test-secret", wav: wav)
        check(transcript == "hello", "end to end using injected fake transport")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SpeechURLProtocol.self]
        let localSession = URLSession(configuration: config)
        let networkClient = ProviderSpeechClient(transport: URLSessionSpeechTransport(session: localSession))
        var insecureRequest = multipart
        insecureRequest.url = URL(string: "http://example.invalid/v1/audio/transcriptions")!
        do {
            _ = try await URLSessionSpeechTransport(session: localSession).send(insecureRequest)
            fatalError("insecure transport accepted")
        } catch let error as SpeechProviderError { check(error == .invalidConfiguration, "transport refuses HTTP") }
        for raw in invalidAuthorities {
            guard let url = URL(string: raw) else { continue }
            var badRequest = multipart
            badRequest.url = url
            do {
                _ = try await URLSessionSpeechTransport(session: localSession).send(badRequest)
                fatalError("transport accepted malformed destination: \(raw)")
            } catch let error as SpeechProviderError { check(error == .invalidConfiguration, "transport independently rejects malformed authority") }
        }
        for authority in validAuthorities {
            var validRequest = multipart
            validRequest.url = URL(string: "https://\(authority)/v1/audio/transcriptions")!
            let (response, status) = try await URLSessionSpeechTransport(session: localSession).send(validRequest)
            check(status == 200 && !response.isEmpty, "transport accepts canonical authority: \(authority)")
        }
        let sessionTranscript = try await networkClient.transcribe(endpoint: open, selection: selection, apiKey: "test-secret", wav: wav)
        check(sessionTranscript == "mock session", "URLSession transport through intercepting URLProtocol")
        let redirect = SpeechProviderEndpoint(providerID: "provider-1", kind: .openAICompatible, baseURL: URL(string: "https://example.invalid/redirect")!)
        do {
            _ = try await networkClient.transcribe(endpoint: redirect, selection: selection, apiKey: "test-secret", wav: wav)
            fatalError("redirect accepted")
        } catch let error as SpeechProviderError { check(error == .redirectRejected, "redirect rejected") }
        let task = localSession.dataTask(with: multipart)
        let redirectResponse = HTTPURLResponse(url: multipart.url!, statusCode: 307, httpVersion: "HTTP/1.1", headerFields: nil)!
        var redirected: URLRequest? = multipart
        SpeechRejectRedirects().urlSession(localSession, task: task, willPerformHTTPRedirection: redirectResponse,
                                           newRequest: multipart) { redirected = $0 }
        check(redirected == nil, "redirect delegate refuses forwarding")
        task.cancel()
        localSession.invalidateAndCancel()
        let delayed = DelayedTransport()
        let delayedClient = ProviderSpeechClient(transport: delayed)
        let work = Task { try await delayedClient.transcribe(endpoint: open, selection: selection, apiKey: nil, wav: wav) }
        for _ in 0..<10_000 {
            if await delayed.started() { break }
            await Task.yield()
        }
        check(await delayed.started(), "delayed request started")
        work.cancel()
        await delayed.release()
        do { _ = try await work.value; fatalError("cancelled request returned a result") }
        catch is CancellationError { check(true, "late callback after cancellation rejected") }
        print("PASS provider speech core: \(count) checks; synthetic audio, no network")
    }
}
