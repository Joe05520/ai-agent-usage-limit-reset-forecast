# Release validation — 1.4.0

The release is built from public source. Private local account readings, databases, account fingerprints, user preference backups and full local test logs are excluded from this repository.

## macOS

- Universal Release build: arm64 and x86_64, deployment target macOS 14.
- Apple Silicon execution tested on the development Mac. Intel execution and macOS 14 hardware execution are not separately verified.
- 83 Swift package tests passed, including opt-in official local Codex and public-source reads.
- Xcode test target: 83 tests, 81 passed / 2 opt-in live tests skipped, zero failures.
- Five-stage reminder tests: ordered crossings, restart deduplication, combined five-stage jump, cycle recovery, settings migration, stage limits, removal and zero threshold.
- Agent export tests: namespace separation, provider switch migration, invalid/future/boolean rejection and correct vendor source URL for personal events.
- 205 localization keys validated across English, Traditional Chinese, Simplified Chinese, Japanese and Korean.
- The 1.4 app was installed over the prior app with a database backup; the prior 30% / 10% reminder preferences were retained. Live data is acquired without inference prompts.
- macOS notifications and login launch were already validated in prior native releases. The current UI and notification check is recorded below when completed.

## Windows / Linux beta

- 28 portable core tests passed locally: reminders, personal/reset classification, signal confidence, source clustering, stale reports, threshold upgrades, SQLite and official Claude bridge data minimization.
- Local Qt offscreen smoke passed: window, settings, quota rendering, unexpected personal reset event and five-stage engine.
- GitHub Actions builds target-OS executable packages and smoke-tests both source and bundled clients on Windows and Ubuntu.
- Offscreen tests verify startup and logic, not actual system-tray rendering or OS notification banners. Windows/Linux real desktop notifications, DND, login, sleep/wake and broad Wayland/desktop compatibility remain beta validation tasks.

## Website

The buildless page supports English / Traditional Chinese, accessible controls, mobile/desktop layouts, menu-style preview, optional signal count and a browser-only five-stage reminder demonstration. Illustrative quota values are labeled; no website account connection exists. There are no analytics, external fonts or third-party scripts. Language preference remains browser-local.
