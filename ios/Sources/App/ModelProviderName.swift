import Foundation

/// Android ProviderConnection.displayName for iOS's one saved service: the
/// name of a provider preset at the same address, otherwise the host. The
/// presets follow settings/ProviderPresets.kt at 465a17c9; Ollama and LM
/// Studio use loopback HTTP, which iOS never saves, so they are left out.
enum ModelProviderName {
    private static let presets: [(name: String, baseURL: String)] = [
        ("OpenRouter", "https://openrouter.ai/api/v1"),
        ("Requesty", "https://router.requesty.ai/v1"),
        ("OpenCode Go", "https://opencode.ai/zen/go/v1"),
        ("Anthropic", "https://api.anthropic.com"),
        ("Gemini", "https://generativelanguage.googleapis.com"),
        ("OpenAI", "https://api.openai.com/v1"),
        ("xAI", "https://api.x.ai/v1"),
        ("Mistral", "https://api.mistral.ai/v1"),
        ("Groq", "https://api.groq.com/openai/v1"),
        // iOS calls chat/completions only: the OpenAI-compatible addresses
        // of the Anthropic and Gemini presets name the same providers.
        ("Anthropic", "https://api.anthropic.com/v1"),
        ("Gemini", "https://generativelanguage.googleapis.com/v1beta/openai"),
    ]

    static func name(for baseURL: URL) -> String {
        let host = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)?.host
        guard let address = normalized(baseURL) else { return host ?? baseURL.absoluteString }
        return presets.first { URL(string: $0.baseURL).flatMap(normalized) == address }?.name
            ?? host ?? baseURL.absoluteString
    }

    /// Android compares addresses without trailing slashes; host letter case
    /// and an explicit default port do not make a different address either.
    private static func normalized(_ url: URL) -> String? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), let host = parts.host?.lowercased() else { return nil }
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        let port = parts.port.map { scheme == "https" && $0 == 443 ? "" : ":\($0)" } ?? ""
        return scheme + "://" + host + port + path
    }
}
