# AI agent setup

Usage Sentinel 1.4 supports a selected **Codex, Claude, Gemini, Grok or Custom** usage provider. Each provider has an independent export path; switching the visible provider is not treated as a reset. History is kept locally. This version shows one selected provider at a time; simultaneous combined quota display is not implemented. OpenAI public reset monitoring continues independently and does not imply Claude/Gemini/Grok public coverage.

| Agent | Integration | Automatic data availability |
| --- | --- | --- |
| Codex | Official local `app-server` → `account/rateLimits/read` | Reads actual returned windows after official CLI sign-in. No inference call. |
| Claude | Official Claude Code `statusLine` quota bridge | Updates when Claude Code publishes `rate_limits`; requires user setup. Not a background account endpoint. |
| Gemini | User-provided quota-only local JSON or manual snapshot | CLI `/stats` documents model quota information, but this app does not assume a supported standalone JSON quota command. |
| Grok | User-provided quota-only local JSON or manual snapshot | API rate limits are not SuperGrok subscription remaining allowance. No personal-subscription endpoint is assumed. |
| Custom | Same local export schema | Choose any product/bucket names from a source you are authorized to read. |

Official references: [Codex app-server](https://developers.openai.com/codex/app-server), [Claude Code status line](https://code.claude.com/docs/en/statusline), [Gemini CLI commands](https://github.com/google-gemini/gemini-cli/blob/main/docs/reference/commands.md), [xAI API rate limits](https://docs.x.ai/developers/rate-limits).

## Codex

Install and sign in to the official Codex CLI. On macOS Sentinel also discovers known official desktop executable paths. On Windows/Linux, put `codex` on PATH or set its executable in Settings. The npm Windows shim uses the official installed `@openai/codex/bin/codex.js` with Node.js. Sentinel never parses your authentication file. It does not create a prompt or consume a banked reset.

## Claude: official status-line bridge

Claude Code's documented JSON includes `rate_limits.five_hour.used_percentage`, `seven_day.used_percentage` and each `resets_at` timestamp. Availability depends on the account/provider and begins after an API response. Missing data is not inferred from context-window usage or token cost.

1. Download the source or use `claude_statusline_bridge.py` included with the portable distribution. Keep the script at a stable path. Python 3.9+ is required for this optional bridge.
2. In your own Claude settings, add or compose a `statusLine` command pointing at this script. Do not overwrite an existing status-line setup blindly. Example macOS/Linux configuration (replace the absolute script path):

```json
{
  "statusLine": {
    "type": "command",
    "command": "python3 /absolute/path/claude_statusline_bridge.py --profile main-claude"
  }
}
```

Windows uses `python "C:\\absolute\\path\\claude_statusline_bridge.py" --profile main-claude` as the command, with JSON escaping. `--profile` is an optional non-secret account label; change it when switching accounts. Without an account identifier, a quota jump has lower confidence.

3. Select **Claude** in Sentinel and choose the bridge output:

- macOS: `~/Library/Application Support/OpenAIUsageSentinel/claude-usage.json`
- Windows: `%LOCALAPPDATA%\UsageSentinel\claude-usage.json`
- Linux: `$XDG_DATA_HOME/usage-sentinel/claude-usage.json` (defaults to `~/.local/share/usage-sentinel/claude-usage.json`)

The script can use `--output` for another path. It writes atomically and stores no raw session payload, transcript path, workspace path, token, cookie or conversation. A missing/expired quota writes an empty export, invalidating the previous data. Sentinel marks files older than ten minutes stale; a quiet Claude session does not count as a new observation. The bridge does not run Claude or make any request itself.

## Gemini, Grok and Custom JSON

Use the local export selector. The schema is interoperable across Swift and Qt clients:

```json
{
  "schemaVersion": 1,
  "product": "Gemini",
  "origin": "user-provided export",
  "timestamp": "2026-10-04T08:00:00Z",
  "profile": "main-gemini",
  "buckets": [
    {
      "id": "daily-model",
      "name": "Daily model allowance",
      "remainingPercent": 72,
      "windowDurationMins": 1440,
      "resetAt": "2026-10-05T08:00:00Z"
    }
  ]
}
```

**These are illustrative values, not an actual account.** `timestamp` must be the source's observation time, not the time Sentinel rereads a file. `resetAt` and `windowDurationMins` may be null; never invent a reset time. Each bucket needs a unique ID, name and finite percentage in 0–100. Export at most 1 MB. Future timestamps, invalid percentages and duplicate IDs are rejected. An old export stays visibly stale and cannot trigger fresh low-quota reminders.

For macOS, **Use manual snapshot → Enter Manual Snapshot** can record a selected agent's known values. Portable clients accept manual evidence through the same JSON format. This is a fallback, not automatic live usage. Personal increases from user-provided evidence have reduced confidence. Do not convert API dollars or token counts into a subscription percentage without an authoritative allowance.

## 五階段提醒（繁體中文）

設定 → 剩餘額度提醒，最多新增五個 0–99% 的不同門檻，例如 **50 → 30 → 20 → 10 → 5%**。可新增、刪除、修改，依比例由高到低排列。有兩個以上門檻時，最低門檻為緊急提醒；只有一個時是一般提醒。

每個額度週期中，每階段只提醒一次。一次跨越多階段會合併為一則最嚴重的通知，重開 app 不會重複。可暫停一小時。舊版自訂 30%／10% 等設定會保留。手動資料或 JSON 超過十分鐘後，不會當作新資料發出低額度提醒。
