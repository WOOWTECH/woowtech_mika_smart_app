#if WOOWTECHBOT
import AssistantBrowser
import SwiftUI

/// A finished download already copied into Files.
struct BotSavedDownload: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let url: URL
}

/// Files › On My iPhone › 渥屋助理 Bot: the app's Documents, which the app treats as the person's own files (Files shows it
/// because of UIFileSharingEnabled). Downloads from a service are kept there, as Android keeps them in Downloads.
enum BotDownloadsFolder {
    static var url: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    /// The folder's name in Files: the app's display name (渥屋助理 Bot, WOOW Assistant Bot in English).
    static var displayName: String {
        (Bundle.main.localizedInfoDictionary?["CFBundleDisplayName"] ?? Bundle.main.infoDictionary?["CFBundleDisplayName"]) as? String
            ?? "渥屋助理 Bot"
    }

    /// Copies a finished download in, as "name (2).ext" when the name is taken.
    static func copy(_ source: URL, named name: String) throws -> URL {
        let folder = url
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
        var target = folder.appendingPathComponent(name)
        var number = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent(ext.isEmpty ? "\(base) (\(number))" : "\(base) (\(number)).\(ext)")
            number += 1
        }
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }
}

/// What the status line says once no download is running.
enum BotDownloadNotice: Equatable {
    case saved(BotSavedDownload)
    /// It finished but could not be copied into Files; it stays in the service menu's 下載.
    case unsaved(String)
    /// The website started it without the person's tap (Android: 已擋下沒有經過你點擊的下載。).
    case untapped
    /// A file another site's page made (a blob: or data: link not from this service).
    case unsupported
    case failed(UUID)
}

/// Android's download row on the service screen (owner 2026-11-28, Android PR #64): 「正在下載：名稱 NN%」 with a progress bar
/// and 取消; when done, where it was kept with 開啟 (Quick Look, which can share or save it elsewhere) and 關閉; otherwise
/// why it did not download, with 知道了. A refusal while another download runs is shown first, until 知道了.
struct BotDownloadStatusLine: View {
    @ObservedObject var web: BotWebSession
    @ObservedObject var downloads: BrowserDownloadManager
    let localizer: AppLocalizer
    let open: (URL) -> Void
    @Environment(\.colorScheme) private var scheme
    private var english: Bool { localizer.language == .english }
    private func t(_ zh: String, _ en: String) -> String { english ? en : zh }

    var body: some View {
        let palette = MikaVisualPalette(scheme)
        let active = downloads.items.first(where: { $0.phase.isActive })
        if let notice = web.downloadNotice, active == nil || notice == .untapped || notice == .unsupported || isBusy(notice) {
            noticeRow(notice, palette: palette)
        } else if let active {
            VStack(spacing: 0) {
                row(text: progressText(active), palette: palette) {
                    button(t("取消", "Cancel"), "bot.download.cancel", palette) { downloads.cancel(active.id) }
                }
                BotLinearProgress(fraction: fraction(active))
            }
        }
    }

    @ViewBuilder private func noticeRow(_ notice: BotDownloadNotice, palette: MikaVisualPalette) -> some View {
        switch notice {
        case .saved(let saved):
            row(text: english ? "Saved to Files › \(BotDownloadsFolder.displayName): \(saved.name)"
                              : "已下載到「檔案」App 的「\(BotDownloadsFolder.displayName)」：\(saved.name)", palette: palette) {
                button(t("開啟", "Open"), "bot.download.open", palette) { open(saved.url) }
                button(t("關閉", "Close"), "bot.download.close", palette) { web.downloadNotice = nil }
            }
        case .unsaved(let name):
            row(text: english ? "Downloaded, but it could not be kept in Files: \(name). Share it or save it from Downloads in the service menu."
                              : "已下載，但沒能存到「檔案」App：\(name)。可以在服務選單的「下載」裡分享或存到檔案。", palette: palette) {
                dismiss(palette)
            }
        case .untapped:
            row(text: t("已擋下沒有經過你點擊的下載。", "Blocked a download you didn’t tap."), palette: palette) { dismiss(palette) }
        case .unsupported:
            row(text: Self.unsupportedText(english), palette: palette) { dismiss(palette) }
        case .failed(let id):
            if let item = downloads.items.first(where: { $0.id == id }), case .failed(let failure) = item.phase {
                row(text: failureText(failure, pageMade: web.pageMadeDownloads.contains(id)), palette: palette) { dismiss(palette) }
            }
        }
    }

    private static func unsupportedText(_ english: Bool) -> String {
        english ? "This file can’t be downloaded: the link isn’t supported or doesn’t come from this service."
                : "無法下載這個檔案：連結格式不支援，或不是來自這個服務。"
    }

    private func isBusy(_ notice: BotDownloadNotice) -> Bool {
        guard case .failed(let id) = notice, let item = downloads.items.first(where: { $0.id == id }) else { return false }
        return item.phase == .failed(.tooMany)
    }

    private func row<Buttons: View>(text: String, palette: MikaVisualPalette, @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: text).scaledFont(size: 12).foregroundStyle(palette.ink).lineLimit(2).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("bot.download.status")
            buttons()
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(palette.background)
    }

    private func button(_ title: String, _ identifier: String, _ palette: MikaVisualPalette, action: @escaping () -> Void) -> some View {
        Button(title, action: action).scaledFont(size: 14, weight: .medium).foregroundStyle(palette.accent)
            .padding(.horizontal, 8).frame(minHeight: 40).contentShape(Rectangle()).accessibilityIdentifier(identifier)
    }

    private func dismiss(_ palette: MikaVisualPalette) -> some View {
        button(t("知道了", "OK"), "bot.download.dismiss", palette) { web.downloadNotice = nil }
    }

    private func fraction(_ item: BrowserDownloadItem) -> Double? {
        guard let expected = item.expectedBytes, expected > 0 else { return nil }
        return min(1, max(0, Double(item.receivedBytes) / Double(expected)))
    }

    private func progressText(_ item: BrowserDownloadItem) -> String {
        let name = item.fileName.isEmpty ? t("檔案", "file") : item.fileName
        let head = english ? "Downloading \(name)" : "正在下載：\(name)"
        return fraction(item).map { "\(head) \(Int($0 * 100))%" } ?? head
    }

    /// Android's reasons, with iOS's own two (the app's waiting downloads, a full device).
    private func failureText(_ failure: BrowserDownloadFailure, pageMade: Bool) -> String {
        switch failure {
        case .tooLarge: return t("檔案太大，無法下載（上限 2 GB）。", "This file is too large to download (limit 2 GB).")
        case .tooMany: return t("另一個下載還在進行，請等它完成。", "Another download is still running. Wait for it to finish.")
        case .unsafeAddress: return Self.unsupportedText(english)
        case .storageFull:
            return t("下載失敗：App 裡暫存的下載已達 4 GB，請先在服務選單的「下載」移除幾個。",
                     "The download failed: downloads kept in the app have reached 4 GB. Remove a few from Downloads in the service menu.")
        case .deviceFull: return t("下載失敗：這台裝置的空間不足。", "The download failed: this device is out of space.")
        default:
            return pageMade ? t("無法讀取網頁產生的檔案，請在網頁上再按一次下載。", "Couldn’t read the file the page made. Tap download on the page again.")
                            : t("下載失敗，檔案沒有儲存。請確認網路後再試一次。", "The download failed and nothing was saved. Check your connection and try again.")
        }
    }
}

#endif
