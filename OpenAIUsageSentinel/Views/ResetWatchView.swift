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
                    SourceCredibilityBar(value: 0.85)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.t("Sources")).font(.caption).foregroundStyle(.secondary)
                    Link("@codex_resets", destination: URL(string: "https://x.com/codex_resets")!).font(.headline)
                    SourceCredibilityBar(value: 0.75)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            let latestCompletion = signals.filter { $0.behavior == .suspectedGlobal }.compactMap(\.source.publishedAt).max() ?? .distantPast
            let fresh = signals.filter { store.settings.watchResets && [ResetEventType.poll, .forecast].contains($0.behavior) && ($0.source.publishedAt ?? .distantPast) > Date().addingTimeInterval(-86400) && ($0.source.publishedAt ?? .distantPast) > latestCompletion && ($0.source.expiresAt ?? .distantFuture) > Date() }
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
                        Text(L10n.t("Unexpected account reset")).foregroundStyle(.orange)
                        ForEach(event.affectedBuckets, id: \.self) { id in
                            Text("\(id): \(Int(event.beforeValue[id] ?? 0))% → \(Int(event.afterValue[id] ?? 0))%").font(.caption.monospacedDigit())
                        }
                    } else { Text(L10n.t("No correlated unexpected account reset observed.")).font(.caption).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            ResetAnnouncementCalendar(signals: signals)
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


private struct ResetAnnouncementCalendar: View {
    let signals: [ResetSignal]
    @State private var monthOffset = 0
    @State private var selectedDay: Date?
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.locale = L10n.locale
        value.timeZone = .current
        return value
    }
    private var month: Date {
        let current = calendar.date(from: calendar.dateComponents([.year, .month], from: Date()))!
        return calendar.date(byAdding: .month, value: monthOffset, to: current)!
    }
    private var leading: Int { (calendar.component(.weekday, from: month) - 1) % 7 }
    private var count: Int { calendar.range(of: .day, in: .month, for: month)!.count }
    private func records(_ day: Date) -> [ResetSignal] {
        signals.filter { signal in signal.source.publishedAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(month.formatted(.dateTime.year().month(.wide).locale(L10n.locale))).font(.headline)
                Spacer()
                Button { monthOffset -= 1 } label: { Image(systemName: "chevron.left") }.disabled(monthOffset <= -12).help(L10n.t("Previous month"))
                Button { monthOffset += 1 } label: { Image(systemName: "chevron.right") }.disabled(monthOffset >= 0).help(L10n.t("Next month"))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 7), spacing: 5) {
                ForEach(Array(calendar.shortStandaloneWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
                ForEach(0..<((leading + count + 6) / 7 * 7), id: \.self) { index in
                    let number = index - leading + 1
                    if number < 1 || number > count { Color.clear.frame(height: 52).accessibilityHidden(true) }
                    else {
                        let day = calendar.date(byAdding: .day, value: number - 1, to: month)!
                        let entries = records(day)
                        Button { selectedDay = day } label: {
                            VStack(spacing: 5) {
                                Text("\(number)").font(.callout.monospacedDigit()).foregroundStyle(calendar.isDateInToday(day) ? Color.accentColor : Color.primary)
                                HStack(spacing: 3) {
                                    if entries.contains(where: { $0.behavior == .suspectedGlobal }) { Circle().fill(Color.accentColor).frame(width: 5, height: 5) }
                                    if entries.contains(where: { $0.behavior == .banked }) { Circle().fill(Color.orange).frame(width: 5, height: 5) }
                                    if entries.contains(where: { [.poll, .forecast].contains($0.behavior) }) { Circle().fill(Color.secondary).frame(width: 5, height: 5) }
                                }.frame(height: 5)
                            }.frame(maxWidth: .infinity).frame(height: 52)
                                .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5))
                        }.buttonStyle(.plain).help(day.formatted(date: .complete, time: .omitted) + " · \(entries.count)")
                    }
                }
            }
        }.popover(isPresented: Binding(get: { selectedDay != nil }, set: { if !$0 { selectedDay = nil } })) {
            if let selectedDay {
                VStack(alignment: .leading, spacing: 12) {
                    Text(selectedDay.formatted(.dateTime.year().month().day().locale(L10n.locale))).font(.headline)
                    let entries = records(selectedDay)
                    if entries.isEmpty { Text(L10n.t("No announcements recorded for this date.")).foregroundStyle(.secondary) }
                    ForEach(entries, id: \.source.id) { signal in
                        Text(signal.behavior.label).font(.caption.bold())
                        Text(signal.source.snippet).font(.callout).lineLimit(4)
                        Link(L10n.t("Original X post ↗"), destination: signal.source.url)
                        if let via = signal.source.viaURL { Link(L10n.t("Data attribution ↗") + " · " + (via.host ?? ""), destination: via) }
                    }
                }.padding(20).frame(width: 360)
            }
        }
    }
}


struct SourceCredibilityBar: View {
    let value: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(L10n.t("Source credibility")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(value * 100))%").font(.caption.bold().monospacedDigit())
            }
            ProgressView(value: value).tint(.orange)
        }.frame(maxWidth: 280).accessibilityElement(children: .combine)
    }
}
