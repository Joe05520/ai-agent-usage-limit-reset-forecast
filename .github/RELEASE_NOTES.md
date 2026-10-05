AI Usage Sentinel 1.7.0 gives Settings separate category pages and animates quota displays from zero to the current percentage.

- Safari-inspired icon toolbar: General, Panel visualization, Menu Bar Appearance, Refresh, Reminders, Notifications, Sources, Usage provider, Updates, Analytics, Privacy & Diagnostics, and Testing.
- Panel mode and visualization choices are now available only in Settings; the usage panel focuses on quota and reset signals.
- Professional bars, Intuitive rings/batteries and Compact percentage counters animate together. Entrance transitions run once and stop; macOS Reduce Motion and the animation switch display the actual value immediately.
- Windows/Linux Qt settings are also split into separate tabs, with finite quota transitions when enabled.
- Existing preferences, reminder stages, account data, update trust and detection behavior are preserved.

macOS 14+, universal Apple Silicon/Intel. Ad-hoc signed, not notarized. Windows/Linux are unsigned beta ports; CI validation does not replace physical desktop validation. Existing installed versions retain their data in the same location. The macOS bundle is now named AI Usage Sentinel.app; replace the previous app rather than running both copies. Package filenames remain UsageSentinel for updater compatibility.

Codex uses the official local app-server. Claude needs the status-line bridge. Gemini/Grok accept local JSON/manual data. Public reset feeds focus on OpenAI/Codex. No invented quota or future global reset dates.
