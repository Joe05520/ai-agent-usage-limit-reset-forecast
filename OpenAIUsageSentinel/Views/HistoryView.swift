import SwiftUI
import Charts

struct HistoryView: View {
    @EnvironmentObject var store: SentinelStore
    var body: some View {
        HSplitView {
            List(selection: $store.selectedEventID) {
                if let external = store.externalMockEvent { Text("[MOCK] " + external.type.label).tag(external.id) }
                ForEach(store.events) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        EventRow(event: event)
                        Text(event.detectedAt, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical, 4).tag(event.id)
                }
            }.frame(minWidth: 260, idealWidth: 290, maxWidth: 340)
            Group {
            if let event = (store.externalMockEvent?.id == store.selectedEventID ? store.externalMockEvent : nil) ?? store.events.first(where: { $0.id == store.selectedEventID }) { EventDetailView(event: event).id(event.id) }
            else {
                ScrollView { VStack(alignment: .leading, spacing: 16) {
                    ResetWatchView()
                    Divider()
                    Text(L10n.t("Usage History")).font(.title2.bold())
                    Text(L10n.t("35 days of local snapshots. Select an event to inspect its evidence.")).foregroundStyle(.secondary)
                    if store.history.isEmpty { Text(L10n.t("Snapshots appear after the first successful account read.")) }
                    else {
                        Chart {
                            ForEach(Array(store.history.filter { $0.source == store.usage?.source && $0.accountFingerprint == store.usage?.accountFingerprint && $0.plan == store.usage?.plan }.enumerated()), id: \.offset) { _, snapshot in
                                ForEach(snapshot.buckets) { bucket in
                                    LineMark(x: .value(L10n.t("Time"), snapshot.timestamp), y: .value(L10n.t("Remaining %"), bucket.remainingPercent), series: .value(L10n.t("Bucket"), bucket.id))
                                        .foregroundStyle(by: .value(L10n.t("Bucket"), bucket.product + " " + L10n.t(bucket.name)))
                                }
                            }
                        }.chartYScale(domain: 0...100).frame(height: 260)
                    }
                    Text(L10n.t("Irregular reset: no known schedule")).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }.padding(24) }
            }
            }.frame(minWidth: 440, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).clipped()
        }.frame(minWidth: 820, minHeight: 530)
    }
}
struct EventDetailView: View {
    let event: ResetEvent
    @EnvironmentObject var store: SentinelStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text((event.isMockEvidence ? "[MOCK] " : "") + event.type.label).font(.title2.bold())
                if event.isMockEvidence { Text(L10n.t("Test fixture · no real quota was changed.")).font(.caption).foregroundStyle(.orange) }
                HStack { Text(event.product); if let model = event.model { Text(model.capitalized) }; Spacer(); Label("\(Int(event.confidence*100))% · \(event.level.label)", systemImage: "circle.fill").foregroundStyle(event.level.color) }
                ProgressView(value: event.confidence).tint(event.level.color).accessibilityLabel(L10n.t("Confidence %"))
                LabeledContent(L10n.t("First detected"), value: event.detectedAt.localizedFormatted())
                LabeledContent(L10n.t("Last evidence update"), value: event.updatedAt.localizedFormatted())
                LabeledContent(L10n.t("Reports"), value: String(event.reportCount))
                if !event.plans.isEmpty { LabeledContent(L10n.t("Plans mentioned"), value: event.plans.joined(separator: ", ")) }
                ForEach(["plus", "pro", "business", "free"], id: \.self) { plan in
                    let count = event.sources.filter { $0.reportedPlan == plan && !$0.official }.count
                    if count > 0 { LabeledContent(L10n.f("%@ reports", plan.capitalized), value: String(count)) }
                }
                Text(L10n.explanation(event.explanation)).font(.callout)
                if let wave = EventEngine.waveDescription(event) { Label(wave, systemImage: "waveform.path").font(.callout).foregroundStyle(.orange) }
                Divider()
                Text(L10n.t("Your account")).font(.headline)
                if event.ownAccountReset {
                    ForEach(event.affectedBuckets, id: \.self) { id in
                        Text("\(id): \(Int(event.beforeValue[id] ?? 0))% → \(Int(event.afterValue[id] ?? 0))%")
                    }
                } else {
                    Text(L10n.t("No correlated unexpected account reset observed.")).foregroundStyle(.secondary)
                    if let usage = store.usage { ForEach(usage.buckets) { bucket in Text(L10n.f("Current %@: %d%% left", L10n.t(bucket.name), Int(bucket.remainingPercent))).font(.caption) } }
                }
                LabeledContent(L10n.t("Official confirmation"), value: L10n.t(event.sources.contains(where: \.official) ? "Source attached · check scope and eligibility" : "Not found in monitored sources"))
                if event.timeline.count > 1 {
                    Text(L10n.t("Confidence timeline")).font(.headline)
                    Chart(Array(event.timeline.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value(L10n.t("Time"), point.timestamp), y: .value(L10n.t("Confidence %"), point.score*100))
                    }.chartYScale(domain: 0...100).frame(height: 110)
                }
                Divider(); Text(L10n.t("Sources")).font(.headline)
                ForEach(event.sources) { source in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(source.platform).font(.headline); Spacer(); if SafeURL.external(source.url) { Link(L10n.t("Open ↗"), destination: source.url) } }
                        if let via = source.viaURL, SafeURL.external(via) {
                            Link(L10n.t("Data attribution ↗") + " · " + (via.host ?? ""), destination: via).font(.caption)
                        }
                        if let weight = ResetWatchPolicy.weight(source) { Text(L10n.f("Source weight: %d%% · not a reset probability", Int(weight * 100))).font(.caption).foregroundStyle(.secondary) }
                        if let expiry = source.expiresAt { Text(L10n.t("Watch expires") + ": " + expiry.localizedFormatted()).font(.caption) }
                        if let target = source.announcedTarget { Text(L10n.t("Announced target · execution unverified") + ": " + target.localizedFormatted()).font(.caption) }
                        Text(source.title).font(.subheadline.weight(.medium))
                        if let author = source.author { Text(author).font(.caption).foregroundStyle(.secondary) }
                        SourceTranslationView(source: source)
                        if let modified = source.modifiedAt { Text(L10n.t("Document updated: ") + modified.localizedFormatted()).font(.caption2).foregroundStyle(.secondary) }
                        Text(L10n.f("Published: %@\nFetched: %@", source.publishedAt?.localizedFormatted() ?? L10n.t("unknown"), source.fetchedAt.localizedFormatted())).font(.caption2).foregroundStyle(.secondary)
                        Text(source.url.absoluteString).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                    }.padding(.vertical, 6)
                    Divider()
                }
            }.padding(24)
        }
    }
}
