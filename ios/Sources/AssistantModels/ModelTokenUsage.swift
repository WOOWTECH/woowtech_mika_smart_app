import Foundation

/// Counters supplied by the endpoint for one successful response. Nil means
/// unreported or invalid, including when another field is available. Cached
/// input and reasoning output are subsets, not extra tokens to add again.
public struct ModelTokenUsage: Sendable, Equatable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?
    public let cachedInputTokens: Int?
    public let reasoningTokens: Int?

    /// Other explicitly implemented adapters may construct a partial report.
    /// At least one counter must be known and all known values are nonnegative.
    public init?(inputTokens: Int? = nil, outputTokens: Int? = nil, totalTokens: Int? = nil,
                 cachedInputTokens: Int? = nil, reasoningTokens: Int? = nil) {
        let fields = [inputTokens, outputTokens, totalTokens, cachedInputTokens, reasoningTokens]
        guard fields.contains(where: { $0 != nil }), fields.compactMap({ $0 }).allSatisfy({ $0 >= 0 }),
              cachedInputTokens == nil || inputTokens == nil || cachedInputTokens! <= inputTokens!,
              reasoningTokens == nil || outputTokens == nil || reasoningTokens! <= outputTokens! else { return nil }
        self.inputTokens = inputTokens; self.outputTokens = outputTokens; self.totalTokens = totalTokens
        self.cachedInputTokens = cachedInputTokens; self.reasoningTokens = reasoningTokens
    }
}

public struct ModelCompletionWithUsage: Sendable, Equatable {
    public let text: String
    /// Nil is unknown; no estimate and no inferred zero.
    public let usage: ModelTokenUsage?
    public init(text: String, usage: ModelTokenUsage?) { self.text = text; self.usage = usage }
}

/// The final event is emitted only after a successful, fully validated response.
/// Text deltas may precede an error and must not themselves imply completion.
public enum ModelStreamWithUsageEvent: Sendable, Equatable {
    case text(String)
    case completed(usage: ModelTokenUsage?)
}

/// Optional additive capability: existing text-only clients keep their API.
public protocol UsageReportingChatModelClient: ChatModelClient {
    func completeWithUsage(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) async throws -> ModelCompletionWithUsage
}

public enum ModelStreamUsageRequest: Sendable {
    /// Preserve the existing request shape and retain any unsolicited usage.
    case ifProvided
    /// Explicitly request the OpenAI Chat Completions stream_options extension.
    /// Other endpoints may reject it; this layer never silently retries.
    case requestOpenAICompatible
}

public protocol UsageReportingStreamingChatModelClient: UsageReportingChatModelClient, StreamingChatModelClient {
    func streamWithUsage(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String,
                         usageRequest: ModelStreamUsageRequest) -> AsyncThrowingStream<ModelStreamWithUsageEvent, Error>
}

public extension UsageReportingStreamingChatModelClient {
    func streamWithUsage(messages: [ModelMessage], configuration: ModelConfiguration, apiKey: String) -> AsyncThrowingStream<ModelStreamWithUsageEvent, Error> {
        streamWithUsage(messages: messages, configuration: configuration, apiKey: apiKey, usageRequest: .ifProvided)
    }
}

/// OpenAI Chat Completions fields only; this is not an adapter for Responses,
/// Anthropic or Gemini. Unknown/malformed individual fields never become zero.
struct OpenAIReportedUsage: Decodable {
    let value: ModelTokenUsage?
    private enum Keys: String, CodingKey {
        case prompt_tokens, completion_tokens, total_tokens, prompt_tokens_details, completion_tokens_details
        case prompt_cache_hit_tokens, prompt_cache_miss_tokens
    }
    private enum Details: String, CodingKey { case cached_tokens, reasoning_tokens }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        func count(_ key: Keys) -> Int? {
            guard let value = try? c.decode(Int.self, forKey: key), value >= 0 else { return nil }
            return value
        }
        let hit = count(.prompt_cache_hit_tokens), miss = count(.prompt_cache_miss_tokens)
        let sum = hit.flatMap { a in miss.flatMap { b in a.addingReportingOverflow(b).overflow ? nil : a + b } }
        let input = count(.prompt_tokens) ?? sum
        let output = count(.completion_tokens)
        let promptDetails = try? c.nestedContainer(keyedBy: Details.self, forKey: .prompt_tokens_details)
        let completionDetails = try? c.nestedContainer(keyedBy: Details.self, forKey: .completion_tokens_details)
        let rawCached = (try? promptDetails?.decode(Int.self, forKey: .cached_tokens)) ?? hit
        let rawReasoning = try? completionDetails?.decode(Int.self, forKey: .reasoning_tokens)
        let cached = rawCached.flatMap { $0 >= 0 && (input == nil || $0 <= input!) ? $0 : nil }
        let reasoning = rawReasoning.flatMap { $0 >= 0 && (output == nil || $0 <= output!) ? $0 : nil }
        let total = count(.total_tokens)
        value = ModelTokenUsage(inputTokens: input, outputTokens: output, totalTokens: total,
                                cachedInputTokens: cached, reasoningTokens: reasoning)
    }
}
