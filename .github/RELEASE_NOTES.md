AI Usage Sentinel 1.8.2 fixes obscured event details and adds optional 50% reset-message alerts and source translation.

- Event History uses a standard split pane without an overlapping navigation toolbar. App windows no longer merge automatically into tabs.
- Enable **Notify reset messages ≥50%** in the macOS menu or Settings (Windows/Linux tray/settings also supported). When enabled, public message alerts use a 50% threshold. Personal reset alerts remain separate. Persisted deduplication allows one alert when reaching 50%, then confidence-level upgrades or a correlated account reset. Stale/expired messages remain quiet.
- Source cards retain their original evidence and offer translation into the app language. macOS 15+ uses Apple's on-device Translation framework; language downloads may require a system prompt. macOS 14, Windows/Linux and the website offer an explicit Google Translate link for public excerpts only. No translation runs or sends text to Google automatically. Local account evidence never gets a web-translation link.
- No change to quota readings, source confidence calculations, signature keys or local data paths. No paid translation API is used.

macOS 14+ universal Apple Silicon/Intel, ad-hoc signed and not notarized. Windows/Linux remain unsigned beta ports. Existing update trust remains enforced; replace the installed app instead of running duplicate copies.
