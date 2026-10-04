import Foundation

public enum EventEngine {
    public static func ageWeight(_ date: Date?, now: Date) -> Double {
        guard let date else { return 0.25 }
        let age = max(0, now.timeIntervalSince(date))
        return age <= 3600 ? 1 : age <= 10800 ? 0.9 : age <= 43200 ? 0.7 : age <= 86400 ? 0.5 : 0.25
    }
    public static func uniqueSources(_ sources: [SignalSource]) -> [SignalSource] {
        var urls = Set<String>(), texts = Set<String>(), authors = Set<String>()
        return sources.sorted { $0.official && !$1.official }.filter { source in
            let text = SignalClassifier.normalized(source.title + " " + source.snippet)
            let author = source.author.map { source.platform.lowercased() + ":" + $0.lowercased() }
            guard !urls.contains(source.id), !texts.contains(text), author.map({ !authors.contains($0) }) ?? true else { return false }
            urls.insert(source.id); texts.insert(text); if let author { authors.insert(author) }; return true
        }
    }
    public static func score(sources: [SignalSource], ownReset: Bool, now: Date) -> Double {
        let sources = uniqueSources(sources)
        if sources.contains(where: { $0.official }) { return 0.95 }
        var score = ownReset ? 0.60 : 0.0
        let community = sources.filter { !$0.official && $0.platform != "Local Codex" && $0.platform != "Manual" }
        for source in community {
            let base = source.platform == "GitHub" ? 0.20 : source.platform == "Reddit" ? 0.12 : 0.08
            // Unknown authors / hearsay do not count as full independent account evidence.
            let independent = source.author != nil && SignalClassifier.classify(source)?.isFirsthand == true
            score += base * ageWeight(source.publishedAt, now: now) * (independent ? 1 : 0.5)
        }
        let independent = community.filter { $0.author != nil && SignalClassifier.classify($0)?.isFirsthand == true && ($0.publishedAt.map { now.timeIntervalSince($0) <= 86400 } ?? false) }
        if independent.count >= 3 { score += 0.15 }
        if independent.count >= 10 { score += 0.20 }
        if community.contains(where: { $0.screenshotEvidence }) { score += 0.10 }
        // Two fresh independent reports meet the user's Early threshold without claiming Likely.
        if independent.count >= 2 { score += 0.08 }
        return min(0.89, score) // Community + account evidence never become Official/Confirmed.
    }
    public static func merge(signals: [ResetSignal], personal: [ResetEvent], into existing: [ResetEvent], now: Date) -> [ResetEvent] {
        var events = existing
        for incoming in personal {
            if incoming.ownAccountReset, let index = events.firstIndex(where: { compatible($0, product: incoming.product, model: incoming.model, type: .suspectedGlobal, at: now) }) {
                events[index].sources = uniqueSources(events[index].sources + incoming.sources)
                events[index].ownAccountReset = true
                events[index].beforeValue.merge(incoming.beforeValue) { _, new in new }
                events[index].afterValue.merge(incoming.afterValue) { _, new in new }
                events[index].affectedBuckets = Array(Set(events[index].affectedBuckets + incoming.affectedBuckets)).sorted()
                events[index].updatedAt = now
                events[index].explanation = incoming.explanation + " Public reports are also attached; product matches, account eligibility is unverified."
            } else { events.insert(incoming, at: 0) }
        }
        for signal in signals {
            guard let published = signal.source.publishedAt ?? (signal.source.official ? signal.source.modifiedAt : nil), now.timeIntervalSince(published) <= 86400, published <= now.addingTimeInterval(300) else { continue }
            if events.contains(where: { $0.sources.contains(where: { $0.id == signal.source.id }) }) { continue }
            if let index = events.firstIndex(where: { compatible($0, product: signal.product, model: signal.model, type: signal.behavior, at: published) }) {
                let sources = uniqueSources(events[index].sources + [signal.source])
                if sources.count != events[index].sources.count { events[index].updatedAt = now }
                events[index].sources = sources
                if let plan = signal.plan { events[index].plans = Array(Set(events[index].plans + [plan])).sorted() }
                if signal.source.official { events[index].type = signal.behavior }
            } else {
                events.insert(ResetEvent(type: signal.behavior, detectedAt: now, updatedAt: now, product: signal.product, model: signal.model, plans: signal.plan.map { [$0] } ?? [], affectedBuckets: [], beforeValue: [:], afterValue: [:], confidence: 0, sources: [signal.source], explanation: signal.source.official ? "Official source describes this reset or offer. See wording and eligibility in the source; this does not confirm your account reset." : "Fresh public report. No official confirmation found in monitored sources. No irregular reset date is predicted.", ownAccountReset: false, timeline: []), at: 0)
            }
        }
        for index in events.indices where events[index].type != .scheduled && events[index].type != .unknown && events[index].type != .purchased && !(events[index].type == .banked && events[index].sources.allSatisfy({ $0.platform == "Local Codex" || $0.platform == "Manual" })) {
            let score = score(sources: events[index].sources, ownReset: events[index].ownAccountReset, now: now)
            if abs(events[index].confidence-score) > 0.001 || events[index].timeline.isEmpty {
                events[index].confidence = score
                events[index].timeline.append(ConfidencePoint(timestamp: now, score: score))
            }
            if events[index].ownAccountReset && events[index].reportCount > 0 && events[index].type == .accountUnexpected { events[index].type = .suspectedGlobal }
        }
        return events.sorted { $0.updatedAt > $1.updatedAt }
    }
    static func compatible(_ event: ResetEvent, product: String, model: String?, type: ResetEventType, at: Date) -> Bool {
        guard event.product == product, event.model == model, abs(at.timeIntervalSince(event.detectedAt)) <= 6*3600 else { return false }
        let global: Set<ResetEventType> = [.suspectedGlobal, .automaticGlobal, .accountUnexpected]
        return (global.contains(event.type) && global.contains(type)) || (event.type == type && type != .scheduled && type != .unknown)
    }
    public static func waveDescription(_ event: ResetEvent) -> String? {
        let sources = uniqueSources(event.sources).filter { !$0.official && $0.author != nil && SignalClassifier.classify($0)?.isFirsthand == true }
        let dates = sources.compactMap(\.publishedAt).sorted()
        guard dates.count >= 3, let first = dates.first, let last = dates.last, last.timeIntervalSince(first) <= 1800 else { return nil }
        return L10n.f("Reset wave: %d independent reports within %d minutes. Possible phased rollout.", dates.count, max(1, Int(last.timeIntervalSince(first)/60)))
    }
}

public enum NotificationPolicy {
    public static func shouldNotify(_ event: ResetEvent, settings: AppSettings, now: Date) -> Bool {
        guard event.type != .scheduled, event.updatedAt > now.addingTimeInterval(-86400) else { return false }
        // Personal purchases/known banked redemption are history, not global alerts.
        if (event.type == .banked || event.type == .purchased) && event.sources.allSatisfy({ $0.platform == "Local Codex" || $0.platform == "Manual" }) { return false }
        if event.ownAccountReset && !event.notifiedOwnReset && settings.notifyUnexpected { return true }
        guard event.confidence >= settings.threshold else { return false }
        let enabled = event.level == .confirmed ? settings.notifyOfficial : event.level == .likely ? settings.notifyLikely : settings.notifyEarly
        guard enabled else { return false }
        return event.notifiedRank < 0 || event.level.rank > event.notifiedRank
    }
}
