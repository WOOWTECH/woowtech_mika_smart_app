# GitHub 與商店版共用功能對齊

來源：商店版 `SHARED_CORE_ALIGNMENT_HANDOFF_2026-11-12.md`。本次只改兩版都有的外部 MCP 與個人技能行為；商店版不加入 GitHub 版的手機對電腦服務或跨 App 控制。

## 實作

- MCP 清單：一般工具、合成 `resource_read`、合成 `prompt_get` 都在組裝時遵守每伺服器的 `allowedTools`。`null` 保持舊設定的「不限制」；空集合保持「全部不允許」。呼叫前從目前伺服器設定重查，刪除、停用或撤銷工具後，下一次呼叫回傳 `mcp_tool_not_allowed`。任務開始時發給模型的工具定義仍是快照；已開始的呼叫無法追溯取消，下一次呼叫會被阻擋。
- 技能評分：把本次成功工具名稱提供給回答結果評分器，避免只因回答未提工具名稱就判作沒有使用。工具名稱不證明特定技能已成功完成任務。試用技能不因單次回答文字判定失敗而立即停用；可歸因的核查退回仍按原規則處理。
- MCP 長結果：GitHub 版沿用 `ConversationMcpResultStore` 寫入本對話工作區，再由既有沙箱 `read_file` 以位元組 offset 讀取。商店版沿用其專用結果讀取器；兩者 offset 單位不同，未合併成同名工具。

## 驗證與界線

- 核心測試涵蓋清單過濾、呼叫前撤銷、技能結果。App JVM 測試涵蓋長結果後段繁中與 emoji、跨對話工作區隔離、刪除清理。
- `:core:test` 指定 `McpClientTest`、`OutcomeJudgeTest`、`SkillOutcomesTest` 與 `:app:testUpstreamDebugUnitTest --tests '*ConversationMcpResultStoreTest'` 通過；商店版 `McpClientTest` 通過。
- GitHub 版 `:app:compileWoowtechDebugKotlin` 通過；商店版同任務通過。
- POCO 以 ADB 更新安裝 GitHub 候選 `0.1.37-woow.10` 和商店候選 `0.1.37-play.2`，兩個套件均可啟動；GitHub 版 MCP 設定頁仍顯示無伺服器，商店版原有 HA-MCP 設定仍可見。GitHub APK 已驗證 v2 簽章。這是候選包實測，不代表公開下載或 Play 上架。
- POCO 上同模型、同 MCP 設定的雙版本完整模型任務尚待實測；建置與單元測試不等於這項驗收。
- 兩版原本獨立的帳號、MCP 設定、技能資料不會自動同步。
