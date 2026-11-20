# 非上架 Android 文件產生功能

範圍：woowtech／Apporo 共用核心。此變更不包含 iOS、新增商店發布流程、XLSX 或 DOCX。

## 使用流程

1. 在對話要求將已知內容製成 HTML、PDF 或 CSV。
2. 模型呼叫 `create_document`，傳入明確內容。來源或多表格指涉不明時先詢問。
3. 工具在目前對話工作區的 `documents/` 新建文件，重名另編序號，不覆寫舊文件。
4. 模型呼叫既有 `share_file`，以 MediaStore 寫入品牌的下載資料夾，對話顯示附件卡片。
5. 點附件預覽；預覽頂欄可另存副本、開啟系統分享或使用其他 App 開啟。

產檔本身在本機完成；對話模型是否需要網路依既有設定。`share_file` 是儲存下載附件，沒有自動傳送給聯絡人。系統分享面板的開啟不代表收件者收到。

## 技術與依賴

- `core/document/Document.kt`：共用資料模型、欄位驗證、HTML 轉義、CSV 序列化及安全檔名。
- `CreateDocument`／`SandboxTools.createDocument`：模型工具註冊、工作區安全寫入、儲存額度與錯誤回報。
- `SandboxPort.renderDocumentPdf`：平台介面；未實作的平台明確回報不支援。
- `core/document/DocumentToolDefinition.kt`：單一工具 schema，渠道轉接提供各自的交付說明。
- Android `app/.../document/DocumentPdf.kt`：使用系統 PdfDocument、StaticLayout 與字型 fallback 分頁；不下載字型、不建立 WebView、不載入外部資源。
- 沿用 WebView HTML 預覽、PdfRenderer PDF 預覽、文字 CSV 預覽、MediaStore 匯出及系統分享。
- 新增 Storage Access Framework 的 CreateDocument「另存副本」。只在寫入成功後回報儲存成功；取消另行提示。
- 沒有新增第三方依賴、廣泛儲存權限或外部產檔服務。

平台參考：[PdfDocument](https://developer.android.com/reference/android/graphics/pdf/PdfDocument)、[系統文件選擇器](https://developer.android.com/training/data-storage/shared/documents-files)。

## 文件契約

```json
{
  "format": "html",
  "document": {
    "title": "中文報告",
    "sections": [
      {"type": "heading", "level": 1, "text": "摘要"},
      {"type": "paragraph", "text": "報告內容"},
      {"type": "bulletList", "items": ["項目一", "項目二"]},
      {"type": "table", "columns": ["項目", "數量"], "rows": [["A", "10"], ["B", "20"]]}
    ]
  }
}
```

也支援 `orderedList`。CSV 多表格時必須指定零起算的 `tableIndex`；不任意合併資料。

## 限制與資料處理

- 文件 JSON 上限 250,000 字元；標題 200 字元；區段 200 個；表格 12 欄、1,000 列；PDF 200 頁；輸出 20 MiB。
- HTML 是靜態文件，文字轉義並帶 CSP，禁止腳本及外部資源。不提供公開網址。
- CSV 為 UTF-8 BOM、CRLF、所有欄位加引號；雙引號加倍。疑似公式欄位加前置單引號，工具回應與技能指引要求告知使用者。試算表仍可能自行轉換日期、前導零等資料。
- PDF 表格使用格線與跨頁重複標題列；過長的欄名超過 200pt 時，改採逐列「欄名：內容」版面，避免標題佔滿頁面而無法交付。中文使用裝置系統字型；Emoji 與不常見字形仍需目標手機驗收。
- 工作區文件沿用對話工作區生命週期；下載附件為持久副本，使用者可從下載資料夾刪除；另存或傳送的副本不由 App 自動清除。
- 工具沿用既有沙箱能力提供條件；首次環境準備仍可能等待。非 Android 平台不宣稱 PDF 支援。
- 當前 UI 使用既有檔案卡片，沒有新增文件歷史庫或對話範圍選取編輯器。

## 測試與交付狀態

測試結果待本次執行完成後填入。POCO 目前未透過 ADB 連線，不能把模擬器結果當成 POCO 實機通過。

尚未合併 main 或公開發布。測試 APK 是開發驗證用途，不是使用者正式更新包。
