import SwiftUI

struct MenuView: View {
    @EnvironmentObject var store: SentinelStore
    @State private var presentationID = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI Usage Sentinel", systemImage: "gauge.with.dots.needle.50percent").font(.headline)
                Spacer()
                if store.isMock { Text(L10n.t("MOCK")).font(.caption.bold()).foregroundStyle(.orange) }
                if let plan = store.usage?.plan { Text(plan.capitalized).font(.caption).foregroundStyle(.secondary) }
            }
            if let usage = store.usage {
                if !store.usageAvailable { Text(L10n.t("Last known values · live fetch unavailable")).font(.caption).foregroundStyle(.orange) }
                if store.settings.manualMode { Text(L10n.t("Manual snapshot · user entered")).font(.caption).foregroundStyle(.orange) }
                ForEach(usage.buckets) { bucket in
                    VStack(alignment: .leading, spacing: 3) {
                        QuotaVisualizationView(bucket: bucket, appearance: store.settings.panel)
                            .id("\(bucket.id)-\(presentationID)-\(store.settings.panel.mode.rawValue)-\(store.settings.panel.visualStyle.rawValue)")
                        if store.settings.reminders.showDailyTrend, let points = ObservedUsageTrend.consumedPoints(bucketID: bucket.id, history: store.history, now: Date()) {
                            Text(L10n.f("Observed today: %@ percentage points used", points.formatted(.number.precision(.fractionLength(0...1)).locale(L10n.locale)))).font(.caption2).foregroundStyle(.secondary)
                                .help(L10n.t("Measured consumption only. Unsampled periods and reset jumps are excluded; this may be less than total daily usage."))
                        }
                    }
                }
                if store.settings.reminders.enabled {
                    HStack {
                        Label(L10n.t("Reminder stages") + ": " + store.settings.reminders.stages.map { "\(Int($0))%" }.joined(separator: " · "), systemImage: "bell").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if let until = store.settings.reminders.snoozedUntil, until > Date() {
                            Button(L10n.t("Resume")) { store.resumeReminders() }.font(.caption)
                        } else { Button(L10n.t("Pause 1h")) { store.snoozeReminders() }.font(.caption) }
                    }
                }
                if store.settings.appearance.showBankedCredits, let credits = usage.resetCredits { Text(L10n.f("%d banked reset credits available · not applied", credits)).font(.caption).foregroundStyle(.secondary) }
                if usage.ordinaryUsageAllowed == false { Text(L10n.t("Provider says ordinary usage is unavailable.")).font(.caption).foregroundStyle(.orange) }
            } else {
                Text(L10n.t("Usage unavailable")).font(.subheadline)
                Text(L10n.t("Sign in to official Codex, then refresh. No missing limits are estimated.")).font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack { Label(L10n.t("Reset Signals"), systemImage: "bolt.fill").font(.headline); Spacer(); Button { store.openWindow?("resets") } label: { Image(systemName: "waveform.path").help(L10n.t("Reset Watch & Forecast")) }.buttonStyle(.link); Button(L10n.t("History")) { store.openWindow?("history") }.buttonStyle(.link) }
            if store.activeEvents.isEmpty {
                Text(L10n.t("No fresh irregular reset signal")).font(.subheadline).foregroundStyle(.secondary)
                Text(L10n.t("Irregular reset: no known schedule")).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(store.activeEvents.prefix(3)) { event in
                    Button {
                        store.selectedEventID = event.id; store.openWindow?("history")
                    } label: { EventRow(event: event) }.buttonStyle(.plain)
                }
            }
            Divider()
            HStack {
                Text(store.usage.map { L10n.t("Usage updated: ") + $0.timestamp.localizedFormatted(date: .omitted, time: .shortened) } ?? L10n.t("No usage update")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if store.usageBusy || store.newsBusy { ProgressView().controlSize(.small) }
                Button { Task { await store.refreshAll() } } label: { Image(systemName: "arrow.clockwise") }.help(L10n.t("Refresh all sources"))
            }
            HStack {
                Button(L10n.t("Settings…")) { store.openWindow?("settings") }
                Button(L10n.t("Diagnostics")) { store.openWindow?("diagnostics") }
                Spacer()
                Button(L10n.t("Quit")) { NSApplication.shared.terminate(nil) }
            }.font(.caption)
        }
        .padding(16).frame(width: 390)
        .onChange(of: store.settings.panel) { _, _ in store.saveSettings() }
        .onAppear { presentationID = UUID(); Task { await store.refreshAll(force: false) } }
    }
}

struct BucketRow: View {
    @Environment(\.locale) private var locale
    let bucket: UsageBucket
    var displayedValue: Double? = nil
    var color: Color { bucket.remainingPercent < 5 ? .red : bucket.remainingPercent < 20 ? .orange : bucket.remainingPercent <= 50 ? .yellow : .accentColor }
    var body: some View {
        let _ = locale.identifier
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n.t(bucket.name)).font(.subheadline.weight(.medium))
                if bucket.product != "Codex" { Text(bucket.product).font(.caption).foregroundStyle(.secondary) }
                Spacer(); AnimatedQuotaPercent(value: displayedValue ?? bucket.remainingPercent, remainingLabel: true).font(.subheadline.monospacedDigit().weight(.semibold))
            }
            GeometryReader { geometry in
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule().fill(color).frame(width: geometry.size.width * min(100, max(0, displayedValue ?? bucket.remainingPercent)) / 100)
            }.frame(height: 6).accessibilityHidden(true)
            HStack {
                Text(DateParsing.countdown(bucket.resetAt))
                Spacer()
                if let reset = bucket.resetAt { Text(reset, format: .dateTime.month(.abbreviated).day().hour().minute()) }
            }.font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }.accessibilityElement(children: .combine)
    }
}

struct EventRow: View {
    @Environment(\.locale) private var locale
    let event: ResetEvent
    var body: some View {
        let _ = locale.identifier
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "circle.fill").font(.system(size: 8)).foregroundStyle(event.level.color)
                Text(event.type.label).font(.subheadline.weight(.medium)).lineLimit(2)
                Spacer()
            }
            Text(L10n.f("%@ · %d%% · %d reports · %@", event.product, Int(event.confidence*100), event.reportCount, event.level.label)).font(.caption).foregroundStyle(.secondary)
        }.contentShape(Rectangle())
    }
}
extension ConfidenceLevel {
    var color: Color { switch self { case .rumor: return .secondary; case .early: return .orange; case .likely: return .yellow; case .confirmed: return .green } }
}
