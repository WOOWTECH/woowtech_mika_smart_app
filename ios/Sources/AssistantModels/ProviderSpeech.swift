import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Validate the serialized authority as well as Foundation's parsed values.
/// An empty or overflowing explicit port can otherwise appear as a nil port.
private enum SpeechHTTPSDestination {
    static func authority(_ url: URL) throws -> String {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              let delimiter = url.absoluteString.range(of: "://"),
              url.absoluteString[..<delimiter.lowerBound].lowercased() == "https" else {
            throw SpeechProviderError.invalidConfiguration
        }
        let rest = url.absoluteString[delimiter.upperBound...]
        let authority = String(rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
        guard !authority.isEmpty, !authority.contains("@"), !authority.contains("\\"),
              !authority.contains("%") else { throw SpeechProviderError.invalidConfiguration }
        let portSuffix: Substring
        if authority.first == "[" {
            guard let close = authority.firstIndex(of: "]") else { throw SpeechProviderError.invalidConfiguration }
            let literal = String(authority[authority.index(after: authority.startIndex)..<close])
            var address = in6_addr()
            guard literal.withCString({ inet_pton(AF_INET6, $0, &address) }) == 1 else {
                throw SpeechProviderError.invalidConfiguration
            }
            portSuffix = authority[authority.index(after: close)...]
        } else {
            guard !authority.contains("["), !authority.contains("]") else { throw SpeechProviderError.invalidConfiguration }
            if let colon = authority.firstIndex(of: ":") {
                guard colon != authority.startIndex else { throw SpeechProviderError.invalidConfiguration }
                portSuffix = authority[colon...]
            } else { portSuffix = authority[authority.endIndex...] }
        }
        if portSuffix.isEmpty {
            guard parts.port == nil else { throw SpeechProviderError.invalidConfiguration }
        } else {
            guard portSuffix.first == ":" else { throw SpeechProviderError.invalidConfiguration }
            let digits = portSuffix.dropFirst()
            guard !digits.isEmpty, digits.utf8.allSatisfy({ (48...57).contains($0) }),
                  let port = Int(digits), (1...65535).contains(port), parts.port == port else {
                throw SpeechProviderError.invalidConfiguration
            }
        }
        return authority
    }
}

/// Serializable choice contains only a provider reference, never credentials.
public enum SpeechProviderMethod: String, Codable, CaseIterable, Sendable {
    case audioTranscriptions = "AudioTranscriptions"
    case chatInputAudio = "ChatInputAudio"
    case chatInputAudioURI = "ChatInputAudioUri"
    case chatInputAudioOnly = "ChatInputAudioOnly"
    case geminiInline = "GeminiInline"
}

public enum SpeechProviderKind: String, Codable, Sendable {
    case openAICompatible, openAIResponses, gemini
}

public struct SpeechProviderSelection: Codable, Equatable, Sendable {
    public let providerID: String
    public let model: String
    public let method: SpeechProviderMethod
    public init(providerID: String, model: String, method: SpeechProviderMethod) throws {
        guard Self.validField(providerID), Self.validField(model) else { throw SpeechProviderError.invalidConfiguration }
        self.providerID = providerID; self.model = model; self.method = method
    }
    fileprivate static func validField(_ value: String) -> Bool {
        !value.isEmpty && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.utf8.count <= 512 && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}

/// Persist a choice, not an API key. Invalid stored values throw instead of
/// silently selecting another destination or paid model.
public enum SpeechModelChoice: Equatable {
    case automatic, system, off, provider(SpeechProviderSelection)
    public func encoded() throws -> Data {
        var fields: [String: String]
        switch self {
        case .automatic: fields = ["type": "auto"]
        case .system: fields = ["type": "system"]
        case .off: fields = ["type": "off"]
        case .provider(let selection):
            fields = ["type": "provider", "providerId": selection.providerID,
                      "model": selection.model, "method": selection.method.rawValue]
        }
        return try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    }
    public static func decode(_ data: Data) throws -> SpeechModelChoice {
        guard data.count <= 4096, let value = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let type = value["type"] else { throw SpeechProviderError.invalidConfiguration }
        switch type {
        case "auto": return .automatic
        case "system": return .system
        case "off": return .off
        case "provider":
            guard let id = value["providerId"], let model = value["model"], let raw = value["method"],
                  let method = SpeechProviderMethod(rawValue: raw) else { throw SpeechProviderError.invalidConfiguration }
            return .provider(try SpeechProviderSelection(providerID: id, model: model, method: method))
        default: throw SpeechProviderError.invalidConfiguration
        }
    }
}

/// The host chooses an isolated or application UserDefaults suite explicitly.
public struct SpeechChoiceStore {
    private let defaults: UserDefaults
    private let key: String
    public init(defaults: UserDefaults, key: String = "speech.choice.v1") { self.defaults = defaults; self.key = key }
    public func load() throws -> SpeechModelChoice {
        guard let value = defaults.object(forKey: key) else { return .automatic }
        guard let data = value as? Data else { throw SpeechProviderError.invalidConfiguration }
        return try SpeechModelChoice.decode(data)
    }
    public func save(_ choice: SpeechModelChoice) throws { defaults.set(try choice.encoded(), forKey: key) }
}

public enum SpeechProviderError: Error, Equatable {
    case invalidConfiguration, invalidAudio, responseTooLarge, invalidResponse, redirectRejected
    case unauthorized, rateLimited, unsupported, provider(status: Int), transport
}

/// Canonical 16 kHz, mono, signed 16-bit PCM WAV as used by Android.
public enum SpeechWAV {
    public static let sampleRate = 16_000
    public static let maxSamples = sampleRate * 60
    public static func encode(_ samples: [Int16]) throws -> Data {
        guard !samples.isEmpty, samples.count <= maxSamples else { throw SpeechProviderError.invalidAudio }
        var data = Data()
        func ascii(_ text: String) { data.append(contentsOf: text.utf8) }
        func u16(_ value: UInt16) { data.append(UInt8(truncatingIfNeeded: value)); data.append(UInt8(truncatingIfNeeded: value >> 8)) }
        func u32(_ value: UInt32) { u16(UInt16(truncatingIfNeeded: value)); u16(UInt16(truncatingIfNeeded: value >> 16)) }
        ascii("RIFF"); u32(UInt32(36 + samples.count * 2)); ascii("WAVEfmt "); u32(16)
        u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        ascii("data"); u32(UInt32(samples.count * 2))
        for sample in samples { u16(UInt16(bitPattern: sample)) }
        return data
    }
    fileprivate static func isCanonical(_ data: Data) -> Bool {
        guard data.count >= 46, data.count <= 44 + maxSamples * 2, data.count % 2 == 0 else { return false }
        let bytes = [UInt8](data.prefix(44))
        func u16(_ n: Int) -> UInt32 { UInt32(bytes[n]) | (UInt32(bytes[n+1]) << 8) }
        func u32(_ n: Int) -> UInt32 { u16(n) | (u16(n+2) << 16) }
        return Array(bytes[0..<4]) == Array("RIFF".utf8) && Array(bytes[8..<16]) == Array("WAVEfmt ".utf8)
            && Array(bytes[36..<40]) == Array("data".utf8) && u32(4) == data.count - 8
            && u32(16) == 16 && u16(20) == 1 && u16(22) == 1 && u32(24) == 16000
            && u32(28) == 32000 && u16(32) == 2 && u16(34) == 16 && u32(40) == data.count - 44
    }
}

/// One user-selected provider; the credential is passed separately per request.
public struct SpeechProviderEndpoint: Sendable {
    public let providerID: String
    public let kind: SpeechProviderKind
    public let baseURL: URL
    public init(providerID: String, kind: SpeechProviderKind, baseURL: URL) {
        self.providerID = providerID; self.kind = kind; self.baseURL = baseURL
    }
}

public struct SpeechProviderRequest {
    private static let instruction = "Transcribe this recording word for word. Output only the transcript text."
    public static func make(endpoint: SpeechProviderEndpoint, selection: SpeechProviderSelection,
                            apiKey: String?, wav: Data, language: String? = nil) throws -> URLRequest {
        guard SpeechWAV.isCanonical(wav) else { throw SpeechProviderError.invalidAudio }
        guard SpeechProviderSelection.validField(selection.providerID), selection.providerID == endpoint.providerID,
              SpeechProviderSelection.validField(selection.model),
              var parts = URLComponents(url: endpoint.baseURL, resolvingAgainstBaseURL: false) else {
            throw SpeechProviderError.invalidConfiguration
        }
        let originalAuthority = try SpeechHTTPSDestination.authority(endpoint.baseURL)
        if let key = apiKey, (key.isEmpty || key.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.union(.controlCharacters).contains($0) })) {
            throw SpeechProviderError.invalidConfiguration
        }
        if let language = language, (!SpeechProviderSelection.validField(language) || language.utf8.count > 32
            || !language.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-").contains($0) })) {
            throw SpeechProviderError.invalidConfiguration
        }
        let isGemini = endpoint.kind == .gemini
        guard isGemini == (selection.method == .geminiInline) else { throw SpeechProviderError.invalidConfiguration }
        var path = parts.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        switch selection.method {
        case .audioTranscriptions: path += "/audio/transcriptions"
        case .chatInputAudio, .chatInputAudioURI, .chatInputAudioOnly: path += "/chat/completions"
        case .geminiInline:
            // Avoid treating model IDs as arbitrary path, query or authority components.
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
            guard selection.model.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { throw SpeechProviderError.invalidConfiguration }
            path += "/v1beta/models/\(selection.model):generateContent"
        }
        parts.percentEncodedPath = path
        guard let url = parts.url,
              try SpeechHTTPSDestination.authority(url) == originalAuthority,
              URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath == path else {
            throw SpeechProviderError.invalidConfiguration
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "POST"; request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let key = apiKey { request.setValue(isGemini ? key : "Bearer \(key)", forHTTPHeaderField: isGemini ? "x-goog-api-key" : "Authorization") }
        switch selection.method {
        case .audioTranscriptions:
            let boundary = "WoowSpeech-" + UUID().uuidString
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            var body = Data()
            func append(_ s: String) { body.append(contentsOf: s.utf8) }
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n\(selection.model)\r\n")
            if let language { append("--\(boundary)\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\n\(language)\r\n") }
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
            body.append(wav); append("\r\n--\(boundary)--\r\n"); request.httpBody = body
        case .chatInputAudio, .chatInputAudioURI, .chatInputAudioOnly:
            let base64 = wav.base64EncodedString()
            let audio = selection.method == .chatInputAudio ? base64 : "data:audio/wav;base64," + base64
            var content: [[String: Any]] = [["type": "input_audio", "input_audio": ["data": audio, "format": "wav"]]]
            if selection.method != .chatInputAudioOnly { content.append(["type": "text", "text": instruction]) }
            let message: [String: Any] = ["role": "user", "content": content]
            let json: [String: Any] = ["model": selection.model, "stream": false, "messages": [message]]
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        case .geminiInline:
            let audioPart: [String: Any] = ["inline_data": ["mime_type": "audio/wav", "data": wav.base64EncodedString()]]
            let content: [String: Any] = ["parts": [audioPart, ["text": instruction]]]
            let json: [String: Any] = ["contents": [content]]
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        return request
    }
    public static func parse(_ data: Data, status: Int, method: SpeechProviderMethod) throws -> String {
        guard data.count <= 1_048_576 else { throw SpeechProviderError.responseTooLarge }
        switch status {
        case 200..<300: break
        case 300..<400: throw SpeechProviderError.redirectRejected
        case 401, 403: throw SpeechProviderError.unauthorized
        case 429: throw SpeechProviderError.rateLimited
        case 400, 404, 405, 422: throw SpeechProviderError.unsupported
        default: throw SpeechProviderError.provider(status: status)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw SpeechProviderError.invalidResponse }
        let text: String?
        switch method {
        case .audioTranscriptions: text = root["text"] as? String
        case .chatInputAudio, .chatInputAudioURI, .chatInputAudioOnly:
            let choices = root["choices"] as? [[String: Any]]
            let content = (choices?.first?["message"] as? [String: Any])?["content"]
            if let string = content as? String { text = string }
            else if let blocks = content as? [[String: Any]] { text = blocks.compactMap { $0["text"] as? String }.joined() }
            else { text = nil }
        case .geminiInline:
            if let candidate = (root["candidates"] as? [[String: Any]])?.first {
                let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
                text = parts.compactMap { $0["text"] as? String }.joined()
            } else { text = nil }
        }
        guard let text else { throw SpeechProviderError.invalidResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// No implicit probe or fallback: a caller explicitly selects the provider/method
/// and authorizes each upload. Injected transport permits local, synthetic tests.
public protocol SpeechProviderTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

/// Ephemeral session, no cookie/cache/credential persistence, and no redirect
/// forwarding of recordings or authorization headers. Never logs payloads.
public struct URLSessionSpeechTransport: SpeechProviderTransport {
    private let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration)
    }
    init(session: URLSession) { self.session = session }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            guard request.httpMethod == "POST", let url = request.url,
                  let body = request.httpBody, body.count <= 4_000_000 else {
                throw SpeechProviderError.invalidConfiguration
            }
            _ = try SpeechHTTPSDestination.authority(url)
            try Task.checkCancellation()
            let (bytes, response) = try await session.bytes(for: request, delegate: SpeechRejectRedirects())
            defer { bytes.task.cancel() }
            guard let response = response as? HTTPURLResponse else { throw SpeechProviderError.invalidResponse }
            // No need to ingest provider error bodies, which may echo secrets.
            guard (200..<300).contains(response.statusCode) else { return (Data(), response.statusCode) }
            return try await withTaskCancellationHandler {
                var data = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    guard data.count < 1_048_576 else { throw SpeechProviderError.responseTooLarge }
                    data.append(byte)
                }
                try Task.checkCancellation()
                return (data, response.statusCode)
            } onCancel: { bytes.task.cancel() }
        } catch is CancellationError { throw CancellationError() }
        catch let error as SpeechProviderError { throw error }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw SpeechProviderError.transport
        }
    }
}
final class SpeechRejectRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
public struct ProviderSpeechClient: Sendable {
    private let transport: any SpeechProviderTransport
    public init(transport: any SpeechProviderTransport) { self.transport = transport }
    public func transcribe(endpoint: SpeechProviderEndpoint, selection: SpeechProviderSelection,
                           apiKey: String?, wav: Data, language: String? = nil) async throws -> String {
        let request = try SpeechProviderRequest.make(endpoint: endpoint, selection: selection, apiKey: apiKey, wav: wav, language: language)
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        return try SpeechProviderRequest.parse(data, status: status, method: selection.method)
    }
}
