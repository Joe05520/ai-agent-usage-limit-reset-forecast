import Foundation

public struct UsageReminderSettings: Codable, Equatable, Sendable {
    public var enabled = true
    public var warningPercent = 20.0
    public var criticalEnabled = true
    public var criticalPercent = 5.0
    /// Optional storage migrates existing two-threshold preferences without resetting them.
    public var stagedThresholds: [Double]?
    public var excludedBucketIDs: Set<String> = []
    public var snoozedUntil: Date?
    public var showDailyTrend = true
    public init() {}
    public static let maximumStages = 5
    public var stages: [Double] {
        get {
            let legacy = [min(99, max(1, warningPercent))] + (criticalEnabled ? [min(min(99, max(1, warningPercent)) - 1, max(0, criticalPercent))] : [])
            return Self.normalize(stagedThresholds ?? legacy)
        }
        set { stagedThresholds = Self.normalize(newValue) }
    }
    public var thresholds: [Double] { stages.sorted() }
    public var hasCriticalStage: Bool { stages.count > 1 }
    private static func normalize(_ values: [Double]) -> [Double] {
        Array(Set(values.filter { $0.isFinite && (0...99).contains($0) }.map { $0.rounded() }).sorted(by: >).prefix(maximumStages))
    }
    public mutating func addStage() {
        guard stages.count < Self.maximumStages else { return }
        let available: [Double] = [50, 30, 20, 10, 5] + (0...99).reversed().map { Double($0) }
        if let next = available.first(where: { !stages.contains($0) }) { stages += [next] }
    }

}

public struct UsageReminder: Identifiable, Sendable {
    public var id: String { "quota-\(cycleID)-\(Int(threshold))" }
    public var bucket: UsageBucket
    public var cycleID: UUID
    public var threshold: Double
    public var coveredThresholds: [Double]
    public var critical: Bool
    public var observedAt: Date
}

public struct ReminderCycle: Codable, Sendable {
    public var context: String
    public var id = UUID()
    public var resetAt: Date?
    public var lastRemaining: Double
    public var observedAt: Date
    public var deliveredThresholds: [Double] = []
}

public struct UsageReminderEngine: Codable, Sendable {
    public private(set) var cycles: [String: ReminderCycle] = [:]
    public init() {}
    public static func context(_ state: UsageState, bucket: UsageBucket) -> String {
        [state.source, state.accountFingerprint ?? "unknown", state.plan ?? "unknown", bucket.product, bucket.id, String(bucket.windowDuration ?? -1)].joined(separator: "|")
    }
    /// Observe only successfully acquired snapshots; failures never enter this engine.
    public mutating func observe(_ state: UsageState) {
        for bucket in state.buckets where bucket.remainingPercent.isFinite && (0...100).contains(bucket.remainingPercent) {
            let context = Self.context(state, bucket: bucket)
            if let prior = cycles[bucket.id], state.timestamp <= prior.observedAt { continue }
            if let prior = cycles[bucket.id], prior.context == context {
                guard state.timestamp > prior.observedAt else { continue }
                let scheduleChanged = prior.resetAt != nil && bucket.resetAt != nil && abs(prior.resetAt!.timeIntervalSince(bucket.resetAt!)) > 60
                let restored = bucket.remainingPercent >= 95 && prior.lastRemaining <= 75 && bucket.remainingPercent - prior.lastRemaining >= 20
                if !scheduleChanged && !restored {
                    var next = prior
                    next.lastRemaining = bucket.remainingPercent; next.observedAt = state.timestamp; next.resetAt = bucket.resetAt
                    cycles[bucket.id] = next
                    continue
                }
            }
            cycles[bucket.id] = ReminderCycle(context: context, resetAt: bucket.resetAt, lastRemaining: bucket.remainingPercent, observedAt: state.timestamp)
        }
    }
    public func pending(_ state: UsageState, settings: UsageReminderSettings, now: Date) -> [UsageReminder] {
        // Old saved/manual values are never presented as a newly observed low allowance.
        guard settings.enabled, settings.snoozedUntil.map({ $0 > now }) != true,
              now.timeIntervalSince(state.timestamp) >= -60, now.timeIntervalSince(state.timestamp) <= 600 else { return [] }
        return state.buckets.compactMap { bucket in
            guard !settings.excludedBucketIDs.contains(bucket.id), let cycle = cycles[bucket.id],
                  cycle.context == Self.context(state, bucket: bucket), cycle.observedAt == state.timestamp,
                  cycle.resetAt.map({ $0 > now }) != false else { return nil }
            let crossed = settings.thresholds.filter { bucket.remainingPercent <= $0 && !cycle.deliveredThresholds.contains($0) }
            guard let threshold = crossed.first else { return nil }
            return UsageReminder(bucket: bucket, cycleID: cycle.id, threshold: threshold, coveredThresholds: crossed,
                                 critical: settings.hasCriticalStage && threshold == settings.thresholds.first,
                                 observedAt: state.timestamp)
        }
    }
    /// Call only after UserNotifications accepts delivery; denied permission remains retryable.
    public mutating func markDelivered(_ reminder: UsageReminder) {
        guard var cycle = cycles[reminder.bucket.id], cycle.id == reminder.cycleID else { return }
        cycle.deliveredThresholds = Array(Set(cycle.deliveredThresholds + reminder.coveredThresholds)).sorted()
        cycles[reminder.bucket.id] = cycle
    }
}

public enum ObservedUsageTrend {
    /// Sum measured consumption between close samples in today's local calendar day.
    /// Reset jumps, context changes and gaps longer than 15 minutes are excluded.
    public static func consumedPoints(bucketID: String, history: [UsageSnapshot], now: Date, calendar: Calendar = .current) -> Double? {
        guard let current = history.last, let currentBucket = current.buckets.first(where: { $0.id == bucketID }) else { return nil }
        let context = UsageReminderEngine.context(current, bucket: currentBucket)
        let start = calendar.startOfDay(for: now)
        let samples = history.filter { $0.timestamp >= start && $0.timestamp <= now }.sorted { $0.timestamp < $1.timestamp }
        var total = 0.0; var pairs = 0
        for (before, after) in zip(samples, samples.dropFirst()) {
            guard let a = before.buckets.first(where: { $0.id == bucketID }), let b = after.buckets.first(where: { $0.id == bucketID }),
                  UsageReminderEngine.context(before, bucket: a) == context, UsageReminderEngine.context(after, bucket: b) == context,
                  a.resetAt == b.resetAt, after.timestamp.timeIntervalSince(before.timestamp) > 0,
                  after.timestamp.timeIntervalSince(before.timestamp) <= 900,
                  a.remainingPercent.isFinite, b.remainingPercent.isFinite, b.remainingPercent <= a.remainingPercent else { continue }
            total += a.remainingPercent - b.remainingPercent; pairs += 1
        }
        return pairs > 0 ? total : nil
    }
}
