import SwiftUI

struct ResetWatchView: View {
    @EnvironmentObject var store: SentinelStore
    private var signals: [ResetSignal] {
        // Timeline retains separate posts by an author, while event confidence deduplicates authors.
        return store.watchSignals.reduce(into: [String: ResetSignal]()) { result, signal in
            if result[signal.source.id] == nil || (ResetWatchPolicy.weight(signal.source) ?? 0) > (ResetWatchPolicy.weight(result[signal.source.id]!.source) ?? 0) { result[signal.source.id] = signal }
        }.values.sorted { ($0.source.publishedAt ?? .distantPast) > ($1.source.publishedAt ?? .distantPast) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(L10n.t("Reset Watch & Forecast"), systemImage: "waveform.path").font(.title2.bold())
                Spacer()
                Button { Task { await store.refreshNews(force: true) } } label: { Image(systemName: "arrow.clockwise") }.disabled(store.newsBusy)
            }
            Text(L10n.t("Polls and teasers are early evidence, not completed resets. Source weights are not probabilities of a future reset.")).font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("Priority watch")).font(.caption).foregroundStyle(.secondary)
                    Link("Tibo · @thsottiaux", destination: URL(string: "https://x.com/thsottiaux")!).font(.headline)
                    Text(L10n.t("85% editorial weight · polls & replies")).font(.caption)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("Trusted community tracker")).font(.caption).foregroundStyle(.secondary)
                    Link("@codex_resets", destination: URL(string: "https://x.com/codex_resets")!).font(.headline)
                    Text(L10n.t("75% user-selected source weight")).font(.caption)
                }
            }
            let latestCompletion = signals.filter { $0.behavior == .suspectedGlobal }.compactMap(\.source.publishedAt).max() ?? .distantPast
            let fresh = signals.filter { [ResetEventType.poll, .forecast].contains($0.behavior) && ($0.source.publishedAt ?? .distantPast) > Date().addingTimeInterval(-86400) && ($0.source.publishedAt ?? .distantPast) > latestCompletion && ($0.source.expiresAt ?? .distantFuture) > Date() }
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.t(fresh.isEmpty ? "Irregular reset: no known schedule" : "Possible reset · watch active"), systemImage: fresh.isEmpty ? "clock" : "eye").font(.headline)
                    if let latest = fresh.first {
                        Text(latest.behavior.label).foregroundStyle(.orange)
                        Text(latest.source.snippet).font(.callout).lineLimit(4)
                        Link(L10n.t("Open ↗"), destination: latest.source.url)
                        if let target = latest.source.announcedTarget { Text(L10n.t("Announced target · execution unverified") + ": " + target.localizedFormatted()).font(.caption) }
                    }
                    Text(L10n.t("Your account")).font(.caption.bold())
                    if let event = store.events.first(where: { $0.ownAccountReset && $0.isActive }) {
                        Text(event.type.label).foregroundStyle(.orange)
                    } else { Text(L10n.t("No correlated unexpected account reset observed.")).font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(L10n.t("Announcement calendar · last 84 days")).font(.headline)
            let days = (0..<84).map { Calendar.current.startOfDay(for: Date().addingTimeInterval(Double($0 - 83) * 86400)) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 14), spacing: 4) {
                ForEach(days, id: \.self) { day in
                    let matches = signals.filter { $0.source.publishedAt.map { Calendar.current.isDate($0, inSameDayAs: day) } ?? false }
                    let kind = matches.contains { $0.behavior == .suspectedGlobal } ? 2 : matches.contains { $0.behavior == .banked } ? 1 : 0
                    RoundedRectangle(cornerRadius: 3).fill(kind == 2 ? Color.accentColor : kind == 1 ? Color.orange : Color.secondary.opacity(0.12)).frame(height: 12)
                        .help(day.formatted(date: .abbreviated, time: .omitted) + " · \(matches.count)")
                }
            }
            Text(L10n.t("Accent: reported reset announcement · orange: banked offer · empty: no record. Historical posts do not trigger new alerts.")).font(.caption).foregroundStyle(.secondary)
            HStack { Text(L10n.t("Latest polls, teasers & announcements")).font(.headline); Spacer() }
            if signals.isEmpty { Text(L10n.t("No public watch data yet. Refresh or check Diagnostics; missing data stays unknown.")).foregroundStyle(.secondary) }
            ForEach(Array(signals.prefix(12).enumerated()), id: \.element.source.id) { _, signal in
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(signal.behavior.label).font(.subheadline.bold()); Spacer(); Text(signal.source.publishedAt?.localizedFormatted() ?? L10n.t("unknown")).font(.caption).foregroundStyle(.secondary) }
                    Text(signal.source.snippet).font(.callout).lineLimit(3)
                    HStack {
                        Link(L10n.t("Original X post ↗"), destination: signal.source.url)
                        if let via = signal.source.viaURL { Link("Data · " + (via.host ?? ""), destination: via) }
                    }.font(.caption)
                    Divider()
                }
            }
            Text(L10n.t("Secondary public feeds may omit posts, poll options or vote counts. Open the original poll on X for live results. No automated votes are cast.")).font(.caption).foregroundStyle(.secondary)
        }
    }
}
