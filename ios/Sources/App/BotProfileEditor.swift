#if WOOWTECHBOT
import AssistantPersistence
import ImageIO
import PhotosUI
import SwiftUI

/// Conversation name and icon, laid out like the design's `avatarPage` (Android `BotUiProfileEditor`): no title, save and close
/// as round buttons at the top right, a 68-point tile with a pencil badge, the name centred below it, and the icon card opening
/// under them. Only the name and the icon (robot or an uploaded picture) can change.
struct BotProfileEditor: View {
    let id: String
    @ObservedObject var archive: ConversationArchiveStore
    @ObservedObject var workspace: BotWorkspaceStore
    let localizer: AppLocalizer
    let close: () -> Void
    @State private var name = ""
    @State private var avatar = BotConversationAvatar()
    @State private var photo: PhotosPickerItem?
    @State private var cardOpen = false
    @State private var uploadTab = false
    @State private var busy = false
    @State private var failed = false
    @FocusState private var nameFocused: Bool
    @Environment(\.colorScheme) private var scheme
    private func t(_ zh: String, _ en: String) -> String { localizer.language == .english ? en : zh }
    private var english: Bool { localizer.language == .english }
    private var canSave: Bool { !busy && ConversationArchive.normalizedTitle(name) != nil }

    var body: some View {
        let palette = MikaVisualPalette(scheme)
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                BotCircleButton(symbol: "checkmark", label: t("儲存", "Save"), identifier: "bot.edit.save", enabled: canSave, action: save)
                BotCircleButton(symbol: "xmark", label: t("關閉", "Close"), identifier: "bot.edit.cancel") { if !busy { close() } }
            }.padding(.leading, 14).padding(.trailing, 14).padding(.top, 14).padding(.bottom, 4)
            ScrollView {
                VStack(spacing: 0) {
                    avatarButton(palette)
                    Spacer().frame(height: 18)
                    nameRow(palette)
                    if ConversationArchive.normalizedTitle(name) == nil {
                        Text(t("請輸入名稱", "Enter a name")).scaledFont(size: 12).foregroundStyle(palette.destructive)
                            .accessibilityIdentifier("bot.edit.nameRequired")
                    }
                    Spacer().frame(height: 24)
                    if cardOpen { card(palette).transition(.opacity.combined(with: .move(edge: .top))) }
                    if busy { ProgressView().padding(.top, 16) }
                    if failed {
                        Text(t("無法讀取圖片或儲存變更。原有設定仍保留，請重試。", "Could not load the image or save changes. Your previous profile is preserved. Please try again."))
                            .scaledFont(size: 13).foregroundStyle(palette.warn).padding(.top, 16).accessibilityIdentifier("bot.edit.error")
                    }
                }.padding(.horizontal, 12).padding(.top, 18).padding(.bottom, 30).frame(maxWidth: .infinity)
            }.scrollDismissesKeyboard(.interactively)
        }
        .mikaReadableColumn()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background.ignoresSafeArea())
        .tint(palette.accent)
        .onAppear {
            let row = archive.conversations.first { $0.id.uuidString == id }
            name = row?.title ?? workspace.presentation(id).title ?? t("新對話", "New chat")
            avatar = workspace.presentation(id).avatar.upgraded()
            uploadTab = avatar.jpeg != nil
        }
        .task(id: photo) {
            guard let photo else { return }
            busy = true
            defer { busy = false }
            do {
                guard let bytes = try await photo.loadTransferable(type: Data.self), !Task.isCancelled,
                      let image = Self.thumbnail(bytes) else { failed = true; return }
                avatar.jpeg = image; failed = false
            } catch { failed = true }
        }
    }

    // MARK: Pieces

    /// `.avatar-large`: a 68-point tile with a 23-point pencil badge 4 points outside its corner.
    private func avatarButton(_ palette: MikaVisualPalette) -> some View {
        Button { withAnimation(.easeOut(duration: 0.2)) { cardOpen.toggle() } } label: {
            ZStack(alignment: .bottomTrailing) {
                BotAvatar(avatar: avatar).frame(width: 68, height: 68)
                Image(systemName: "pencil").font(.system(size: 11, weight: .regular)).foregroundStyle(palette.secondaryInk)
                    .frame(width: 19, height: 19).background(palette.glass, in: Circle())
                    .padding(2).background(palette.background, in: Circle())
                    .offset(x: 4, y: 4)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(busy)
        .accessibilityLabel(t("修改對話圖示", "Edit icon")).accessibilityAddTraits(cardOpen ? .isSelected : [])
        .accessibilityIdentifier("bot.edit.avatar")
    }

    /// `.profile-name-row`: 18/600 centred, a 10-point radius, an accent ring while editing, a pencil of the same width on the right.
    private func nameRow(_ palette: MikaVisualPalette) -> some View {
        HStack(spacing: 4) {
            Color.clear.frame(width: 32, height: 1)
            TextField("", text: Binding(get: { name }, set: { name = String($0.prefix(60)) }))
                .scaledFont(size: 18, weight: .semibold).multilineTextAlignment(.center).foregroundStyle(palette.ink).tint(palette.accent)
                .focused($nameFocused).submitLabel(.done).onSubmit { nameFocused = false }
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(nameFocused ? palette.accent : .clear, lineWidth: 1))
                .disabled(busy).accessibilityLabel(t("名稱", "Name")).accessibilityIdentifier("bot.edit.name")
            Button { nameFocused = true } label: {
                Image(systemName: "pencil").font(.system(size: 16, weight: .regular)).foregroundStyle(palette.secondaryInk)
                    .frame(width: 32, height: 36).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(busy).accessibilityLabel(t("修改對話名稱", "Edit name")).accessibilityIdentifier("bot.edit.nameButton")
        }
    }

    /// `.avatar-card`: the control colour, a 1-point hairline, 24-point corners.
    private func card(_ palette: MikaVisualPalette) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return VStack(spacing: 0) {
            HStack(spacing: 3) {
                tab(t("機器人", "Robot"), selected: !uploadTab, identifier: "bot.edit.tab.robot", palette: palette) { uploadTab = false }
                tab(t("上傳", "Upload"), selected: uploadTab, identifier: "bot.edit.tab.upload", palette: palette) { uploadTab = true }
                Spacer(minLength: 0)
                Button {
                    avatar = BotConversationAvatar(); uploadTab = false; photo = nil
                } label: {
                    Text(t("重設", "Reset")).scaledFont(size: 12).foregroundStyle(palette.secondaryInk)
                        .padding(.horizontal, 12).padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("bot.edit.reset")
            }.padding(9)
            Rectangle().fill(palette.edge).frame(height: 1)
            Group {
                if uploadTab { uploadPane(palette) } else { robotPane(palette) }
            }.padding(.horizontal, 16).padding(.vertical, 20)
        }
        .background(palette.glass, in: shape).overlay(shape.strokeBorder(palette.hair, lineWidth: 1))
    }

    private func tab(_ title: String, selected: Bool, identifier: String, palette: MikaVisualPalette, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).scaledFont(size: 14).foregroundStyle(selected ? palette.ink : palette.secondaryInk)
                .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 36)
                .background(selected ? palette.raised : .clear, in: RoundedRectangle(cornerRadius: 13)).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(busy).accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier(identifier)
    }

    /// `.avatar-upload`: a dashed 16-point frame with the camera, the action and the formats line.
    private func uploadPane(_ palette: MikaVisualPalette) -> some View {
        VStack(spacing: 10) {
            PhotosPicker(selection: $photo, matching: .images) {
                VStack(spacing: 10) {
                    Image(systemName: "camera").font(.system(size: 28, weight: .regular)).foregroundStyle(palette.secondaryInk)
                    Text(t("選擇圖片", "Choose an image")).scaledFont(size: 15, weight: .semibold).foregroundStyle(palette.ink)
                    Text(t("PNG、JPG、WebP 或 GIF · 最大 12 MB", "PNG, JPG, WebP or GIF · up to 12 MB"))
                        .scaledFont(size: 11).foregroundStyle(palette.secondaryInk).multilineTextAlignment(.center)
                }
                .padding(.horizontal, 8).padding(.vertical, 32).frame(maxWidth: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(palette.hair, style: StrokeStyle(lineWidth: 1, dash: [6, 4])))
                .contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("bot.edit.photo")
            Text(t("圖片會以正方形置中裁切。", "Pictures are center-cropped to a square."))
                .scaledFont(size: 11).foregroundStyle(palette.secondaryInk).multilineTextAlignment(.center).frame(maxWidth: .infinity)
        }
    }

    /// The current colours and face on each robot style, as the style tiles show them.
    private func sample(_ style: Int) -> BotConversationAvatar {
        var value = avatar
        value.robot = style; value.jpeg = nil
        return value
    }

    private func robotPane(_ palette: MikaVisualPalette) -> some View {
        let styles = [t("經典", "Classic"), t("方形", "Square"), t("圓形", "Round")]
        let noPhoto = avatar.jpeg == nil
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { style in
                    let picked = noPhoto && avatar.robot == style
                    Button { avatar.robot = style; avatar.jpeg = nil } label: {
                        VStack(spacing: 6) {
                            BotAvatar(avatar: sample(style)).frame(width: 50, height: 50)
                            Text(styles[style]).scaledFont(size: 11).foregroundStyle(palette.secondaryInk)
                        }
                        .padding(.horizontal, 5).padding(.vertical, 10).frame(maxWidth: .infinity)
                        .background(picked ? palette.raised : .clear, in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(picked ? palette.ink : .clear, lineWidth: 2))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).disabled(busy).accessibilityLabel(styles[style]).accessibilityAddTraits(picked ? .isSelected : [])
                    .accessibilityIdentifier("bot.edit.style.\(style)")
                }
            }
            Spacer().frame(height: 23)
            BotFlow(spacing: 12) {
                ForEach(0..<BotAvatar.colors.count, id: \.self) { index in
                    let picked = noPhoto && avatar.color == index
                    Button { avatar.color = index; avatar.jpeg = nil } label: {
                        Circle().fill(BotAvatar.colors[index].color).frame(width: 27, height: 27)
                            .overlay(Circle().strokeBorder(palette.ink, lineWidth: picked ? 2 : 0).padding(-7))
                            .contentShape(Circle().inset(by: -6))
                    }
                    .buttonStyle(.plain).disabled(busy)
                    .accessibilityLabel(english ? BotAvatar.colors[index].en : BotAvatar.colors[index].zh)
                    .accessibilityAddTraits(picked ? .isSelected : []).accessibilityIdentifier("bot.edit.color.\(index)")
                }
            }
            Spacer().frame(height: 28)
            HStack {
                Text(t("五官", "Face")).scaledFont(size: 12).foregroundStyle(palette.secondaryInk).frame(maxWidth: .infinity, alignment: .leading)
                Button { avatar.face = 0; avatar.jpeg = nil } label: {
                    Text(t("依顏色預設", "Match color")).scaledFont(size: 12)
                        .foregroundStyle(avatar.face == 0 && noPhoto ? palette.ink : palette.secondaryInk)
                        .padding(.horizontal, 6).padding(.vertical, 4).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("bot.edit.face.auto")
            }.padding(.bottom, 10)
            HStack(spacing: 0) {
                ForEach([(1, t("白色", "White")), (2, t("黑色", "Black"))], id: \.0) { face, label in
                    let picked = noPhoto && avatar.face == face
                    Button { avatar.face = face; avatar.jpeg = nil } label: {
                        Text(label).scaledFont(size: 14).foregroundStyle(picked ? palette.ink : palette.secondaryInk)
                            .padding(9).frame(maxWidth: .infinity)
                            .background(picked ? palette.background : .clear, in: Capsule()).contentShape(Capsule())
                    }.buttonStyle(.plain).disabled(busy).accessibilityAddTraits(picked ? .isSelected : [])
                        .accessibilityIdentifier("bot.edit.face.\(face)")
                }
            }.padding(4).background(palette.raised, in: Capsule())
        }
    }

    // MARK: Saving

    private func save() {
        guard let normalized = ConversationArchive.normalizedTitle(name) else { return }
        do {
            let saved = avatar.upgraded()
            if let row = archive.conversations.first(where: { $0.id.uuidString == id }) {
                try archive.rename(id: row.id, expectedTitle: row.customTitle, to: normalized)
            }
            try workspace.savePresentation(id, title: normalized, avatar: saved)
            close()
        } catch { failed = true }
    }

    /// Bounded decode and a local 320-point centre crop; never persists a provider URL or uploads anything.
    private static func thumbnail(_ data: Data) -> Data? {
        guard data.count <= 12 * 1024 * 1024, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg), side = min(image.size.width, image.size.height)
        guard side > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let result = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 320), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 320, height: 320))
            let factor = 320 / side
            image.draw(in: CGRect(x: (320 - image.size.width * factor) / 2, y: (320 - image.size.height * factor) / 2,
                                  width: image.size.width * factor, height: image.size.height * factor))
        }
        return result.jpegData(compressionQuality: 0.9)
    }
}

/// `.profile-top .icon-button`: a 36-point control circle with a hairline ring.
struct BotCircleButton: View {
    let symbol: String
    let label: String
    var identifier: String
    var enabled = true
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let palette = MikaVisualPalette(scheme)
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .regular)).foregroundStyle(palette.ink.opacity(enabled ? 1 : 0.4))
                .frame(width: 36, height: 36).background(palette.glass, in: Circle())
                .overlay(Circle().strokeBorder(palette.hair, lineWidth: 1))
                .frame(width: 44, height: 44).contentShape(Circle())
        }.buttonStyle(.plain).disabled(!enabled).accessibilityLabel(label).accessibilityIdentifier(identifier)
    }
}

/// Wraps its children onto rows, centred (Compose `FlowRow` with a centred arrangement).
struct BotFlow: Layout {
    var spacing: CGFloat = 12
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? 320, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX + (bounds.width - row.width) / 2
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }
    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }
    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + extra + size.width > width { rows.append(Row()) }
            let extra2 = rows[rows.count - 1].indices.isEmpty ? 0 : spacing
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += extra2 + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
#endif
