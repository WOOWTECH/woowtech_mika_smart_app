import Photos
import SwiftUI
import UIKit
import AssistantSkills
import AssistantPersistence
import AssistantBrowser
import AssistantDocuments

@MainActor
struct ContentView: View {
    @State private var selection: AppSection = .chat
    @State private var browserReturnSection: AppSection = .chat
    #if WOOWTECHBOT
    @State private var showsDrawer = true
    @StateObject private var botWorkspace = BotWorkspaceStore.shared
    @State private var botSheet: BotChatSheet?
    @State private var botPage: BotChatPage?
    @State private var botChatMenu: BotChatMenu?
    @State private var botChatMenuFrame: CGRect?
    @State private var botDraftSave: Task<Void, Never>?
    @State private var botRestored = false
    #else
    @State private var showsDrawer = false
    #endif
    @State private var showsNewConversationConfirmation = false
    @State private var pendingNewConversationProtection: NewConversationProtection?
    @AccessibilityFocusState private var menuHasVoiceOverFocus: Bool
    @AccessibilityFocusState private var backHasVoiceOverFocus: Bool
    @State private var notificationNavigationID = UUID()
    @State private var showsDownloads = false
    @StateObject private var session = ChatSession()
    @StateObject private var mcpServers = MCPServers()
    @StateObject private var browserWorkspace = BrowserWorkspace()
    @StateObject private var preferences = SelfConfigurationStore.applicationPreferences()
    @StateObject private var languages = AppLanguageStore.applicationPreferences()
    @StateObject private var notifications = TaskNotificationStore.applicationStore()
    private var browser: BrowserSession { browserWorkspace.selected }
    @Environment(\.scenePhase) private var scenePhase
    /// Extra background time for a reply that is still streaming.
    @State private var replyBackgroundTask: UIBackgroundTaskIdentifier = .invalid
    @Environment(\.colorScheme) private var colorScheme
    private var palette: MikaVisualPalette { MikaVisualPalette(colorScheme) }
    private var webTaskColors: ChatWebTaskColors {
        ChatWebTaskColors(ink: palette.ink, secondaryInk: palette.secondaryInk, accent: palette.accent,
                          fill: palette.assistant, background: palette.background)
    }
    private var localizer: AppLocalizer { AppLocalizer(language: languages.resolved) }
    /// Play's drawer readiness: 一切就緒, or 還不能開始任務 without a model.
    private var drawerStatus: String {
        localizer.text(session.chatStatusMessage == .chatStatusUnconfigured ? .chatSendBlockedTitle : .drawerStatusReady)
    }

    var body: some View {
        shell
        #if WOOWTECHBOT
        .fullScreenCover(isPresented: Binding(get: { botWorkspace.selectedService != nil }, set: { if !$0 { botWorkspace.selectedService = nil } })) {
            if let id = botWorkspace.selectedService, let web = botWorkspace.session(id) {
                BotServiceScreen(web: web, chat: session, notifications: notifications, localizer: localizer,
                    close: { botWorkspace.selectedService = nil }, attach: { url in
                        let attached = await attachDownload(url)
                        if attached { botWorkspace.selectedService = nil }
                        return attached
                    })
                    .id(web.service.profileID)
            }
        }
        .fullScreenCover(item: $botPage) { page in
            switch page {
            case .edit:
                if let archive = session.archive {
                    BotProfileEditor(id: session.conversationID, archive: archive, workspace: botWorkspace, localizer: localizer) { botPage = nil }
                }
            case .search: BotConversationSearch(chat: session, localizer: localizer) { botPage = nil }
            case .files: BotConversationFiles(chat: session, localizer: localizer) { botPage = nil }
            }
        }
        .sheet(item: $botSheet) { sheet in
            switch sheet {
            case .notifications: BotNotificationsSheet(localizer: localizer) { botSheet = nil }
            }
        }
        // A notice (signed out, a change that could not be saved...) in the app's own dialog, not the system alert.
        .botDialog(isPresented: botWorkspace.notice != nil, dismiss: { botWorkspace.notice = nil }) {
            BotDialogSurface {
                BotDialogTitle(text: botText("提示", "Notice"))
                BotDialogBody(text: botWorkspace.notice?.text(localizer) ?? "")
                BotDialogButton(title: botText("確認", "OK"), kind: .confirm, identifier: "bot.notice.ok") { botWorkspace.notice = nil }
                    .padding(.top, 24)
            }
        }
        .onChange(of: languages.resolved, initial: true) { _, language in
            BotPushController.shared.setInterfaceLanguage(english: language == .english)
        }
        .onReceive(session.draftModel.$text) { text in
            guard botRestored else { return }
            botDraftSave?.cancel()
            let id = session.conversationID
            botDraftSave = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(500)); try botWorkspace.saveDraft(id, text: text) }
                catch is CancellationError {}
                catch { botWorkspace.notice = .draftUnsaved }
            }
        }
        .onAppear {
            guard !botRestored else { return }
            if let id = botWorkspace.state.currentChat.flatMap(UUID.init(uuidString:)) {
                _ = session.switchBotConversation(to: id, workspace: botWorkspace)
            }
            botRestored = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { BotPushController.shared.schedule() }
            if phase == .active && !botWorkspace.available {
                do { try botWorkspace.reload() }
                catch { botWorkspace.notice = .unreadable }
            }
            if phase != .active {
                botDraftSave?.cancel()
                do { try botWorkspace.saveDraft(session.conversationID, text: session.draft) }
                catch { botWorkspace.notice = .draftUnsaved }
            }
        }
        #endif
        .animation(.easeOut(duration: 0.22), value: showsDrawer)
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
        .mikaPageCanvas(palette.background)
        .appLanguage(languages)
        .preferredColorScheme(preferences.preferredColorScheme)
        .firstLaunchOnboarding(session: session, languages: languages, accent: palette.accent)
        .modifier(BrowserDownloadPresentations(manager: browserWorkspace.downloads, chat: session,
                                               showsList: $showsDownloads, localizer: localizer, attach: attachDownload))
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
            }
            mcpServers.onConnectionChange = { [weak session] in session?.cancelMCP() }
            session.interfaceLanguage = { [weak languages] in languages?.resolved ?? .traditionalChinese }
            session.fileTool = ChatFileCreation.tool(store: session.createdFileStore)
            // Like Android, no banner about the chat that is already in front.
            notifications.isOnScreen = { destination in
                switch destination {
                case .chat: return selection == .chat && !showsDrawer
                case .browser: return selection == .browser
                }
            }
            session.webTaskEnvironment = { [weak browserWorkspace] in
                guard let browserWorkspace else { return nil }
                var environment = ChatWebTaskEnvironment(dataStore: browserWorkspace.websiteDataStore,
                                                         searchTemplate: browserWorkspace.library.searchSettings.selected.template)
                environment.onSignInObserved = { [weak browserWorkspace] url, state in
                    browserWorkspace?.observeSignIn(url, state)
                }
                environment.downloads = browserWorkspace.downloads
                #if DEBUG
                if let fixture = ChatWebTaskFixture.shared {
                    environment.fixtureOrigin = fixture.originURL
                    environment.skipsPacing = true
                }
                #endif
                return environment
            }
            #if DEBUG
            Task { _ = try? await ChatWebTaskFixture.shared?.start() }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            session.webTaskScenePhaseChanged(isActive: phase == .active, isBackground: phase == .background)
            if phase != .active { browserWorkspace.cancelAllWork() }
            // Like the Play build, MCP stays set up. A brief interruption (Notification
            // Center, a permission alert) keeps the connections; in the background iOS
            // stops the MCP work of a running request, and the connections come back
            // when the app is active. A plain reply keeps its extra background time.
            if phase == .background {
                session.cancelMCP(leavingScreen: true)
                mcpServers.appWillLeaveForeground()
                session.appLeftScreen()
                keepReplyRunningInBackground()
            }
            // Closing the app from the app switcher goes no further than inactive, so a
            // reply still arriving is saved as unfinished as soon as the app leaves the front.
            if phase != .active { session.checkpointPendingTurn() }
            if phase == .active {
                mcpServers.appDidBecomeActive()
                endReplyBackgroundTime()
            }
        }
        .onChange(of: session.isSubmitting) { _, submitting in
            if !submitting { endReplyBackgroundTime() }
        }
        .onChange(of: selection) { previous, destination in
            // Like Play, leaving the browser closes its page; coming back shows the start page.
            if previous == .browser && destination != .browser { browserWorkspace.leaveBrowser() }
            if destination == .chat { menuHasVoiceOverFocus = true }
            else { backHasVoiceOverFocus = true }
        }
    }

    /// 附加到對話: the download goes into the chat's tray as a picked file
    /// does, from a temporary copy, and the chat comes to the front.
    private func attachDownload(_ url: URL) async -> Bool {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChatAttachmentImports/" + UUID().uuidString, isDirectory: true)
        let copy = folder.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: url, to: copy)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            return false
        }
        let before = Set(session.pendingAttachments.map(\.id))
        await session.addAttachments([ChatPickedFile(temporaryURL: copy, suggestedName: url.lastPathComponent,
                                                     contentType: nil, dedupeKey: nil)])
        guard session.pendingAttachments.contains(where: { !before.contains($0.id) }) else { return false }
        showsDrawer = false
        browserReturnSection = .chat
        selection = .chat
        return true
    }

    private var shell: some View {
        ZStack(alignment: .leading) {
          NavigationStack {
            sectionContent
            #if WOOWTECHBOT
            .safeAreaInset(edge: .top, spacing: 0) { if selection == .chat { botChatHeader } }
            #endif
            .navigationTitle(selection == .chat ? localizer.text(.shellBrandTitle) : selection.title(using: localizer))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            // The opaque canvas has a known appearance. Automatic toolbar
            // contrast chose white text on the light canvas after rotating an
            // iPad with the keyboard open, including the system status bar.
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .toolbar { rootToolbar }
            #if WOOWTECHBOT
            // The chat has its own header (back, name capsule, menu); the other sections keep the system bar.
            .toolbar(selection == .chat ? .hidden : .visible, for: .navigationBar)
            #endif
            .safeAreaInset(edge: .bottom, spacing: 0) { fixtureObservation }
          }
          .id(notificationNavigationID)
          .accessibilityHidden(showsDrawer)
          if let task = session.webTask {
              // The task tab stays in the window on every screen; it is seen
              // only in the chat (Android's small view).
              ChatWebTaskPreview(task: task, localizer: localizer, colors: webTaskColors,
                                 isOnScreen: selection == .chat && !showsDrawer, onStop: { session.cancel() })
                  .id(task.id)
          }
          if showsDrawer {
              #if WOOWTECHBOT
              if let archive = session.archive {
                  BotConversationList(chat: session, archive: archive, workspace: botWorkspace, localizer: localizer,
                      close: closeDrawer, new: requestNewConversation, select: botSelect)
                      .transition(.move(edge: .leading))
              }
              #else
              GeometryReader { geometry in
                  // Like Android's ChatDrawer the panel fills the whole screen
                  // height behind the status and home-indicator areas and pads
                  // its content by those insets. Top-leading alignment matters:
                  // the panel is taller than this safe-area container, and a
                  // centred panel ended 46.5 pt above the bottom edge (showing
                  // the composer) with its title under the clock.
                  ZStack(alignment: .topLeading) {
                      Button { closeDrawer() } label: {
                          palette.scrim.ignoresSafeArea()
                      }
                      .buttonStyle(.plain)
                      .accessibilityHidden(true)
                      MikaNavigationDrawer(
                          status: drawerStatus,
                          session: session,
                          canStartNew: !session.isSubmitting,
                          palette: palette,
                          localizer: localizer,
                          topInset: geometry.safeAreaInsets.top,
                          bottomInset: geometry.safeAreaInsets.bottom,
                          leadingInset: geometry.safeAreaInsets.leading,
                          onClose: closeDrawer,
                          onNew: requestNewConversation,
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
                      .frame(width: min(304, max(0, geometry.size.width - 48)) + geometry.safeAreaInsets.leading,
                             height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom)
                      .offset(x: -geometry.safeAreaInsets.leading, y: -geometry.safeAreaInsets.top)
                      .transition(.move(edge: .leading))
                  }
                  .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
              }
              #endif
          }
          #if WOOWTECHBOT
          // The chat header's "…" popover sits above everything in the shell, so a tap anywhere else reaches it first.
          BotPopoverLayer(active: $botChatMenu, frame: botChatMenuFrame) { _ in botChatMenuView }
          #endif
        }
    }

    @ToolbarContentBuilder private var rootToolbar: some ToolbarContent {
                ToolbarItem(placement: .topBarLeading) {
                    if selection == .chat {
                        Button { showsDrawer = true } label: {
                            #if WOOWTECHBOT
                            Image(systemName: "chevron.backward")
                                .foregroundStyle(palette.accent).frame(width: 40, height: 40)
                            #else
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(palette.accent)
                                .frame(width: 40, height: 40)
                            #endif
                        }
                        .accessibilityLabel(localizer.text(.shellMenu))
                        .accessibilityIdentifier("chat.menu")
                        .accessibilityFocused($menuHasVoiceOverFocus)
                    } else {
                        Button {
                            let destination = selection == .browser ? browserReturnSection : .chat
                            browserReturnSection = .chat
                            selection = destination
                            #if WOOWTECHBOT
                            // Android: the tool and settings pages are entered from History, so Back returns to History.
                            if destination == .chat { showsDrawer = true }
                            #endif
                        } label: {
                            Image(systemName: "chevron.backward")
                                .foregroundStyle(palette.accent)
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
                        #if WOOWTECHBOT
                        EmptyView()
                        #else
                        VStack(spacing: 1) {
                            Text(localizer.text(.shellBrandTitle))
                                .scaledFont(size: 17, weight: .semibold)
                                .lineLimit(1)
                            Text(verbatim: localizer.text(session.chatStatusMessage))
                                .scaledFont(size: 12)
                                .foregroundStyle(palette.secondaryInk)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .accessibilityIdentifier("chat.status")
                        }
                        // The bar keeps its height at the largest sizes, so the conversation keeps the screen.
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        #endif
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        #if WOOWTECHBOT
                        EmptyView()
                        #else
                        Button(action: requestNewConversation) {
                            Image(systemName: "square.and.pencil")
                                .foregroundStyle(session.isSubmitting ? palette.secondaryInk : palette.accent)
                                .frame(width: 40, height: 40)
                        }
                        .disabled(session.isSubmitting)
                        .accessibilityLabel(localizer.text(.shellNewConversation))
                        .accessibilityIdentifier("chat.newConversation")
                        #endif
                    }
                }
    }

    private var sectionContent: some View {
            Group {
                switch selection {
                case .chat:
                    ChatView(session: session, mcp: mcpServers, showsDrawer: $showsDrawer, localizer: localizer,
                             openSettings: {
                                 browserReturnSection = .chat
                                 selection = .settings
                                 showsDrawer = false
                             },
                             openPendingSkills: {
                                 session.learning.requestPendingSkills()
                                 selection = .memory
                                 showsDrawer = false
                             })
                        .mikaReadableColumn()
                        .mikaPageCanvas(palette.background)
                case .settings:
                    MikaAlignedSettingsView(session: session, preferences: preferences, notifications: notifications,
                                            languages: languages,
                                            mcpDestination: { MCPToolsView(servers: mcpServers) },
                                            memoryDestination: { memoryDataView(resetNavigation: true) })
                case .about:
                    MikaAboutView(languages: languages, info: MikaAboutInfo(bundle: .main))
                case .tools:
                    MCPToolsView(servers: mcpServers)
                case .memory:
                    memoryDataView(resetNavigation: false)
                case .browser:
                    BrowserView(browser: browser, chat: session, workspace: browserWorkspace,
                                openDownloads: { showsDownloads = true })
                }
            }
    }

    /// iOS suspends the app soon after it leaves the screen, which cuts a
    /// streaming reply; Android keeps the task running in a foreground service.
    /// A reply that is still arriving gets iOS's usual extra background time,
    /// about 30 seconds, so a short trip to another app does not lose it.
    private func keepReplyRunningInBackground() {
        guard session.isSubmitting, replyBackgroundTask == .invalid else { return }
        replyBackgroundTask = UIApplication.shared.beginBackgroundTask(withName: "woow.chat.reply") {
            endReplyBackgroundTime()
        }
    }

    private func endReplyBackgroundTime() {
        guard replyBackgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(replyBackgroundTask)
        replyBackgroundTask = .invalid
    }

    private func closeDrawer() {
        showsDrawer = false
        if selection == .chat { menuHasVoiceOverFocus = true }
    }

    private func memoryDataView(resetNavigation: Bool) -> some View {
        MemoryDataView(store: session.learning, workspace: browserWorkspace, modelAccess: session.modelAccess,
                       modelChanges: session.$savedSettings.dropFirst().map { _ in () }.eraseToAnyPublisher(),
                       onOpenBrowser: {
                           browserReturnSection = .memory
                           selection = .browser
                           if resetNavigation { notificationNavigationID = UUID() }
                       },
                       onOpenSignIns: {
                           browserReturnSection = .memory
                           selection = .browser
                           if resetNavigation { notificationNavigationID = UUID() }
                           browserWorkspace.presentsSignIns = true
                       })
    }

    private func requestNewConversation() {
        #if WOOWTECHBOT
        if session.switchBotConversation(to: nil, workspace: botWorkspace) {
            selection = .chat; closeDrawer()
        }
        #else
        guard !session.isSubmitting else { return }
        if let protection = NewConversationProtection.current(in: session) {
            pendingNewConversationProtection = protection
            showsNewConversationConfirmation = true
        } else if NewConversationAction.start(in: session, approved: nil) {
            selection = .chat
            closeDrawer()
        }
        #endif
    }

    #if WOOWTECHBOT
    private func botText(_ zh: String, _ en: String) -> String { localizer.language == .english ? en : zh }
    private var botCurrentTitle: String {
        let record = session.archive?.conversations.first { $0.id.uuidString == session.conversationID }
        return record?.customTitle ?? botWorkspace.presentation(session.conversationID).title ?? record?.title ?? BotBrand.appName(localizer)
    }
    /// Android `BotUiChatHeader`: a round back button, a capsule with the identity tile and name that hugs its content and sits
    /// in the middle, and a round "…" whose popover has name and icon, new chat, find and files.
    private var botChatHeader: some View {
        HStack(spacing: 0) {
            BotRoundButton(symbol: "chevron.left", label: botText("歷史對話", "Conversation history"), identifier: "chat.menu") { showsDrawer = true }
                .accessibilityFocused($menuHasVoiceOverFocus)
            ZStack {
                Button { botChatMenu = nil; botPage = .edit } label: {
                    HStack(spacing: 8) {
                        BotAvatar(avatar: botWorkspace.presentation(session.conversationID).avatar).frame(width: 24, height: 24)
                        Text(botCurrentTitle).scaledFont(size: 14, weight: .semibold).foregroundStyle(palette.ink).lineLimit(1)
                    }
                    .padding(.leading, 8).padding(.trailing, 14).frame(height: 40)
                    .background(palette.glass, in: Capsule()).contentShape(Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("bot.chat.identity")
            }.frame(maxWidth: .infinity).dynamicTypeSize(...DynamicTypeSize.accessibility1)
            BotRoundButton(symbol: "ellipsis", label: botText("對話選單", "Conversation menu"), identifier: "bot.chat.menu") {
                withAnimation(BotMotion.pop) { botChatMenu = botChatMenu == .more ? nil : .more }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { botChatMenuFrame = $0 }
        }
        // The page colour reaches up behind the status bar only: a background that also ignored the other edges painted over the chat.
        .padding(.horizontal, 8).mikaReadableColumn()
        .background(palette.background, ignoresSafeAreaEdges: .top)
    }

    @ViewBuilder private var botChatMenuView: some View {
        BotPopoverSurface {
            BotPopoverRow(symbol: "pencil", title: botText("名稱與圖示", "Name and icon"), identifier: "bot.chat.menu.edit") { botChatMenu = nil; botPage = .edit }
            BotPopoverRow(symbol: "square.and.pencil", title: botText("新對話", "New chat"), enabled: !session.isSubmitting,
                          identifier: "bot.chat.menu.new") { botChatMenu = nil; requestNewConversation() }
            BotPopoverRow(symbol: "magnifyingglass", title: botText("對話中尋找", "Find in conversation"), identifier: "bot.chat.menu.find") { botChatMenu = nil; botPage = .search }
            BotPopoverRow(symbol: "doc.text", title: botText("檔案", "Files"), identifier: "bot.chat.menu.files") { botChatMenu = nil; botPage = .files }
        }
    }

    private func botSelect(_ destination: BotLocalDestination) {
        switch destination {
        case .files: botPage = .files; return
        case .notifications: botSheet = .notifications; return
        case .tools: selection = .tools
        case .memory: selection = .memory
        case .browser: selection = .browser
        case .settings: selection = .settings
        case .about: selection = .about
        }
        browserReturnSection = .chat; showsDrawer = false
    }
    #endif

    @ViewBuilder private var fixtureObservation: some View {
        #if DEBUG
        VStack(spacing: 0) {
            // -UITestAttachments: adds a generated photo and note to the tray on demand,
            // after a test has saved its model.
            if session.isUITestMode, ProcessInfo.processInfo.arguments.contains("-UITestAttachments") {
                Button("加入測試附件") { Task { await session.addAttachments(ChatAttachmentUITestFixture.pickedFiles()) } }
                    .font(.caption2)
                    .accessibilityIdentifier("uitest.attach.fixture")
            }
            if (try? UITestChatStreamingConfiguration.resolve(arguments: ProcessInfo.processInfo.arguments)) != nil {
                Text("串流通知送出測試觀測")
                    .font(.caption2)
                    .accessibilityIdentifier("stream.fixture.notifications")
                    .accessibilityValue(String(notifications.streamingFixtureCompletedAddAttempts))
            }
            if Self.exposesNotificationRoute(arguments: ProcessInfo.processInfo.arguments) {
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

    #if DEBUG
    /// Only the isolated MCP fixture mode shows the notification test the root
    /// route generation. Reuse the side-effect-free strict mode/UUID parser;
    /// never create a store or request permission while rendering it.
    static func exposesNotificationRoute(arguments: [String]) -> Bool {
        guard arguments.filter({ $0 == "-UITestMode" }).count == 1,
              arguments.filter({ $0 == "-UITestMCPFixture" }).count == 1,
              !arguments.contains(where: { $0.hasPrefix("-Live") }),
              let configuration = try? TaskNotificationStoreConfiguration.resolve(arguments: arguments)
        else { return false }
        return configuration.scope != "production"
    }
    #endif
}

/// WOOWTECH Android brand.properties and ui/theme/Colors.kt at de5be358.
/// Keep these visual tokens local to the shell; model and browser policy are unchanged.
struct MikaVisualPalette {
    private let dark: Bool
    private func rgb(_ red: Double, _ green: Double, _ blue: Double) -> Color {
        Color(red: red / 255, green: green / 255, blue: blue / 255)
    }

    #if WOOWTECHBOT
    /// The woowtechbot website has a phone-only Midnight set (below its 768 px breakpoint) and a
    /// separate set for the sheets that mirror its settings dialogs on every width; Daylight keeps one
    /// set (white cards in those sheets). Android's Colors.kt carries the same two (`WoowDarkColors`
    /// and `WoowSheetDarkColors`); Mika's own settings pages use the first.
    enum Look { case app, sheet }
    private let phoneMidnight: Bool
    private let sheet: Bool
    init(_ scheme: ColorScheme, look: Look = .app) {
        dark = scheme == .dark
        sheet = look == .sheet
        phoneMidnight = scheme == .dark && look == .app && UIDevice.current.userInterfaceIdiom == .phone
    }
    var background: Color { dark ? (phoneMidnight ? rgb(20, 20, 20) : rgb(18, 18, 18)) : rgb(252, 252, 252) }
    var surface: Color { dark ? (phoneMidnight ? rgb(36, 36, 38) : rgb(31, 31, 31)) : (sheet ? .white : rgb(239, 239, 239)) }
    var ink: Color { dark ? rgb(245, 245, 245) : rgb(28, 28, 28) }
    var secondaryInk: Color { ink.opacity(dark ? 168.0 / 255 : 173.0 / 255) }
    /// Android ink3: hints and quiet glyphs.
    var hintInk: Color { ink.opacity(dark ? 145.0 / 255 : 166.0 / 255) }
    var accent: Color { dark ? rgb(127, 192, 255) : rgb(11, 105, 204) }
    var assistant: Color { surface }
    var glass: Color { dark ? (phoneMidnight ? rgb(44, 44, 46) : rgb(40, 40, 40)) : rgb(227, 227, 227) }
    var disabledControl: Color { glass }
    var hair: Color { dark ? (phoneMidnight ? rgb(58, 58, 60) : rgb(56, 56, 56)) : ink.opacity(61.0 / 255) }
    /// The 0.5 pt card edge and card dividers: ink at 9 % / 10 % in the sheets, 6 % / 12 % on the page.
    var edge: Color { ink.opacity(sheet ? (dark ? 23.0 / 255 : 26.0 / 255) : (dark ? 15.0 / 255 : 31.0 / 255)) }
    /// Android `hair.copy(alpha = .5f)` REPLACES the alpha: half of the opaque Midnight hairline, but ink at 50 % on Daylight
    /// (not 24 % x 50 %). Popover and dialog borders and the popover divider.
    var hair50: Color { dark ? hair.opacity(0.5) : ink.opacity(0.5) }
    /// The composer pill's 0.5 pt edge (`glassEdge`): the Midnight hairline, ink at 12 % on Daylight.
    var glassEdge: Color { dark ? hair : ink.opacity(31.0 / 255) }
    /// Popovers, menus and dialogs.
    var menu: Color { dark ? (phoneMidnight ? rgb(44, 44, 46) : rgb(31, 31, 31)) : .white }
    var inset: Color { dark ? (phoneMidnight ? rgb(28, 28, 30) : rgb(27, 27, 27)) : rgb(233, 233, 233) }
    var menuRadius: CGFloat { phoneMidnight ? 22 : 12 }
    /// Hover/selected fills on controls: tabs, picked tiles, segmented tracks.
    var raised: Color { dark ? (phoneMidnight ? rgb(58, 58, 60) : rgb(44, 44, 44)) : rgb(216, 216, 216) }
    var destructive: Color { dark ? rgb(255, 86, 103) : rgb(205, 40, 52) }
    var warn: Color { dark ? rgb(255, 179, 64) : rgb(184, 110, 0) }
    var ok: Color { dark ? rgb(56, 213, 145) : rgb(0, 122, 68) }
    /// Android Direct's user bubble: grey on Midnight, near-black on Daylight, with #F5F5F5 text.
    var userBubble: Color { dark ? rgb(90, 90, 90) : rgb(28, 28, 28) }
    var onUserBubble: Color { rgb(245, 245, 245) }
    #else
    init(_ scheme: ColorScheme) { dark = scheme == .dark }
    var background: Color { dark ? rgb(14, 14, 16) : rgb(247, 247, 248) }
    var surface: Color { dark ? rgb(26, 26, 29) : .white }
    var ink: Color { dark ? rgb(242, 242, 244) : rgb(28, 28, 30) }
    var secondaryInk: Color { dark ? rgb(164, 165, 173) : rgb(95, 96, 104) }
    var accent: Color { dark ? rgb(97, 131, 252) : rgb(64, 105, 251) }
    var assistant: Color { dark ? .white.opacity(13.0 / 255) : .black.opacity(9.0 / 255) }
    var glass: Color { surface.opacity(184.0 / 255) }
    var disabledControl: Color { rgb(118, 118, 128).opacity((dark ? 56.0 : 31.0) / 255) }
    var hair: Color { dark ? .white.opacity(20.0 / 255) : .black.opacity(18.0 / 255) }
    #endif
    var scrim: Color { .black.opacity(0.32) }
}

/// Selected routes match the existing iOS feature set; phone, Plans and remote
/// desktop control entries from Android are deliberately absent.
@MainActor
private struct MikaNavigationDrawer: View {
    let status: String
    @ObservedObject var session: ChatSession
    let canStartNew: Bool
    let palette: MikaVisualPalette
    let localizer: AppLocalizer
    let topInset: CGFloat
    let bottomInset: CGFloat
    /// The landscape notch side: the panel reaches the screen edge behind it.
    let leadingInset: CGFloat
    let onClose: () -> Void
    let onNew: () -> Void
    let onOpenRecent: (ArchivedConversation) -> Void
    let onSelect: (AppSection) -> Void
    @AccessibilityFocusState private var closeHasVoiceOverFocus: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(localizer.text(.shellBrandTitle)).scaledFont(size: 17, weight: .semibold)
                        .foregroundStyle(palette.ink)
                    Text(status).scaledFont(size: 12).foregroundStyle(palette.secondaryInk)
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
        .padding(.leading, leadingInset)
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
                Image(systemName: symbol).scaledFont(size: 22).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .frame(width: 22).foregroundStyle(palette.secondaryInk)
                Text(title).scaledFont(size: 15.5).foregroundStyle(palette.ink)
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

}

/// Holds the chat's follow policy where SwiftUI does not watch it. On the
/// iPhone (builds 230 and 232) a long chat with tables froze at full CPU, its
/// memory growing, when the policy was @State: each geometry report changed it,
/// which redrew the chat, whose new layout could report new geometry again.
@MainActor
private final class ChatScrollFollowBox {
    var policy = ChatScrollFollowPolicy()
    var pageBasis: ChatTranscriptPageBasis?
}

private struct ChatTranscriptLayout: Equatable {
    let basis: ChatTranscriptPageBasis
    let viewport: ChatTranscriptViewport
}

private struct ChatTranscriptViewportPreferenceKey: PreferenceKey {
    static var defaultValue: ChatTranscriptLayout? { nil }
    static func reduce(value: inout ChatTranscriptLayout?, nextValue: () -> ChatTranscriptLayout?) {
        value = nextValue() ?? value
    }
}

private struct ChatComposerHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    // Siblings without a measurement contribute zero; they must not erase
    // the composer's height. Reduction starts fresh when the composer shrinks.
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Only this subtree observes keystrokes; transcript layout does not.
@MainActor
private struct ChatDraftObserver<Content: View>: View {
    @ObservedObject var draft: ChatDraft
    let content: (Binding<String>) -> Content

    var body: some View { content($draft.text) }
}

@MainActor
private struct ChatView: View {
    @ObservedObject var session: ChatSession
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    /// Every chat may use the enabled servers; there is no switch per chat.
    let mcp: MCPServers
    @Binding var showsDrawer: Bool
    let localizer: AppLocalizer
    let openSettings: () -> Void
    /// 看看 under a learned-skill note (Play opens 待確認).
    var openPendingSkills: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var messageFontSize: CGFloat = 15.5
    @StateObject private var voice = ChatVoiceViewModel()
    #if DEBUG
    @ObservedObject private var voiceFixture = VoiceUITestFixture.shared
    #endif
    @FocusState private var isEditingDraft: Bool
    /// Refresh only an idle, empty editor when its text metrics change.
    @State private var idleComposerFieldID = UUID()
    @StateObject private var keyboardDock = ChatKeyboardDock()
    @State private var showsMCPResults = false
    /// Android's attach panel takes the keyboard's place under the input bar.
    @State private var showsAttachPanel = false
    @State private var attachPicker: ChatAttachPicker?
    @State private var showsCamera = false
    @State private var attachmentPreview: ChatAttachmentPreviewTarget?
    @State private var selectingText: ChatSelectTextTarget?
    @State private var reportTarget: AIResponseReportTarget?
    @State private var documentTarget: DocumentExportSource?
    @State private var createdFileDelivery: ChatCreatedFileDelivery?
    @State private var messageToast: ChatToast?
    /// The transcript's visible height; see blockedCardFitsTranscript.
    @State private var transcriptViewportHeight: CGFloat = 0
    @State private var scrollFollowBox = ChatScrollFollowBox()
    @State private var transcriptPage = ChatTranscriptPage()
    /// Whether the return-to-latest button shows (!followsTail): the only part
    /// of following that redraws the chat.
    @State private var showsReturnToLatest = false
    @State private var scrollToTailRequest = 0
    @State private var scrollSettleTask: Task<Void, Never>?
    @State private var scheduledSettleRevision: Int?
    @State private var measuredComposerHeight: CGFloat?
    private var palette: MikaVisualPalette { MikaVisualPalette(colorScheme) }
    private var webTaskColors: ChatWebTaskColors {
        ChatWebTaskColors(ink: palette.ink, secondaryInk: palette.secondaryInk, accent: palette.accent,
                          fill: palette.assistant, background: palette.background)
    }
    private var attachmentText: ChatAttachmentText { ChatAttachmentText(localizer: localizer) }
    private var menuText: ChatMessageMenuText { ChatMessageMenuText(localizer: localizer) }
    private var attachmentColors: ChatAttachmentColors {
        ChatAttachmentColors(ink: palette.ink, secondaryInk: palette.secondaryInk, accent: palette.accent,
                             surface: palette.surface, fill: palette.assistant, hair: palette.hair)
    }

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

    /// The follow policy, read without redrawing the chat.
    private var scrollFollow: ChatScrollFollowPolicy { scrollFollowBox.policy }

    private var transcriptRange: Range<Int> {
        transcriptPage.range(conversationID: session.conversationID, messageCount: session.entries.count)
    }

    private var transcriptBasis: ChatTranscriptPageBasis {
        transcriptPage.basis(conversationID: session.conversationID, messageCount: session.entries.count)
    }

    private var pageIncludesLatest: Bool { transcriptRange.upperBound == session.entries.count }

    private func pinTranscriptPage() {
        guard session.entries.count > ChatTranscriptPage.maximumMessages else { return }
        var page = transcriptPage
        page.pin(conversationID: session.conversationID, messageCount: session.entries.count)
        if page != transcriptPage { transcriptPage = page }
    }

    private func trackLatestPage() {
        var page = transcriptPage
        page.trackLatest(conversationID: session.conversationID)
        if page != transcriptPage { transcriptPage = page }
    }

    private func navigateTranscript(_ destination: ChatTranscriptPage.Destination) {
        cancelScrollSettle()
        transcriptPage.navigate(destination, conversationID: session.conversationID,
                                messageCount: session.entries.count)
        // The matching layout report applies the policy and anchor together.
        // Neither old-page geometry nor a delayed drag settle may scroll this page.
    }

    /// Changes the follow policy. Only a change of the return button redraws the
    /// chat: geometry arrives on every layout pass, and redrawing for each
    /// report let a long chat's layout and its reports feed each other.
    @discardableResult
    private func updateFollow<Result>(_ change: (inout ChatScrollFollowPolicy) -> Result) -> Result {
        let result = change(&scrollFollowBox.policy)
        let shows = !scrollFollowBox.policy.followsTail
        if shows { pinTranscriptPage() }
        if showsReturnToLatest != shows { showsReturnToLatest = shows }
        return result
    }

    private func cancelScrollSettle() {
        scrollSettleTask?.cancel()
        scrollSettleTask = nil
        scheduledSettleRevision = nil
    }

    /// Notices, the copying caption and the tray above the input bar (Android ChatScreen).
    @ViewBuilder private var attachmentRows: some View {
        if let notice = session.attachmentNotice {
            ChatAttachmentNoticeRow(notice: notice, colors: attachmentColors, text: attachmentText) { session.dismissAttachmentNotice() }
        }
        if session.isAddingAttachments {
            Text(verbatim: attachmentText.adding)
                .font(.caption).foregroundStyle(palette.secondaryInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("chat.attach.adding")
        }
        if !session.pendingAttachments.isEmpty {
            ChatAttachmentTray(items: session.pendingAttachments, store: session.attachmentStore,
                               colors: attachmentColors, text: attachmentText, canRemove: !session.isSubmitting,
                               onOpen: openAttachment, onRemove: { session.removeAttachment(id: $0) })
        }
    }

    private func toggleAttachPanel() {
        voice.cancel()
        // Like Android: × brings the keyboard back and the panel goes away.
        if showsAttachPanel { showsAttachPanel = false; isEditingDraft = true }
        else { isEditingDraft = false; showsAttachPanel = true }
    }

    #if WOOWTECHBOT
    /// Android Direct: the plus is its own 48-point circle on the card colour, beside the input bar rather than inside it.
    private var botAttachToggle: some View {
        Button(action: toggleAttachPanel) {
            Image(systemName: "plus").dynamicTypeSize(...Self.fixedControlTypeSize).foregroundStyle(palette.ink)
                .rotationEffect(.degrees(showsAttachPanel ? 45 : 0))
                .animation(.easeOut(duration: 0.2), value: showsAttachPanel)
                .frame(width: 48, height: 48).background(palette.surface, in: Circle()).contentShape(Circle())
        }
        .accessibilityLabel(showsAttachPanel ? attachmentText.close : attachmentText.add)
        .disabled(session.isSubmitting || session.isAddingAttachments)
        .accessibilityIdentifier("chat.attach.toggle")
    }
    #endif

    private var attachToggle: some View {
        Button(action: toggleAttachPanel) {
            Image(systemName: "plus").dynamicTypeSize(...Self.fixedControlTypeSize).frame(width: 40, height: 40)
                .rotationEffect(.degrees(showsAttachPanel ? 45 : 0))
                .animation(.easeOut(duration: 0.2), value: showsAttachPanel)
        }
        .accessibilityLabel(showsAttachPanel ? attachmentText.close : attachmentText.add)
        .disabled(session.isSubmitting || session.isAddingAttachments)
        .accessibilityIdentifier("chat.attach.toggle")
    }

    /// Android's attach panel takes the keyboard's place under the input bar.
    @ViewBuilder private var attachPanel: some View {
        if showsAttachPanel {
            ChatAttachPanel(colors: attachmentColors, text: attachmentText, onCamera: openCamera, onAlbum: openAlbum,
                            onFiles: { attachPicker = .files })
                .frame(height: 320)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// One transcript message, like Android's UserBubble: what it quoted on top,
    /// then attachments, then the bubble; attachments alone get no empty bubble.
    /// A long press opens the message menu (ChatMessageMenu).
    @ViewBuilder private func messageRow(index: Int, entry: ChatEntry, targets: ChatMessageActionTargets) -> some View {
        let shown = ChatAttachmentLines.displayText(entry.content, items: entry.attachments)
        // Only your own messages carry a quote; a reply that starts with the marker stays text.
        let parsed = ConversationQuote.parse(shown)
        let quote = entry.role == "user" ? parsed.quote : nil
        let words = quote == nil ? shown : parsed.words
        VStack(alignment: entry.role == "user" ? .trailing : .leading, spacing: 6) {
            if let quote { sentQuote(quote, index: index) }
            if !entry.attachments.isEmpty {
                ChatSentAttachments(items: entry.attachments, store: session.attachmentStore,
                                    colors: attachmentColors, text: attachmentText,
                                    identifier: "chat.message.\(index).attachments",
                                    onOpen: openAttachment)
            }
            // Attachments alone get no empty bubble.
            if !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || entry.attachments.isEmpty {
                messageBubble(index: index, entry: entry, words: words, targets: targets)
            }
            // The files this reply made (file_create), each waiting for the person.
            if let files = session.createdFiles[entry.id], !files.isEmpty {
                ChatCreatedFileCards(files: files, colors: attachmentColors, localizer: localizer,
                                     identifier: "chat.message.\(index).files",
                                     onPreview: previewCreatedFile,
                                     onSave: { deliverCreatedFile(.save($0)) },
                                     onShare: { deliverCreatedFile(.share($0)) },
                                     onRemove: { session.finishCreatedFile($0, as: .removed) })
            }
        }
        .frame(maxWidth: .infinity, alignment: entry.role == "user" ? .trailing : .leading)
        .id(entry.id)
    }

    private func sentQuote(_ quote: ConversationQuote.Quote, index: Int) -> some View {
        HStack {
            Spacer(minLength: 40)
            ChatSentQuote(quote: quote, colors: attachmentColors, label: menuText.quoting(quote))
                .accessibilityIdentifier("chat.message.\(index).quote")
        }
    }

    @ViewBuilder
    private func messageBubble(index: Int, entry: ChatEntry, words: String, targets: ChatMessageActionTargets) -> some View {
        if let outcome = entry.outcome, entry.role == "assistant" {
            ChatTurnOutcomeRow(outcome: outcome, reason: localizer.stored(entry.content), notDone: localizer.text(.chatTurnNotDone),
                               stopped: localizer.text(.chatTurnStopped), ink: palette.ink, secondary: palette.secondaryInk)
                .accessibilityIdentifier("chat.message.\(index).assistant")
        } else {
            answerOrQuestionBubble(index: index, entry: entry, words: words, targets: targets)
        }
    }

    private func answerOrQuestionBubble(index: Int, entry: ChatEntry, words: String,
                                        targets: ChatMessageActionTargets) -> some View {
        let user = entry.role == "user"
        let reply = user ? nil : ChatReplyMarkdown.parse(entry.content)
        let bubble = bubbleText(user: user, words: words, reply: reply)
            .font(.system(size: messageFontSize))
            .lineSpacing(user ? 1 : 4)
            #if WOOWTECHBOT
            .foregroundStyle(user ? palette.onUserBubble : palette.ink)
            #else
            .foregroundStyle(user ? Color.white : palette.ink)
            #endif
            .accessibilityIdentifier("chat.message.\(index).\(entry.role)")
            .padding(.horizontal, 14).padding(.vertical, user ? 10 : 12)
            #if WOOWTECHBOT
            // Android Direct: the assistant's answer fills the row (20 / 20 / 20 and 6 on the bottom-start corner); your own
            // message is a tail-less 18-point bubble at most 80 % of the row wide.
            .frame(maxWidth: user ? nil : .infinity, alignment: .leading)
            .background(user ? palette.userBubble : palette.assistant,
                        in: user ? AnyShape(RoundedRectangle(cornerRadius: 18))
                                 : AnyShape(UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 6,
                                                                   bottomTrailingRadius: 20, topTrailingRadius: 20)))
            #else
            .background(user ? palette.accent : palette.assistant, in: RoundedRectangle(cornerRadius: 20))
            #endif
            .modifier(ChatMessageMenu(entry: entry, targets: targets, text: menuText,
                                      perform: { perform($0, on: entry) }))
        #if WOOWTECHBOT
        return AnyView(user ? AnyView(BotFractionWidth(fraction: 0.8) { bubble }) : AnyView(bubble))
        #else
        return AnyView(HStack {
            if user { Spacer(minLength: 40) }
            bubble
            if !user { Spacer(minLength: 0) }
        })
        #endif
    }

    /// Like Android, a reply with a table or a code block lays them out as
    /// blocks; it stays one accessibility element with the whole reply.
    @ViewBuilder
    private func bubbleText(user: Bool, words: String, reply: ChatReplyMarkdown.Result?) -> some View {
        if let reply, reply.hasRichBlocks {
            ChatReplyBlocksView(blocks: reply.blocks, ink: palette.ink)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(reply.text))
                .accessibilityAddTraits(.isStaticText)
        } else {
            Text(user ? AttributedString(words) : reply?.text ?? AttributedString())
        }
    }

    private func perform(_ action: ChatMessageAction, on entry: ChatEntry) {
        switch action {
        case .copy:
            UIPasteboard.general.string = session.plainText(of: entry)
            showToast(menuText.copied)
        case .quote:
            guard let conversation = UUID(uuidString: session.conversationID),
                  session.selectQuote(messageID: entry.id, expectedContent: entry.content, in: conversation) else {
                showToast(menuText.quoteFailed); return
            }
        case .selectText:
            selectingText = ChatSelectTextTarget(text: session.plainText(of: entry))
        case .exportDocument:
            documentTarget = DocumentExportSource(content: entry.content)
        case .report:
            reportTarget = AIResponseReportTarget(
                reference: AIResponseReference(conversationID: session.conversationID, messageKey: entry.id.uuidString),
                response: session.plainText(of: entry))
        case .branch:
            if let toast = menuText.toast(for: session.branch(fromReply: entry.id, title: branchTitle)) { showToast(toast) }
        case .askAgain:
            if let toast = menuText.toast(for: session.askAgain(from: entry.id, title: branchTitle)) { showToast(toast) }
        }
    }

    /// The source's sidebar title without a quote, then " · 分支" (Android ChatCopy.branchTitle).
    private func branchTitle(_ record: ArchivedConversation) -> String {
        ChatBranchTitle.make(base: ConversationQuote.parse(ChatAttachmentLines.title(of: record, localizer: localizer)).words,
                             suffix: menuText.titleSuffix, fallback: localizer.text(.shellNewConversation))
    }

    private func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { messageToast = ChatToast(text: text) }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    private func openCamera() {
        guard ChatCameraPicker.isAvailable else { session.attachmentNotice = .cameraUnavailable; return }
        guard session.pendingAttachments.count < ChatAttachmentLimits.maximumCount else { session.attachmentNotice = .trayFull; return }
        showsCamera = true
    }

    private func openAlbum() {
        guard session.pendingAttachments.count < ChatAttachmentLimits.maximumCount else { session.attachmentNotice = .trayFull; return }
        attachPicker = .album
    }

    private func openAttachment(_ item: ChatAttachmentItem) {
        guard attachmentPreview == nil else { return }
        let url = session.attachmentStore.url(for: item)
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              FileManager.default.isReadableFile(atPath: url.path) else {
            session.attachmentNotice = .missing
            return
        }
        // Imports already live in the store. Opening and closing the modal must
        // leave the draft, pending items and stored bytes untouched.
        voice.cancel()
        isEditingDraft = false
        attachmentPreview = ChatAttachmentPreviewTarget(url: url)
    }

    /// Quick Look, as for attachments; a file the app already deleted says so on its card.
    private func previewCreatedFile(_ file: ChatCreatedFile) {
        guard attachmentPreview == nil, session.createdFileIsAvailable(file) else { return }
        voice.cancel()
        isEditingDraft = false
        attachmentPreview = ChatAttachmentPreviewTarget(url: file.url)
    }

    /// The system's save or share sheet for a created file; nothing leaves the app before it.
    private func deliverCreatedFile(_ target: ChatCreatedFileDelivery) {
        guard createdFileDelivery == nil, session.createdFileIsAvailable(target.file) else { return }
        voice.cancel()
        isEditingDraft = false
        createdFileDelivery = target
    }

    /// Keyboard and composer resizing, and a header row coming or going, can move UIKit's
    /// content offset without a reader gesture. Keep the existing follow intent until layout settles.
    private func composerLayoutChanged() {
        // VoiceOver can scroll without the drag events that cancel this grace
        // period. Preserve its existing conservative reading protection.
        guard !UIAccessibility.isVoiceOverRunning, pageIncludesLatest,
              !session.entries.isEmpty || session.replyPreview != nil || session.webTask != nil else { return }
        updateFollow { $0.beginLayoutTransition() }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-UITestTranscriptDiagnostics") {
            NSLog("%@", "TRANSCRIPT_LAYOUT pending=\(String(describing: scrollFollow.pendingSettleRevision)) following=\(scrollFollow.followsTail)")
        }
#endif
        scheduleScrollSettle()
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
            let settled = updateFollow { $0.settle(expectedRevision: revision) }
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-UITestTranscriptDiagnostics") {
                NSLog("%@", "TRANSCRIPT_SETTLE revision=\(revision) settled=\(settled) needs=\(scrollFollow.needsTailScroll) pending=\(String(describing: scrollFollow.pendingSettleRevision))")
            }
#endif
            if settled && scrollFollow.followsTail { trackLatestPage() }
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

    /// What the header rows show. A row that comes, goes or rewraps moves the transcript's top edge,
    /// and a chat pinned to its tail reads that as the reader scrolling away (native 281's keyboard
    /// did the same). So the view declares it as it does for the composer (composerLayoutChanged).
    /// Every row of chatHeader is here; LearningChatNotes declares its own.
    private struct HeaderRows: Equatable {
        var fixtureNotice = false, profileReceipt = false, memoryReceipt = false
        var unavailableServers: [String] = [], omittedTools = 0, mcpResults = 0
        var mcpActivity: String?, skillStep: String?
    }

    private var headerRows: HeaderRows {
        HeaderRows(fixtureNotice: session.isUITestMode,
                   profileReceipt: session.profileReceipt != nil, memoryReceipt: session.memoryReceipt != nil,
                   unavailableServers: session.mcpUnavailableServers, omittedTools: session.mcpOmitted,
                   mcpResults: session.mcpSteps.count, mcpActivity: session.mcpActivity,
                   skillStep: session.skillStep.map {
                       localizer.text($0 == .find ? .chatSkillFind : $0 == .read ? .chatSkillRead : .chatSkillSave)
                   })
    }

    /// Notes, MCP activity and receipts above the transcript.
    @ViewBuilder private var chatHeader: some View {
        if session.isUITestMode {
            Text(verbatim: localizer.text(.chatFixtureNotice))
                .font(.caption)
                .accessibilityIdentifier("uitest.banner")
        }

        LearningChatNotes(store: session.learning, openPendingSkills: openPendingSkills,
                          onLayoutChange: { composerLayoutChanged() })

        if !session.mcpUnavailableServers.isEmpty {
            // Like Android's task card note; the request went on with the other servers.
            Text(localizer.text(.chatMcpUnavailable(names: session.mcpUnavailableServers
                .map { $0.isEmpty ? localizer.text(.mcpServerDefaultName) : $0 }
                .joined(separator: localizer.text(.mcpNameSeparator)))))
                .font(.caption)
                .accessibilityIdentifier("chat.mcpUnavailable")
        }
        if session.mcpOmitted > 0 {
            Text(localizer.text(.chatMcpOmitted(count: session.mcpOmitted)))
                .font(.caption)
                .accessibilityIdentifier("chat.mcpOmitted")
        }
        if let activity = session.mcpActivity {
            Text(localizer.stored(activity)).font(.caption)
                .accessibilityIdentifier("chat.mcpActivity")
                .accessibilityValue(session.mcpDiagnostics ?? "")
        }
        if let step = session.skillStep {
            // Play's chat step line while a skill tool runs.
            Text(localizer.text(step == .find ? .chatSkillFind : step == .read ? .chatSkillRead : .chatSkillSave))
                .font(.caption).accessibilityIdentifier("chat.skillStep")
        }
        if session.profileReceipt != nil {
            Text(localizer.text(.chatReceiptProfile))
                .font(.caption).accessibilityIdentifier("chat.profileReceipt")
        }
        if session.memoryReceipt != nil {
            Text(localizer.text(.chatReceiptMemory))
                .font(.caption).accessibilityIdentifier("chat.memoryReceipt")
        }
        if !session.mcpSteps.isEmpty {
            Button(localizer.text(.chatMcpResultsView(count: session.mcpSteps.count))) { showsMCPResults = true }
                .font(.caption).accessibilityIdentifier("chat.mcpResults")
                .disabled(session.isSubmitting)
        }
    }

    /// Android's NeedCard for a send that cannot start: 知道了 closes it, 去設定 opens Settings.
    private var sendBlockedCard: some View {
        ChatSendBlockedCard(palette: palette, localizer: localizer,
                            dismiss: { session.dismissSendBlocker() },
                            openSettings: {
                                session.dismissSendBlocker()
                                isEditingDraft = false
                                openSettings()
                            })
    }

    /// Like Android, the card is the transcript's last item. On the physical iPad
    /// the transcript once collapsed to almost nothing; a card that would not fit
    /// shows above the input bar instead, so a blocked send is never silent.
    private var blockedCardFitsTranscript: Bool { pageIncludesLatest && transcriptViewportHeight >= 200 }

    private func transcriptContent(viewportHeight: Double) -> some View {
        // Which messages can be quoted or branched from, read once per render.
        let targets = session.messageActionTargets
        let range = transcriptRange
        let basis = transcriptBasis
        let rows = range.map { (offset: $0, element: session.entries[$0]) }
        return VStack(alignment: .leading, spacing: 16) {
            welcomeRows
            // A lazy history container can remeasure indefinitely when the keyboard
            // changes the viewport. On a physical iPad, the same eight-entry archive
            // (table and PDF/CSV attachments) froze before send at ~100% CPU; changing
            // only this container to VStack kept input and submission responsive.
            // Keep one ForEach identity domain, too: appending a turn must not move
            // existing messages between history/recent containers during tail layout.
            // Do not restore deferred layout here without the device regression.
            messageRows(rows[...], targets: targets)
            if range.upperBound == session.entries.count { tailRows }
        }
        .padding(.vertical, 4)
        .background {
            GeometryReader { content in
                Color.clear.preference(key: ChatTranscriptViewportPreferenceKey.self,
                    value: ChatTranscriptLayout(basis: basis, viewport: ChatTranscriptViewport(
                        // Whole points: a fraction of a point between two layout
                        // passes is not a change worth following.
                        contentHeight: Double(content.size.height).rounded(),
                        bottomY: Double(content.frame(in: .named("chat.transcript.viewport")).maxY).rounded(),
                        viewportHeight: viewportHeight.rounded())))
            }
        }
    }

    @ViewBuilder private var welcomeRows: some View {
        // Android hides the welcome while the blocked card is up.
        if session.entries.isEmpty && session.replyPreview == nil && session.webTask == nil && session.shownSendBlocker == nil {
            ChatEmptyState(draft: Binding(get: { session.draft }, set: { session.draft = $0 }), palette: palette, localizer: localizer)
        }
        if !session.hasStoredKey && session.shownSendBlocker == nil {
            Text(verbatim: localizer.text(.chatModelSetupHint))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("chat.explanation")
        }
    }

    @ViewBuilder private func messageRows(_ rows: ArraySlice<EnumeratedSequence<[ChatEntry]>.Element>,
                                          targets: ChatMessageActionTargets) -> some View {
        ForEach(rows, id: \.element.id) { index, entry in
            messageRow(index: index, entry: entry, targets: targets)
        }
    }

    /// What the working row says: a file being made, the vision model looking, or the plain wait.
    /// A file is not a header row: that row would move the whole transcript for the moment it takes.
    private var workingLabel: AppText {
        if session.creatingFile { return .chatFileCreating }
        return session.visionLooking ? .chatVisionLooking : .chatTurnWorking
    }

    @ViewBuilder private var tailRows: some View {
        if let preview = session.replyPreview {
            // Like Play's DraftText: the reply grows in place, without a status line.
            Text(ChatReplyMarkdown.render(preview.text, streaming: true))
                .font(.system(size: messageFontSize)).lineSpacing(4)
                .foregroundStyle(palette.ink).textSelection(.enabled)
                .accessibilityIdentifier("chat.partialReply")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(palette.assistant, in: RoundedRectangle(cornerRadius: 20))
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(preview.id)
        } else if session.isSubmitting, session.webTask == nil, let started = session.requestStartedAt {
            ChatWorkingRow(started: started, label: localizer.text(workingLabel),
                           tint: palette.accent,
                           ink: palette.ink, secondary: palette.secondaryInk)
        }
        if let task = session.webTask {
            ChatWebTaskCard(task: task, localizer: localizer, colors: webTaskColors, onStop: { session.cancel() })
                .id(task.id)
        }
        if session.shownSendBlocker != nil && blockedCardFitsTranscript {
            sendBlockedCard.padding(.top, 8).padding(.bottom, 12)
        }
        Color.clear.frame(height: 1).id("chat.transcript.tail")
    }

    private func transcriptScroll(proxy: ScrollViewProxy, viewportHeight: Double) -> some View {
        ScrollView {
            transcriptContent(viewportHeight: viewportHeight)
        }
        // The keyboard's inherited animation is for the composer. Animating
        // transcript scroll offsets at the same time can leave an earlier target
        // after a completed reply and look like an upward reader gesture.
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .coordinateSpace(name: "chat.transcript.viewport")
        .accessibilityIdentifier("chat.transcript")
        .contentShape(Rectangle())
        // A simultaneous drag observes scrolling without taking the long
        // press away from the message menu or the streaming reply's text.
        .simultaneousGesture(DragGesture(minimumDistance: 5)
            .onChanged { drag in
                guard pageIncludesLatest, scrollFollowBox.pageBasis == transcriptBasis else { return }
                // Do not evict the row under a finger when a reply completes.
                if session.entries.count > ChatTranscriptPage.maximumMessages { pinTranscriptPage() }
                updateFollow { $0.beginDrag() }
                if drag.translation.height > 4 { updateFollow { $0.userDraggedTowardEarlierContent() } }
                if drag.translation.height < -4 { updateFollow { $0.userDraggedTowardLatestContent() } }
            }
            .onEnded { _ in
                guard pageIncludesLatest, scrollFollowBox.pageBasis == transcriptBasis else { return }
                updateFollow { $0.endDrag() }
                scheduleScrollSettle()
            })
        .onPreferenceChange(ChatTranscriptViewportPreferenceKey.self) { layout in
            // An empty conversation is a browsable list, not a transcript
            // to pin to the tail. This also leaves VoiceOver scrolling alone.
            guard let layout, layout.basis == transcriptBasis else { return }
            let position = layout.viewport
            let hasTranscript = !session.entries.isEmpty || session.replyPreview != nil || session.webTask != nil
            if scrollFollowBox.pageBasis != layout.basis {
                let previous = scrollFollowBox.pageBasis
                let explicit = previous?.conversationID != layout.basis.conversationID
                    || previous?.requestRevision != layout.basis.requestRevision
                let landing = transcriptPage.landing(conversationID: session.conversationID)
                let follows = explicit ? landing == .tail : scrollFollow.followsTail
                cancelScrollSettle()
                scrollFollowBox.pageBasis = layout.basis
                updateFollow { $0.presentationChanged(to: hasTranscript ? position : nil, followsTail: follows) }
                if explicit, hasTranscript {
                    switch landing {
                    case .start:
                        if let index = transcriptRange.first { proxy.scrollTo(session.entries[index].id, anchor: .top) }
                    case .end:
                        if let index = transcriptRange.last { proxy.scrollTo(session.entries[index].id, anchor: .bottom) }
                    case .tail:
                        proxy.scrollTo("chat.transcript.tail", anchor: .bottom)
                    }
                } else if follows && pageIncludesLatest && hasTranscript {
                    proxy.scrollTo("chat.transcript.tail", anchor: .bottom)
                }
                return
            }
            // The end of an older page is not the transcript's tail. Its native
            // scrolling and VoiceOver browsing must never re-arm tail following.
            guard pageIncludesLatest else { return }
            let followed = scrollFollow.followsTail
            let shouldScroll = updateFollow { $0.observe(position, contentRevision: session.transcriptContentRevision, hasTranscript: hasTranscript) }
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-UITestTranscriptDiagnostics") {
                NSLog("%@", "TRANSCRIPT_TRACE revision=\(session.transcriptContentRevision) height=\(position.contentHeight) bottom=\(position.bottomY) viewport=\(position.viewportHeight) followed=\(followed) following=\(scrollFollow.followsTail) scroll=\(shouldScroll) submitting=\(session.isSubmitting)")
            }
#endif
            if shouldScroll {
                proxy.scrollTo("chat.transcript.tail", anchor: .bottom)
            }
            scheduleScrollSettle()
        }
        .onChange(of: session.conversationID) { _, _ in
            navigateTranscript(.latest)
        }
        .onChange(of: session.isSubmitting) { _, submitting in
            guard submitting else { return }
            navigateTranscript(.latest)
        }
        .onChange(of: scrollToTailRequest) { _, _ in
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-UITestTranscriptDiagnostics") {
                NSLog("%@", "TRANSCRIPT_REQUEST latest=\(pageIncludesLatest) basis=\(scrollFollowBox.pageBasis == transcriptBasis) canScroll=\(scrollFollow.canScrollToTail)")
            }
#endif
            guard pageIncludesLatest, scrollFollowBox.pageBasis == transcriptBasis,
                  scrollFollow.canScrollToTail else { return }
            proxy.scrollTo("chat.transcript.tail", anchor: .bottom)
        }
    }

    /// Reserve a separate row so the control cannot cover transcript text.
    /// The transcript measures its remaining viewport, excluding this row.
    @ViewBuilder private var returnToLatestControl: some View {
        // Paged histories already expose Latest above the viewport.
        if session.entries.count <= ChatTranscriptPage.maximumMessages,
           showsReturnToLatest && (!session.entries.isEmpty || session.replyPreview != nil || session.webTask != nil) {
            // Keep the compact-height fallback for landscape keyboard layouts.
            ViewThatFits(in: .vertical) {
                Button {
                    navigateTranscript(.latest)
                } label: {
                    Label(localizer.text(.shellReturnToLatest), systemImage: "arrow.down")
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                .accessibilityIdentifier("chat.returnToLatest")
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                Color.clear.frame(width: 0, height: 0).accessibilityHidden(true)
            }
        }
    }

    private func pageButton(_ destination: ChatTranscriptPage.Destination, text: AppText,
                            identifier: String, disabled: Bool) -> some View {
        Button(localizer.text(text)) { navigateTranscript(destination) }
            .font(.caption)
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(disabled)
            .accessibilityIdentifier(identifier)
    }

    private var transcriptNavigation: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                pageButton(.earliest, text: .chatHistoryEarliest, identifier: "chat.history.earliest",
                           disabled: transcriptRange.lowerBound == 0)
                pageButton(.earlier, text: .chatHistoryEarlier, identifier: "chat.history.earlier",
                           disabled: transcriptRange.lowerBound == 0)
                pageButton(.newer, text: .chatHistoryNewer, identifier: "chat.history.newer",
                           disabled: pageIncludesLatest)
                pageButton(.latest, text: .chatHistoryLatest, identifier: "chat.history.latest",
                           disabled: pageIncludesLatest && scrollFollow.followsTail)
            }
            Text(localizer.text(.chatHistoryRange(first: transcriptRange.lowerBound + 1,
                                                 last: transcriptRange.upperBound, total: session.entries.count)))
                .font(.caption2).foregroundStyle(palette.secondaryInk)
                .accessibilityIdentifier("chat.history.range")
        }
    }

    private var transcript: some View {
        VStack(spacing: 0) {
            if session.entries.count > ChatTranscriptPage.maximumMessages { transcriptNavigation }
            GeometryReader { viewport in
                ScrollViewReader { proxy in
                    transcriptScroll(proxy: proxy, viewportHeight: Double(viewport.size.height))
                }
                .onAppear { transcriptViewportHeight = viewport.size.height }
                .onChange(of: viewport.size.height) { _, height in transcriptViewportHeight = height }
            }
        }
        // Keep scrolling content inside the space assigned above the status and
        // composer, including while the keyboard or attachment panel moves them.
        .clipped()
        .overlay(alignment: .top) {
            if let messageToast {
                ChatToastView(toast: messageToast).padding(.top, 8).transition(.opacity)
            }
        }
    }

    /// The quote waiting to go with the next message (Android QuoteChip), above the tray.
    @ViewBuilder private var quoteChip: some View {
        if let quote = session.pendingQuote {
            ChatQuoteChip(quote: quote, colors: attachmentColors, text: menuText,
                          canRemove: !session.isSubmitting) { session.clearQuote() }
        }
    }

    /// Errors, notices, voice status and the send-blocked card above the composer.
    @ViewBuilder private var chatStatus: some View {
        chatStatusLines
            // At the largest sizes one notice took about a quarter of the screen (iPhone run
            // of 285); it stops at AX2 like the top bar and the welcome footer.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    @ViewBuilder private var chatStatusLines: some View {
        if let error = session.chatError {
            Text(session.chatErrorText.map { localizer.text($0) } ?? localizer.stored(error))
                .font(.callout)
                .foregroundStyle(.red)
                .accessibilityIdentifier("chat.error")
        }
        if let notice = session.chatNotice {
            Text(localizer.stored(notice))
                .font(.callout)
                .accessibilityIdentifier("chat.notice")
        }
        if let notice = session.archiveNotice {
            Text(localizer.stored(notice)).font(.callout).foregroundStyle(.orange)
                .accessibilityIdentifier("chat.archiveNotice")
            if session.canRetryArchiveSave {
                Button(localizer.text(.chatArchiveRetry)) { session.retryArchiveSave() }
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
        if session.shownSendBlocker != nil && !blockedCardFitsTranscript {
            sendBlockedCard
        }
    }

    /// The input bar's buttons keep 40 pt slots at every text size, like Play's
    /// fixed 40 dp IconButtons; their glyphs stop growing at the largest
    /// standard size so they stay inside the slots.
    private static let fixedControlTypeSize = DynamicTypeSize.xxxLarge

    /// Five lines, then the draft scrolls (Play's maxLines = 5). At the largest
    /// accessibility size five lines would make the input bar about 350 pt tall,
    /// over half of an iPhone SE screen and nearly all the room above its
    /// keyboard, so at accessibility sizes the draft scrolls after three.
    private func composer(draft: Binding<String>, availableHeight: CGFloat) -> some View {
        // With a docked keyboard in landscape, three accessibility-sized lines
        // can consume the whole viewport. Keep editing scrollable in one line.
        let lines = dynamicTypeSize.isAccessibilitySize ? (availableHeight < 400 ? 1...1 : 1...3) : 1...5
        // Same pill at one line; bounded corners leave room for multiline text.
        #if WOOWTECHBOT
        let shape = RoundedRectangle(cornerRadius: 27, style: .continuous)
        #else
        let shape = RoundedRectangle(cornerRadius: 32, style: .continuous)
        #endif
        let pill = HStack(alignment: .bottom, spacing: 4) {
            #if !WOOWTECHBOT
            attachToggle
            #endif
            // Return adds a line; the Done bar closes editing without sending.
            TextField(localizer.text(session.entries.isEmpty ? .shellMessagePlaceholder : .shellMessageContinuationPlaceholder),
                      text: draft, axis: .vertical)
                .id(idleComposerFieldID)
                .lineLimit(lines)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($isEditingDraft)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                .disabled(session.isSubmitting)
                .accessibilityLabel(localizer.text(.shellMessageDraft))
                .accessibilityIdentifier("chat.draft")
            #if WOOWTECHBOT
            // Android Direct: the mic shows when there is nothing to send (or while typing), a task shows stop, and the send
            // button exists only when there is something to send - both ink circles with page-coloured glyphs.
            if (session.draft.isEmpty && !session.isSubmitting) || isEditingDraft {
                ChatVoicePressControl(label: localizer.text(.voiceLabel), hint: localizer.text(.voiceHint),
                                      cancelLabel: localizer.text(.voiceAccessibilityCancel),
                                      active: voice.isActive, enabled: !session.isSubmitting,
                                      begin: { time in isEditingDraft = false; voice.begin(startedAt: time) },
                                      drag: { voice.drag($0) }, release: { voice.release() },
                                      cancel: { voice.cancel() })
                    .frame(width: 40, height: 40)
            }
            if session.isSubmitting {
                Button { session.cancel() } label: {
                    Image(systemName: "stop.fill").font(.system(size: 15, weight: .regular)).dynamicTypeSize(...Self.fixedControlTypeSize)
                        .foregroundStyle(palette.background).frame(width: 40, height: 40).background(palette.ink, in: Circle())
                }
                .accessibilityLabel(localizer.text(.shellStop))
                .accessibilityIdentifier("chat.cancel")
            }
            if session.canAttemptSend {
                Button {
                    voice.cancel()
                    isEditingDraft = false
                    showsAttachPanel = false
                    session.attemptSend(mcp: mcp)
                    if session.isSubmitting { navigateTranscript(.latest) }
                } label: {
                    Image(systemName: "arrow.up")
                        .scaledFont(size: 20, weight: .semibold).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(palette.background).frame(width: 40, height: 40).background(palette.ink, in: Circle())
                }
                .accessibilityLabel(localizer.text(.shellSend))
                .accessibilityIdentifier("chat.send")
            }
            #else
            ChatVoicePressControl(label: localizer.text(.voiceLabel), hint: localizer.text(.voiceHint),
                                  cancelLabel: localizer.text(.voiceAccessibilityCancel),
                                  active: voice.isActive, enabled: !session.isSubmitting,
                                  begin: { time in isEditingDraft = false; voice.begin(startedAt: time) },
                                  drag: { voice.drag($0) }, release: { voice.release() },
                                  cancel: { voice.cancel() })
                .frame(width: 40, height: 40)
            if session.isSubmitting {
                Button { session.cancel() } label: {
                    Image(systemName: "stop.fill").dynamicTypeSize(...Self.fixedControlTypeSize).frame(width: 40, height: 40)
                }
                .accessibilityLabel(localizer.text(.shellStop))
                .accessibilityIdentifier("chat.cancel")
            }
            Button {
                voice.cancel()
                isEditingDraft = false
                showsAttachPanel = false
                // Asking for a file in any words reaches the model, which makes it
                // with file_create; a reply's long-press menu still exports it.
                session.attemptSend(mcp: mcp)
                if session.isSubmitting {
                    // Only an accepted send restores follow.
                    navigateTranscript(.latest)
                }
            } label: {
                Image(systemName: "arrow.up")
                    .scaledFont(size: 20, weight: .semibold).dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(session.canAttemptSend ? Color.white : palette.secondaryInk)
                    .frame(width: 40, height: 40)
                    .background(session.canAttemptSend ? palette.accent : palette.disabledControl, in: Circle())
            }
            .disabled(!session.canAttemptSend)
            .accessibilityLabel(localizer.text(.shellSend))
            .accessibilityIdentifier("chat.send")
            #endif
        }
        .onChange(of: dynamicTypeSize) { _, _ in
            guard session.draft.isEmpty, !isEditingDraft else { return }
            idleComposerFieldID = UUID()
        }
        .frame(minHeight: 52)
        .layoutPriority(1)
        .padding(6)
        .background {
            if reduceTransparency {
                shape.fill(palette.surface)
            } else {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill(palette.glass))
            }
        }
        #if WOOWTECHBOT
        .overlay(shape.stroke(palette.glassEdge, lineWidth: 0.5))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.3), radius: 14, y: 4)
        #else
        .overlay(shape.stroke(palette.hair, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
        #endif
        #if WOOWTECHBOT
        return HStack(alignment: .bottom, spacing: 8) {
            botAttachToggle
            pill
        }
        #else
        return pill
        #endif
    }

    private var photoPickerLimit: Int { max(1, ChatAttachmentLimits.maximumCount - session.pendingAttachments.count) }

    private var composerContext: some View {
        VStack(spacing: 12) {
            chatStatus
            quoteChip
            attachmentRows
        }
    }

    @ViewBuilder private func composerContext(availableHeight: CGFloat) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            // Keep long notices reachable without pushing their dismiss action
            // above the navigation bar. The normal text size keeps its layout.
            MikaContentHeightLimit(maximumHeight: max(64, availableHeight * 0.35)) {
                ViewThatFits(in: .vertical) {
                    composerContext.fixedSize(horizontal: false, vertical: true)
                    ScrollView { composerContext }
                        .scrollBounceBehavior(.basedOnSize)
                        .accessibilityIdentifier("chat.composerContext")
                }
            }
        } else {
            composerContext
        }
    }

    private func chatColumn(availableHeight: CGFloat) -> some View {
        VStack(spacing: 12) {
            chatHeader
            VStack(spacing: 0) {
                transcript
                returnToLatestControl
            }
            VStack(spacing: 12) {
                composerContext(availableHeight: availableHeight)
                ChatDraftObserver(draft: session.draftModel) { draft in
                    composer(draft: draft, availableHeight: availableHeight)
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: ChatComposerHeightPreferenceKey.self, value: geometry.size.height)
                    }
                }
                attachPanel
                if isEditingDraft && !showsAttachPanel {
                    MikaKeyboardDoneBar(title: localizer.text(.commonDone),
                                        identifier: "chat.dismissKeyboard") { isEditingDraft = false }
                }
            }
            .layoutPriority(1)
            .background {
                LinearGradient(stops: [
                    .init(color: palette.background.opacity(0), location: 0),
                    .init(color: palette.background, location: 0.6),
                    .init(color: palette.background, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)
        .background(palette.background)
        .onPreferenceChange(ChatComposerHeightPreferenceKey.self) { height in
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-UITestTranscriptDiagnostics") {
                NSLog("%@", "TRANSCRIPT_COMPOSER height=\(height) previous=\(String(describing: measuredComposerHeight))")
            }
#endif
            guard height.isFinite, height > 0 else { return }
            let previous = measuredComposerHeight
            measuredComposerHeight = height
            if let previous, abs(height - previous) > 0.5 { composerLayoutChanged() }
        }
    }

    private var chatColumn: some View {
        GeometryReader { viewport in
            chatColumn(availableHeight: viewport.size.height)
        }
        // This app's own docked keyboard lifts the composer (see ChatKeyboardDock);
        // the attach panel takes the keyboard's place, so it drops that space at once.
        .chatKeyboardReserve(keyboardDock, replaced: showsAttachPanel)
    }

    /// The attach pickers, Quick Look and the review sheets.
    private var presentedChat: some View {
        chatColumn
            .modifier(ChatAttachPresentations(
                picker: $attachPicker, showsCamera: $showsCamera, preview: $attachmentPreview,
                photoLimit: photoPickerLimit,
                add: { files in Task { await session.addAttachments(files) } },
                loadingStarted: { session.attachmentsLoadingStarted() }))
            .modifier(ChatCreatedFilePresentations(delivery: $createdFileDelivery,
                                                   finish: { session.finishCreatedFile($0, as: $1) }))
            .onChange(of: isEditingDraft) { _, editing in
                if editing { showsAttachPanel = false }
                composerLayoutChanged()
#if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-UITestTranscriptDiagnostics") {
                    NSLog("%@", "TRANSCRIPT_FOCUS editing=\(editing) submitting=\(session.isSubmitting) following=\(scrollFollow.followsTail) entries=\(session.entries.count)")
                }
#endif
            }
            .onChange(of: keyboardDock.frameInWindow) { _, _ in composerLayoutChanged() }
            .onChange(of: headerRows) { _, _ in composerLayoutChanged() }
            .sheet(isPresented: $showsMCPResults) { MCPResultsView(steps: session.mcpSteps, owners: session.mcpStepOwners) }
            .sheet(item: $selectingText) { ChatSelectTextSheet(target: $0, text: menuText) }
            .sheet(item: $reportTarget) { AIResponseReportSheet(target: $0, delivery: AIResponseReportService.shared, localizer: localizer) }
            .sheet(item: $documentTarget) { DocumentExportView(source: $0, localizer: localizer) }
            // App Review 5.1.2(i): a main model set up before the consent existed asks before the first send.
            .sheet(item: Binding(get: { session.pendingSendConsent }, set: { _ in })) { prompt in
                ModelConsentSheet(prompt: prompt, localizer: localizer,
                                  agree: { session.resolveSendConsent(agreed: true) },
                                  decline: { session.resolveSendConsent(agreed: false) })
            }
    }

    var body: some View {
        presentedChat
            .onChange(of: showsDrawer) { _, visible in
                if visible { voice.cancel(); isEditingDraft = false }
            }
            .onChange(of: session.shownSendBlocker) { _, blocker in
                // VoiceOver users hear why the tap did not send.
                guard blocker != nil else { return }
                // Android scrolls to the card only while following the latest message.
                if scrollFollow.followsTail { scrollToTailRequest += 1 }
                UIAccessibility.post(notification: .announcement,
                                     argument: localizer.text(.chatSendBlockedTitle) + " " + localizer.text(.chatSendBlockedNoModel))
            }
            .task(id: messageToast?.id) {
                guard messageToast != nil else { return }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) { messageToast = nil }
            }
            .onAppear { voice.attach(session: session) }
            // Like Android's chat screen: reports waiting on this device are sent while the chat is shown.
            .task { await AIResponseReportService.shared.deliverDueWhileVisible() }
            .onDisappear { voice.cancel() }
            .onChange(of: session.conversationID) { _, _ in
                voice.cancel()
                // An explicit conversation reset owns disposal of unsent copies.
                // Do not leave its old URL presented in the new conversation.
                attachmentPreview = nil
            }
            .onChange(of: session.isSubmitting) { _, submitting in if submitting { voice.cancel() } }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { voice.cancel(interrupted: true) }
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

/// The Android store build's chat NeedCard for a send that cannot start:
/// a warning dot, title, what is missing, then 知道了 and 去設定, on the
/// card surface (white, 0.5 pt edge, 16 pt corners, a faint shadow in light
/// appearance only).
@MainActor
private struct ChatSendBlockedCard: View {
    let palette: MikaVisualPalette
    let localizer: AppLocalizer
    let dismiss: () -> Void
    let openSettings: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Color.orange).frame(width: 8, height: 8).accessibilityHidden(true)
                Text(verbatim: localizer.text(.chatSendBlockedTitle))
                    .scaledFont(size: 15, weight: .semibold).foregroundStyle(palette.ink)
            }
            Text(verbatim: localizer.text(.chatSendBlockedNoModel))
                .scaledFont(size: 14).foregroundStyle(palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            HStack(spacing: 8) {
                Button(action: dismiss) {
                    Text(verbatim: localizer.text(.chatSendBlockedDismiss)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("chat.sendBlocked.dismiss")
                Button(action: openSettings) {
                    Text(verbatim: localizer.text(.chatSendBlockedOpenSettings)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                .accessibilityIdentifier("chat.sendBlocked.openSettings")
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.hair, lineWidth: 0.5))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 6, y: 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.sendBlocked")
    }
}

@MainActor
private struct ChatEmptyState: View {
    @Binding var draft: String
    let palette: MikaVisualPalette
    let localizer: AppLocalizer

    // Store-flavor examples only fill the editable draft; they do not start a task.
    private var examples: [(text: AppText, icon: String, identifier: String)] {
        [(.shellReplyExample, "doc", "chat.emptyExample.reply"),
         (.shellNewsExample, "globe", "chat.emptyExample.news"),
         (.shellWebExample, "globe", "chat.emptyExample.web"),
         (.shellShoppingExample, "globe", "chat.emptyExample.shopping"),
         (.shellRememberExample, "doc", "chat.emptyExample.remember"),
         (.shellRecallExample, "doc", "chat.emptyExample.recall")]
    }

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
            Text(greeting).font(.title.bold())
                .foregroundStyle(palette.ink)
            Text(localizer.text(.shellWhatToDo))
                .font(.body).foregroundStyle(palette.secondaryInk)
                .padding(.top, 6)
            VStack(spacing: 0) {
                ForEach(Array(examples.enumerated()), id: \.offset) { index, example in
                    if index > 0 { Divider().padding(.leading, 52) }
                    Button {
                        draft = localizer.text(example.text)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: example.icon).scaledFont(size: 22)
                                .foregroundStyle(palette.secondaryInk)
                                .accessibilityHidden(true)
                            Text(localizer.text(example.text))
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundStyle(palette.ink)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(example.identifier)
                }
            }
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(palette.hair, lineWidth: 0.5))
            .padding(.top, 28)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8).padding(.top, 52)
    }
}

@MainActor
private struct LearningChatNotes: View {
    @ObservedObject var store: LearningStore
    var openPendingSkills: () -> Void = {}
    /// A note came, went or rewrapped: that moves the transcript's top edge (ContentView.HeaderRows).
    var onLayoutChange: () -> Void = {}
    @Environment(\.appLocalizer) private var localizer

    /// What the rows show, with whether a memory note has its buttons.
    private struct Rows: Equatable {
        var learning = false
        var notice: String?, error: String?
        var memoryNotes: [String] = [], skillNotes: [String] = []
    }

    private var rows: Rows {
        Rows(learning: store.isLearning, notice: store.notice, error: store.error,
             memoryNotes: store.notes.map { "\(store.noteText($0, localizer: localizer))|\(store.canReviewMemory($0))|\($0.undoToken != nil)" },
             skillNotes: store.skillNotes.map { skillNoteText($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.isLearning {
                Text(localizer.text(.chatLearningOrganizing))
                    .font(.caption).accessibilityIdentifier("chat.learning")
            }
            if let notice = store.notice {
                Text(localizer.stored(notice)).font(.caption).accessibilityIdentifier("chat.learningNotice")
            }
            if let error = store.error {
                Text(localizer.stored(error)).font(.caption).foregroundStyle(.orange)
                    .accessibilityIdentifier("chat.learningError")
            }
            ForEach(Array(store.notes.enumerated()), id: \.element.memoryID) { index, note in
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.noteText(note, localizer: localizer)).font(.caption)
                        .accessibilityIdentifier("chat.memoryNote.\(index)")
                    HStack {
                        if store.canReviewMemory(note) {
                            Button(localizer.text(.chatMemoryApprove)) { store.approvePendingMemory(note) }
                                .accessibilityIdentifier("chat.approveMemory.\(index)")
                            Button(localizer.text(.chatMemoryReject)) { store.rejectPendingMemory(note) }
                                .accessibilityIdentifier("chat.rejectMemory.\(index)")
                        }
                        if note.undoToken != nil {
                            Button(localizer.text(.chatMemoryUndo)) { store.undo(note) }
                                .accessibilityIdentifier("chat.undoMemory.\(index)")
                        }
                    }
                    .font(.caption)
                }
            }
            ForEach(Array(store.skillNotes.enumerated()), id: \.element.id) { index, note in
                HStack(spacing: 8) {
                    Text(skillNoteText(note)).font(.caption)
                        .accessibilityIdentifier("chat.skillNote.\(index)")
                    if case .learned = note.kind {
                        Button(localizer.text(.chatSkillNoteView)) { openPendingSkills() }
                            .font(.caption)
                            .accessibilityIdentifier("chat.skillNote.view.\(index)")
                    }
                }
            }
        }
        .onChange(of: rows) { _, _ in onLayoutChange() }
    }

    private func skillNoteText(_ note: ChatSkillNote) -> String {
        switch note.kind {
        case .learned(_, let description): return localizer.text(.chatSkillNoteLearned(description: description))
        case .verified(let name): return localizer.text(.chatSkillNoteVerified(name: name))
        case .suspended: return localizer.text(.chatSkillNoteSuspended)
        }
    }
}

/// The Play build's work row under a question still on its way: a spinner,
/// 正在處理 and the time since it was sent ("0:24").
private struct ChatWorkingRow: View {
    let started: Date
    let label: String
    let tint: Color
    let ink: Color
    let secondary: Color

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(tint)
            Text(verbatim: label).font(.callout).foregroundStyle(ink)
            Spacer(minLength: 8)
            TimelineView(.periodic(from: started, by: 1)) { context in
                Text(verbatim: Self.clock(context.date.timeIntervalSince(started)))
                    .font(.caption.monospacedDigit()).foregroundStyle(secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("chat.working")
    }

    /// Play's ChatCopy.clock: 0:24, 12:05, 1:02:03.
    static func clock(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        let hours = seconds / 3600, minutes = seconds % 3600 / 60, rest = seconds % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }
}

/// A turn without an answer, as the Play build shows it: a red dot with 沒有完成
/// and the reason under it, or 已停止。
private struct ChatTurnOutcomeRow: View {
    let outcome: ArchivedConversationTurn.Outcome
    let reason: String
    let notDone: String
    let stopped: String
    let ink: Color
    let secondary: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch outcome {
            case .failed:
                HStack(spacing: 8) {
                    Circle().fill(Color.red).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text(verbatim: notDone).font(.body.weight(.semibold)).foregroundStyle(ink)
                }
                Text(verbatim: reason).font(.callout).foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .cancelled:
                Text(verbatim: stopped).font(.body).foregroundStyle(secondary)
            }
        }
        .padding(.horizontal, 2).padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: outcome == .failed ? notDone + "\n" + reason : stopped))
        .accessibilityAddTraits(.isStaticText)
    }
}
