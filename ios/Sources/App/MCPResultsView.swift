import SwiftUI
import AssistantMCP

/// This submission's MCP result records, including local failures. Like the Play build,
/// selected tools run without a per-call approval; this list is where a person
/// sees each call record and its selected server.
struct MCPResultsView: View {
    @Environment(\.appLocalizer) private var localizer
    let steps: [MCPConversationStep]
    var owners: [UUID: MCPStepOwner] = [:]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(Array(steps.enumerated()), id: \.offset) { index, step in
                VStack(alignment: .leading, spacing: 8) {
                    if let owner = owners[step.proposal.id] {
                        Text(verbatim: owner.server.isEmpty ? localizer.text(.mcpServerDefaultName) : owner.server)
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("mcp.result.\(index).server")
                    }
                    if case .callTool(let name, _) = step.proposal.action {
                        Text(verbatim: owners[step.proposal.id]?.target ?? name).font(.headline)
                    }
                    if case .readResource = step.proposal.action { Text(localizer.text(.mcpReadResource)).font(.headline) }
                    Text(localizer.text(categoryText(step.diagnostic)))
                        .accessibilityIdentifier("mcp.result.\(index).category")
                    if step.diagnostic?.outcomeUnknown == true {
                        Text(localizer.text(.mcpDiagnosticOutcomeUnknown))
                            .font(.caption)
                            .accessibilityIdentifier("mcp.result.\(index).unknownOutcome")
                    }
                    Text(verbatim: resultText(step.result))
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .privacySensitive().accessibilityIdentifier("mcp.result.\(index)")
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(localizer.text(.mcpResultsTransient))
                    .font(.footnote).foregroundStyle(.secondary).padding()
                    .frame(maxWidth: .infinity).background(.regularMaterial)
                    .accessibilityIdentifier("mcp.results.transient")
            }
            .navigationTitle(localizer.text(.mcpResultsTitle))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localizer.text(.commonClose)) { dismiss() }
                        .accessibilityIdentifier("mcp.results.close")
                }
            }
        }
    }
    private func categoryText(_ diagnostic: MCPExecutionDiagnostic?) -> AppText {
        guard let diagnostic else { return .mcpDiagnosticUnclassified }
        switch diagnostic.category {
        case .result: return .mcpToolResult
        case .toolError: return .mcpToolError
        case .http:
            guard let code = diagnostic.code else { return .mcpDiagnosticUnclassified }
            return .mcpDiagnosticHTTP(code: code)
        case .rpc:
            guard let code = diagnostic.code else { return .mcpDiagnosticUnclassified }
            return .mcpDiagnosticRPC(code: code)
        case .timeout: return .mcpDiagnosticTimeout
        case .cancelled: return .mcpDiagnosticCancelled
        case .transport: return .mcpDiagnosticTransport
        case .protocolFailure: return .mcpDiagnosticProtocol
        case .other: return .mcpDiagnosticOther
        }
    }
    private func resultText(_ value: JSONValue) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? localizer.text(.mcpResultUnavailable)
    }
}
