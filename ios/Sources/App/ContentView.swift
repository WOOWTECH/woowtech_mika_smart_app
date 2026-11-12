import SwiftUI
import UIKit
import AssistantSkills
import AssistantPersistence

@MainActor
struct ContentView: View {
    @State private var selection: AppSection = .chat
    @State private var browserReturnSection: AppSection = .chat
    @State private var showsDrawer = false
    @State private var showsArchive = false
    @State private var showsNewConversationConfirmation = false
    @State private var pendingNewConversationProtection: NewConversationProtection?
    @AccessibilityFocusState private var menuHasVoiceOverFocus: Bool
    @AccessibilityFocusState private var backHasVoiceOverFocus: Bool
    @State private var notificationNavigationID = UUID()
    @StateObject private var session = ChatSession()
    @StateObject private var mcpSession = MCPSession()
    @StateObject private var browserWorkspace = BrowserWorkspace()
    @StateObject private var preferences = SelfConfigurationStore.applicationPreferences()
    @StateObject private var languages = AppLanguageStore.applicationPreferences()
    @StateObject private var notifications = TaskNotificationStore.applicationStore()
    private var browser: BrowserSession { browserWorkspace.selected }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    private var palette: MikaVisualPalette { MikaVisualPalette(colorScheme) }
    private var localizer: AppLocalizer { AppLocalizer(language: languages.resolved) }

    var body: some View {
        shell
        .animation(.easeOut(duration: 0.22), value: showsDrawer)
        .sheet(isPresented: $showsArchive) {
            if let store = session.archive { ConversationArchiveView(store: store, session: session) }
        }
        .alert(localizer.text(.newConversationConfirmTitle), isPresented: $showsNewConversationConfirmation) {
            Button(localizer.text(.newConversationDiscard), role: .destructive) {
                let approved = pendingNewConversationProtection
                pendingNewConversationProtection = nil
                guard let approved, NewConversationAction.start(in: session, approved: approved) else { return }
                selection = .chat
                closeDrawer()
            }
            Button(localizer.text(.newConversationKeep), role: .cancel) {
                pendingNewConversationProtection = nil
            }
        } message: {
            Text(pendingNewConversationProtection?.warningKeys.map { localizer.text($0) }.joined(separator: "\n") ?? "")
        }
        .tint(palette.accent)
        .background(palette.background)
        #if DEBUG
        .environment(\.notificationRouteObservation,
                     MCPApprovalView.exposesFixtureIdentity(arguments: ProcessInfo.processInfo.arguments)
                     ? "generation=\(notificationNavigationID.uuidString);destination=\(selection.rawValue)" : "")
        #endif
        .environmentObject(preferences)
        .appLanguage(languages)
        .preferredColorScheme(preferences.preferredColorScheme)
        .taskNotifications(chat: session, store: notifications) { destination in
            showsDrawer = false
            browserReturnSection = .chat
            switch destination {
            case .chat: selection = .chat
            case .browser: selection = .browser
            }
            // Destination-style links are not all represented in NavigationPath.
            // Pop pushed details when the user opens a notification, retaining
            // the root-owned sessions and stores above.
            notificationNavigationID = UUID()
        }
        .onAppear {
            session.learning.onUserChange = { [weak browserWorkspace, weak session] in
                browserWorkspace?.cancelAllWork(preservingFrozenReferences: session?.learning.referenceEditInProgress == true)
                session?.invalidateProfileReview()
            }
            mcpSession.onConnectionChange = { [weak session] in session?.cancelMCP() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { session.pdfEnteredBackground() }
            if phase != .active {
                session.cancelMCP()
                session.invalidateProfileReview()
                browserWorkspace.cancelAllWork()
                if mcpSession.phase == .connected || mcpSession.isBusy { mcpSession.disconnect() }
            }
        }
        .onChange(of: selection) { _, destination in
            if destination == .chat { menuHasVoiceOverFocus = true }
            else { backHasVoiceOverFocus = true }
        }
    }

    private var shell: some View {
        ZStack(alignment: .leading) {
          NavigationStack {
            sectionContent
            .navigationTitle(selection == .chat ? localizer.text(.shellBrandTitle) : selection.title(using: localizer))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar { rootToolbar }
            .safeAreaInset(edge: .bottom, spacing: 0) { fixtureObservation }
          }
          .id(notificationNavigationID)
          .accessibilityHidden(showsDrawer)
          if showsDrawer {
              GeometryReader { geometry in
                  ZStack(alignment: .leading) {
                      Button { closeDrawer() } label: {
                          palette.scrim.ignoresSafeArea()
                      }
                      .buttonStyle(.plain)
                      .accessibilityHidden(true)
                      MikaNavigationDrawer(
                          status: localizer.text(session.chatStatusMessage),
                          session: session,
                          canStartNew: !session.isSubmitting,
                          canOpenArchive: session.archive != nil && !session.isSubmitting,
                          palette: palette,
                          localizer: localizer,
                          topInset: geometry.safeAreaInsets.top,
                          bottomInset: geometry.safeAreaInsets.bottom,
                          onClose: closeDrawer,
                          onNew: requestNewConversation,
                          onArchive: { showsDrawer = false; showsArchive = true },
                          onOpenRecent: { record in
                              if RecentConversationAccess.isCurrent(record, in: session) {
                                  closeDrawer()
                              } else if RecentConversationAccess.open(record, in: session) {
                                  browserReturnSection = .chat
                                  selection = .chat
                                  closeDrawer()
                              }
                          },
                          onSelect: { section in
                              if section == .chat { closeDrawer() }
                              else {
                                  browserReturnSection = .chat
                                  selection = section
                                  showsDrawer = false
                              }
                          }
                      )
                      .frame(width: min(304, max(0, geometry.size.width - 48)),
                             height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom)
                      .offset(y: -geometry.safeAreaInsets.top)
                      .transition(.move(edge: .leading))
                  }
                  .frame(width: geometry.size.width, height: geometry.size.height, alignment: .leading)
              }
          }
        }
    }

    @ToolbarContentBuilder private var rootToolbar: some ToolbarContent {
                ToolbarItem(placement: .topBarLeading) {
                    if selection == .chat {
                        Button { showsDrawer = true } label: {
                            Image(systemName: "line.3.horizontal")
                                .frame(width: 40, height: 40)
                        }
                        .accessibilityLabel(localizer.text(.shellMenu))
                        .accessibilityIdentifier("chat.menu")
                        .accessibilityFocused($menuHasVoiceOverFocus)
                    } else {
                        Button {
                            let destination = selection == .browser ? browserReturnSection : .chat
                            browserReturnSection = .chat
                            selection = destination
                        } label: {
                            Image(systemName: "chevron.backward")
                                .frame(width: 40, height: 40)
                        }
                        .accessibilityLabel(localizer.text(selection == .browser && browserReturnSection == .memory
                                                           ? .shellBackToMemory : .shellBackToChat))
                        .accessibilityIdentifier("section.back")
                        .accessibilityFocused($backHasVoiceOverFocus)
                    }
                }
                if selection == .chat {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 1) {
                            Text(localizer.text(.shellBrandTitle))
                                .font(.system(size: 17, weight: .semibold))
                                .lineLimit(1)
                            Text(verbatim: localizer.text(session.chatStatusMessage))
                                .font(.system(size: 12))
                                .foregroundStyle(palette.secondaryInk)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .accessibilityIdentifier("chat.status")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: requestNewConversation) {
                            Image(systemName: "square.and.pencil")
                                .frame(width: 40, height: 40)
                        }
                        .disabled(session.isSubmitting)
                        .accessibilityLabel(localizer.text(.shellNewConversation))
                        .accessibilityIdentifier("chat.newConversation")
                    }
                }
    }

    private var sectionContent: some View {
            Group {
                switch selection {
                case .chat:
                    ChatView(session: session, mcp: mcpSession, showsDrawer: $showsDrawer, localizer: localizer)
                        .frame(maxWidth: 720)
                        .frame(maxWidth: .infinity)
                case .settings:
                    MikaAlignedSettingsView(session: session, preferences: preferences, notifications: notifications,
                                            languages: languages,
                                            mcpDestination: { MCPToolsView(session: mcpSession) },
                                            memoryDestination: { memoryDataView(resetNavigation: true) })
                case .about:
                    MikaAboutView(languages: languages, info: MikaAboutInfo(bundle: .main))
                case .tools:
                    MCPToolsView(session: mcpSession)
                case .memory:
                    memoryDataView(resetNavigation: false)
                case .browser:
                    BrowserView(browser: browser, chat: session, workspace: browserWorkspace)
                }
            }
    }

    private func closeDrawer() {
        showsDrawer = false
        if selection == .chat { menuHasVoiceOverFocus = true }
    }

    private func memoryDataView(resetNavigation: Bool) -> some View {
        MemoryDataView(store: session.learning, browser: browser, modelAccess: session.modelAccess,
                       modelChanges: session.$savedSettings.dropFirst().map { _ in () }.eraseToAnyPublisher(),
                       onOpenBrowser: {
                           browserReturnSection = .memory
                           selection = .browser
                           if resetNavigation { notificationNavigationID = UUID() }
                       })
    }

    private func requestNewConversation() {
        guard !session.isSubmitting else { return }
        if let protection = NewConversationProtection.current(in: session) {
            pendingNewConversationProtection = protection
            showsNewConversationConfirmation = true
        } else if NewConversationAction.start(in: session, approved: nil) {
            selection = .chat
            closeDrawer()
        }
    }

    @ViewBuilder private var fixtureObservation: some View {
        #if DEBUG
        VStack(spacing: 0) {
            if (try? ChatPDFUITestConfiguration.resolve(arguments: ProcessInfo.processInfo.arguments)) != nil {
                Text("PDF 模型請求事件測試觀測").font(.caption2)
                    .accessibilityIdentifier("chat.pdf.requestEvents")
                    .accessibilityValue(String(session.pdfModelRequestEvents))
            }
            if (try? UITestChatStreamingConfiguration.resolve(arguments: ProcessInfo.processInfo.arguments)) != nil {
                Text("串流通知送出測試觀測")
                    .font(.caption2)
                    .accessibilityIdentifier("stream.fixture.notifications")
                    .accessibilityValue(String(notifications.streamingFixtureCompletedAddAttempts))
            }
            if MCPApprovalView.exposesFixtureIdentity(arguments: ProcessInfo.processInfo.arguments) {
                // Observe the existing route identity only. No test can mutate
                // it or invoke the notification-open callback through this Text.
                Text("通知導頁測試觀測")
                    .font(.caption2)
                    .accessibilityIdentifier("notifications.routeObservation")
                    .accessibilityValue("generation=\(notificationNavigationID.uuidString);destination=\(selection.rawValue)")
            }
        }
        #endif
    }
}

/// WOOWTECH Android brand.properties and ui/theme/Colors.kt at de5be358.
/// Keep these visual tokens local to the shell; model and browser policy are unchanged.
private struct MikaVisualPalette {
    private let dark: Bool
    init(_ scheme: ColorScheme) { dark = scheme == .dark }
    private func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(red: red / 255, green: green / 255, blue: blue / 255)
    }

    var background: Color { dark ? rgb(14, 14, 16) : rgb(247, 247, 248) }
    var surface: Color { dark ? rgb(26, 26, 29) : .white }
    var ink: Color { dark ? rgb(242, 242, 244) : rgb(28, 28, 30) }
    var secondaryInk: Color { dark ? rgb(164, 165, 173) : rgb(95, 96, 104) }
    var accent: Color { dark ? rgb(97, 131, 252) : rgb(64, 105, 251) }
    var assistant: Color { dark ? .white.opacity(13.0 / 255) : .black.opacity(9.0 / 255) }
    var glass: Color { dark ? surface.opacity(184.0 / 255) : .white.opacity(184.0 / 255) }
    var hair: Color { dark ? .white.opacity(20.0 / 255) : .black.opacity(18.0 / 255) }
    var scrim: Color { .black.opacity(0.32) }
}

/// Selected routes match the existing iOS feature set; phone, Plans and remote
/// desktop control entries from Android are deliberately absent.
@MainActor
private struct MikaNavigationDrawer: View {
    let status: String
    @ObservedObject var session: ChatSession
    let canStartNew: Bool
    let canOpenArchive: Bool
    let palette: MikaVisualPalette
    let localizer: AppLocalizer
    let topInset: CGFloat
    let bottomInset: CGFloat
    let onClose: () -> Void
    let onNew: () -> Void
    let onArchive: () -> Void
    let onOpenRecent: (ArchivedConversation) -> Void
    let onSelect: (AppSection) -> Void
    @AccessibilityFocusState private var closeHasVoiceOverFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(localizer.text(.shellBrandTitle)).font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Text(status).font(.system(size: 12)).foregroundStyle(palette.secondaryInk)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark").frame(width: 44, height: 44)
                }
                .accessibilityLabel(localizer.text(.shellCloseMenu))
                .accessibilityIdentifier("drawer.close")
                .accessibilityFocused($closeHasVoiceOverFocus)
            }
            .padding(.leading, 20).padding(.trailing, 8).padding(.top, 14).padding(.bottom, 10)
            ScrollView {
                VStack(spacing: 0) {
                    row(localizer.text(.shellNewConversation), symbol: "square.and.pencil", id: "drawer.newConversation", enabled: canStartNew, action: onNew)
                    row(localizer.text(.shellChatHistory), symbol: "clock.arrow.circlepath", id: "drawer.archive", enabled: canOpenArchive, action: onArchive)
                    row(localizer.text(.shellChat), symbol: "message", id: "navigation.chat") { onSelect(.chat) }
                    row(localizer.text(.shellMemoryAndSkills), symbol: "heart", id: "navigation.memory") { onSelect(.memory) }
                    row(localizer.text(.shellMCPServers), symbol: "link", id: "navigation.tools") { onSelect(.tools) }
                    row(localizer.text(.shellBrowser), symbol: "globe", id: "navigation.browser") { onSelect(.browser) }
                    if let store = session.archive {
                        MikaRecentConversationsSection(store: store, session: session,
                            localizer: localizer, ink: palette.ink,
                            secondaryInk: palette.secondaryInk, hair: palette.hair,
                            onOpen: onOpenRecent)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
            .accessibilityIdentifier("drawer.scroll")
            Divider().overlay(palette.hair)
            row(localizer.text(.shellSettings), symbol: "gearshape", id: "navigation.settings") { onSelect(.settings) }
                .padding(.horizontal, 12).padding(.vertical, 6)
            row(MikaAboutCopy(language: localizer.language).text(.title), symbol: "info.circle", id: "navigation.about") { onSelect(.about) }
                .padding(.horizontal, 12).padding(.bottom, 6)
        }
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
        .frame(maxHeight: .infinity)
        .background(palette.background)
        .clipShape(MikaDrawerShape())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawer.panel")
        .onAppear { closeHasVoiceOverFocus = true }
    }

    private func row(_ title: String, symbol: String, id: String, enabled: Bool = true,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 22))
                    .frame(width: 22).foregroundStyle(palette.secondaryInk)
                Text(title).font(.system(size: 15.5)).foregroundStyle(palette.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(id)
    }
}

private struct MikaDrawerShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(24.0, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private enum AppSection: String, CaseIterable, Identifiable, Equatable {
    case chat
    case browser
    case tools
    case memory
    case settings
    case about

    var id: String { rawValue }

    func title(using localizer: AppLocalizer) -> String {
        switch self {
        case .chat: return localizer.text(.shellChat)
        case .browser: return localizer.text(.shellBrowser)
        case .tools: return localizer.text(.shellToolsTitle)
        case .memory: return localizer.text(.shellMemoryTitle)
        case .settings: return localizer.text(.shellSettings)
        case .about: return MikaAboutCopy(language: localizer.language).text(.title)
        }
    }

    var explanation: String {
        switch self {
        case .chat:
            return "請先到設定填寫模型服務與 API Key。"
        case .browser:
            return "此版本尚未載入網頁，也未進行網站連線驗證。分頁、登入、上傳、下載與頁面操作仍待實作。"
        case .tools:
            return "此版本尚未載入或執行 Skills，也未連接 MCP 伺服器；目前沒有可呼叫的工具。"
        case .memory:
            return "記憶、個人技能與待確認草稿；附件與網站資料另行管理。"
        case .settings:
            return "設定模型服務；通知、語言與外觀設定仍待實作。"
        case .about:
            return "版本、資源與支援。"
        }
    }
}

@MainActor
private struct ChatTranscriptViewportPreferenceKey: PreferenceKey {
    static var defaultValue: ChatTranscriptViewport? = nil
    static func reduce(value: inout ChatTranscriptViewport?, nextValue: () -> ChatTranscriptViewport?) {
        value = nextValue() ?? value
    }
}

@MainActor
private struct ChatView: View {
    @ObservedObject var session: ChatSession
    @ObservedObject var mcp: MCPSession
    @Binding var showsDrawer: Bool
    let localizer: AppLocalizer
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @StateObject private var voice = ChatVoiceViewModel()
    #if DEBUG
    @ObservedObject private var voiceFixture = VoiceUITestFixture.shared
    @ObservedObject private var mcpRecoveryFixture = UITestMCPRecoveryObservation.shared
    #endif
    @FocusState private var isEditingDraft: Bool
    @State private var showsMCPResults = false
    @State private var showsMCPRecovery = false
    @State private var mcpRecoveryReview: MCPRecoveryReview?
    @State private var showsPDF = false
    @State private var scrollFollow = ChatScrollFollowPolicy()
    @State private var scrollToTailRequest = 0
    @State private var scrollSettleTask: Task<Void, Never>?
    @State private var scheduledSettleRevision: Int?
    private var palette: MikaVisualPalette { MikaVisualPalette(colorScheme) }

    private var voiceMessage: AppText? {
        switch voice.state {
        case .idle: return voice.wasInterrupted ? .voiceInterrupted : nil
        case .listening(_, let armed, _): return armed ? .voiceCancelArmed : .voiceListening
        case .finishing: return .voiceFinishing
        case .noMatch: return .voiceNoMatch
        case .failed(.microphoneDenied): return .voiceMicrophoneDenied
        case .failed(.speechDenied): return .voiceSpeechDenied
        case .failed(.speechRestricted): return .voiceSpeechRestricted
        case .failed(.unavailable): return .voiceUnavailable
        case .failed(.audio): return .voiceAudioError
        case .failed(.recognition): return .voiceRecognitionError
        case .failed(.timeout): return .voiceTimeout
        }
    }

    private func cancelScrollSettle() {
        scrollSettleTask?.cancel()
        scrollSettleTask = nil
        scheduledSettleRevision = nil
    }

    private func scheduleScrollSettle() {
        guard let revision = scrollFollow.pendingSettleRevision else {
            cancelScrollSettle()
            return
        }
        guard scheduledSettleRevision != revision else { return }
        cancelScrollSettle()
        scheduledSettleRevision = revision
        scrollSettleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let settled = scrollFollow.settle(expectedRevision: revision)
            if settled && scrollFollow.needsTailScroll {
                // A no-op drag may have paused scrolling while a new fragment
                // arrived. Catch up only after its final offset is known.
                scrollToTailRequest += 1
            }
            if scheduledSettleRevision == revision {
                scheduledSettleRevision = nil
                scrollSettleTask = nil
            }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            if session.isUITestMode {
                Text(verbatim: localizer.text(.chatFixtureNotice))
                    .font(.caption)
                    .accessibilityIdentifier("uitest.banner")
            }

            #if DEBUG
            if (try? UITestMCPRecoveryConfiguration.resolve(arguments: ProcessInfo.processInfo.arguments)) == true {
                Text(verbatim: "entries=\(mcpRecoveryFixture.entries)")
                    .font(.caption).accessibilityIdentifier("mcp.recovery.fixtureEntries")
            }
            #endif
            LearningChatNotes(store: session.learning)

            if let attachment = session.pdfAttachment {
                HStack {
                    Text(verbatim: attachment.plan.filename).lineLimit(1).accessibilityIdentifier("chat.pdf.card")
                    Button("移除") { session.removePDF() }.accessibilityIdentifier("chat.pdf.removeInline")
                }
            }
            if session.pdfAttachment != nil {
                Text(session.usesMCP ? "PDF 查詢不使用 MCP；請先關閉 MCP 選項。" : ChatPDFAttachment.scopeNotice)
                    .font(.caption).accessibilityIdentifier("chat.pdf.boundary")
            }

            if mcp.canUseInConversation || session.usesMCP {
                Toggle("本次對話使用 MCP 工具", isOn: $session.usesMCP)
                    .font(.callout)
                    .disabled(session.isSubmitting)
                    .accessibilityIdentifier("chat.useMCP")
            }
            if let activity = session.mcpActivity {
                Text(activity).font(.caption)
                    .accessibilityIdentifier("chat.mcpActivity")
                    .accessibilityValue(session.mcpDiagnostics ?? "")
            }
            if session.profileReceipt != nil {
                Text("本次對話曾儲存個人檔案；可到資料頁查看目前內容。")
                    .font(.caption).accessibilityIdentifier("chat.profileReceipt")
            }
            if session.memoryReceipt != nil {
                Text("本次對話曾儲存記憶修改；可在資料頁查看目前內容。")
                    .font(.caption).accessibilityIdentifier("chat.memoryReceipt")
            }
            if !session.mcpSteps.isEmpty {
                Button("檢視工具結果（\(session.mcpSteps.count)）") { showsMCPResults = true }
                    .font(.caption).accessibilityIdentifier("chat.mcpResults")
                    .disabled(session.isSubmitting)
            }

            GeometryReader { viewport in
              ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if session.entries.isEmpty && session.replyPreview == nil {
                            ChatEmptyState(draft: $session.draft, palette: palette, localizer: localizer)
                        }
                        if !session.hasStoredKey {
                            Text(verbatim: localizer.text(.chatModelSetupHint))
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("chat.explanation")
                        }
                        ForEach(Array(session.entries.enumerated()), id: \.element.id) { index, entry in
                            VStack(alignment: entry.role == "user" ? .trailing : .leading, spacing: 6) {
                                HStack {
                                    if entry.role == "user" { Spacer(minLength: 40) }
                                    Text(entry.role == "assistant"
                                         ? ChatReplyMarkdown.render(entry.content) : AttributedString(entry.content))
                                        .font(.system(size: 15.5))
                                        .lineSpacing(entry.role == "user" ? 1 : 4)
                                        .foregroundStyle(entry.role == "user" ? Color.white : palette.ink)
                                        .textSelection(.enabled)
                                        .accessibilityIdentifier("chat.message.\(index).\(entry.role)")
                                        .padding(.horizontal, 14).padding(.vertical, entry.role == "user" ? 10 : 12)
                                        .background(entry.role == "user" ? palette.accent : palette.assistant,
                                                    in: RoundedRectangle(cornerRadius: 20))
                                    if entry.role != "user" { Spacer(minLength: 0) }
                                }
                                if let pdf = entry.pdf {
                                    ArchivedPDFEvidenceView(evidence: pdf, identifier: "chat.pdf.saved.\(index)")
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: entry.role == "user" ? .trailing : .leading)
                            .id(entry.id)
                        }
                        if let preview = session.replyPreview {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(preview.status).font(.caption.bold()).foregroundStyle(.secondary)
                                    .accessibilityIdentifier("chat.partialStatus")
                                Text(ChatReplyMarkdown.render(preview.text, streaming: preview.phase == .receiving))
                                    .font(.system(size: 15.5)).lineSpacing(4)
                                    .foregroundStyle(palette.ink).textSelection(.enabled)
                                    .accessibilityIdentifier("chat.partialReply")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14).padding(.vertical, 12)
                                    .background(palette.assistant, in: RoundedRectangle(cornerRadius: 20))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(preview.id)
                        }
                        Color.clear.frame(height: 1).id("chat.transcript.tail")
                    }
                    .padding(.vertical, 4)
                    .background {
                        GeometryReader { content in
                            Color.clear.preference(key: ChatTranscriptViewportPreferenceKey.self,
                                value: ChatTranscriptViewport(
                                    contentHeight: Double(content.size.height),
                                    bottomY: Double(content.frame(in: .named("chat.transcript.viewport")).maxY),
                                    viewportHeight: Double(viewport.size.height)))
                        }
                    }
                }
                .coordinateSpace(name: "chat.transcript.viewport")
                .accessibilityIdentifier("chat.transcript")
                // A simultaneous drag observes scrolling without taking the
                // long-press/text-selection gesture away from selectable Text.
                .simultaneousGesture(DragGesture(minimumDistance: 5)
                    .onChanged { drag in
                        scrollFollow.beginDrag()
                        if drag.translation.height > 4 { scrollFollow.userDraggedTowardEarlierContent() }
                        if drag.translation.height < -4 { scrollFollow.userDraggedTowardLatestContent() }
                    }
                    .onEnded { _ in
                        scrollFollow.endDrag()
                        scheduleScrollSettle()
                    })
                .onPreferenceChange(ChatTranscriptViewportPreferenceKey.self) { position in
                    guard let position else { return }
                    if scrollFollow.observe(position) {
                        proxy.scrollTo("chat.transcript.tail", anchor: .bottom)
                    }
                    scheduleScrollSettle()
                }
                .onChange(of: session.conversationID) { _, _ in
                    cancelScrollSettle()
                    scrollFollow.conversationChanged()
                    proxy.scrollTo("chat.transcript.tail", anchor: .bottom)
                }
                .onChange(of: session.isSubmitting) { _, submitting in
                    guard submitting else { return }
                    cancelScrollSettle()
                    scrollFollow.userSubmitted()
                    proxy.scrollTo("chat.transcript.tail", anchor: .bottom)
                }
                .onChange(of: scrollToTailRequest) { _, _ in
                    proxy.scrollTo("chat.transcript.tail", anchor: .bottom)
                }
                .overlay(alignment: .bottomTrailing) {
                    if !scrollFollow.followsTail {
                        Button {
                            cancelScrollSettle()
                            scrollFollow.userRequestedLatest()
                            scrollToTailRequest += 1
                        } label: {
                            Label(localizer.text(.shellReturnToLatest), systemImage: "arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                        .accessibilityIdentifier("chat.returnToLatest")
                        .padding(12)
                    }
                }
              }
            }

            if mcp.unresolvedToolOutcome && !session.isSubmitting {
                VStack(alignment: .leading, spacing: 6) {
                    Text(localizer.text(.mcpUnknownOutcomeRecovery))
                        .font(.callout)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("chat.mcpUnknownOutcome")
                    Button(localizer.text(.mcpRecoveryButton)) {
                        if let review = mcp.prepareToolRecovery() {
                            mcpRecoveryReview = review; showsMCPRecovery = true
                        }
                    }
                    .accessibilityIdentifier("chat.mcpRecovery")
                }
            }
            if let issue = mcp.recoveryIssue {
                Text(localizer.text(issue)).font(.callout).foregroundStyle(.red)
                    .accessibilityIdentifier("chat.mcpRecoveryError")
            }
            if let notice = mcp.recoveryNotice {
                Text(localizer.text(notice)).font(.callout)
                    .accessibilityIdentifier("chat.mcpRecoveryNotice")
            }
            if let error = session.chatError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("chat.error")
            }
            if let notice = session.chatNotice {
                Text(notice)
                    .font(.callout)
                    .accessibilityIdentifier("chat.notice")
            }
            if let notice = session.archiveNotice {
                Text(notice).font(.callout).foregroundStyle(.orange)
                    .accessibilityIdentifier("chat.archiveNotice")
                if session.canRetryArchiveSave {
                    Button("重試保存") { session.retryArchiveSave() }
                        .accessibilityIdentifier("chat.archiveRetry")
                }
            }
            #if DEBUG
            if VoiceUITestFixture.selected() != nil {
                VStack {
                    Text(verbatim: voiceFixture.observation)
                        .accessibilityIdentifier("voice.fixture.observation")
                    HStack {
                        Button("Emit") { voiceFixture.emitLatest() }
                            .accessibilityIdentifier("voice.fixture.emit")
                        Button("AX") { _ = voiceFixture.activateAccessibility?() }
                            .accessibilityIdentifier("voice.fixture.accessibility")
                        Button("Cancel AX") { voiceFixture.performAccessibilityCancel() }
                            .accessibilityIdentifier("voice.fixture.cancelAccessibility")
                    }
                    if !voiceFixture.accessibilityAction.isEmpty {
                        Text(verbatim: voiceFixture.accessibilityAction)
                            .accessibilityIdentifier("voice.fixture.actionName")
                    }
                }.font(.caption2)
            }
            #endif
            if let message = voiceMessage {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: localizer.text(message))
                        if case .listening(let partial, _, _) = voice.state, !partial.isEmpty {
                            Text(verbatim: partial).lineLimit(2)
                        }
                    }
                    .font(.caption)
                    .accessibilityIdentifier("chat.voice.status")
                    Spacer(minLength: 0)
                    if voice.state == .failed(.microphoneDenied) || voice.state == .failed(.speechDenied) {
                        Button(localizer.text(.voiceSettings)) {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .font(.caption)
                        .accessibilityIdentifier("chat.voice.settings")
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 4) {
                Button {
                    voice.cancel(); isEditingDraft = false; showsPDF = true
                } label: {
                    Image(systemName: "plus").frame(width: 40, height: 40)
                }
                    .accessibilityLabel(localizer.text(session.pdfAttachment == nil ? .shellAttachPDF : .shellViewPDFAttachment))
                    .disabled(session.isSubmitting)
                    .accessibilityIdentifier("chat.pdf.open")
                // Return adds a line; the keyboard toolbar Done closes editing without sending.
                TextField(localizer.text(.shellMessagePlaceholder), text: $session.draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .focused($isEditingDraft)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                    .disabled(session.isSubmitting)
                    .accessibilityLabel(localizer.text(.shellMessageDraft))
                    .accessibilityIdentifier("chat.draft")
                ChatVoicePressControl(label: localizer.text(.voiceLabel), hint: localizer.text(.voiceHint),
                                      cancelLabel: localizer.text(.voiceAccessibilityCancel),
                                      active: voice.isActive, enabled: !session.isSubmitting,
                                      begin: { time in isEditingDraft = false; voice.begin(startedAt: time) },
                                      drag: { voice.drag($0) }, release: { voice.release() },
                                      cancel: { voice.cancel() })
                    .frame(width: 40, height: 40)
                if session.isSubmitting {
                    Button { session.cancel() } label: {
                        Image(systemName: "stop.fill").frame(width: 40, height: 40)
                    }
                    .accessibilityLabel(localizer.text(.shellStop))
                    .accessibilityIdentifier("chat.cancel")
                }
                Button {
                    voice.cancel()
                    isEditingDraft = false
                    session.send(mcp: session.usesMCP ? mcp : nil)
                    if session.isSubmitting {
                        // Only an accepted send restores follow. The observer
                        // also covers sends launched from the PDF sheet.
                        cancelScrollSettle()
                        scrollFollow.userSubmitted()
                        scrollToTailRequest += 1
                    }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(session.canSend && !(session.usesMCP && mcp.unresolvedToolOutcome) ? Color.white : palette.secondaryInk)
                        .frame(width: 40, height: 40)
                        .background(session.canSend && !(session.usesMCP && mcp.unresolvedToolOutcome) ? palette.accent : palette.assistant, in: Circle())
                }
                .disabled(!session.canSend || (session.usesMCP && mcp.unresolvedToolOutcome))
                .accessibilityLabel(localizer.text(.shellSend))
                .accessibilityIdentifier("chat.send")
            }
            .frame(minHeight: 52)
            .layoutPriority(1)
            .padding(6)
            .background(palette.glass, in: Capsule())
            .overlay(Capsule().stroke(palette.hair, lineWidth: 0.5))
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)
        .background(palette.background)
        .sheet(isPresented: $showsPDF) { ChatPDFAttachmentView(session: session) }
        .alert(localizer.text(.mcpRecoveryTitle), isPresented: $showsMCPRecovery) {
            Button(localizer.text(.configurationCancel), role: .cancel) { mcpRecoveryReview = nil }
                .accessibilityIdentifier("chat.mcpRecovery.cancel")
            Button(localizer.text(.mcpRecoveryConfirm)) {
                guard let review = mcpRecoveryReview else { return }
                mcpRecoveryReview = nil
                if mcp.acknowledgeToolRecovery(review) { session.mcpRecoveryAcknowledged() }
            }.accessibilityIdentifier("chat.mcpRecovery.confirm")
        } message: { Text(localizer.text(.mcpRecoveryExplanation)) }
        .sheet(item: Binding(get: { session.pendingMCPApproval }, set: { _ in })) { proposal in
            MCPApprovalView(proposal: proposal,
                            approve: { session.resolveMCPApproval(id: proposal.id, approved: true) },
                            decline: { session.resolveMCPApproval(id: proposal.id, approved: false) })
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showsMCPResults) { MCPResultsView(steps: session.mcpSteps) }
        .sheet(item: Binding(get: { session.pendingProfileReview }, set: { _ in })) { review in
            UserProfileToolReviewView(review: review,
                approve: { session.resolveProfileReview(id: review.id, approved: true) },
                decline: { session.resolveProfileReview(id: review.id, approved: false) })
                .interactiveDismissDisabled()
        }
        .sheet(item: Binding(get: { session.pendingMemoryReview }, set: { _ in })) { review in
            MemoryToolReviewView(review: review,
                approve: { session.resolveMemoryReview(id: review.id, approved: true) },
                decline: { session.resolveMemoryReview(id: review.id, approved: false) })
                .interactiveDismissDisabled()
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") { isEditingDraft = false }
                    .accessibilityIdentifier("chat.dismissKeyboard")
            }
        }
        .onChange(of: showsDrawer) { _, visible in
            if visible { voice.cancel(); isEditingDraft = false }
        }
        .onAppear { voice.attach(session: session) }
        .onDisappear { voice.cancel() }
        .onChange(of: session.conversationID) { _, _ in voice.cancel() }
        .onChange(of: session.isSubmitting) { _, submitting in if submitting { voice.cancel() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { voice.cancel(interrupted: true) } }
        // Other processes cannot publish to this process's NotificationCenter.
        // Poll only while this chat view is active, and update only on change.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                mcp.refreshRecoveryState()
                do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                catch { return }
            }
        }
        .task(id: voice.isActive) {
            while voice.isActive && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled else { return }
                voice.tick()
            }
        }
    }
}

@MainActor
private struct ChatEmptyState: View {
    @Binding var draft: String
    let palette: MikaVisualPalette
    let localizer: AppLocalizer

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5...10: return localizer.text(.shellGreetingMorning)
        case 11...12: return localizer.text(.shellGreetingNoon)
        case 13...17: return localizer.text(.shellGreetingAfternoon)
        case 18...22: return localizer.text(.shellGreetingEvening)
        default: return localizer.text(.shellGreetingNight)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(greeting).font(.system(size: 28, weight: .bold))
                .foregroundStyle(palette.ink)
            Text(localizer.text(.shellWhatToDo))
                .font(.system(size: 15)).foregroundStyle(palette.secondaryInk)
                .padding(.top, 6)
            // This is the WOOWTECH web example. Android's phone/app examples
            // are outside the iOS feature set and are intentionally omitted.
            Button {
                draft = localizer.text(.shellWebExample)
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "globe").font(.system(size: 22))
                        .foregroundStyle(palette.secondaryInk)
                    Text(localizer.text(.shellWebExample))
                        .font(.system(size: 15)).foregroundStyle(palette.ink)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).frame(minHeight: 56)
            }
            .buttonStyle(.plain)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.hair, lineWidth: 0.5))
            .padding(.top, 28)
            .accessibilityIdentifier("chat.emptyExample.web")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.top, 52)
    }
}

@MainActor
private struct LearningChatNotes: View {
    @ObservedObject var store: LearningStore
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.isLearning {
                Text("正在整理你說過的事…")
                    .font(.caption).accessibilityIdentifier("chat.learning")
            }
            if let notice = store.notice {
                Text(notice).font(.caption).accessibilityIdentifier("chat.learningNotice")
            }
            if let error = store.error {
                Text(error).font(.caption).foregroundStyle(.orange)
                    .accessibilityIdentifier("chat.learningError")
            }
            ForEach(Array(store.notes.enumerated()), id: \.element.memoryID) { index, note in
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.noteText(note)).font(.caption)
                        .accessibilityIdentifier("chat.memoryNote.\(index)")
                    HStack {
                        if store.canReviewMemory(note) {
                            Button("批准") { store.approvePendingMemory(note) }
                                .accessibilityIdentifier("chat.approveMemory.\(index)")
                            Button("拒絕") { store.rejectPendingMemory(note) }
                                .accessibilityIdentifier("chat.rejectMemory.\(index)")
                        }
                        if note.undoToken != nil {
                            Button("撤銷") { store.undo(note) }
                                .accessibilityIdentifier("chat.undoMemory.\(index)")
                        }
                    }
                    .font(.caption)
                }
            }
        }
    }
}
