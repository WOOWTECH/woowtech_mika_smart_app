import SwiftUI

/// Settings › MCP 伺服器, like Android's McpServersScreen: the saved servers
/// with their status, add, test all, and one server's page with its endpoint,
/// token, tool choice, test and delete. The pages change in place, so the
/// section's own back control stays on screen.
@MainActor
struct MCPToolsView: View {
    @Environment(\.appLocalizer) private var localizer
    @ObservedObject var servers: MCPServers
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var page = Page.list

    enum Page: Equatable { case list, add, server(UUID) }

    init(servers: MCPServers) { self.servers = servers }

    var body: some View {
        Group {
            switch page {
            case .list: list
            case .add:
                MCPServerAddForm(servers: servers, back: { page = .list }, opened: { page = .server($0) })
            case .server(let id):
                if let server = servers.server(id: id) {
                    MCPServerDetail(servers: servers, record: server.record, session: server.session, back: { page = .list })
                        .id(id)
                } else {
                    list.onAppear { page = .list }
                }
            }
        }
        .tint(MCPPageStyle.accent(colorScheme))
        .background(MCPPageStyle.background(colorScheme))
        // Leaving the page or the app clears what was typed. The connections
        // themselves are the app's (ContentView): like the Play build they stay
        // set up, and a connection that started here may finish for a chat.
        .onDisappear { servers.clearDrafts() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { servers.clearDrafts() }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            MCPPageHeader(status: servers.servers.isEmpty ? .mcpNotConfigured : .mcpServersStatus(count: servers.servers.count),
                          detail: servers.servers.isEmpty ? .mcpNotStored : .mcpServersStored,
                          symbol: "link", tint: MCPPageStyle.accent(colorScheme))
            List {
                Section(localizer.text(.mcpServersSection)) {
                    if servers.servers.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(localizer.text(.mcpServersEmpty)).font(.subheadline.weight(.semibold))
                            Text(localizer.text(.mcpServersEmptyDetail)).font(.footnote).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("mcp.servers.empty")
                    }
                    ForEach(Array(servers.servers.enumerated()), id: \.element.id) { index, server in
                        Button { page = .server(server.id) } label: {
                            MCPServerRow(record: server.record, session: server.session)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("mcp.server.\(index)")
                    }
                    Button(localizer.text(.mcpAddServer)) { servers.clearDrafts(); page = .add }
                        .disabled(servers.servers.count >= MCPServerDirectory.maximumServers)
                        .accessibilityIdentifier("mcp.addServer")
                    Button(localizer.text(.mcpTestAll)) { servers.testAll() }
                        .disabled(!servers.canTestAll)
                        .accessibilityIdentifier("mcp.testAll")
                }
                Section {
                    Text(localizer.text(.mcpExplanation))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("tools.explanation")
                    if !servers.allowsNetwork {
                        Text(localizer.text(.mcpIsolation))
                            .accessibilityIdentifier("mcp.testIsolation")
                    }
                    if let error = servers.errorText {
                        Text(localizer.text(error)).foregroundStyle(.red).accessibilityIdentifier("mcp.error")
                    }
                    if let notice = servers.noticeText {
                        Text(localizer.text(notice)).font(.footnote).accessibilityIdentifier("mcp.notice")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
    }
}

/// One server in the list: its name and, like Android, 可用 · N 個工具 or why not.
private struct MCPServerRow: View {
    @Environment(\.appLocalizer) private var localizer
    @Environment(\.colorScheme) private var colorScheme
    let record: MCPServerRecord
    @ObservedObject var session: MCPSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .font(.system(size: 16))
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.04), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: record.name.isEmpty ? localizer.text(.mcpServerDefaultName) : record.name)
                Text(localizer.text(status)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary).accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    private var status: AppText {
        guard record.enabled else { return .mcpServerDisabled }
        switch session.phase {
        case .connected: return .mcpServerStatusOK(count: session.toolNames.count)
        case .failed: return .mcpServerStatusFailed
        default: return session.statusMessage
        }
    }
}

/// A new server: name, endpoint and optional token. Saving sends no request.
private struct MCPServerAddForm: View {
    @Environment(\.appLocalizer) private var localizer
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var servers: MCPServers
    let back: () -> Void
    let opened: (UUID) -> Void
    @FocusState private var focused: Field?
    enum Field { case name, endpoint, token }

    var body: some View {
        VStack(spacing: 0) {
            MCPPageHeader(status: .mcpAddSection, detail: .mcpNotStored, symbol: "plus", tint: MCPPageStyle.accent(colorScheme),
                          back: back)
            List {
                Section(localizer.text(.mcpAddSection)) {
                    TextField(localizer.text(.mcpServerName), text: $servers.nameDraft)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focused = .endpoint }
                        .accessibilityIdentifier("mcp.add.name")
                    SecureField(localizer.text(.mcpEndpoint), text: $servers.endpointDraft)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                        .focused($focused, equals: .endpoint)
                        .submitLabel(.done)
                        .onSubmit { focused = nil }
                        .accessibilityLabel(localizer.text(.mcpEndpointAX))
                        .accessibilityIdentifier("mcp.add.endpoint")
                    Text(localizer.text(.mcpEndpointHelp))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    SecureField(localizer.text(.mcpToken), text: $servers.tokenDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                        .focused($focused, equals: .token)
                        .submitLabel(.done)
                        .onSubmit { focused = nil }
                        .accessibilityLabel(localizer.text(.mcpTokenAX))
                        .accessibilityIdentifier("mcp.add.token")
                    HStack(spacing: 12) {
                        Button(localizer.text(.mcpSave)) {
                            focused = nil
                            if let id = servers.add() { opened(id) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!servers.canAdd)
                        .accessibilityIdentifier("mcp.add.save")
                        Button(localizer.text(.mcpClearDraft)) { servers.clearDrafts() }
                            .buttonStyle(.bordered)
                            .disabled(servers.nameDraft.isEmpty && servers.endpointDraft.isEmpty && servers.tokenDraft.isEmpty)
                            .accessibilityIdentifier("mcp.add.clearDraft")
                    }
                    if let error = servers.errorText {
                        Text(localizer.text(error)).foregroundStyle(.red).accessibilityIdentifier("mcp.error")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(localizer.text(.keyboardDone)) { focused = nil }
                    .accessibilityIdentifier("mcp.dismissKeyboard")
            }
        }
    }
}

/// One server: name, whether chats use it, endpoint and token, its test
/// (connect and discover), its tools, and delete.
private struct MCPServerDetail: View {
    @Environment(\.appLocalizer) private var localizer
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var servers: MCPServers
    let record: MCPServerRecord
    @ObservedObject var session: MCPSession
    let back: () -> Void
    @State private var nameDraft = ""
    @State private var confirmDelete = false
    @FocusState private var focused: Field?
    enum Field { case name, endpoint, token, search }

    private var current: MCPServerRecord { servers.server(id: record.id)?.record ?? record }
    private var nameChanged: Bool {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && name != current.name
    }

    var body: some View {
        VStack(spacing: 0) {
            MCPPageHeader(status: session.statusMessage,
                          detail: session.hasStoredEndpoint ? .mcpStored : .mcpNotStored,
                          symbol: statusSymbol, tint: statusTint, back: back,
                          name: current.name.isEmpty ? localizer.text(.mcpServerDefaultName) : current.name)
            List {
                Section(localizer.text(.mcpConnectionSection)) {
                    TextField(localizer.text(.mcpServerName), text: $nameDraft)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .name)
                        .submitLabel(.done)
                        .onSubmit { focused = nil }
                        .disabled(session.isBusy)
                        .accessibilityIdentifier("mcp.serverName")
                    Toggle(localizer.text(.mcpServerEnabled), isOn: Binding(
                        get: { current.enabled }, set: { servers.setEnabled(id: record.id, $0) }))
                        .disabled(session.isBusy)
                        .accessibilityIdentifier("mcp.serverEnabled")
                    if !session.allowsNetwork {
                        Text(localizer.text(.mcpIsolation))
                            .accessibilityIdentifier("mcp.testIsolation")
                    }
                    SecureField(localizer.text(.mcpEndpoint), text: $session.endpointDraft)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                        .focused($focused, equals: .endpoint)
                        .submitLabel(.done)
                        .onSubmit { focused = nil }
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
                        .focused($focused, equals: .token)
                        .submitLabel(.done)
                        .onSubmit { focused = nil }
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
                            focused = nil
                            if nameChanged, servers.rename(id: record.id, to: nameDraft) { nameDraft = current.name }
                            if session.canSave { session.saveEndpoint() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(session.isBusy || !(nameChanged || session.canSave))
                        .accessibilityIdentifier("mcp.save")
                        Button(localizer.text(.mcpClearDraft)) {
                            session.endpointDraft = ""; session.tokenDraft = ""; nameDraft = current.name
                        }
                        .buttonStyle(.bordered)
                        .disabled((session.endpointDraft.isEmpty && session.tokenDraft.isEmpty && !nameChanged) || session.isBusy)
                        .accessibilityIdentifier("mcp.clearDraft")
                    }
                    if let error = servers.errorText {
                        Text(localizer.text(error)).foregroundStyle(.red).accessibilityIdentifier("mcp.serverError")
                    }
                    Button(localizer.text(.mcpDeleteServer), role: .destructive) { confirmDelete = true }
                        .disabled(session.isBusy)
                        .accessibilityIdentifier("mcp.deleteServer")
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
                            focused = nil
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
                            .focused($focused, equals: .search).submitLabel(.done)
                            .onSubmit { focused = nil }
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(localizer.text(.keyboardDone)) { focused = nil }
                    .accessibilityIdentifier("mcp.dismissKeyboard")
            }
        }
        .confirmationDialog(localizer.text(.mcpDeleteServerQuestion), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(localizer.text(.mcpDeleteServerConfirm), role: .destructive) {
                servers.delete(id: record.id)
                back()
            }
            .accessibilityIdentifier("mcp.confirmDeleteServer")
        }
        .onAppear { nameDraft = current.name }
        .onDisappear {
            session.endpointDraft = ""
            session.tokenDraft = ""
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
        case .notConfigured, .saved, .connecting, .discovering, .disconnected, .cancelled, .suspended:
            return MCPPageStyle.accent(colorScheme)
        }
    }
}

/// The page title and its status card. Kept outside the List so a long tool
/// catalog cannot virtualize it away.
private struct MCPPageHeader: View {
    @Environment(\.appLocalizer) private var localizer
    @Environment(\.colorScheme) private var colorScheme
    let status: AppText
    let detail: AppText
    let symbol: String
    let tint: Color
    var back: (() -> Void)?
    var name: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let back {
                Button(action: back) {
                    Label(localizer.text(.mcpBackToServers), systemImage: "chevron.backward")
                        .font(.callout)
                }
                .accessibilityIdentifier("mcp.backToServers")
            }
            Text(localizer.text(.mcpTitle))
                .font(.title2.bold())
                .accessibilityIdentifier("tools.status")
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    if let name {
                        Text(verbatim: name)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("mcp.serverTitle")
                    }
                    Text(localizer.text(status))
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("mcp.status")
                    Text(localizer.text(detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("mcp.endpointStatus")
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MCPPageStyle.card(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
            .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.04), radius: 6, y: 2)
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

/// The reference page's colors.
private enum MCPPageStyle {
    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 97.0 / 255, green: 131.0 / 255, blue: 252.0 / 255)
            : Color(red: 64.0 / 255, green: 105.0 / 255, blue: 251.0 / 255)
    }

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 14.0 / 255, green: 14.0 / 255, blue: 16.0 / 255)
            : Color(red: 247.0 / 255, green: 247.0 / 255, blue: 248.0 / 255)
    }

    static func card(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 26.0 / 255, green: 26.0 / 255, blue: 29.0 / 255) : .white
    }
}
