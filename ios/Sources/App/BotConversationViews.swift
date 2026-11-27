#if WOOWTECHBOT
import AssistantPersistence
import ImageIO
import PhotosUI
import SwiftUI

enum BotLocalDestination { case tools, memory, browser, settings, about, files, notifications }

struct BotConversationList: View {
    @ObservedObject var chat: ChatSession
    @ObservedObject var archive: ConversationArchiveStore
    @ObservedObject var workspace: BotWorkspaceStore
    let localizer: AppLocalizer
    let close: () -> Void
    let new: () -> Void
    let select: (BotLocalDestination) -> Void
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @State private var showsServices = false
    @State private var editID: String?
    @State private var deleteID: UUID?
    @Environment(\.colorScheme) private var colorScheme
    private var palette: MikaVisualPalette { .init(colorScheme) }
    private func t(_ zh: String, _ en: String) -> String { localizer.language == .english ? en : zh }
    private var records: [ArchivedConversation] {
        archive.drawerConversations.filter { row in
            search.isEmpty || row.title.localizedCaseInsensitiveContains(search) ||
                row.turns.contains { $0.userText.localizedCaseInsensitiveContains(search) || $0.assistantText.localizedCaseInsensitiveContains(search) }
        }
    }
    private var drafts: [String] {
        workspace.state.chats.keys.filter { id in
            !archive.conversations.contains { $0.id.uuidString == id } &&
            (id == chat.conversationID || workspace.presentation(id).hasSavedContent) &&
            (search.isEmpty || workspace.presentation(id).draft.localizedCaseInsensitiveContains(search) ||
                workspace.presentation(id).title?.localizedCaseInsensitiveContains(search) == true)
        }.sorted { workspace.presentation($0).updatedAt > workspace.presentation($1).updatedAt }
    }

    var body: some View {
        NavigationStack {
          VStack(spacing: 0) {
            header
            searchHeader
            List {
                if !archive.available {
                    Text(t("對話暫時無法讀取，原檔保留。", "Conversations cannot be read yet; the original file is preserved."))
                    Button(t("重新讀取", "Reload")) { archive.reload() }
                }
                if chat.entries.isEmpty && !drafts.contains(chat.conversationID) && search.isEmpty {
                    draftRow(chat.conversationID)
                }
                ForEach(drafts, id: \.self, content: draftRow)
                ForEach(records) { record in
                    Button {
                        if chat.switchBotConversation(to: record.id, workspace: workspace) { close() }
                    } label: { row(title: record.title, id: record.id.uuidString,
                        excerpt: workspace.presentation(record.id.uuidString).draft.isEmpty ? record.turns.last?.assistantText ?? "" : t("草稿：", "Draft: ") + workspace.presentation(record.id.uuidString).draft,
                        date: record.updatedAt, pinned: record.pinnedAt != nil) }
                    .buttonStyle(.plain).accessibilityIdentifier("bot.chat.\(record.id)")
                    .contextMenu {
                        Button(t("名稱與圖示", "Name & icon"), systemImage: "pencil") { editID = record.id.uuidString }
                        Button(record.pinnedAt == nil ? t("置頂", "Pin") : t("取消置頂", "Unpin"), systemImage: "pin") {
                            do { try archive.setPinned(id: record.id, expectedPinnedAt: record.pinnedAt, pinned: record.pinnedAt == nil) }
                            catch { workspace.notice = .changesUnsaved }
                        }
                        Button(t("刪除對話", "Delete conversation"), systemImage: "trash", role: .destructive) { deleteID = record.id }
                    }
                }
                if records.isEmpty && drafts.isEmpty && !search.isEmpty { Text(t("沒有符合的對話", "No matching conversations")) }
            }
            .listStyle(.plain).scrollContentBackground(.hidden).background(palette.background)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 12) {
                    Menu {
                        tool("MCP", "MCP", "wrench.and.screwdriver", .tools)
                        tool("記憶／技能", "Memory / skills", "brain", .memory)
                        tool("瀏覽器", "Browser", "globe", .browser)
                        tool("檔案", "Files", "folder", .files)
                        tool("關於", "About", "info.circle", .about)
                    } label: { BotRoundIcon(symbol: "square.grid.2x2") }
                    .accessibilityLabel(t("快捷功能", "Shortcuts"))
                    .accessibilityIdentifier("bot.history.shortcuts")
                    Text(localizer.text(chat.chatStatusMessage == .chatStatusUnconfigured ? .chatSendBlockedTitle : .drawerStatusReady))
                        .font(.caption).foregroundStyle(palette.secondaryInk).lineLimit(1)
                    Spacer(minLength: 0)
                }.padding(.horizontal, 16).padding(.vertical, 8).background(palette.background)
            }
            .sheet(isPresented: $showsServices) {
                BotServicesView(workspace: workspace, localizer: localizer) { id in
                    showsServices = false
                    Task { try? await Task.sleep(for: .milliseconds(350)); workspace.selectedService = id }
                }
            }
            .sheet(isPresented: Binding(get: { editID != nil }, set: { if !$0 { editID = nil } })) {
                if let editID { BotConversationEditor(id: editID, archive: archive, workspace: workspace, localizer: localizer) }
            }
            .alert(t("刪除這段對話？", "Delete this conversation?"), isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } })) {
                Button(t("刪除", "Delete"), role: .destructive) {
                    if let id = deleteID { _ = chat.deleteBotConversation(id, workspace: workspace) }
                    deleteID = nil
                }
                Button(t("取消", "Cancel"), role: .cancel) { deleteID = nil }
            }
          }
          .toolbar(.hidden, for: .navigationBar)
          .background(palette.background)
          .tint(palette.accent)
        }
        .accessibilityIdentifier("bot.history")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { select(.settings) } label: { BotRoundIcon(symbol: "gearshape") }
                .accessibilityLabel(t("設定", "Settings")).accessibilityIdentifier("bot.history.settings")
            Menu {
                Button(t("本機助理", "Local assistant"), systemImage: "iphone", action: close)
                ForEach(workspace.services.filter(\.enabled)) { service in
                    Button(service.name, systemImage: "server.rack") { workspace.selectedService = service.id }
                }
                Button(t("管理服務", "Manage services"), systemImage: "slider.horizontal.3") { showsServices = true }
            } label: { BotRoundIcon(symbol: "arrow.left.arrow.right") }
            .accessibilityLabel(t("服務", "Services")).accessibilityIdentifier("bot.serviceSwitcher")
            Spacer(minLength: 8)
            Button { select(.notifications) } label: { BotRoundIcon(symbol: "bell") }
                .accessibilityLabel(t("通知", "Notifications")).accessibilityIdentifier("bot.history.notifications")
            Button(action: new) { BotRoundIcon(symbol: "plus") }
                .disabled(chat.isSubmitting).opacity(chat.isSubmitting ? 0.45 : 1)
                .accessibilityLabel(t("新增對話", "New conversation")).accessibilityIdentifier("bot.history.new")
        }.buttonStyle(.plain).padding(.horizontal, 16).frame(height: 64)
    }
    private var searchHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Text(t("對話", "Conversations")).font(.headline)
                Spacer()
                Button(t("返回對話", "Back to chat"), action: close).font(.subheadline)
                    .accessibilityIdentifier("bot.history.back")
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(palette.secondaryInk)
                TextField(t("搜尋名稱或訊息", "Search names or messages"), text: $search)
                    .focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }
                    .accessibilityIdentifier("bot.history.search")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel(t("清除搜尋", "Clear search"))
                }
            }.padding(12).background(palette.surface, in: RoundedRectangle(cornerRadius: 18))
        }.padding(.horizontal, 20).padding(.bottom, 8).foregroundStyle(palette.ink)
    }

    private func draftRow(_ id: String) -> some View {
        Button {
            if chat.switchBotConversation(to: UUID(uuidString: id), workspace: workspace) { close() }
        } label: { row(title: workspace.presentation(id).title ?? t("新對話", "New conversation"), id: id,
                      excerpt: id == chat.conversationID ? chat.draft : workspace.presentation(id).draft,
                      date: workspace.presentation(id).updatedAt, pinned: false) }
            .buttonStyle(.plain).accessibilityIdentifier("bot.draft.\(id)")
            .contextMenu {
                Button(t("名稱與圖示", "Name & icon"), systemImage: "pencil") { editID = id }
                Button(t("刪除草稿", "Delete draft"), systemImage: "trash", role: .destructive) { deleteID = UUID(uuidString: id) }
            }
    }
    private func row(title: String, id: String, excerpt: String, date: Date, pinned: Bool) -> some View {
        HStack(spacing: 12) {
            BotAvatar(avatar: workspace.presentation(id).avatar).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(title).font(.headline).lineLimit(1)
                    if pinned { Image(systemName: "pin.fill").font(.caption).accessibilityLabel(t("已置頂", "Pinned")) }
                    Spacer()
                    Text(date, style: .date).font(.caption2).foregroundStyle(.secondary)
                }
                Text(excerpt.isEmpty ? t("尚未傳送訊息", "No messages yet") : excerpt)
                    .lineLimit(1).font(.subheadline).foregroundStyle(palette.secondaryInk)
            }
        }.padding(10).foregroundStyle(palette.ink)
            .background(id == chat.conversationID ? palette.glass : .clear, in: RoundedRectangle(cornerRadius: 24))
            .contentShape(Rectangle())
            .accessibilityAddTraits(id == chat.conversationID ? .isSelected : [])
    }
    private func tool(_ zh: String, _ en: String, _ icon: String, _ destination: BotLocalDestination) -> some View {
        Button { select(destination) } label: {
            Label(t(zh, en), systemImage: icon)
        }.accessibilityIdentifier("bot.tool.\(destination)")
    }
}

struct BotRoundIcon: View {
    let symbol: String
    @Environment(\.colorScheme) private var scheme
    private var palette: MikaVisualPalette { .init(scheme) }
    var body: some View {
        Image(systemName: symbol).font(.system(size: 19, weight: .regular))
            .foregroundStyle(palette.ink).frame(width: 42, height: 42)
            .background(palette.surface, in: Circle())
            .overlay(Circle().strokeBorder(palette.hair, lineWidth: 0.7))
            .frame(width: 48, height: 48).contentShape(Circle())
            .accessibilityHidden(true)
    }
}

struct BotAvatar: View {
    let avatar: BotConversationAvatar
    static let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan]
    var body: some View {
        GeometryReader { proxy in
            if let data = avatar.jpeg, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipShape(Circle())
            } else {
                let size = proxy.size.width
                ZStack {
                    Circle().fill(Self.colors[avatar.color])
                    Capsule().fill(.white).frame(width: size * 0.045, height: size * 0.16).offset(y: -size * 0.24)
                    Circle().fill(.white).frame(width: size * 0.075, height: size * 0.075).offset(y: -size * 0.33)
                    if avatar.robot == 0 {
                        RoundedRectangle(cornerRadius: size * 0.035).fill(.white)
                            .frame(width: size * 0.74, height: size * 0.16).offset(y: size * 0.04)
                    }
                    RoundedRectangle(cornerRadius: size * [0.14, 0.06, 0.30][avatar.robot])
                        .fill(.white).frame(width: size * 0.60, height: size * 0.49).offset(y: size * 0.035)
                    HStack(spacing: size * 0.12) {
                        Circle().frame(width: size * 0.085, height: size * 0.085)
                        if avatar.face == 1 { Capsule().frame(width: size * 0.10, height: size * 0.04) }
                        else { Circle().frame(width: size * 0.085, height: size * 0.085) }
                    }.foregroundStyle(Self.colors[avatar.color]).offset(y: -size * 0.015)
                    if avatar.face == 2 {
                        Circle().fill(Self.colors[avatar.color]).frame(width: size * 0.075, height: size * 0.075).offset(y: size * 0.13)
                    } else {
                        Path { path in
                            path.move(to: CGPoint(x: size * 0.41, y: size * 0.61))
                            path.addQuadCurve(to: CGPoint(x: size * 0.59, y: size * 0.61), control: CGPoint(x: size * 0.50, y: size * 0.74))
                        }.stroke(Self.colors[avatar.color], style: StrokeStyle(lineWidth: max(1, size * 0.035), lineCap: .round))
                    }
                }
            }
        }.accessibilityHidden(true)
    }
}

struct BotConversationEditor: View {
    let id: String
    @ObservedObject var archive: ConversationArchiveStore
    @ObservedObject var workspace: BotWorkspaceStore
    let localizer: AppLocalizer
    @State private var title = ""
    @State private var avatar = BotConversationAvatar()
    @State private var photo: PhotosPickerItem?
    @State private var importing = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    private func t(_ zh: String, _ en: String) -> String { localizer.language == .english ? en : zh }
    var body: some View {
        NavigationStack {
            Form {
                Section { HStack { Spacer(); BotAvatar(avatar: avatar).frame(width: 96, height: 96); Spacer() } }
                TextField(t("對話名稱", "Conversation name"), text: $title).accessibilityIdentifier("bot.edit.name")
                Section(t("圖示", "Icon")) {
                    Picker(t("樣式", "Style"), selection: $avatar.robot) { ForEach(0..<3) { Text("\($0 + 1)").tag($0) } }.pickerStyle(.segmented)
                    HStack {
                        ForEach(0..<6) { color in
                            Button { avatar.color = color } label: {
                                Circle().fill(BotAvatar.colors[color]).frame(width: 30, height: 30)
                                    .padding(4).overlay(Circle().stroke(avatar.color == color ? Color.primary : .clear, lineWidth: 2))
                            }.buttonStyle(.plain).frame(maxWidth: .infinity)
                                .accessibilityLabel(localizer.language == .english ? ["Blue", "Green", "Orange", "Purple", "Pink", "Cyan"][color] : ["藍色", "綠色", "橘色", "紫色", "粉紅色", "青色"][color])
                                .accessibilityValue(avatar.color == color ? t("已選擇", "Selected") : "")
                                .accessibilityIdentifier("bot.edit.color.\(color)")
                        }
                    }
                    Picker(t("表情", "Expression"), selection: $avatar.face) {
                        ForEach(0..<3) { Text(localizer.language == .english ? ["Smile", "Wink", "Surprised"][$0] : ["微笑", "眨眼", "驚訝"][$0]).tag($0) }
                    }.pickerStyle(.segmented)
                    PhotosPicker(t("選擇照片", "Choose photo"), selection: $photo, matching: .images)
                    if avatar.jpeg != nil { Button(t("使用內建圖示", "Use built-in icon")) { avatar.jpeg = nil } }
                    Text(t("照片會裁成正方形，只用於這段對話。", "Photos are cropped to a square and used only for this conversation."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(t("名稱與圖示", "Name & icon")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("取消", "Cancel")) { dismiss() }.accessibilityIdentifier("bot.edit.cancel") }
                ToolbarItem(placement: .confirmationAction) { Button(t("儲存", "Save"), action: save).disabled(importing).accessibilityIdentifier("bot.edit.save") }
            }
            .onAppear {
                let row = archive.conversations.first { $0.id.uuidString == id }
                title = row?.title ?? workspace.presentation(id).title ?? ""
                avatar = workspace.presentation(id).avatar
            }
            .task(id: photo) {
                guard let photo else { return }; importing = true
                defer { importing = false }
                do {
                    guard let bytes = try await photo.loadTransferable(type: Data.self), !Task.isCancelled,
                          let image = Self.thumbnail(bytes) else { return }
                    avatar.jpeg = image
                } catch { self.error = t("無法讀取這張照片，原圖示保留。", "Could not read this photo. The original icon is preserved.") }
            }
        }
    }
    private func save() {
        guard let normalized = ConversationArchive.normalizedTitle(title) else {
            error = t("請填寫有效的對話名稱。", "Enter a valid conversation name."); return
        }
        do {
            if let row = archive.conversations.first(where: { $0.id.uuidString == id }) {
                try archive.rename(id: row.id, expectedTitle: row.customTitle, to: normalized)
            }
            try workspace.savePresentation(id, title: normalized, avatar: avatar)
            dismiss()
        } catch { self.error = t("變更尚未完整保存，請重試。", "Changes were not fully saved. Try again.") }
    }
    private static func thumbnail(_ data: Data) -> Data? {
        guard data.count <= 30_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 640, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg), side = min(image.size.width, image.size.height)
        guard side > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let result = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 320), format: format).image { context in
            UIColor.systemBackground.setFill(); context.fill(CGRect(x: 0, y: 0, width: 320, height: 320))
            let factor = 320 / side
            image.draw(in: CGRect(x: (320 - image.size.width * factor) / 2, y: (320 - image.size.height * factor) / 2,
                                  width: image.size.width * factor, height: image.size.height * factor))
        }
        return result.jpegData(compressionQuality: 0.75)
    }
}
#endif
