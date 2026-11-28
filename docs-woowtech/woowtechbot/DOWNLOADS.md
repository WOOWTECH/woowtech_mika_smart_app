# Downloads in the woowtechbot service screen (2026-11-28)

Owner, 2026-11-28: on a phone, files from woowtechbot did not download ("無法儲存此下載……尚不支援網頁產生的 blob 下載"). Every file
type has to download on iOS and Android, including images, video, audio, PDF, Word, Excel, HTML and ZIP. Android is in this
repository. The iOS bot app does the same through `WKDownload` (iOS line, conversation 37b531c3).

## What the website does (App.js, 2026-11-27 bundle)

- **Workspace files** (the ↓ next to a path in a chat):
  - The page sends `POST /api/threads/{thread}/messages/{message}/file` with `{path, entry | listFolder | media}`.
  - A response with `x-openmausbot-folder: 1` is a folder listing (JSON), not a download.
  - Otherwise the page builds a Blob, creates an object URL and clicks an `<a download>`. The name comes from Content-Disposition, a fallback and the type. Right after the click the page calls `setTimeout(revokeObjectURL, 0)`.
  - The app hears about the download only once the object URL is already gone.
- **Other Blob downloads:**
  - Code snippets (text/plain, revoked after 1 s).
  - Table CSV export (revoked after 1 s).
  - Transcript `.md` (revoked after 60 s).
  - The HTML page preview's "save": the type is `application/octet-stream` and the name ends in `.html`. On touch devices it first tries `navigator.share`, which Android WebView does not have.
- **Direct link:** only the workspace backup, `/api/workspace-backup/download/{id}`, opened with `<a download>`.
- **Not used for downloads:** `window.open` (sign-in and connectors only) and `location.href`.

## Android behaviour

| Source | How |
| --- | --- |
| `blob:<service origin>/…` | `assets/woowtechbot/workspace-downloads.js` runs at document start (`addDocumentStartJavaScript`, also on page load for older WebViews). It wraps `URL.createObjectURL` so each Blob stays readable for 60 s after the page revokes its URL. It records each `<a download>` name. It hands the Blob over in 512 KiB base64 chunks; `BotBlobReader` polls with `evaluateJavascript` and the page gets no native interface. Object URLs of other origins are refused. |
| `data:` | Decoded natively (`BotDataUrl`), base64 or percent-encoded, 32 MB at most. |
| The service's own URL | OkHttp with the profile's cookie and the service's Origin. Up to 5 redirects. A redirect to another https host (storage) gets no cookie and no Origin. |
| Another site's https URL | Confirmation first: "下載其他網站的檔案？", with the file name and host. Then the same download without cookie. This only happens when the WebView reports another site's file as a download, for example from a frame. A link to another site is stopped before it loads (the WebView decides before the response), so it gets the existing "在外部瀏覽器開啟連結？" and the browser downloads it. iOS can see the response type first and asks "下載其他網站的檔案？" there. |

- Only a download within 60 s of the user's last touch on the page is taken, the same rule as iOS. Others show "已擋下沒有經過你點擊的下載。".
- **Names and types** (`BotDownloadNames`):
  - Name: `<a download>`, then Content-Disposition (`filename*` before `filename`), then the URL's last segment.
  - For direct and `data:` downloads the WebView reports only the URL. The page script remembers the anchors clicked in the last 10 s, and the app asks for the name by the URL's first 128 characters and its length.
  - Type: a known extension decides it, so the website's `octet-stream` HTML saves as `text/html`. Otherwise the response or Blob type is used, and its extension is added when the name has none.
  - Names are cleaned: no path, control characters, direction overrides or reserved characters; 120 characters at most, keeping the extension.
- **Saving:** files go to the phone's Downloads folder through MediaStore (`IS_PENDING` until complete, removed on failure or cancel). No location picker and no storage permission.
- **Status row:**
  - Above the page: "正在下載：名稱" with a percentage, a progress bar and 取消.
  - When done: "已下載到「下載」資料夾：名稱" with 開啟 (the system app for that type) and 關閉.
  - On failure: the reason with 知道了. The old row's 重試 reloaded the page; it is now used only for page errors.
- **Limits:** direct and Blob downloads 2 GB, `data:` 32 MB. One download at a time.

## Tests

- `app/src/test/.../BotDownloadNamesTest.kt`:
  - Content-Disposition, including RFC 5987 and quoted names.
  - Name order, type by extension, extension by type, cleaning.
  - `data:` URLs, the object URL origin check and the evaluateJavascript answers.
- `tools/woowtechbot-ui/workspace-downloads-test.cjs` (Playwright):
  - The hook against the website's own pattern: the URL is revoked at once and a 1 MiB+ Blob is read back exactly.
  - The anchor name, the unknown and failed cases, and the release of revoked Blobs after 60 s.
- `app/src/androidTest/.../BotDownloadsDeviceTest.kt` runs in the GitHub emulator workflow `woowtechbot-device.yml`:
  - A real WebView page makes a revoked 1.5 MiB `.xlsx` Blob. It is read back, saved into Downloads, and checked byte for byte, by type and by folder.
  - Common types save under their own names, and a `data:` CSV is saved.
  - Failed and cancelled downloads leave nothing behind.
- `app/src/androidTest/.../BotDownloadsEndToEndTest.kt`, in the same workflow:
  - The real service screen opens the test page below. The page runs on the emulator's host and is reached as `http://10.0.2.2:8766` with the trusted-LAN option.
  - A download without a tap is blocked.
  - After a tap, each way saves its file into Downloads under its own name and type, byte for byte: the website's POST → Blob → revoke (xlsx, html, png, Chinese name), direct (pdf), attachment (docx), redirect (zip) and `data:` (csv with its anchor name).
- `tools/woowtechbot-ui/downloads-fixture.py`, a test page for both platforms:
  - Every type comes four ways: direct, attachment header, redirect, and the website's POST → Blob → revoke pattern.
  - It also has `data:` links, a Chinese file name, another site's PDF (asks first) and a download that starts 70 s after the last tap (must be blocked).
  - Run it as `python3 tools/woowtechbot-ui/downloads-fixture.py --host <LAN IP>`. Add the address as a service with the trusted-LAN option.
