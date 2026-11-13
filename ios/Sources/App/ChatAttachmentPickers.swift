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

/// The panel's recent-photos grid. Unlike the system pickers it reads the library itself,
/// so it needs permission, and it asks on its own only once: the first time the panel opens.
@MainActor final class ChatRecentPhotos: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    enum Access: Equatable { case notDetermined, full, limited, denied }

    nonisolated static let hasAskedKey = "chat.attachments.photosAsked"

    @Published private(set) var access: Access = .notDetermined
    /// Images only, newest first, at most 120.
    @Published private(set) var assets: [PHAsset] = []
    /// True only while nothing is shown yet and the first fetch is running.
    @Published private(set) var isLoading = false

    private let defaults: UserDefaults
    private let imageManager = PHCachingImageManager()
    private var fetchResult: PHFetchResult<PHAsset>?
    /// Drops an older fetch that finishes after a newer one.
    private var generation = 0
    private var observing = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        access = Self.readAccess()
    }

    deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self) }

    /// Re-reads permission and the newest photos. Call when the panel appears and when the
    /// scene becomes active again: the user may have changed access in Settings.
    func refresh() {
        let latest = Self.readAccess()
        if latest != access { access = latest }
        guard latest == .full || latest == .limited else {
            // Reading the library before the user decides would raise the system prompt.
            generation += 1
            fetchResult = nil
            if !assets.isEmpty { assets = [] }
            if isLoading { isLoading = false }
            return
        }
        if !observing {
            observing = true
            PHPhotoLibrary.shared().register(self)
        }
        reload()
    }

    /// Shows the system prompt if the user has not decided yet; otherwise returns at once.
    func requestAccess() async {
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        refresh()
    }

    /// Android asks by itself only the first time the panel ever opens; after that the
    /// panel offers "允許存取照片" instead.
    func askOnceIfNeeded() async {
        guard Self.readAccess() == .notDetermined, !defaults.bool(forKey: Self.hasAskedKey) else { return }
        defaults.set(true, forKey: Self.hasAskedKey)
        await requestAccess()
    }

    /// "更改範圍": lets a limited-access user change which photos the app may see.
    func presentLimitedLibraryPicker() {
        guard let presenter = Self.topViewController() else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter) { @Sendable _ in
            Task { @MainActor in self.refresh() }
        }
    }

    /// A square thumbnail `side` points wide. Cancelling the calling task cancels the request.
    func thumbnail(for asset: PHAsset, side: CGFloat) async -> UIImage? {
        guard side.isFinite, side > 0 else { return nil }
        let pixels = (side * max(Self.activeScene()?.screen.scale ?? 2, 1)).rounded(.up)
        let request = ChatThumbnailRequest(manager: imageManager)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                request.start(continuation, asset: asset, pixels: pixels)
            }
        } onCancel: {
            request.cancel()
        }
    }

    /// The photo as the library shows it (edits included), staged like a picked file.
    func export(_ asset: PHAsset) async -> ChatPickedFile? {
        let resources = PHAssetResource.assetResources(for: asset)
        let original = (resources.first { $0.type == .photo } ?? resources.first)?.originalFilename
        let identifier = asset.localIdentifier
        let options = PHImageRequestOptions()
        options.version = .current
        options.isNetworkAccessAllowed = true
        let exported: (data: Data, type: String?)? = await withCheckedContinuation { continuation in
            // Photos answers exactly once, on the main thread, after any iCloud download.
            _ = PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { @Sendable data, type, _, _ in
                continuation.resume(returning: data.map { (data: $0, type: type) })
            }
        }
        guard let exported else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> ChatPickedFile? in
            let ext = exported.type.flatMap { UTType($0)?.preferredFilenameExtension }
                ?? ((original ?? "") as NSString).pathExtension
            return ChatPickerStaging.stagePhoto(exported.data, name: ChatPickerStaging.photoName(original, fileExtension: ext),
                                                contentType: exported.type, dedupeKey: identifier)
        }.value
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        // Arrives on a Photos queue; edits to a limited selection arrive here too.
        Task { @MainActor in self.libraryDidChange(changeInstance) }
    }

    private func libraryDidChange(_ change: PHChange) {
        guard Self.readAccess() == access, let fetchResult else { refresh(); return }
        if change.changeDetails(for: fetchResult) != nil { reload() }
    }

    private func reload() {
        generation += 1
        let current = generation
        if assets.isEmpty { isLoading = true }
        Task { @MainActor in
            let fetched = await Task.detached(priority: .userInitiated) { ChatRecentPhotos.fetchRecent() }.value
            guard self.generation == current else { return }
            self.fetchResult = fetched.result
            self.assets = fetched.assets
            self.isLoading = false
        }
    }

    /// The user's own library only (no shared albums), newest first, like Photos' Recents.
    nonisolated private static func fetchRecent() -> (result: PHFetchResult<PHAsset>, assets: [PHAsset]) {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 120
        options.includeAssetSourceTypes = [.typeUserLibrary]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        return (result, result.objects(at: IndexSet(integersIn: 0..<result.count)))
    }

    private static func readAccess() -> Access {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: return .full
        case .limited: return .limited
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    private static func activeScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    private static func topViewController() -> UIViewController? {
        var top = activeScene()?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
        return top
    }
}

/// One thumbnail request. Photos may answer on the calling thread, more than once (a
/// degraded image first), or not at all once cancelled; the waiting task resumes once,
/// with the degraded image if nothing better arrived.
private final class ChatThumbnailRequest: @unchecked Sendable {
    private let manager: PHImageManager
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UIImage?, Never>?
    private var requestID: PHImageRequestID?
    private var degraded: UIImage?
    private var cancelled = false

    init(manager: PHImageManager) { self.manager = manager }

    func start(_ continuation: CheckedContinuation<UIImage?, Never>, asset: PHAsset, pixels: CGFloat) {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            continuation.resume(returning: nil)
            return
        }
        self.continuation = continuation
        lock.unlock()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        let id = manager.requestImage(for: asset, targetSize: CGSize(width: pixels, height: pixels),
                                      contentMode: .aspectFill, options: options) { @Sendable image, info in
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue ?? false
            if isDegraded { self.keep(image) } else { self.finish(image) }
        }
        lock.lock()
        requestID = id
        let cancelNow = cancelled
        lock.unlock()
        if cancelNow { manager.cancelImageRequest(id) }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let id = requestID
        lock.unlock()
        if let id { manager.cancelImageRequest(id) }
        finish(nil)
    }

    private func keep(_ image: UIImage?) {
        guard let image else { return }
        lock.lock()
        degraded = image
        lock.unlock()
    }

    private func finish(_ image: UIImage?) {
        lock.lock()
        let waiting = continuation
        continuation = nil
        let result = image ?? degraded
        lock.unlock()
        waiting?.resume(returning: result)
    }
}

/// One square of the recent-photos grid. The caller wraps it in a button and owns the selection.
@MainActor struct ChatRecentPhotoCell: View {
    let asset: PHAsset
    /// The 1-based number shown in the badge (the photo's place in the tray), or nil.
    let selectedIndex: Int?
    let accent: Color
    let photos: ChatRecentPhotos
    /// VoiceOver words in the chosen interface language.
    var photoLabel: String = ChatAttachmentPickerText.photo
    var selectedLabel: String = ChatAttachmentPickerText.selected
    @State private var loaded: Loaded?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6)
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { GeometryReader { proxy in picture(side: proxy.size.width) } }
            .overlay { if selectedIndex != nil { accent.opacity(0.12) } }
            .clipShape(shape)
            .overlay { if selectedIndex != nil { shape.strokeBorder(accent, lineWidth: 2.5) } }
            .overlay(alignment: .topTrailing) { badge.padding(5) }
            .contentShape(shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(photoLabel)
            .accessibilityValue(selectedIndex == nil ? "" : selectedLabel)
            .accessibilityAddTraits(.isButton)
    }

    private func picture(side: CGFloat) -> some View {
        let id = asset.localIdentifier
        return ZStack {
            Color(uiColor: .secondarySystemFill)
            if let loaded, loaded.id == id {
                Image(uiImage: loaded.image).resizable().scaledToFill()
            }
        }
        .frame(width: side, height: side)
        .clipped()
        .task(id: Request(id: id, modified: asset.modificationDate, side: side.rounded())) {
            guard side >= 1, let image = await photos.thumbnail(for: asset, side: side), !Task.isCancelled else { return }
            loaded = Loaded(id: id, image: image)
        }
    }

    @ViewBuilder private var badge: some View {
        if let selectedIndex {
            Text(verbatim: String(selectedIndex))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 22, height: 22)
                .background(accent, in: Circle())
        } else {
            Circle()
                .strokeBorder(Color.white, lineWidth: 1.5)
                .frame(width: 22, height: 22)
                // Keeps the empty ring visible on light photos.
                .shadow(color: Color.black.opacity(0.3), radius: 1.5)
        }
    }

    private struct Loaded {
        let id: String
        let image: UIImage
    }

    /// Reloads for another asset, an edited photo or a new size, not on every redraw.
    private struct Request: Equatable {
        let id: String
        let modified: Date?
        let side: CGFloat
    }
}
