# 電腦端 AI 快速連線

繁體中文 | [English](agent-quickstart.en.md)

給電腦上的 AI 助手（例如 Claude Code、Codex）：照下面固定步驟，安裝 CLI 或 Skill，連上手機上的渥屋助理（woowtech agent）。步驟已經定好，不用自己比較方案。

渥屋助理是開源專案 [Mika](https://github.com/wangzan101/Mika) 的 WOOWTECH 品牌版。CLI 和 Skill 沿用上游的 `mika` 名稱。手機上的套件名是 `io.woowtech.agent`，CLI 經 ADB 會自己找到它。

## 1. 查最新版本

```sh
curl -s https://api.github.com/repos/WOOWTECH/woowtech_mika_smart_app/releases/latest   # 讀 tag_name
```

```powershell
(Invoke-RestMethod https://api.github.com/repos/WOOWTECH/woowtech_mika_smart_app/releases/latest).tag_name
```

下面的 `<tag>` 是這個值，例如 `v0.1.37-woow.1`；`<ver>` 是去掉開頭 `v` 的版本，例如 `0.1.37-woow.1`。

## 2. 裝 Skill 還是 CLI

- AI 助手支援 Skill：**預設裝 Skill**，裡面附 CLI 指令碼。
- 不支援 Skill：裝 CLI：`pipx install 'git+https://github.com/WOOWTECH/woowtech_mika_smart_app.git@<tag>#subdirectory=tools/mika'`。

## 3. 安裝 Skill

`<skills-directory>` 是 AI 助手的 Skill 資料夾，位置以該助手自己的文件為準。Skill 放在裡面的 `mika` 資料夾。

macOS、Linux：

```sh
curl -L -o mika.zip https://github.com/WOOWTECH/woowtech_mika_smart_app/archive/refs/tags/<tag>.zip
unzip -q mika.zip -d mika-src
mkdir -p <skills-directory> && cp -R mika-src/woowtech_mika_smart_app-<ver>/tools/mika <skills-directory>/mika
python3 <skills-directory>/mika/scripts/mika_cli.py --version
```

Windows PowerShell：

```powershell
Invoke-WebRequest https://github.com/WOOWTECH/woowtech_mika_smart_app/archive/refs/tags/<tag>.zip -OutFile mika.zip
Expand-Archive mika.zip -DestinationPath mika-src
New-Item -ItemType Directory -Force "<skills-directory>" | Out-Null
Copy-Item -Recurse mika-src\woowtech_mika_smart_app-<ver>\tools\mika "<skills-directory>\mika"
py -3 "<skills-directory>\mika\scripts\mika_cli.py" --version
```

需要 Python 3.10 以上：Windows 用 `py -3`，其他系統用 `python3`。只裝 Skill 時，下面的 `mika` 指的是 `python3 <skills-directory>/mika/scripts/mika_cli.py`（Windows 是 `py -3 ...`）。

## 4. 連線

用使用者在手機上選的方式連線，位置在渥屋助理的「設定 › 連接電腦」。你看不到手機：使用者沒說用哪一種時，問一次，不要自己猜。

1. USB：使用已授權的 ADB。
   ```sh
   mika devices --json
   mika connect --device SERIAL --json
   ```
   同時有不只一支手機在線時，問使用者要用哪一支，之後都用那一支。
2. Wi-Fi 或私人 VPN：使用使用者給你的 HTTP 位址和權杖檔路徑。權杖只從檔案讀，永遠不要顯示出來。
   ```sh
   mika --url http://PHONE:8765 --token-file /path/to/token doctor --json
   ```

常見錯誤：

| 錯誤 | 怎麼處理 |
| --- | --- |
| `unauthorized` | 請使用者在手機上允許 USB 偵錯。 |
| `offline` | 請使用者重新插拔傳輸線。 |
| `connection_info`（讀不到連線資訊） | 請使用者解鎖手機、打開渥屋助理一次，再執行一次 `connect`。 |
| `incompatible_api` | 請使用者把手機上的渥屋助理更新到最新版。 |

## 注意

- 安裝和連線不代表可以替使用者送任務；使用者沒要求就不要送。
- 權杖永遠不要印出、念出，也不要放進指令、任務內容或回覆。
- `connect`、`doctor` 成功只代表連得上，不代表任務一定會成功。
- 想直接用 MCP 用戶端連線，見 [電腦連線（MCP）](mcp.md)。
