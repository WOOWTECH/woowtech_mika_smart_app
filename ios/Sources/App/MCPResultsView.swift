import SwiftUI
import AssistantMCP

/// What this conversation's MCP calls returned, in order. Like the Play build,
/// selected tools run without a per-call approval; this list is where a person
/// sees each call and its result.
struct MCPResultsView: View {
    @Environment(\.appLocalizer) private var localizer
    let steps: [MCPConversationStep]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(Array(steps.enumerated()), id: \.offset) { index, step in
                VStack(alignment: .leading, spacing: 8) {
                    if case .callTool(let name, _) = step.proposal.action { Text(verbatim: name).font(.headline) }
                    if case .readResource = step.proposal.action { Text(localizer.text(.mcpReadResource)).font(.headline) }
                    Text(step.isError ? localizer.text(.mcpToolError) : localizer.text(.mcpToolResult))
                    Text(verbatim: resultText(step.result))
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .privacySensitive().accessibilityIdentifier("mcp.result.\(index)")
                }
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
    private func resultText(_ value: JSONValue) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? localizer.text(.mcpResultUnavailable)
    }
}
