#if WOOWTECHBOT
import AssistantPersistence
import AVFoundation
import SwiftUI
import VisionKit

struct BotPairingView: View {
    let service: BotServiceRecord
    let localizer: AppLocalizer
    let connect: (URL) -> Void
    @State private var scanning = false
    @State private var requesting = false
    @State private var pasted = ""
    @State private var pending: URL?
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    private func t(_ zh: String, _ en: String) -> String { localizer.language == .english ? en : zh }
    var body: some View {
        let palette = MikaVisualPalette(scheme, look: .sheet)
        BotSheetScaffold(title: t("掃描配對 QR", "Scan pairing QR"), closeLabel: t("關閉", "Close"), closeIdentifier: "bot.pair.cancel",
                         close: { pending = nil; pasted = ""; dismiss() }) {
            Text(service.name + "\n" + service.origin).scaledFont(size: 13).foregroundStyle(palette.secondaryInk).textSelection(.enabled)
                .padding(.horizontal, 8).frame(maxWidth: .infinity, alignment: .leading)
            BotCard {
                BotSettingsRow(title: t("掃描配對 QR", "Scan pairing QR"), symbol: "camera", enabled: !requesting,
                               identifier: "bot.pair.scan") { Task { await startScanner() } }
            }
            Text(t("只接受這個服務的 HTTPS 配對碼。掃描後需再確認連線。", "Only HTTPS invitations for this service are accepted. Confirm before connecting."))
                .scaledFont(size: 13).lineSpacing(2).foregroundStyle(palette.secondaryInk)
                .padding(.horizontal, 8).frame(maxWidth: .infinity, alignment: .leading)
            BotSectionLabel(text: t("或貼上配對連結", "Or paste pairing link"))
            BotTextField(label: t("配對連結", "Pairing link"), text: $pasted, identifier: "bot.pair.link", secure: true)
            BotPillButton(title: t("檢查連結", "Check link"), enabled: !pasted.isEmpty, identifier: "bot.pair.check") { accept(pasted); pasted = "" }
            if let error {
                Text(error).scaledFont(size: 13).foregroundStyle(palette.destructive).padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("bot.pair.error")
            }
        }
        .fullScreenCover(isPresented: $scanning) {
            NavigationStack {
                BotQRScanner { result in
                    scanning = false
                    if let result { accept(result) }
                    else { error = t("無法讀取相機，請確認權限後重試。", "Camera is unavailable. Check permission and try again.") }
                }.ignoresSafeArea(edges: .bottom)
                    .navigationTitle(t("對準服務的配對 QR", "Point at the service pairing QR"))
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button(t("取消", "Cancel")) { scanning = false }
                    } }
            }
        }
        // Android: a dialog on the popover surface - the service's name and origin, then Cancel / Connect.
        .botDialog(isPresented: pending != nil && !scanning, dismiss: { pending = nil }) {
            BotDialogSurface {
                BotDialogTitle(text: t("連線至此服務？", "Connect to this service?"))
                BotDialogBody(text: service.name + "\n" + service.origin)
                HStack(spacing: 10) {
                    BotDialogButton(title: t("取消", "Cancel"), kind: .dismiss, identifier: "bot.pair.dismiss") { pending = nil }
                    BotDialogButton(title: t("連線", "Connect"), kind: .confirm, identifier: "bot.pair.connect") {
                        if let url = pending { connect(url) }; pending = nil; dismiss()
                    }
                }.padding(.top, 24)
            }
        }
        .onDisappear { pasted = ""; pending = nil }
    }
    private func accept(_ raw: String) {
        do { pending = try BotPairingLink.validate(raw, for: service.policy); error = nil }
        catch { self.error = t("這不是此服務的有效配對連結。尚未連線。", "This is not a valid pairing link for this service. Nothing was connected.") }
    }
    private func startScanner() async {
        guard !requesting else { return }; requesting = true
        defer { requesting = false }
        guard DataScannerViewController.isSupported else {
            error = t("此裝置無法使用相機掃描，可改貼上配對連結。", "Camera scanning is unavailable on this device. Paste a pairing link instead."); return
        }
        var granted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        }
        guard granted, DataScannerViewController.isAvailable, !Task.isCancelled else {
            error = t("請在系統設定允許相機，或貼上配對連結。", "Allow camera access in Settings, or paste a pairing link."); return
        }
        error = nil; scanning = true
    }
}

private struct BotQRScanner: UIViewControllerRepresentable {
    let result: (String?) -> Void
    func makeCoordinator() -> Coordinator { .init(result: result) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced, recognizesMultipleItems: false, isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true, isGuidanceEnabled: true, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        do { try scanner.startScanning() }
        catch { Task { @MainActor in context.coordinator.finish(nil, scanner: scanner) } }
        return scanner
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) { controller.stopScanning() }
    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let result: (String?) -> Void
        private var completed = false
        init(result: @escaping (String?) -> Void) { self.result = result }
        func finish(_ text: String?, scanner: DataScannerViewController) {
            guard !completed else { return }; completed = true; scanner.stopScanning(); result(text)
        }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                if case .barcode(let code) = item, let payload = code.payloadStringValue { finish(payload, scanner: dataScanner); return }
            }
        }
        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            finish(nil, scanner: dataScanner)
        }
    }
}
#endif
