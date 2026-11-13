import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// zh-Hant copy used in this file; the coordinator moves it into the localization table.
enum ChatAttachmentPickerText {
    static let photo = "照片"
    static let selected = "已選取"
    static let file = "檔案"
}


/// The system camera. Check `isAvailable` first (simulators have none) and present it
/// full screen. The shot goes to the tray as JPEG, never into the photo library.
@MainActor struct ChatCameraPicker: UIViewControllerRepresentable {
    /// JPEG at quality 0.9, with the orientation drawn into the pixels.
    let onCaptured: (Data) -> Void
    let onCancel: () -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeCoordinator() -> Coordinator { Coordinator(onCaptured: onCaptured, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        if Self.isAvailable {
            picker.sourceType = .camera
            picker.mediaTypes = [UTType.image.identifier]
            picker.cameraCaptureMode = .photo
        } else {
            // Asking for .camera without one raises; report that nothing was taken instead.
            let coordinator = context.coordinator
            Task { @MainActor in coordinator.cancel() }
        }
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    @MainActor final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCaptured: (Data) -> Void
        private let onCancel: () -> Void
        private var finished = false

        init(onCaptured: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
            self.onCaptured = onCaptured
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard !finished else { return }
            guard let image = info[.originalImage] as? UIImage else { cancel(); return }
            finished = true
            Task { @MainActor in
                // Redrawing and encoding a full-size photo takes a moment; keep it off the main thread.
                let jpeg = await Task.detached(priority: .userInitiated) { ChatCameraJPEG.upright(image) }.value
                if let jpeg { self.onCaptured(jpeg) } else { self.onCancel() }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { cancel() }

        func cancel() {
            guard !finished else { return }
            finished = true
            onCancel()
        }
    }
}

/// UIImagePickerController returns pixels plus an orientation flag that some readers
/// ignore, so the shot is redrawn upright before it is encoded.
private enum ChatCameraJPEG {
    static func upright(_ image: UIImage) -> Data? {
        guard image.imageOrientation != .up else { return image.jpegData(compressionQuality: 0.9) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        // 8-bit sRGB keeps a full-size redraw at four bytes a pixel.
        format.preferredRange = .standard
        let upright = UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        return upright.jpegData(compressionQuality: 0.9)
    }
}

/// The system photo picker: it needs no photo-library permission and keeps the original
/// bytes (HEIC stays HEIC). Each choice is copied while its file URL is still valid.
@MainActor struct ChatPhotoLibraryPicker: UIViewControllerRepresentable {
    /// The room left in the tray, 1...9.
    let selectionLimit: Int
    /// Called once on the main actor after every copy finished, in the order chosen;
    /// empty when the user cancels.
    let onPicked: ([ChatPickedFile]) -> Void
    /// Called as soon as the user confirms a non-empty choice, before the copies finish,
    /// so the sheet can close while iCloud originals download. `onPicked` still follows.
    var onLoadingStarted: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked, onLoadingStarted: onLoadingStarted) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        // A limit of 0 would mean "no limit".
        configuration.selectionLimit = min(max(selectionLimit, 1), ChatAttachmentLimits.maximumCount)
        configuration.preferredAssetRepresentationMode = .current
        configuration.selection = .ordered
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: PHPickerViewController, context: Context) {}

    @MainActor final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPicked: ([ChatPickedFile]) -> Void
        private let onLoadingStarted: () -> Void
        private var finished = false
        /// Keeps the providers alive until every load has reported back.
        private var loading: [NSItemProvider] = []

        init(onPicked: @escaping ([ChatPickedFile]) -> Void, onLoadingStarted: @escaping () -> Void) {
            self.onPicked = onPicked
            self.onLoadingStarted = onLoadingStarted
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !finished else { return }
            finished = true
            var seen = Set<String>()
            let chosen = results.filter { result in
                guard let id = result.assetIdentifier else { return true }
                return seen.insert(id).inserted
            }
            guard !chosen.isEmpty else { onPicked([]); return }
            onLoadingStarted()
            loading = chosen.map(\.itemProvider)
            // NSItemProvider is not Sendable, so every load starts here on the main actor
            // and only the staged copy comes back from the provider's queue.
            let (stream, continuation) = AsyncStream.makeStream(of: (Int, ChatPickedFile?).self)
            for (index, result) in chosen.enumerated() {
                let provider = result.itemProvider
                let suggestedName = provider.suggestedName
                let key = result.assetIdentifier
                _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { @Sendable url, _ in
                    // The file is deleted as soon as this callback returns.
                    var file: ChatPickedFile?
                    if let url {
                        let name = ChatPickerStaging.photoName(suggestedName ?? url.lastPathComponent,
                                                               fileExtension: url.pathExtension)
                        file = ChatPickerStaging.stagePhoto(copying: url, name: name, dedupeKey: key)
                    }
                    continuation.yield((index, file))
                }
            }
            let count = chosen.count
            Task { @MainActor in
                let files = await Coordinator.collect(stream, count: count)
                self.loading = []
                self.onPicked(files)
            }
        }

        /// Waits until every load reported back and keeps the order the user chose.
        nonisolated private static func collect(_ stream: AsyncStream<(Int, ChatPickedFile?)>,
                                                count: Int) async -> [ChatPickedFile] {
            var files = [ChatPickedFile?](repeating: nil, count: count)
            var received = 0
            for await (index, file) in stream {
                files[index] = file
                received += 1
                if received == count { break }
            }
            return files.compactMap { $0 }
        }
    }
}

/// The Files picker. With `asCopy` the system puts its own copies in the app's Inbox;
/// they are moved into staging and the app keeps no access to the originals.
@MainActor struct ChatDocumentPicker: UIViewControllerRepresentable {
    /// Called once on the main actor, in the order picked; empty when the user cancels.
    let onPicked: ([ChatPickedFile]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {}

    @MainActor final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPicked: ([ChatPickedFile]) -> Void
        private var finished = false

        init(onPicked: @escaping ([ChatPickedFile]) -> Void) { self.onPicked = onPicked }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard !finished else { return }
            finished = true
            Task { @MainActor in
                // A move is instant, but a fallback copy of a large file is not.
                let files = await Task.detached(priority: .userInitiated) {
                    urls.compactMap { ChatPickerStaging.stageDocument($0) }
                }.value
                self.onPicked(files)
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            guard !finished else { return }
            finished = true
            onPicked([])
        }
    }
}

/// Staging shared by the pickers, in ChatAttachmentImport's layout: one folder per file,
/// so equal names never collide and the store can delete the folder after the move.
private enum ChatPickerStaging {
    static let root = FileManager.default.temporaryDirectory
        .appending(component: "ChatAttachmentImports", directoryHint: .isDirectory)

    /// Copies a file the system lends only for the length of a callback.
    static func stagePhoto(copying source: URL, name: String, dedupeKey: String?) -> ChatPickedFile? {
        let safeName = ChatAttachmentNaming.sanitized(name, fallback: ChatAttachmentPickerText.photo + ".jpg")
        guard let destination = destination(for: safeName) else { return nil }
        do { try FileManager.default.copyItem(at: source, to: destination) } catch {
            removeFolder(of: destination)
            return nil
        }
        return ChatPickedFile(temporaryURL: destination, suggestedName: safeName,
                              contentType: typeIdentifier(forExtension: destination.pathExtension), dedupeKey: dedupeKey)
    }

    /// Writes bytes Photos exported. Call off the main actor: originals can be large.
    static func stagePhoto(_ data: Data, name: String, contentType: String?, dedupeKey: String?) -> ChatPickedFile? {
        let safeName = ChatAttachmentNaming.sanitized(name, fallback: ChatAttachmentPickerText.photo + ".jpg")
        guard let destination = destination(for: safeName) else { return nil }
        do { try data.write(to: destination, options: .atomic) } catch {
            removeFolder(of: destination)
            return nil
        }
        return ChatPickedFile(temporaryURL: destination, suggestedName: safeName,
                              contentType: contentType ?? typeIdentifier(forExtension: destination.pathExtension),
                              dedupeKey: dedupeKey)
    }

    /// Takes over a document picker's copy. Only a copy inside the app's own container is
    /// moved; anything else is copied, so a user's original can never be moved away.
    static func stageDocument(_ source: URL) -> ChatPickedFile? {
        let safeName = ChatAttachmentNaming.sanitized(source.lastPathComponent, fallback: ChatAttachmentPickerText.file)
        guard let destination = destination(for: safeName) else { return nil }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let manager = FileManager.default
        do {
            if isInsideAppContainer(source) {
                do { try manager.moveItem(at: source, to: destination) } catch {
                    try manager.copyItem(at: source, to: destination)
                    try? manager.removeItem(at: source)
                }
            } else {
                try manager.copyItem(at: source, to: destination)
            }
        } catch {
            removeFolder(of: destination)
            return nil
        }
        return ChatPickedFile(temporaryURL: destination, suggestedName: safeName,
                              contentType: typeIdentifier(forExtension: destination.pathExtension), dedupeKey: nil)
    }

    /// The library's own name ("IMG_0001.HEIC") with an extension that matches the bytes,
    /// so an edit Photos rendered as JPEG becomes "IMG_0001.jpeg".
    static func photoName(_ raw: String?, fileExtension ext: String) -> String {
        let fallback = ChatAttachmentPickerText.photo + "." + (ext.isEmpty ? "jpg" : ext)
        var name = ChatAttachmentNaming.sanitized(raw ?? "", fallback: "")
        guard !name.isEmpty else { return fallback }
        let current = (name as NSString).pathExtension
        if !ext.isEmpty, !sameType(current, ext) {
            if !current.isEmpty, UTType(filenameExtension: current)?.conforms(to: .image) == true {
                name = (name as NSString).deletingPathExtension
            }
            name += "." + ext
        }
        return ChatAttachmentNaming.sanitized(name, fallback: fallback)
    }

    private static func sameType(_ lhs: String, _ rhs: String) -> Bool {
        guard !lhs.isEmpty, !rhs.isEmpty else { return false }
        if lhs.caseInsensitiveCompare(rhs) == .orderedSame { return true }
        guard let left = UTType(filenameExtension: lhs), let right = UTType(filenameExtension: rhs) else { return false }
        return left == right
    }

    private static func typeIdentifier(forExtension ext: String) -> String? {
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext), !type.isDynamic else { return nil }
        return type.identifier
    }

    private static func destination(for name: String) -> URL? {
        let folder = root.appending(component: UUID().uuidString, directoryHint: .isDirectory)
        do { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) } catch { return nil }
        return folder.appending(component: name, directoryHint: .notDirectory)
    }

    private static func removeFolder(of file: URL) {
        try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
    }

    private static func isInsideAppContainer(_ url: URL) -> Bool {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).resolvingSymlinksInPath().path
        return url.resolvingSymlinksInPath().path.hasPrefix(home.hasSuffix("/") ? home : home + "/")
    }
}
