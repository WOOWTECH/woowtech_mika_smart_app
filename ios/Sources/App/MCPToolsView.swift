import SwiftUI

@MainActor
struct MCPToolsView: View {
    @Environment(\.appLocalizer) private var localizer
    @StateObject private var session: MCPSession
    @FocusState private var isEditingEndpoint: Bool
    @FocusState private var isEditingToken: Bool
    @FocusState private var isSearchingTools: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var confirmRemoval = false

    init() { _session = StateObject(wrappedValue: MCPSession()) }
    init(session: MCPSession) { _session = StateObject(wrappedValue: session) }

    var body: some View {
        VStack(spacing: 0) {
            // Match the reference page's state-first hierarchy. Keep the status
            // outside List so a long tool catalog cannot virtualize it away.
            VStack(alignment: .leading, spacing: 12) {
                Text(localizer.text(.mcpTitle))
                    .font(.title2.bold())
                    .accessibilityIdentifier("tools.status")
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: statusSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(statusTint)
                        .frame(width: 32, height: 32)
                        .background(statusTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(localizer.text(session.statusMessage))
                            .font(.subheadline.weight(.semibold))
                            .accessibilityIdentifier("mcp.status")
                        Text(session.hasStoredEndpoint ? localizer.text(.mcpStored) : localizer.text(.mcpNotStored))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("mcp.endpointStatus")
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
                .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.04), radius: 6, y: 2)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 4)
            List {
                Section(localizer.text(.mcpConnectionSection)) {
                    Text(localizer.text(.mcpExplanation))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("tools.explanation")
                    if !session.allowsNetwork {
                        Text(localizer.text(.mcpIsolation))
                            .accessibilityIdentifier("mcp.testIsolation")
                    }
                    SecureField(localizer.text(.mcpEndpoint), text: $session.endpointDraft)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                        .focused($isEditingEndpoint)
                        .submitLabel(.done)
                        .onSubmit { isEditingEndpoint = false }
                        .disabled(session.isBusy)
                        .accessibilityLabel(localizer.text(.mcpEndpointAX))
                        .accessibilityIdentifier("mcp.endpoint")
                    Text(localizer.text(.mcpEndpointHelp))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    // Like the Play build's optional access token (Bearer header).
                    SecureField(localizer.text(.mcpToken), text: $session.tokenDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                        .focused($isEditingToken)
                        .submitLabel(.done)
                        .onSubmit { isEditingToken = false }
                        .disabled(session.isBusy)
                        .accessibilityLabel(localizer.text(.mcpTokenAX))
                        .accessibilityIdentifier("mcp.token")
                    if session.hasStoredToken {
                        Text(localizer.text(.mcpTokenStored))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("mcp.tokenStatus")
                    }
                    HStack(spacing: 12) {
                        Button(localizer.text(.mcpSave)) {
                            isEditingEndpoint = false
                            isEditingToken = false
                            session.saveEndpoint()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!session.canSave)
                        .accessibilityIdentifier("mcp.save")
                        Button(localizer.text(.mcpClearDraft)) { session.endpointDraft = ""; session.tokenDraft = "" }
                            .buttonStyle(.bordered)
                            .disabled((session.endpointDraft.isEmpty && session.tokenDraft.isEmpty) || session.isBusy)
                            .accessibilityIdentifier("mcp.clearDraft")
                    }
                    if session.hasStoredEndpoint {
                        Button(localizer.text(.mcpRemoveStored), role: .destructive) { confirmRemoval = true }
                            .disabled(session.isBusy)
                            .accessibilityIdentifier("mcp.remove")
                    }
                }

                Section(localizer.text(.mcpExploration)) {
                    Text(localizer.text(.mcpProtocol(version: session.protocolVersion ?? localizer.text(.commonUnknown))))
                        .accessibilityIdentifier("mcp.protocol")
                    if session.phase == .connected {
                        Text(session.supportsTools ? localizer.text(.mcpToolCount(count: session.toolNames.count)) : localizer.text(.mcpNoTools))
                            .accessibilityIdentifier("mcp.toolCount")
                    }
                    if session.isBusy {
                        ProgressView(localizer.text(session.statusMessage))
                        Button(localizer.text(.mcpCancel)) { session.cancel() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("mcp.cancel")
                    } else {
                        Button(localizer.text(.mcpConnect)) {
                            isEditingEndpoint = false
                            isEditingToken = false
                            session.connect()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!session.canConnect)
                        .accessibilityIdentifier("mcp.connect")
                    }
                    if session.phase == .connected {
                        Button(localizer.text(.mcpDisconnect)) { session.disconnect() }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("mcp.disconnect")
                    }
                    if let error = session.errorText {
                        Text(localizer.text(error))
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("mcp.error")
                    }
                    if let notice = session.noticeText {
                        Text(localizer.text(notice))
                            .font(.footnote)
                            .accessibilityIdentifier("mcp.notice")
                    }
                }

                if session.phase == .connected {
                    Section(localizer.text(.mcpServerTools)) {
                        Text(localizer.text(.mcpSelectedCount(count: session.selectedToolNames.count)))
                            .accessibilityIdentifier("mcp.selectionCount")
                        TextField(localizer.text(.mcpSearchTools), text: $session.toolSearch)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .focused($isSearchingTools).submitLabel(.done)
                            .onSubmit { isSearchingTools = false }
                            .accessibilityIdentifier("mcp.toolSearch")
                        ForEach(session.visibleTools, id: \.name) { tool in
                            Toggle(isOn: Binding(get: { session.selectedToolNames.contains(tool.name) },
                                                 set: { session.selectTool(tool.name, enabled: $0) })) {
                                HStack(spacing: 12) {
                                    Image(systemName: "wrench.and.screwdriver")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.primary)
                                        .frame(width: 30, height: 30)
                                        .background(Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.04),
                                                    in: RoundedRectangle(cornerRadius: 9))
                                        .accessibilityHidden(true)
                                    Text(verbatim: tool.name).privacySensitive()
                                }
                            }
                            .accessibilityIdentifier("mcp.enable.\(tool.name)")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .tint(brandAccent)
        .background(pageBackground)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(localizer.text(.keyboardDone)) { isEditingEndpoint = false; isEditingToken = false; isSearchingTools = false }
                    .accessibilityIdentifier("mcp.dismissKeyboard")
            }
        }
        .confirmationDialog(localizer.text(.mcpRemoveQuestion), isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button(localizer.text(.mcpRemove), role: .destructive) { session.removeEndpoint() }
                .accessibilityIdentifier("mcp.confirmRemove")
        }
        // Leaving the page or the app clears what was typed. The connection
        // itself is the app's (ContentView): like the Play build it stays set
        // up, and a connection that started here may finish for a chat.
        .onDisappear {
            session.endpointDraft = ""
            session.tokenDraft = ""
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                session.endpointDraft = ""
                session.tokenDraft = ""
            }
        }
    }

    private var statusSymbol: String {
        switch session.phase {
        case .connected: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .connecting, .discovering: return "arrow.triangle.2.circlepath"
        case .notConfigured, .saved, .disconnected, .cancelled, .suspended: return "link"
        }
    }

    private var statusTint: Color {
        switch session.phase {
        case .connected: return .green
        case .failed: return .red
        case .notConfigured, .saved, .connecting, .discovering, .disconnected, .cancelled, .suspended: return brandAccent
        }
    }

    private var brandAccent: Color {
        colorScheme == .dark
            ? Color(red: 97.0 / 255, green: 131.0 / 255, blue: 252.0 / 255)
            : Color(red: 64.0 / 255, green: 105.0 / 255, blue: 251.0 / 255)
    }

    private var pageBackground: Color {
        colorScheme == .dark
            ? Color(red: 14.0 / 255, green: 14.0 / 255, blue: 16.0 / 255)
            : Color(red: 247.0 / 255, green: 247.0 / 255, blue: 248.0 / 255)
    }

    private var cardBackground: Color {
        colorScheme == .dark
            ? Color(red: 26.0 / 255, green: 26.0 / 255, blue: 29.0 / 255)
            : .white
    }
}
