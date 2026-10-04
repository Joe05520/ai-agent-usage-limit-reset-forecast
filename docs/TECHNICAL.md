# Usage Sentinel

Native Swift / SwiftUI menu bar app for macOS 14+. Apple Silicon first; Release builds also include Intel. It reads real Codex quota, detects unexpected account increases, monitors public reset reports, and keeps evidence on this Mac. This is a working local app, not an OpenAI product.

## Start using it

Installed app: `~/Applications/Usage Sentinel.app`.

Open `OpenAIUsageSentinel.xcodeproj` and select the shared **OpenAIUsageSentinel** scheme to build or debug. The app uses `LSUIElement` and `MenuBarExtra`, so it has no Dock icon. Click its menu bar item to see quota, reset dates, recent signals, Settings and Diagnostics. Reopening the app from Finder opens Settings. Launch at Login uses `SMAppService.mainApp`; the setting reflects the system's current registration.

Version 1.4 adds five menu bar styles, optional reset counts, and English / Traditional Chinese / Simplified Chinese / Japanese / Korean interface languages. The default is live Codex, five-minute usage/news polling, Early ≥25% reset-signal notifications, and low-quota reminders at 20% / 5% remaining. No mock percentage appears in live mode. Failed reads show `◉ Usage ?`; the last successful values are retained in the popover with a visible stale label.

## What it does

- Displays any returned percentage window, including 5-hour and weekly, with absolute and relative regular reset times. Missing windows and reset dates stay unavailable.
- Saves 35 days of snapshots in SQLite and one year of events, evidence, confidence timeline and notification bookkeeping.
- Detects quota increases before the previously scheduled reset, even with no public reports.
- Merges compatible reports by product, model, reset behavior and a six-hour time window; preserves plan mentions and identifies a possible wave of independent reports within 30 minutes.
- Sends native notifications for low-confidence evidence at your chosen threshold, confidence-level upgrades, or a correlated personal reset. Scheduled resets are quiet.
- Provides source URLs, publication/fetch timestamps, public author, original wording excerpts, confidence, event history and a usage chart.
- Includes Settings, manual fallback, isolated mock scenarios, notification testing and copyable diagnostics.

## Language and menu bar appearance

Settings → **General → Language** offers English, 繁體中文, 简体中文, 日本語 and 한국어. Selection takes effect immediately, including open native window titles, settings controls, quota labels/countdowns, event classifications, confidence levels, dates, chart labels and newly generated notifications. It persists locally across app restarts. Existing installs keep English until another language is chosen. Existing reminder thresholds and update intervals are retained.

Product/model names, source titles, snippets, authors and URLs are kept verbatim. Technical provider diagnostics and operating-system errors may remain in their original language. Notifications already delivered retain the text originally sent. App-authored translations live in `Resources/Translations.json`; explicit keys and printf argument types are checked by `python3 Scripts/check_localization.py`. No translation service or additional network request is used.

Settings → **Menu Bar Appearance** offers:

| Style | Illustrative example (72% / 61%) |
|---|---|
| Standard | `◉ 5h 72% · W 61%` |
| Compact | `5h72% · W61%` |
| Percentages only | `72% / 61%` |
| Single quota | `5h 72%` or the quota you select |
| Icon only | `◉` |

The Settings preview uses current real quota, or clearly labeled sample values when live quota is unavailable. Percentages-only mode lists the quota order and exposes names in the tooltip. Single-quota selection is independent of the multiple-quota visibility switches; if the selected bucket disappears, the first available Codex quota (or another available quota) is shown. Short-window and weekly switches control the three multiple-quota styles. Unknown live usage remains visibly unavailable in every style.

**Show reset signal count in menu bar** is independent of style and defaults to off. When enabled and there are active signals, `· ⚡N` is appended. This counts active reset signals, not completed account resets. **Show available banked reset credits in popover** independently controls provider-returned saved reset credits. Display settings do not disable detection, news polling, reminders or notifications.

## Custom remaining-quota reminders

Open Settings → **Remaining quota reminders**. Add, remove or change up to **five distinct thresholds from 0–99%**, sorted from highest to lowest. With multiple stages, the lowest is critical; a single stage is a normal reminder. Existing 20%/5%, 30%/10% or other two-stage settings migrate without resetting preferences. Choose individual returned buckets. Reset-signal confidence is separate from remaining-quota percentages.

Default thresholds are ≤20% and ≤5%. For each bucket/cycle, a threshold notifies once. Startup already below a threshold notifies on the next successful fresh read. If one poll crosses several stages, a single alert covers all crossed thresholds at the most severe value. Minor percentage oscillations do not re-arm. A changed regular reset time (>60 seconds), an observed recovery from ≤75% to ≥95% with a ≥20-point increase, or a new provider/account/plan/window context starts a fresh reminder cycle. This is reminder bookkeeping, not proof of what caused a reset. Changing a threshold creates a new reminder preference and may notify again if the quota is already below it.

Notification state persists in SQLite, so app restarts do not repeat delivered reminders. Permission denial does not mark a reminder delivered. Failed usage fetches, snapshots older than ten minutes, and an expired regular reset time do not produce quota reminders. macOS Focus may suppress the visible banner even when Notification Center accepts delivery. Alerts arrive on a successful poll, not continuously while the Mac sleeps.

**Pause Quota Reminders for 1 Hour** is available in Settings and the menu popover; **Resume** cancels it. Snooze persists across app restarts. Unexpected-reset and public-signal alerts continue independently.

**Show observed consumption today** adds measured percentage points used to each bucket in the popover. It sums decreases between same-context snapshots on today's local calendar day, with matching reset timestamps and gaps of at most 15 minutes. Reset jumps and gaps are excluded. This is an observed lower bound, not a complete daily billing figure or a depletion forecast; a 30-minute polling interval generally cannot supply this short-gap trend.

Clicking a quota notification opens Usage History. Its body includes the quota, remaining percentage, configured threshold, regular reset time, provider and observation time. No public reset event is fabricated from low quota.

An isolated native reminder test is available in mock Settings or through:

```sh
open -n '~/Applications/Usage Sentinel.app' \
  --args --mock --reminder-self-test --show-settings
```

The fixture sequence 30 → 20 → 19 → 5 → 4 → 100 → 20 produces three `[MOCK]` notifications: initial low, critical, then low again after recovery. It preserves real account history. Quit the mock instance after testing.

## Architecture

```
OpenAIUsageSentinel/
  App/                        MenuBarExtra entry point and native window coordinator
  Models/                     UsageBucket, UsageState, ResetSignal, ResetEvent, settings
  Services/Usage/             UsageProvider and local Codex JSON-RPC implementation
  Services/News/              Independent public source adapters, XML parser, HTTP client
  Services/Detection/         Personal detector, classifier, clustering, confidence, fixtures
  Services/Notifications/     UserNotifications authorization, delivery, event routing
  Views/                      Compact popover, Settings, history/detail/chart, diagnostics
  Persistence/                SQLite snapshots and Codable application state
  Utilities/                  MainActor view model, formatting, future Keychain support
Tests/                        Deterministic tests and opt-in live integration tests
Scripts/                      Project generation and reproducible validation
Evidence/                     Build/test logs, xcresult bundles, validation notes
```

`SentinelStore` is the main actor view model. Services are separated from views; the core also builds as a Swift package for fast tests. There are no third-party code dependencies.

## Usage data sources

The app invokes the locally installed official Codex binary with `app-server` and communicates through newline-delimited JSON on private stdin/stdout pipes:

1. `initialize` identifying this client as `openai_usage_sentinel`.
2. `initialized`.
3. `account/rateLimits/read`.

It starts no conversation or inference task and never consumes a reset credit. No `codex status --json` command is assumed. The documented JSON response includes `rateLimitsByLimitId` and a legacy single-bucket fallback. `usedPercent`, `windowDurationMins` and `resetsAt` are parsed without assuming two windows. Null percentages do not become zero. Credits are displayed as available credits, not as already applied resets. `ordinaryUsageAllowed` is displayed when returned, rather than inferred from percentages.

Executable discovery supports this Mac's bundled binary:

```
/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex
```

It also checks the Codex app, common Homebrew paths and `~/.local/bin`; Settings allows an explicit executable. Sign-in stays with the official Codex client. This Mac's bundled version was `0.159.0-alpha.12.1` during validation. Bundled paths/protocol versions can change after an app update.

[Official app-server documentation](https://learn.chatgpt.com/docs/app-server) documents this interface. This is the official local interface; Sentinel does not call the private ChatGPT web backend itself. The actual returned windows are Codex-backed account limits. Sentinel cannot promise that these represent every unrelated ChatGPT model/message quota. `OfficialUsageAPIProvider` is an explicit unconfigured integration point, not an invented endpoint.

Manual mode accepts an explicitly user-entered snapshot and labels it Manual. The simple editor enters one window at a time; the provider model can represent arbitrary windows. Entering another comparable snapshot can trigger the detector. Manual mode cannot supply unattended real-time account monitoring.

## Reset signal sources and requests

All requests are HTTPS reads of public data, with an identifying User-Agent. There is no search-engine backend or cloud service owned by Sentinel.

| Adapter | Public endpoint | Notes |
|---|---|---|
| OpenAI Status | `https://status.openai.com/api/v2/incidents.json` | Only reset-related incident wording is eligible. |
| OpenAI News | `https://openai.com/news/rss.xml` | Dated feed entries. |
| Codex Release Notes | `https://developers.openai.com/codex/changelog/rss.xml` | Dated official feed entries. |
| OpenAI Help / usage | `https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan` | Conservative recent-announcement extraction. |
| OpenAI Help / banked resets | `https://help.openai.com/en/articles/20001498-how-banked-codex-resets-work` | Distinguishes credits from automatic application. |
| ChatGPT Release Notes | `https://help.openai.com/en/articles/6825453-chatgpt-release-notes` | Same conservative document rules. |
| GitHub | `https://api.github.com/search/issues` | `repo:openai/codex reset created:>=DATE`, 50 results; user issues are community evidence, not official statements. |
| Reddit | `https://www.reddit.com/r/codex/search.rss` and `r/OpenaiCodex/search.rss` | `q=reset&restrict_sr=on&sort=new&t=day`; public RSS, no Reddit cookies. |
| Hacker News | `https://hn.algolia.com/api/v1/search_by_date` | Optional, off by default; public Algolia API, Codex/reset stories. |
| X | No request | Clean unavailable adapter; needs a lawful authorized API/feed. No scraping or proxy workaround. |

Help pages sometimes block HTTP clients. A command-line probe received 403 on this Mac, while the app's actual URLSession reads succeeded. Treat live Diagnostics as the current result. A 403 is reported and backed off; no challenge is bypassed.

Help content is not automatically an announcement. The adapter requires a recent machine-readable modification timestamp, irregular-reset wording and announcement context. A document modification is recorded separately from `publishedAt`; unknown publication dates remain unknown. Evergreen definitions alone do not qualify. Undated or unparseable announcements can be missed. No irregular reset date is predicted.

Adapters use a 15-second request / 25-second resource timeout, conditional ETag/Last-Modified caching, a 5 MB accepted-response limit, exponential backoff, and Retry-After for 403/429/503. Retrying occurs on later scheduler ticks rather than in a tight loop. Sources fail independently. Failed fetches do not promote stale cached content into new evidence.

## How confidence works

The rules are intentionally inspectable heuristics, not calibrated probabilities:

- Eligible official wording: 95%, Confirmed. This confirms the statement or offer in the source, not your account's eligibility or completion.
- Your observed unexpected Codex quota increase: +60%.
- Independent firsthand GitHub report: +20%; Reddit: +12%; other configured community platform: +8%.
- Two independent fresh reports: +8%; three: +15%; ten: a further +20%.
- Evidence with an explicitly verified screenshot flag: +10%. Current adapters do not claim to verify screenshot contents automatically.
- Missing public authors or hearsay receive half their platform contribution.
- Community/account evidence caps at 89%, so it cannot become Official/Confirmed through volume.

Two fresh independent Reddit reports yield 32%, Early Signal, and notify at the default 25% threshold. Sources with duplicate URLs, normalized text or same-platform public author count once. Anonymous posts are not claimed to be independently verified accounts; cross-platform identity cannot always be established.

Age weighting: 0–1 h 1.0, 1–3 h 0.9, 3–12 h 0.7, 12–24 h 0.5, older 0.25. Posts older than 24 hours cannot create a new current event. Stored historical events retain their evidence. Current signal badges exclude events without fresh evidence for 24 hours. A wave requires at least three deduplicated firsthand public-author reports within 30 minutes; it remains a possible phased rollout.

Notifications: Very Early ≥15%, Early ≥25%, Likely ≥60%, Official Only ≥90%. After the first notification, small score changes are quiet. Crossing Early → Likely → Confirmed or first observing your own correlated reset can notify again. Successful notification submission is persisted; denied permission does not falsely count as delivered. Concurrent usage/news refreshes serialize notification delivery.

## How unexpected reset detection works

The detector compares consecutive successful snapshots from the same provider/account fingerprint/plan and equal window duration. Account or plan changes start a new baseline. A gap of 24 hours or more does not assert an unexpected reset.

A candidate increase is at least 10 percentage points, or at least 3 points ending at ≥99%. Small fluctuations are ignored. It compares the **previous** reset time; the next response can move that time after a reset.

- At/after the previous schedule, with two-minute tolerance: `scheduled`, silent. A polling gap cannot prove the precise instant.
- A user-recorded banked/purchased action within the previous 30 minutes: corresponding type, history rather than a global alert.
- A decreased reset-credit count: `unknown`. Redemption and expiry cannot be distinguished from count alone, so it does not strengthen global evidence.
- Missing previous schedule: `unknown`, no claim of an early reset.
- Otherwise: `accountUnexpected`, immediately eligible for the personal-reset notification preference.

Banked/purchased actions performed elsewhere are not completely exposed by a quota percentage. Use **Record Banked Reset / Record Purchased Reset** when applying one outside this app. An unexpected increase is described as possible account evidence, not proof that no external reset was used or that everyone received a global reset. Normal reset, banked, purchased, automatic/global, suspected global, account unexpected, complimentary offer and unknown are separate types.

[Official banked-reset explanation](https://help.openai.com/en/articles/20001498-how-banked-codex-resets-work) distinguishes saved credits from a global/automatic reset applied to eligible limits.

## Privacy

### Data that stays local

`~/Library/Application Support/OpenAIUsageSentinel/` contains:

- `sentinel.sqlite`: 35-day usage history, settings, manual snapshot, reset annotations, event/source history, notification state and diagnostics.
- `mock.sqlite`: isolated mock-only state.
- `public-cache.json`: public feed/document responses and HTTP cache validators, retained for up to seven days.

Account identifiers are reduced to a local SHA-256 fingerprint for account-switch detection. Raw access/refresh tokens, cookies and private app-server responses are not persisted by Sentinel. Database/cache files use owner-only permissions; storage is not application-level encrypted. macOS login/FileVault protections remain relevant.

### Credentials and network traffic

Sentinel does **not** read `auth.json`, browser sessions, cookies or the Codex Keychain. The official Codex subprocess uses its existing authentication to read the official service and may maintain its own authentication according to its normal behavior. Thus official OpenAI authentication happens inside Codex, not inside a custom HTTP client. Analytics are explicitly disabled for this spawned app-server.

Public-source network requests contain only public search terms, HTTP validators and User-Agent. They contain no OpenAI token, account identifier, quota history or personal snapshots. Clicking a source opens its public URL in your default browser, where that browser follows its own normal behavior.

No cloud backend exists. No API key is required by current adapters. A reserved `KeychainStore` uses macOS Keychain for future explicitly configured adapters. `.gitignore` excludes local secrets, state databases and build output. App Sandbox is disabled because the app must launch the installed official CLI and use its local context; only the described paths are accessed by Sentinel's implementation. The locally built app is ad-hoc signed and is not notarized for external distribution.

## Build → Test → Run

Requires Xcode with the macOS SDK. Minimum deployment target: macOS 14. The project generator uses only Python standard library; the checked-in project is already generated.

```sh
xcodebuild -project OpenAIUsageSentinel.xcodeproj -scheme OpenAIUsageSentinel \
  -configuration Release -derivedDataPath build build
xcodebuild -project OpenAIUsageSentinel.xcodeproj -scheme OpenAIUsageSentinel \
  -configuration Debug -derivedDataPath build test
SENTINEL_LIVE_TEST=1 swift test
open 'build/Build/Products/Release/Usage Sentinel.app'
```

`swift test` without `SENTINEL_LIVE_TEST` skips two explicitly optional live integration tests. Xcode's hosted tests set `SENTINEL_TEST_HOST=1`: no real account read or permission request is initiated by the test host. The actual app is separately tested in live mode.

Open an isolated interactive mock instance from Settings, or:

```sh
open -n '~/Applications/Usage Sentinel.app' \
  --args --mock --show-settings
```

Mock notifications are visibly prefixed `[MOCK]`. Fixtures use `example.com/mock/...` and explicitly marked fake official snippets; they are not real reset reports. Scenario buttons run:

1. Scheduled weekly 20 → 100: Normal Reset, quiet.
2. Weekly 20 → 100 three days early: Unexpected Account Reset.
3. Two Reddit reports: Early Signal, 32%.
4. Eight Reddit + three GitHub + your quota: Likely, capped at 89%.
5. Official Help announcement fixture: Confirmed, 95%.

Tests additionally cover provider schema/null handling, account/plan changes, stale posts, old reset time versus moved reset time, normal consumption, intents, credit-count ambiguity, duplicate reports, notification dedup/upgrades, segmentation, wave detection, RSS parsing and SQLite round trip/retention. Release validation is recorded in [VALIDATION.md](VALIDATION.md). Private local test artifacts and account-specific measurements are excluded from the public repository.

The scheduler uses a tolerant 30-second Timer to check the configured 2/5/10/15/30-minute deadlines. It coalesces in-flight work, refreshes after wake/foreground/menu expansion, and makes no busy loop. Polling stops while macOS sleeps; wake triggers refresh. A reset can be detected at the next poll, not at an impossible guaranteed instant while the Mac is asleep.

## Known limitations

- Only quota windows returned by the official Codex interface are available automatically; this is not complete coverage of all personal ChatGPT usage limits.
- The bundled CLI is alpha and can move/change. Errors remain visible, with an explicit path/manual fallback.
- X and GitHub Discussions are reserved integrations. X needs authorized access; GitHub Discussions typically needs authenticated GraphQL. Other developer-community sources are not configured in this MVP.
- Public feeds/search are limited samples. Coverage and publication metadata vary; Help Center parsing is deliberately conservative. There is no guarantee of detecting every rumor or announcement.
- Community confidence can be wrong. It is an evidence score, not a probability. Unknown authors, cross-posting and screenshots have practical verification limits.
- Personal resets can be caused by purchases, banked resets, backend corrections or plan changes. The provider does not prove the cause of every increase.
- Notifications obey macOS authorization, Focus and screen-sharing policies. Diagnostics distinguish authorization and delivered Notification Center records.
- Launch at Login registration is verified; a complete logout/reboot cycle is not performed as part of development.
- Build/test/run are validated on this Mac. Older supported macOS releases and Intel execution are not physically tested.

## Adding a source or provider

Implement `ResetSignalSource.fetchSignals()` and return `ResetSignal` with its public URL, accurate dates/author/excerpt and product/model/plan segmentation. Set `official` only for a verified official publisher. Never substitute fetch time for a missing publication time. Register it in `SourceCatalog.enabled`, add Settings and regression tests, and reuse `HTTPClient` for public requests. Authenticated future sources should retrieve keys from `KeychainStore`, not from plaintext settings or browser cookies.

Implement `UsageProvider.fetchUsage()` to return arbitrary `UsageBucket` values and a stable local account fingerprint. Keep parsing outside UI. Report missing fields as unavailable and fail cleanly when no usable percentage window exists. Provider changes must start a new comparison baseline. Regenerate the Xcode project with `python3 Scripts/generate_project.py` after adding source files.

The native notification self-test can be run without user-interface automation:

```sh
open -n '~/Applications/Usage Sentinel.app' \
  --args --mock --self-test
```

It uses isolated mock state, runs all five scenarios, records each classification and successful notification submission, and retains those mock events for notification-click inspection. It leaves the mock instance running; quit that instance after testing. The live instance can open a mock notification's event from the separate mock database without adding it to live history. Native delivered-notification records are asynchronous; Diagnostics queries the latest Notification Center state.
