import Foundation

public enum PersonalResetDetector {
    public static func detect(before: UsageState, after: UsageState, intent: ResetIntent? = nil) -> [ResetEvent] {
        guard before.source == after.source, before.accountFingerprint == after.accountFingerprint,
              before.plan == after.plan, after.timestamp > before.timestamp,
              after.timestamp.timeIntervalSince(before.timestamp) < 86400 else { return [] }
        return after.buckets.compactMap { bucket in
            guard let old = before.buckets.first(where: { $0.id == bucket.id }), old.windowDuration == bucket.windowDuration else { return nil }
            let jump = bucket.remainingPercent - old.remainingPercent
            guard jump >= 10 || (jump >= 3 && bucket.remainingPercent >= 99) else { return nil }
            let activeIntent = intent.flatMap { after.timestamp.timeIntervalSince($0.recordedAt) >= 0 && after.timestamp.timeIntervalSince($0.recordedAt) <= 1800 ? $0 : nil }
            let type: ResetEventType
            let reason: String
            // Compare the PREVIOUS schedule: providers may move resetAt after a reset.
            if let reset = old.resetAt, after.timestamp >= reset.addingTimeInterval(-120) {
                type = .scheduled; reason = "The increase was observed at or after the previously scheduled reset. A polling gap cannot prove the exact reset moment."
            } else if let activeIntent {
                type = activeIntent.type; reason = "You recorded a \(type.englishLabel.lowercased()) within the last 30 minutes."
            } else if let oldCredits = before.resetCredits, let newCredits = after.resetCredits, newCredits < oldCredits {
                type = .unknown; reason = "Quota increased while available reset credits decreased. A banked reset may have been redeemed, or a credit may have expired. The provider does not prove which happened; this is not global-reset evidence."
            } else if old.resetAt == nil {
                type = .unknown; reason = "Quota increased, but the previous scheduled reset time was unavailable."
            } else {
                type = .accountUnexpected
                reason = "Quota increased before its previous regular reset. This is account evidence, not proof of a global reset. Purchased/banked activity outside this app is not always observable."
            }
            let now = after.timestamp
            let local = SignalSource(title: "\(bucket.product) \(bucket.name): \(Int(old.remainingPercent))% → \(Int(bucket.remainingPercent))%", url: AgentKind.forProduct(bucket.product).sourceURL, platform: after.source.contains("Manual") ? "Manual" : "Local " + bucket.product, publishedAt: now, fetchedAt: now, author: nil, snippet: "Provider: \(bucket.source). Previous schedule: \(old.resetAt?.formatted() ?? "unknown"). \(reason)", official: false)
            let score = type == .accountUnexpected ? (local.platform == "Manual" || after.source.contains("user-provided") || (after.source.contains("Local ") && after.accountFingerprint == nil) ? 0.3 : 0.6) : type == .unknown ? 0.25 : 1.0
            return ResetEvent(type: type, detectedAt: now, updatedAt: now, product: bucket.product, model: nil, plans: after.plan.map { [$0] } ?? [], affectedBuckets: [bucket.id], beforeValue: [bucket.id: old.remainingPercent], afterValue: [bucket.id: bucket.remainingPercent], confidence: score, sources: [local], explanation: reason, ownAccountReset: type == .accountUnexpected, timeline: [ConfidencePoint(timestamp: now, score: score)])
        }
    }
}
