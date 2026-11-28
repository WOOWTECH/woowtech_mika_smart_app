/// The names a downloaded file is kept under (owner 2026-11-28: every type downloads with its own name and extension).
/// Run with scripts/CheckBrowserDownloadNames.sh.
@testable import AssistantBrowser
import Foundation

var failures = 0
func check(_ got: String, _ want: String, _ what: String) {
    if got != want { failures += 1; print("FAIL \(what): got \"\(got)\" want \"\(want)\"") } else { print("ok   \(what): \(got)") }
}
let name = { (n: String, m: String?) in BrowserDownloadRules.fileName(BrowserDownloadManager.withExtension(n, mimeType: m)) }
check(name("sample.m4a", "audio/mp4"), "sample.m4a", "m4a kept")
check(name("sample.mp4", "audio/mp4"), "sample.m4a", "audio-only mp4 named m4a")
check(name("sample.mp4", "video/mp4"), "sample.mp4", "video mp4 kept")
check(name("recording", "audio/mp4"), "recording.m4a", "no extension, audio/mp4")
check(name("report-no-extension", "application/pdf"), "report-no-extension.pdf", "no extension, pdf")
check(name("table", "text/csv"), "table.csv", "no extension, csv")
check(name("blob", "application/octet-stream"), "blob", "octet-stream adds nothing")
check(name("sample-page.html", "application/octet-stream"), "sample-page.html", "octet-stream html kept")
check(name("中文檔名 測試.pdf", "application/pdf"), "中文檔名 測試.pdf", "Chinese name kept")
check(name("data-表格.csv", "text/csv"), "data-表格.csv", "data CSV name kept")
check(name("../../etc/passwd", "text/plain"), "_.._etc_passwd.txt", "no path")
check(name("a\u{202E}fdp.exe", "application/pdf"), "a_fdp.exe", "direction override removed")
check(name("q?:*<>|.txt", "text/plain"), "q______.txt", "reserved characters")
let long = String(repeating: "長", count: 200) + ".pdf"
let cut = name(long, "application/pdf")
let kept = cut.hasSuffix(".pdf") && cut.utf8.count <= 120
print(kept ? "ok   long name keeps .pdf within 120 bytes (\(cut.count) characters)" : "FAIL long name: \(cut)")
if !kept { failures += 1 }
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
