#if WOOWTECHBOT
import AssistantPersistence
import SwiftUI

enum BotLocalDestination { case tools, memory, browser, settings, about, files, notifications }

/// Android `conversationTime`: today as a clock time, yesterday by name, within a week the weekday, this year month and
/// day, earlier with the year.
enum BotTime {
    /// Always the Gregorian calendar, as Android's java.time (a device set to another calendar keeps 2026, not 115).
    static let gregorian: Calendar = { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current; return calendar }()
    static func conversation(_ date: Date, now: Date = Date(), english: Bool, calendar: Calendar = BotTime.gregorian) -> String {
        let locale = Locale(identifier: english ? "en_US" : "zh_Hant_TW")
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let formatter = DateFormatter()
        formatter.locale = locale; formatter.calendar = calendar
        switch days {
        case ...0: return String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        case 1: return english ? "Yesterday" : "昨天"
        case 2..<7: formatter.setLocalizedDateFormatFromTemplate("EEE"); return formatter.string(from: date)
        default:
            let sameYear = calendar.component(.year, from: now) == parts.year
            let month = formatter.shortMonthSymbols[(parts.month ?? 1) - 1]
            if english { return sameYear ? "\(month) \(parts.day ?? 1)" : "\(month) \(parts.day ?? 1), \(parts.year ?? 0)" }
            return sameYear ? "\(parts.month ?? 1) 月 \(parts.day ?? 1) 日" : "\(parts.year ?? 0) 年 \(parts.month ?? 1) 月 \(parts.day ?? 1) 日"
        }
    }
}

private enum BotHistoryPopover: BotPopoverID {
    case account, new, shortcuts
    case row(String)
    var anchorID: String {
        switch self {
        case .account: return "history.account"
        case .new: return "history.new"
        case .shortcuts: return "history.shortcuts"
        case .row(let id): return "history.row.\(id)"
        }
    }
    var placement: BotPopoverPlacement {
        switch self {
        case .account: return .belowLeading
        case .new, .row: return .belowTrailing
        case .shortcuts: return .aboveLeading
        }
    }
}

private struct BotServicesRequest: Identifiable {
    let id = UUID()
    let adding: Bool
}

private struct BotHistoryRow: Identifiable {
    let id: String
    let title: String
    let excerpt: String
    let date: Date
    let pinnedAt: Date?
    let record: ArchivedConversation?
    /// The open conversation before anything is saved: a selected-looking row with only its title (no time, preview or "…").
    var isCurrentUnsaved = false
}

/// Android `BotUiHistoryHost`: four round controls on top, the title row, the conversations, and the shortcuts button with
/// the search pill at the bottom. Menus are popovers, switching and notifications are bottom sheets, deletion is a dialog.
struct BotConversationList: View {
    @ObservedObject var chat: ChatSession
    @ObservedObject var archive: ConversationArchiveStore
    @ObservedObject var workspace: BotWorkspaceStore
    let localizer: AppLocalizer
    let close: () -> Void
    let new: () -> Void
    let select: (BotLocalDestination) -> Void
    /// Kept by the caller, as Android's rememberSaveable query and list state: closing and reopening the history keeps both.
    @Binding var search: String
    @Binding var scrollID: String?
    @FocusState private var searchFocused: Bool
    @State private var servicesRequest: BotServicesRequest?
    @State private var popover: BotHistoryPopover?
    @State private var editID: String?
    @State private var deleteID: UUID?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var palette: MikaVisualPalette { .init(colorScheme) }
    private var english: Bool { localizer.language == .english }
    private func t(_ zh: String, _ en: String) -> String { english ? en : zh }

    /// Android trims the query; blank is no search.
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// Saved chats whose name or messages match (Android: the title and every text of the conversation).
    private var records: [ArchivedConversation] {
        archive.drawerConversations.filter { row in
            query.isEmpty || row.title.localizedCaseInsensitiveContains(query) ||
                row.turns.contains { $0.userText.localizedCaseInsensitiveContains(query) || $0.assistantText.localizedCaseInsensitiveContains(query) }
        }
    }
    private func draftText(_ id: String) -> String { id == chat.conversationID ? chat.draft : workspace.presentation(id).draft }
    /// Android: unsaved chats with words typed, a name, or attachments or a quote left waiting (also a custom icon here).
    private var drafts: [String] {
        let parked = chat.parkedBotConversationIDs
        return Set(workspace.state.chats.keys).union(parked).filter { id in
            guard !archive.conversations.contains(where: { $0.id.uuidString == id }) else { return false }
            let presentation = workspace.presentation(id)
            let typed = !draftText(id).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard typed || presentation.title != nil || !presentation.avatar.isDefault || parked.contains(id) else { return false }
            return query.isEmpty || draftText(id).localizedCaseInsensitiveContains(query) || draftTitle(id).localizedCaseInsensitiveContains(query)
        }.sorted { workspace.presentation($0).shownAt > workspace.presentation($1).shownAt }
    }
    /// Android: the name, or the first line of what was typed (80 characters), or 新對話.
    private func draftTitle(_ id: String) -> String {
        if let title = workspace.presentation(id).title { return title }
        let line = draftText(id).components(separatedBy: .newlines).lazy.map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
        return line.map { String($0.prefix(80)) } ?? t("新對話", "New chat")
    }
    /// Android `ChatCopy.plainTitle` of the first message, unless the chat was named.
    private func savedTitle(_ record: ArchivedConversation) -> String {
        chat.botDisplayTitle(record.id.uuidString, workspace: workspace) ?? record.title
    }
    /// The open conversation before its first save, also while its first reply runs: a selected-looking row with only
    /// its title (no time, preview or "…"), the first message's first line or 新對話.
    private var currentUnsaved: BotHistoryRow? {
        guard query.isEmpty, !archive.conversations.contains(where: { $0.id.uuidString == chat.conversationID }),
              !drafts.contains(chat.conversationID) else { return nil }
        let title = chat.botFirstMessageTitle
        var row = BotHistoryRow(id: chat.conversationID, title: title.isEmpty ? t("新對話", "New chat") : title, excerpt: "",
                                date: Date(), pinnedAt: nil, record: nil)
        row.isCurrentUnsaved = true
        return row
    }
    private func draftRow(_ id: String) -> BotHistoryRow {
        let presentation = workspace.presentation(id)
        return .init(id: id, title: draftTitle(id), excerpt: draftText(id), date: presentation.shownAt, pinnedAt: presentation.pinnedAt, record: nil)
    }
    /// Saved and unsaved chats (not the open one before its first save): running first, then pinned (newest pin first),
    /// then by last activity. Android's preview is the conversation's last text, never the draft.
    private var listed: [BotHistoryRow] {
        let saved = records.map { record -> BotHistoryRow in
            let last = record.turns.reversed().lazy.flatMap { [$0.assistantText, $0.userText] }
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
            return .init(id: record.id.uuidString, title: savedTitle(record), excerpt: last,
                         date: record.updatedAt, pinnedAt: record.pinnedAt, record: record)
        }
        return (drafts.map(draftRow) + saved).sorted { left, right in
            let leftRunning = isRunning(left), rightRunning = isRunning(right)
            if leftRunning != rightRunning { return leftRunning }
            if (left.pinnedAt != nil) != (right.pinnedAt != nil) { return left.pinnedAt != nil }
            if let a = left.pinnedAt, let b = right.pinnedAt, a != b { return a > b }
            return left.date > right.date
        }
    }
    private func isRunning(_ row: BotHistoryRow) -> Bool { row.id == chat.conversationID && chat.isSubmitting }

    var body: some View {
        VStack(spacing: 0) {
            header
            titleRow
            if !chat.canSwitchBotConversation {
                Text(t("任務進行中，結束後才能切換對話", "A task is running. You can switch chats when it ends."))
                    .scaledFont(size: 12).foregroundStyle(palette.hintInk).padding(.horizontal, 16).frame(maxWidth: .infinity, alignment: .leading)
            }
            list
            bottomBar
        }
        .mikaReadableColumn()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background.ignoresSafeArea())
        .tint(palette.accent)
        .botPopoverHost(active: $popover) { menu(for: $0) }
        .botDialog(isPresented: deleteID != nil, dismiss: { deleteID = nil }) { deleteDialog }
        .sheet(item: $servicesRequest) { request in
            BotServicesSheet(workspace: workspace, localizer: localizer, selectedID: nil, startAdding: request.adding,
                             onLocal: { servicesRequest = nil },
                             onOpen: { id in switchTo(id, manage: false) },
                             onManage: { id in switchTo(id, manage: true) },
                             onClose: { servicesRequest = nil })
        }
        .fullScreenCover(isPresented: Binding(get: { editID != nil }, set: { if !$0 { editID = nil } })) {
            if let editID {
                // Android opens it with the row's title.
                BotProfileEditor(id: editID, archive: archive, workspace: workspace, localizer: localizer,
                                 fallbackName: rowTitle(editID)) { self.editID = nil }
            }
        }
    }

    // MARK: Top

    private var header: some View {
        HStack(spacing: 0) {
            BotRoundButton(symbol: "gearshape", label: t("設定", "Settings"), identifier: "bot.history.settings") { toggle(.account) }
                .botPopoverAnchor(BotHistoryPopover.account.anchorID)
            BotRoundButton(symbol: "arrow.left.arrow.right", label: t("切換助理／服務", "Switch assistant or service"),
                           identifier: "bot.serviceSwitcher") { popover = nil; servicesRequest = .init(adding: false) }
            Spacer(minLength: 0)
            BotRoundButton(symbol: "bell", label: t("通知", "Notifications"), identifier: "bot.history.notifications") {
                popover = nil; select(.notifications)
            }
            BotRoundButton(symbol: "plus", label: t("新對話", "New chat"), identifier: "bot.history.new") { toggle(.new) }
                .botPopoverAnchor(BotHistoryPopover.new.anchorID)
        }.frame(height: 64).padding(.horizontal, 8)
    }

    private var titleRow: some View {
        HStack(spacing: 0) {
            Text(t("歷史對話", "Conversation history")).scaledFont(size: 14, weight: .semibold).foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading).accessibilityAddTraits(.isHeader)
            Button(action: close) {
                HStack(spacing: 0) {
                    Text(t("返回對話", "Back to conversation")).scaledFont(size: 11).foregroundStyle(palette.hintInk)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .regular)).foregroundStyle(palette.hintInk).accessibilityHidden(true)
                }.padding(.horizontal, 8).padding(.vertical, 10).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("bot.history.back")
        }
        .padding(.horizontal, 20)
        // Like the chat's top bar, the title row keeps its height at the largest sizes.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    // MARK: List

    private var list: some View {
        let listed = listed
        return ScrollView {
            LazyVStack(spacing: 0) {
                // Android: when no saved or unsaved chat is left (also before any search), above the open one.
                if listed.isEmpty {
                    Text(t("沒有符合的對話", "No matching conversations"))
                        .scaledFont(size: 16).foregroundStyle(palette.hintInk).frame(maxWidth: .infinity, alignment: .leading)
                }
                if !archive.available {
                    Text(t("對話暫時無法讀取，原檔保留。", "Conversations cannot be read yet; the original file is preserved."))
                        .scaledFont(size: 13).foregroundStyle(palette.secondaryInk).frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    Button(t("重新讀取", "Reload")) { archive.reload() }.scaledFont(size: 14, weight: .medium).padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let current = currentUnsaved { rowView(current).id(current.id) }
                ForEach(listed) { row in rowView(row) }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .scrollPosition(id: $scrollID, anchor: .top)
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .frame(maxHeight: .infinity)
    }

    private func rowView(_ row: BotHistoryRow) -> some View {
        let selected = row.id == chat.conversationID
        let running = isRunning(row)
        let enabled = selected || chat.canSwitchBotConversation
        let avatar = workspace.presentation(row.id).avatar
        let time = BotTime.conversation(row.date, english: english)
        let title = Text(row.title).scaledFont(size: 14, weight: .semibold).foregroundStyle(enabled ? palette.ink : palette.hintInk).lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
        let pin = Image(systemName: "pin").font(.system(size: 12, weight: .regular)).foregroundStyle(palette.hintInk).accessibilityLabel(t("置頂", "Pinned"))
        // Android's route mark on a chat branched from another one.
        let branched = row.record?.branchOrigin != nil
        let branch = Image(systemName: "arrow.triangle.branch").font(.system(size: 12, weight: .regular)).foregroundStyle(palette.hintInk)
            .accessibilityLabel(t("從另一個對話分支", "Branched from another chat"))
        let preview = Text(running ? t("進行中", "Running") : row.excerpt.isEmpty ? " " : row.excerpt)
            .scaledFont(size: 13).foregroundStyle(running ? palette.accent : palette.secondaryInk).lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
            .frame(minHeight: 22, alignment: .leading)
        return HStack(spacing: 0) {
            Button { open(row) } label: {
                HStack(spacing: 10) {
                    BotAvatar(avatar: avatar).frame(width: 40, height: 40)
                    if row.isCurrentUnsaved {
                        title.frame(maxWidth: .infinity, alignment: .leading)
                    } else if typeSize.isAccessibilitySize {
                        // The time no longer fits beside the name at accessibility sizes: stack the lines.
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) { if row.pinnedAt != nil { pin }; if branched { branch }; title }
                            Text(time).scaledFont(size: 12).foregroundStyle(palette.secondaryInk)
                            preview
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 4) {
                                if row.pinnedAt != nil { pin }
                                if branched { branch }
                                title.frame(maxWidth: .infinity, alignment: .leading)
                                Text(time).scaledFont(size: 12).foregroundStyle(palette.secondaryInk).lineLimit(1)
                            }
                            preview
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 10).padding(.leading, 10).padding(.trailing, row.isCurrentUnsaved ? 10 : 0)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(!enabled)
            .accessibilityIdentifier(row.record == nil ? "bot.draft.\(row.id)" : "bot.chat.\(row.id)")
            if !row.isCurrentUnsaved {
                Button { toggle(.row(row.id)) } label: {
                    Image(systemName: "ellipsis").font(.system(size: 16, weight: .regular)).foregroundStyle(palette.secondaryInk)
                        .frame(width: 40, height: 40).contentShape(Circle())
                }
                .buttonStyle(.plain)
                // Android: the menu hangs from the 40 dp control itself, 10 dp after the text, 6 dp before the row's end.
                .botPopoverAnchor(BotHistoryPopover.row(row.id).anchorID)
                .padding(.leading, 10).padding(.trailing, 6)
                .accessibilityLabel(t("對話操作", "Chat options")).accessibilityIdentifier("bot.row.menu.\(row.id)")
            }
        }
        .background(selected ? palette.glass : .clear, in: RoundedRectangle(cornerRadius: 24))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func open(_ row: BotHistoryRow) {
        popover = nil
        if row.id == chat.conversationID { close(); return }
        if chat.switchBotConversation(to: UUID(uuidString: row.id), workspace: workspace) { close() }
    }

    // MARK: Bottom

    private var bottomBar: some View {
        HStack(spacing: 0) {
            BotRoundButton(symbol: "square.grid.2x2", label: t("快捷功能", "Shortcuts"), identifier: "bot.history.shortcuts") { toggle(.shortcuts) }
                .botPopoverAnchor(BotHistoryPopover.shortcuts.anchorID)
            BotSearchPill(text: $search, placeholder: t("搜尋對話", "Search conversations"), clearLabel: t("關閉", "Close"),
                          identifier: "bot.history.search", focused: $searchFocused)
        }.padding(.horizontal, 8).padding(.vertical, 8)
    }

    // MARK: Popovers and dialog

    private func toggle(_ next: BotHistoryPopover) {
        searchFocused = false
        withAnimation(BotMotion.pop) { popover = popover == next ? nil : next }
    }
    private func dismissPopover() { withAnimation(BotMotion.pop) { popover = nil } }

    @ViewBuilder private func menu(for id: BotHistoryPopover) -> some View {
        switch id {
        case .account:
            BotPopoverSurface(minWidth: 220) {
                BotPopoverRow(symbol: "gearshape", title: t("設定", "Settings"), identifier: "bot.popover.settings") { dismissPopover(); select(.settings) }
                BotPopoverDivider()
                BotPopoverRow(symbol: "info.circle", title: MikaAboutCopy(language: localizer.language).text(.title), identifier: "bot.popover.about") {
                    dismissPopover(); select(.about)
                }
            }
        case .new:
            BotPopoverSurface(minWidth: 220) {
                BotPopoverRow(symbol: "square.and.pencil", title: t("新對話", "New chat"), enabled: chat.canSwitchBotConversation, identifier: "bot.popover.new") {
                    dismissPopover(); new()
                }
                BotPopoverDivider()
                BotPopoverRow(symbol: "link", title: t("新增 woowtechbot 服務", "Add woowtechbot service"), identifier: "bot.popover.addService") {
                    dismissPopover(); servicesRequest = .init(adding: true)
                }
            }
        case .shortcuts:
            // Only tools this app really has; settings and About sit under the top-left control instead.
            BotPopoverSurface(minWidth: 240) {
                tool(t("記憶與技能", "Memory & skills"), "heart", .memory)
                tool(t("MCP 伺服器", "MCP servers"), "link", .tools)
                tool(t("瀏覽器", "Browser"), "globe", .browser)
                tool(t("檔案", "Files"), "doc.text", .files)
            }
        case .row(let rowID):
            let record = archive.conversations.first { $0.id.uuidString == rowID }
            BotPopoverSurface(minWidth: 200) {
                BotPopoverRow(symbol: "pencil", title: t("名稱與圖示", "Name and icon"), identifier: "bot.row.edit") { dismissPopover(); editID = rowID }
                if let record {
                    BotPopoverRow(symbol: "pin", title: record.pinnedAt == nil ? t("置頂", "Pin") : t("取消置頂", "Unpin"), identifier: "bot.row.pin") {
                        dismissPopover()
                        do { try archive.setPinned(id: record.id, expectedPinnedAt: record.pinnedAt, pinned: record.pinnedAt == nil) }
                        catch { workspace.notice = .changesUnsaved }
                    }
                } else {
                    // Android pins unsaved chats too; the pin moves into the archive with the first save.
                    let pinned = workspace.presentation(rowID).pinnedAt != nil
                    BotPopoverRow(symbol: "pin", title: pinned ? t("取消置頂", "Unpin") : t("置頂", "Pin"), identifier: "bot.row.pin") {
                        dismissPopover()
                        do { try workspace.setDraftPinned(rowID, !pinned) } catch { workspace.notice = .changesUnsaved }
                    }
                }
                BotPopoverDivider()
                BotPopoverRow(symbol: "trash", title: t("刪除", "Delete"), destructive: true, identifier: "bot.row.delete") {
                    dismissPopover(); deleteID = UUID(uuidString: rowID)
                }
            }
        }
    }

    private func tool(_ title: String, _ symbol: String, _ destination: BotLocalDestination) -> some View {
        BotPopoverRow(symbol: symbol, title: title, identifier: "bot.tool.\(destination)") { dismissPopover(); select(destination) }
    }

    private func rowTitle(_ id: String) -> String {
        if let record = archive.conversations.first(where: { $0.id.uuidString == id }) { return savedTitle(record) }
        return draftTitle(id)
    }

    private var deleteTitle: String {
        guard let id = deleteID else { return "" }
        if let record = archive.conversations.first(where: { $0.id == id }) { return savedTitle(record) }
        return draftTitle(id.uuidString)
    }

    private var deleteDialog: some View {
        let running = chat.isSubmitting && deleteID?.uuidString == chat.conversationID
        let body = english ? "“\(deleteTitle)” and the files in it will be deleted." : "「\(deleteTitle)」和裡面的檔案都會刪掉。"
        return BotDialogSurface {
            BotDialogTitle(text: t("刪除這個對話？", "Delete this chat?"))
            BotDialogBody(text: running ? body + "\n" + t("正在進行的任務會被停止。", "Its running task will be stopped.") : body)
            HStack(spacing: 10) {
                BotDialogButton(title: t("取消", "Cancel"), kind: .dismiss, identifier: "bot.delete.cancel") { deleteID = nil }
                BotDialogButton(title: t("刪除", "Delete"), kind: .destructive, identifier: "bot.delete.confirm") {
                    if let id = deleteID { Task { _ = await chat.deleteBotConversation(id, workspace: workspace) } }
                    deleteID = nil
                }
            }.padding(.top, 24)
        }
    }

    /// The sheet closes first, then the service opens, so the cover is never raised under a dismissing sheet.
    private func switchTo(_ id: UUID, manage: Bool) {
        servicesRequest = nil
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            workspace.openService(id, manage: manage)
        }
    }
}
#endif
