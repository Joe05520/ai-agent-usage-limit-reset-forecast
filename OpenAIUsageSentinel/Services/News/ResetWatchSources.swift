import Foundation

/// Editorial source weights, not calibrated probabilities of a future reset.
public enum ResetWatchPolicy {
    public static func handle(_ url: URL) -> String? {
        guard url.scheme == "https", ["x.com", "www.x.com", "twitter.com", "www.twitter.com"].contains(url.host?.lowercased() ?? ""), url.user == nil, url.password == nil, url.port == nil else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count == 3, parts[1] == "status", !parts[2].isEmpty, parts[2].allSatisfy(\.isNumber) else { return nil }
        return parts[0].lowercased()
    }
    public static func weight(_ source: SignalSource) -> Double? {
        guard let handle = handle(source.url), ["thsottiaux", "codex_resets"].contains(handle) else { return nil }
        // A mention in arbitrary text or a spoofed URL cannot inherit a watch weight.
        guard source.author?.lowercased().replacingOccurrences(of: "@", with: "") == handle else { return nil }
        if let via = source.viaURL {
            guard via.scheme == "https", via.user == nil, via.port == nil else { return nil }
            if via.host == "codex-resets.com" { return 0.75 }
            if via.host == "codex-reset.com", handle == "thsottiaux" { return 0.85 }
            return nil
        }
        return handle == "codex_resets" ? 0.75 : 0.85
    }
    public static func classify(_ source: SignalSource) -> ResetSignal? {
        guard weight(source) != nil else { return nil }
        let text = source.snippet.lowercased().replacingOccurrences(of: "’", with: "'")
        let context = (source.watchContext ?? "").lowercased()
        guard text.contains("reset") || (context.contains("reset") && (text.contains("vote") || text.contains("poll"))) else { return nil }
        guard !["password", "factory reset", "no reset", "not reset", "won't reset", "can't really give a reset", "didn't get the reset", "did not get the reset"].contains(where: text.contains) else { return nil }
        let completed = ["reset all propagated", "resets all propagated", "reset has been processed", "limits have been reset", "all reset for everyone", "reset is complete"].contains(where: text.contains)
        let banked = text.contains("banked")
        let voting = !completed && !banked && ["vote", "voting", "poll", "choose", "how was day"].contains(where: text.contains)
        let kind: ResetEventType = banked ? .banked : completed ? .suspectedGlobal : voting ? .poll : .forecast
        var enriched = source
        if kind == .forecast || kind == .poll {
            enriched.expiresAt = source.expiresAt ?? source.publishedAt?.addingTimeInterval(86400)
        }
        // Mirrors remain non-official, regardless of the attributed author's employer.
        if source.viaURL != nil { enriched.official = false }
        return ResetSignal(source: enriched, product: "Codex", model: nil, plan: nil, behavior: kind, isFirsthand: false)
    }
}

/// Free, documented public API. Data attribution is retained on every source.
public struct CodexResetsSource: ResetSignalSource {
    public let name = "Codex Resets · @codex_resets · 75%"
    public init() {}
    public func fetchSignals() async throws -> [ResetSignal] {
        async let history = HTTPClient.shared.get(URL(string: "https://codex-resets.com/api/v1/resets?limit=60")!)
        async let status = HTTPClient.shared.get(URL(string: "https://codex-resets.com/api/v1/status")!)
        return try await Self.parse(history: history, status: status, now: Date())
    }
    public static func parse(history: Data, status: Data, now: Date) throws -> [ResetSignal] {
        let list = try JSONSerialization.jsonObject(with: history) as? [String: Any]
        let current = try JSONSerialization.jsonObject(with: status) as? [String: Any]
        guard let rows = list?["data"] as? [[String: Any]], let data = current?["data"] as? [String: Any] else { throw SentinelError.unavailable("Codex Resets schema unavailable.") }
        var result = rows.compactMap { parseRow($0, now: now) }
        for key in ["active_watch", "scheduled_reset"] {
            guard var row = data[key] as? [String: Any] else { continue }
            row["announced_at"] = row["observed_at"] ?? row["announced_at"]
            if var signal = parseRow(row, now: now) {
                signal.behavior = key == "active_watch" && row["text"].map({ String(describing: $0).lowercased().contains("poll") }) == true ? .poll : .forecast
                signal.source.expiresAt = (row["expires_at"] as? String).flatMap(DateParsing.parse) ?? signal.source.publishedAt?.addingTimeInterval(86400)
                signal.source.announcedTarget = (row["scheduled_for"] as? String).flatMap(DateParsing.parse)
                result.append(signal)
            }
        }
        return result
    }
    private static func parseRow(_ row: [String: Any], now: Date) -> ResetSignal? {
        guard let evidence = row["source"] as? [String: Any], evidence["type"] as? String == "x_post", let author = evidence["author"] as? String, let address = evidence["url"] as? String, let url = URL(string: address), ResetWatchPolicy.handle(url) == author.lowercased(), let stamp = row["announced_at"] as? String, let date = DateParsing.parse(stamp), date <= now.addingTimeInterval(300), let text = row["text"] as? String else { return nil }
        let source = SignalSource(title: "Codex · @" + author, url: url, platform: "X via Codex Resets", publishedAt: date, fetchedAt: now, author: author, snippet: String(text.prefix(1500)), official: false, viaURL: URL(string: "https://codex-resets.com")!)
        return ResetWatchPolicy.classify(source)
    }
}

/// Public read-only radar; best effort schema, independent failure/backoff.
/// It is a secondary feed, not an authenticated X API connection.
public struct TiboRadarSource: ResetSignalSource {
    public let name = "Tibo radar · @thsottiaux · 85%"
    public init() {}
    public func fetchSignals() async throws -> [ResetSignal] {
        try Self.parse(await HTTPClient.shared.get(URL(string: "https://codex-reset.com/api/feed")!), now: Date())
    }
    public static func parse(_ body: Data, now: Date) throws -> [ResetSignal] {
        guard let root = try JSONSerialization.jsonObject(with: body) as? [String: Any], let rows = root["tweets"] as? [[String: Any]], root["stale"] as? Bool != true, (root["profile"] as? [String: Any])?["handle"] as? String == "thsottiaux" else { throw SentinelError.unavailable("Tibo radar stale or schema unavailable.") }
        let texts = Dictionary(rows.compactMap { row -> (String, String)? in
            guard let id = row["id"] as? String, let text = row["text"] as? String else { return nil }; return (id, text)
        }, uniquingKeysWith: { first, _ in first })
        return rows.compactMap { row in
            guard let address = row["url"] as? String, let url = URL(string: address), ResetWatchPolicy.handle(url) == "thsottiaux", let stamp = row["at"] as? String, let date = DateParsing.parse(stamp), date <= now.addingTimeInterval(300), let text = row["text"] as? String else { return nil }
            let parent = (row["in_reply_to_tweet_id"] as? String).flatMap { texts[$0] } ?? ""
            let context = parent.lowercased().contains("reset") ? parent : row["tibo_lane"] as? String == "reset_related" ? "Reset-related thread (secondary feed classification)" : nil
            let source = SignalSource(title: "Codex · Tibo @thsottiaux", url: url, platform: "X via Tibo radar", publishedAt: date, fetchedAt: now, author: "thsottiaux", snippet: String(text.prefix(1500)), official: false, viaURL: URL(string: "https://codex-reset.com")!, watchContext: context)
            return ResetWatchPolicy.classify(source)
        }
    }
}
