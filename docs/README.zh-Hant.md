# Usage Sentinel

**讓 AI 剩餘額度，隨時看得見。**

[官方專案網站與互動範例](https://joe05520.github.io/usage-sentinel/) · [下載](https://github.com/Joe05520/usage-sentinel/releases/tag/v1.4.0) · [English](../README.md)

Usage Sentinel 是免費開源的選單列／系統匣工具，結合用量顯示、非例行 reset 偵測與社群初期訊號監控。macOS 採原生 SwiftUI / MenuBarExtra；Windows 與 Linux 使用原生 Qt，目前為 beta。

## 主要功能

- 顯示真實剩餘額度、例行 reset 時間、最後成功更新；資料取得失敗就顯示未知或過期。
- 最多五階段用量提醒，例如 **50%、30%、20%、10%、5%**，支援新增、刪除與修改。每週期每階段只提醒一次，一次跨越多階段只送一則合併通知。
- 偵測帳號額度在原定 reset 之前增加；這是帳號觀察，不直接宣稱全球 reset。
- 監控 OpenAI 官方來源、GitHub、Reddit 初期訊號；預設可信度 **25%** 即可通知，也可改為 15%、60%、90%。
- 每則事件保存來源、時間、網址、可信度；多來源合併，避免重複文字與作者灌水。
- macOS 提供五種選單列樣式，訊號數量與 banked reset credits 可分別關閉。
- App 支援英文、繁體中文、簡體中文、日文、韓文。來源原文不自動翻譯。
- 本機 SQLite 保存 35 天用量快照、最長一年事件；支援診斷、登入自動啟動及原生通知。macOS 另有歷史圖表與可信度時間線。

## AI 代理

| 代理 | 用量來源 |
| --- | --- |
| Codex | 登入官方 CLI 後，自動透過正式本機 app-server 讀取回傳的 quota windows。 |
| Claude | 官方 Claude Code 狀態列桥接，只匯出額度欄位；需使用者先設定。 |
| Gemini | 使用者有權提供的本機 JSON 或手動輸入。 |
| Grok | 使用者有權提供的本機 JSON 或手動輸入；不把 API rate limit 當成訂閱額度。 |
| 自訂 | 使用文件描述的 JSON schema 新增 product / quota。 |

目前一次顯示一個選定代理，各代理匯出路徑與來源歷史分開保存。外部 reset 消息目前聚焦 OpenAI / Codex，尚未加入其他廠商消息來源。[設定指南與 JSON 格式](AGENTS.md)。

## 安裝

[從 Release 下載](https://github.com/Joe05520/usage-sentinel/releases/tag/v1.4.0)，並查看 SHA-256 檔案雜湊。

- macOS 14+：解壓縮後將 Usage Sentinel.app 移到 Applications。支援 Apple Silicon／Intel，實際在 Apple Silicon 執行驗證。此版為 ad-hoc 簽章，尚未 Apple notarize；依 macOS「隱私權與安全性」明確允許開啟，不停用系統安全機制。
- Windows 10/11 x64：解壓縮完整資料夾，執行 UsageSentinel.exe。未使用付費程式簽章，請閱讀發布說明與系統信任提示。
- Linux x64：解壓縮後執行 UsageSentinel/UsageSentinel。部分桌面需 Qt 系統套件或 tray 擴充，沒有 tray 時保留正常視窗。[完整平台指南](../Portable/README.md)。

Windows / Linux 為 beta。CI 建置與 offscreen smoke test 不代表所有桌面的實際通知、休眠喚醒或登入都驗證完成；各平台功能差異已列在指南。

## 隱私

用量、歷史、事件、設定與通知紀錄都留在本機。沒有遙測、自建 server 或帳號資料雲端同步。公開消息請求不帶帳號用量或憑證；Codex 登入由官方程式處理。Sentinel 不讀取 browser cookies 或 vendor auth 檔案。Claude bridge 不保存完整 session payload、對話、workspace 或 transcript path。

## 技術、測試與參與

可直接開啟根目錄的 OpenAIUsageSentinel.xcodeproj。原始模組與 bundle/data 名稱保留，確保升級不丟失既有設定。App 對外名稱為 Usage Sentinel。

[技術說明](TECHNICAL.md) · [驗證紀錄](VALIDATION.md) · [參與貢獻](../CONTRIBUTING.md) · [回報問題](https://github.com/Joe05520/usage-sentinel/issues)

MIT 授權。第三方 Qt / Python 授權見 [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)。獨立社群專案，與 OpenAI、Anthropic、Google、xAI 無隸屬或背書關係。

## 1.5 更新

新增每日更新檢查、Ed25519 簽章與 SHA-256 驗證下載，安裝需手動替換 App，保留原資料。新增預設關閉的匿名每日統計，粗略額度須另行同意。公開圖表至少 10 個匿名參與識別碼；個別帳號歷史仍保留本機。[統計隱私](ANALYTICS.md) · [更新說明](UPDATES.md)。
