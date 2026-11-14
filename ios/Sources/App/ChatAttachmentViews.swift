import ImageIO
import QuickLook
import SwiftUI
import UIKit

/// Copy text from the Android pro edition (woow.10 strings_chat.xml), ASCII
/// punctuation kept, resolved in the chosen interface language.
struct ChatAttachmentText {
    let localizer: AppLocalizer

    var add: String { localizer.text(.chatAttachAdd) }
    var close: String { localizer.text(.chatAttachClose) }
    var camera: String { localizer.text(.chatAttachCamera) }
    var album: String { localizer.text(.chatAttachAlbum) }
    var files: String { localizer.text(.chatAttachFiles) }
    var adding: String { localizer.text(.chatAttachAdding) }
    var gotIt: String { localizer.text(.chatAttachGotIt) }
    var gone: String { localizer.text(.chatAttachGone) }
    var noCamera: String { localizer.text(.chatAttachNoCamera) }
    var seesImages: String { localizer.text(.settingsSeesImages) }
    var seesImagesUnconfirmed: String { localizer.text(.settingsSeesImagesUnconfirmed) }
    var seesImagesUser: String { localizer.text(.settingsSeesImagesUser) }
    func remove(_ name: String) -> String { localizer.text(.chatAttachRemove(name: name)) }
    func full() -> String { localizer.text(.chatAttachFull(limit: ChatAttachmentLimits.maximumCount)) }
    func overLimit(_ n: Int) -> String {
        localizer.text(.chatAttachOverLimit(limit: ChatAttachmentLimits.maximumCount, count: n))
    }
    func refused(_ names: [String]) -> String {
        localizer.text(.chatAttachRefused(names: names.joined(separator: localizer.language == .english ? ", " : "、")))
    }
    func imagesNotSeen(_ n: Int) -> String { localizer.text(.chatAttachImagesNotSeen(count: n)) }
}

/// The chat palette's colors this file needs; ContentView keeps its palette private.
struct ChatAttachmentColors {
    let ink: Color
    let secondaryInk: Color
    let accent: Color
    let surface: Color
    let fill: Color
    let hair: Color
}

// MARK: - Thumbnails

/// Downsampled previews of the app's own copies, cached by path and size.
enum ChatAttachmentThumbnails {
    nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

    static func load(_ url: URL, maxPixels: Int) async -> UIImage? {
        let key = (url.path + "#\(maxPixels)") as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let image = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                            kCGImageSourceCreateThumbnailWithTransform: true,
                                            kCGImageSourceShouldCacheImmediately: true,
                                            kCGImageSourceThumbnailMaxPixelSize: maxPixels]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return UIImage(cgImage: cg)
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

private struct ChatAttachmentThumbnail: View {
    let url: URL
    let maxPixels: Int
    let fill: Color
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            fill
            if let image { Image(uiImage: image).resizable().scaledToFill() }
        }
        .task(id: url) { image = await ChatAttachmentThumbnails.load(url, maxPixels: maxPixels) }
    }
}

// MARK: - File badge

/// Android FileBadge: extension in capitals (at most four) on a colored tile.
struct ChatFileBadge: View {
    let name: String
    let small: Bool
    let accent: Color
    /// Shown when the name has no extension (Android uses the "檔案" label).
    let noExtension: String

    private var ext: String {
        String((name as NSString).pathExtension.lowercased().filter { $0.isLetter || $0.isNumber })
    }
    private var label: String { ext.isEmpty ? noExtension : String(ext.uppercased().prefix(4)) }
    private var color: Color {
        switch ext {
        case "pdf": return Color(red: 0.90, green: 0.27, blue: 0.24)
        case "xls", "xlsx", "csv", "tsv", "numbers", "ods": return Color(red: 0.20, green: 0.65, blue: 0.36)
        case "doc", "docx", "txt", "md", "rtf", "pages", "odt": return accent
        case "ppt", "pptx", "key", "odp": return Color(red: 0.95, green: 0.55, blue: 0.13)
        default: return Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255)
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: small ? 8.5 : 11, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1).minimumScaleFactor(0.6)
            .padding(.horizontal, 2)
            .frame(width: small ? 28 : 38, height: small ? 34 : 44)
            .background(color, in: RoundedRectangle(cornerRadius: small ? 5 : 7))
            .accessibilityHidden(true)
    }
}

// MARK: - Pending tray (above the input bar)

/// Android PendingTray: photos as 58pt squares, files as cards, each with a remove dot.
struct ChatAttachmentTray: View {
    let items: [ChatAttachmentItem]
    let store: ChatAttachmentStore
    let colors: ChatAttachmentColors
    let text: ChatAttachmentText
    let canRemove: Bool
    let onRemove: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ZStack(alignment: .topTrailing) {
                        content(item)
                        Button { onRemove(item.id) } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Color.black.opacity(0.65), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                        .disabled(!canRemove)
                        .accessibilityLabel(text.remove(item.name))
                        .accessibilityIdentifier("chat.attach.remove.\(index)")
                    }
                    // A container keeps the item and its remove button as separate VoiceOver
                    // elements; otherwise this identifier would replace the button's own.
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("chat.attach.item.\(index)")
                }
            }
            .padding(.leading, 4).padding(.trailing, 10).padding(.vertical, 8)
        }
        .accessibilityIdentifier("chat.attach.tray")
    }

    @ViewBuilder private func content(_ item: ChatAttachmentItem) -> some View {
        if item.kind == .photo {
            ChatAttachmentThumbnail(url: store.url(for: item), maxPixels: 180, fill: colors.fill)
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityElement()
                .accessibilityLabel(item.name)
        } else {
            HStack(spacing: 8) {
                ChatFileBadge(name: item.name, small: true, accent: colors.accent, noExtension: text.files)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.name).font(.system(size: 13, weight: .medium)).foregroundStyle(colors.ink).lineLimit(1)
                    Text(verbatim: ChatAttachmentFormat.byteString(item.byteCount))
                        .font(.system(size: 11)).foregroundStyle(colors.secondaryInk)
                }
                .frame(maxWidth: 130, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(height: 58)
            .frame(maxWidth: 200)
            .background(colors.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.hair, lineWidth: 0.5))
            .accessibilityElement(children: .combine)
        }
    }
}

/// Inline warnings above the input bar, with Android's "知道了".
struct ChatAttachmentNoticeRow: View {
    let notice: ChatAttachmentNotice
    let colors: ChatAttachmentColors
    let text: ChatAttachmentText
    let dismiss: () -> Void

    private var message: String {
        switch notice {
        case .overLimit(let n): return text.overLimit(n)
        case .refused(let names): return text.refused(names)
        case .cameraUnavailable: return text.noCamera
        case .imagesNotSeen(let n): return text.imagesNotSeen(n)
        case .trayFull: return text.full()
        case .missing: return text.gone
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: message).font(.callout).foregroundStyle(colors.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(text.gotIt, action: dismiss)
                .font(.callout.weight(.semibold))
                .accessibilityIdentifier("chat.attach.notice.dismiss")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(colors.surface, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.attach.notice")
    }
}

// MARK: - Attach panel (below the input bar)

/// Play's AttachPanel: three tiles. Like the Play build there is no recent-photos
/// grid, so the app never asks for photo library access; photos come from the
/// system picker, which needs no permission.
struct ChatAttachPanel: View {
    let colors: ChatAttachmentColors
    let text: ChatAttachmentText
    let onCamera: () -> Void
    let onAlbum: () -> Void
    let onFiles: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                tile("camera", text.camera, id: "chat.attach.camera", action: onCamera)
                tile("photo", text.album, id: "chat.attach.album", action: onAlbum)
                tile("paperclip", text.files, id: "chat.attach.files", action: onFiles)
            }
        }
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.attach.panel")
    }

    private func tile(_ symbol: String, _ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 22)).foregroundStyle(colors.ink).frame(height: 24)
                Text(verbatim: label).font(.system(size: 12.5)).foregroundStyle(colors.ink)
            }
            .frame(maxWidth: .infinity).frame(height: 76)
            .background(colors.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(colors.hair, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

// MARK: - Sent attachments (in the transcript)

/// Android SentAttachments: photos first (one large, two side by side, or a
/// three-column grid), then file cards. The "附件:" lines are never shown.
struct ChatSentAttachments: View {
    let items: [ChatAttachmentItem]
    let store: ChatAttachmentStore
    let colors: ChatAttachmentColors
    let text: ChatAttachmentText
    let identifier: String
    let onOpen: (ChatAttachmentItem) -> Void

    private var photos: [ChatAttachmentItem] { items.filter { $0.kind == .photo } }
    private var files: [ChatAttachmentItem] { items.filter { $0.kind == .file } }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !photos.isEmpty { photoGrid }
            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                Button { onOpen(file) } label: { fileCard(file) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(identifier).file.\(index)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder private var photoGrid: some View {
        if photos.count == 1 {
            photoButton(photos[0], index: 0, maxPixels: 640)
                .frame(width: 200, height: 200 / 0.75)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            let columns = photos.count == 2 ? 2 : 3
            let side: CGFloat = columns == 2 ? 118 : 96
            VStack(spacing: 4) {
                ForEach(Array(stride(from: 0, to: photos.count, by: columns)), id: \.self) { start in
                    HStack(spacing: 4) {
                        ForEach(start..<min(start + columns, photos.count), id: \.self) { index in
                            photoButton(photos[index], index: index, maxPixels: 256).frame(width: side, height: side).clipped()
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private func photoButton(_ item: ChatAttachmentItem, index: Int, maxPixels: Int) -> some View {
        Button { onOpen(item) } label: {
            ChatAttachmentThumbnail(url: store.url(for: item), maxPixels: maxPixels, fill: colors.fill)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.name)
        .accessibilityIdentifier("\(identifier).photo.\(index)")
    }

    private func fileCard(_ item: ChatAttachmentItem) -> some View {
        HStack(spacing: 10) {
            ChatFileBadge(name: item.name, small: false, accent: colors.accent, noExtension: text.files)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.name).font(.system(size: 14, weight: .medium)).foregroundStyle(colors.ink).lineLimit(2)
                Text(verbatim: ChatAttachmentFormat.byteString(item.byteCount)).font(.system(size: 12)).foregroundStyle(colors.secondaryInk)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(minWidth: 220, maxWidth: 320, alignment: .leading)
        .background(colors.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(colors.hair, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

/// A sent attachment opens in Quick Look, the iOS counterpart of Android's viewer.
struct ChatAttachmentPreview: UIViewControllerRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return UINavigationController(rootViewController: controller)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}

/// Identifies which attachment Quick Look shows.
struct ChatAttachmentPreviewTarget: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - Presentations

/// The panel's photo, file and camera pickers and Quick Look, kept out of the
/// chat view's body so every supported compiler can type-check it quickly.
struct ChatAttachPresentations: ViewModifier {
    @Binding var picker: ChatAttachPicker?
    @Binding var showsCamera: Bool
    @Binding var preview: ChatAttachmentPreviewTarget?
    let photoLimit: Int
    let add: ([ChatPickedFile]) -> Void
    let loadingStarted: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $picker) { kind in sheet(kind) }
            .fullScreenCover(isPresented: $showsCamera) {
                ChatCameraPicker(onCaptured: { data in
                    showsCamera = false
                    if let file = ChatAttachmentImport.temporaryPhoto(jpeg: data) { add([file]) }
                }, onCancel: { showsCamera = false })
                .ignoresSafeArea()
            }
            .sheet(item: $preview) { target in ChatAttachmentPreview(url: target.url).ignoresSafeArea() }
    }

    @ViewBuilder private func sheet(_ kind: ChatAttachPicker) -> some View {
        switch kind {
        case .album:
            // Close as soon as copying starts; originals from iCloud keep loading behind "正在新增附件…".
            ChatPhotoLibraryPicker(selectionLimit: photoLimit,
                                   onPicked: { files in picker = nil; add(files) },
                                   onLoadingStarted: { loadingStarted(); picker = nil })
                .ignoresSafeArea()
        case .files:
            ChatDocumentPicker { files in picker = nil; add(files) }
                .ignoresSafeArea()
        }
    }
}

