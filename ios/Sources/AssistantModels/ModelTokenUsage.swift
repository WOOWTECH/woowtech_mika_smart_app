import Foundation

/// Counters the endpoint reported for one successful response. Nil is
/// unreported or invalid, never zero; an explicit zero stays zero. Cached input
/// and reasoning output are subsets, not extra tokens to add again.
public struct ModelTokenUsage: Sendable, Equatable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?
    public let cachedInputTokens: Int?
    public let reasoningTokens: Int?

    /// At least one counter must be known, known values are nonnegative and a
    /// subset never exceeds the count that contains it.
    public init?(inputTokens: Int? = nil, outputTokens: Int? = nil, totalTokens: Int? = nil,
                 cachedInputTokens: Int? = nil, reasoningTokens: Int? = nil) {
        let fields = [inputTokens, outputTokens, totalTokens, cachedInputTokens, reasoningTokens]
        guard fields.contains(where: { $0 != nil }), fields.allSatisfy({ ($0 ?? 0) >= 0 }) else { return nil }
        if let cached = cachedInputTokens, let input = inputTokens, cached > input { return nil }
        if let reasoning = reasoningTokens, let output = outputTokens, reasoning > output { return nil }
        self.inputTokens = inputTokens; self.outputTokens = outputTokens; self.totalTokens = totalTokens
        self.cachedInputTokens = cachedInputTokens; self.reasoningTokens = reasoningTokens
    }

    /// Android's reading (OpenAiCompatModel.parseUsage): only an input count
    /// makes a report, so total_tokens alone is unreported; a missing output is 0.
    public var isReported: Bool { inputTokens != nil }
}

/// OpenAI Chat Completions `usage` only (not Responses, Anthropic or Gemini).
/// Decoded field by field: a malformed or negative field is unknown, never
/// zero, and no usage value ever fails the response that carries it.
struct OpenAIReportedUsage: Decodable {
    let value: ModelTokenUsage?
    private enum Keys: String, CodingKey {
        case prompt_tokens, completion_tokens, total_tokens, prompt_tokens_details, completion_tokens_details
        case prompt_cache_hit_tokens, prompt_cache_miss_tokens
    }
    private enum Details: String, CodingKey { case cached_tokens, reasoning_tokens }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: Keys.self) else { value = nil; return }
        func count<K: CodingKey>(_ container: KeyedDecodingContainer<K>?, _ key: K) -> Int? {
            guard let value = try? container?.decode(Int.self, forKey: key), value >= 0 else { return nil }
            return value
        }
        let promptDetails = try? c.nestedContainer(keyedBy: Details.self, forKey: .prompt_tokens_details)
        let completionDetails = try? c.nestedContainer(keyedBy: Details.self, forKey: .completion_tokens_details)
        let hit = count(c, .prompt_cache_hit_tokens), miss = count(c, .prompt_cache_miss_tokens)
        let sum = hit.flatMap { a in miss.flatMap { b in a.addingReportingOverflow(b).overflow ? nil : a + b } }
        let input = count(c, .prompt_tokens) ?? sum
        let output = count(c, .completion_tokens)
        // Like Android, the larger of the two cache-hit fields; above input it is unknown.
        let cached = [count(promptDetails, .cached_tokens), hit].compactMap { $0 }.max()
        let reasoning = count(completionDetails, .reasoning_tokens)
        value = ModelTokenUsage(inputTokens: input, outputTokens: output, totalTokens: count(c, .total_tokens),
                                cachedInputTokens: cached.flatMap { $0 <= (input ?? .max) ? $0 : nil },
                                reasoningTokens: reasoning.flatMap { $0 <= (output ?? .max) ? $0 : nil })
    }
}
