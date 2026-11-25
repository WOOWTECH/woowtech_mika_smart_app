import QuickLookThumbnailing
import SwiftUI
import UIKit

/// The cards of the files a reply made (file_create): a Quick Look thumbnail,
/// the name, the kind and the size, then 存到檔案, 分享 and remove. A tap
/// previews the file with Quick Look. Nothing leaves the app until the person
/// taps 存到檔案 or 分享 and finishes in the system's sheet; then, or when the
/// card is removed, the app's copy is deleted and the card says so.
struct ChatCreatedFileCards: View {
    let files: [ChatCreatedFile]
    let colors: ChatAttachmentColors
    let localizer: AppLocalizer
    let identifier: String
    let onPreview: (ChatCreatedFile) -> Void
    let onSave: (ChatCreatedFile) -> Void
    let onShare: (ChatCreatedFile) -> Void
    let onRemove: (ChatCreatedFile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(files.enumerated()), id: \.element.id) { index, file in
                card(file, identifier: "\(identifier).\(index)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private func card(_ file: ChatCreatedFile, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { onPreview(file) } label: {
                HStack(spacing: 10) {
                    ChatCreatedFileThumbnail(file: file, accent: colors.accent, noExtension: localizer.text(.chatAttachFiles))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: file.name).scaledFont(size: 14, weight: .medium).foregroundStyle(colors.ink).lineLimit(2)
                        Text(verbatim: localizer.text(kind(file)) + " · " + ChatAttachmentFormat.byteString(file.byteCount))
                            .scaledFont(size: 12).foregroundStyle(colors.secondaryInk)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(file.state != .ready)
            .accessibilityElement(children: .combine)
            .accessibilityHint(file.state == .ready ? localizer.text(.chatFilePreviewHint) : "")
            .accessibilityIdentifier(identifier + ".preview")
            if file.state == .ready {
                HStack(spacing: 8) {
                    Button(localizer.text(.chatFileSave)) { onSave(file) }
                        .buttonStyle(.bordered).accessibilityIdentifier(identifier + ".save")
                    Button(localizer.text(.chatFileShare)) { onShare(file) }
                        .buttonStyle(.bordered).accessibilityIdentifier(identifier + ".share")
                    Spacer(minLength: 0)
                    Button { onRemove(file) } label: {
                        Image(systemName: "xmark").frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain).foregroundStyle(colors.secondaryInk)
                    .accessibilityLabel(localizer.text(.chatFileRemove))
                    .accessibilityIdentifier(identifier + ".remove")
                }
                .scaledFont(size: 14)
            } else {
                Text(localizer.text(status(file.state)))
                    .scaledFont(size: 12).foregroundStyle(colors.secondaryInk)
                    .accessibilityIdentifier(identifier + ".status")
            }
        }
        .padding(12)
        .frame(minWidth: 220, maxWidth: 360, alignment: .leading)
        .background(colors.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(colors.hair, lineWidth: 0.5))
    }

    private func kind(_ file: ChatCreatedFile) -> AppText {
        switch file.format {
        case "pdf": return .chatFileKindPDF
        case "docx": return .chatFileKindWord
        case "xlsx": return .chatFileKindExcel
        case "pptx": return .chatFileKindPowerPoint
        default: return .chatFileKindZIP
        }
    }

    private func status(_ state: ChatCreatedFile.State) -> AppText {
        switch state {
        case .saved: return .chatFileSaved
        case .shared: return .chatFileShared
        case .removed: return .chatFileRemoved
        case .ready, .missing: return .chatFileMissing
        }
    }
}

/// Quick Look's thumbnail of the file, or its colored type tile until there is one.
private struct ChatCreatedFileThumbnail: View {
    let file: ChatCreatedFile
    let accent: Color
    let noExtension: String
    @Environment(\.displayScale) private var scale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image, file.state == .ready {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ChatFileBadge(name: file.name, small: false, accent: accent, noExtension: noExtension)
            }
        }
        .frame(width: 44, height: 54)
        .accessibilityHidden(true)
        .task(id: file.id) {
            guard file.state == .ready else { return }
            let request = QLThumbnailGenerator.Request(fileAt: file.url, size: CGSize(width: 44, height: 54),
                                                       scale: scale, representationTypes: .thumbnail)
            image = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).uiImage
        }
    }
}

/// Which system sheet a card opened.
enum ChatCreatedFileDelivery: Identifiable {
    case save(ChatCreatedFile), share(ChatCreatedFile)
    var file: ChatCreatedFile { switch self { case .save(let file), .share(let file): return file } }
    var id: String {
        switch self {
        case .save(let file): return "save-" + file.id.uuidString
        case .share(let file): return "share-" + file.id.uuidString
        }
    }
}

/// The save and share sheets of the cards, kept out of the chat view's body.
/// Saving counts once Files has the copy; sharing once the share sheet reports
/// the activity done. A cancel leaves the file and its card as they were.
struct ChatCreatedFilePresentations: ViewModifier {
    @Binding var delivery: ChatCreatedFileDelivery?
    let finish: (ChatCreatedFile, ChatCreatedFile.State) -> Void

    func body(content: Content) -> some View {
        content.sheet(item: $delivery) { target in
            switch target {
            case .save(let file):
                DocumentSavePicker(url: file.url) { saved in
                    delivery = nil
                    if saved { finish(file, .saved) }
                }
                .ignoresSafeArea()
            case .share(let file):
                DocumentSharePicker(url: file.url) { completed, _ in
                    delivery = nil
                    if completed { finish(file, .shared) }
                }
            }
        }
    }
}
