Usage Sentinel combines a usage meter, unexpected personal reset detection and sourced early reset signals.

### Downloads

- **macOS 14+ Universal ZIP:** Apple Silicon + Intel, native SwiftUI / MenuBarExtra. Extract and move Usage Sentinel.app to Applications.
- **Windows x64 ZIP (beta):** Extract the whole folder, run UsageSentinel.exe. Do not move the executable out of its runtime folder.
- **Linux x64 tar.gz (beta):** Extract and run UsageSentinel/UsageSentinel. glibc 2.28+ and compatible Qt graphics libraries required. Some desktops need a tray extension; a normal window is retained if no tray is available.
- **SHA256SUMS.txt:** Hashes of the three download packages.

### Included in 1.4.0

- Up to **five distinct quota reminder stages**, 0–99%, with add/remove/edit controls, once-per-cycle delivery, consolidated multi-stage jumps and one-hour pause. Existing two-stage preferences are retained.
- Actual Codex usage from the official local app-server, regular reset time, 35-day local snapshot history and personal unexpected quota-increase detection.
- Official OpenAI/GitHub/Reddit reset monitoring, optional HN, confidence threshold (default 25%), source links and notification deduplication.
- Codex / Claude / Gemini / Grok / Custom agent selection. Claude supports the official quota-only status-line bridge; Gemini and Grok use authorized local exports or manual evidence. No unsupported personal-usage API is invented.
- English, Traditional Chinese, Simplified Chinese, Japanese and Korean app interfaces.
- macOS five menu styles, optional signal count/banked credits, history charts and confidence timeline. Windows/Linux offer native Qt tray icons and event source details; see the feature differences in the platform guide.
- Local data, no telemetry or hosted account-data backend. Optional login launch and source diagnostics.

### Validation and important limits

Release binaries come from [passing three-platform run 37192161755](https://github.com/Joe05520/usage-sentinel/actions/runs/37192161755). Windows and Ubuntu ran 29 core tests plus source and packaged Qt smoke tests. macOS built a universal app and ran core tests; on the development Mac, 85 Swift tests passed including live reads, and the Xcode target passed 83 tests with 2 opt-in live tests skipped. Native mock scenarios 1–5 were exercised; scheduled stayed quiet and four actionable scenarios submitted notifications.

Windows/Linux are **beta**: offscreen tests are not real desktop tray/notification, login or sleep/wake validation. Intel and minimum-version macOS hardware have not been separately exercised. Native macOS has richer history and appearance controls. This version shows one selected agent at a time; public news currently focuses on OpenAI/Codex. Quotas absent from official data stay unknown. Claude data depends on its active session; exports older than ten minutes are stale. Gemini/Grok fallback is not automatic subscription reading. X is unconfigured.

The macOS app is ad-hoc signed and **not notarized**. Use the explicit macOS Privacy & Security → Open Anyway flow only after reviewing this release. Windows is unsigned and may show SmartScreen warnings. Keep OS security protections enabled. No inference prompts or reset purchases are made by Sentinel.

[Website](https://joe05520.github.io/usage-sentinel/) · [Agent setup](https://github.com/Joe05520/usage-sentinel/blob/main/docs/AGENTS.md) · [Windows/Linux guide](https://github.com/Joe05520/usage-sentinel/blob/main/Portable/README.md) · [Privacy](https://github.com/Joe05520/usage-sentinel/blob/main/SECURITY.md) · [繁體中文](https://github.com/Joe05520/usage-sentinel/blob/main/docs/README.zh-Hant.md)

Independent community project; no vendor affiliation. MIT original source, with Qt/Python upstream license notices retained in portable packages.
