import Foundation

public protocol ResetSignalSource: Sendable {
    var name: String { get }
    func fetchSignals() async throws -> [ResetSignal]
}
public struct RSSSignalSource: ResetSignalSource {
    public var name: String
    public var url: URL
    public var platform: String
    public var official: Bool
    public func fetchSignals() async throws -> [ResetSignal] {
        let data = try await HTTPClient.shared.get(url)
        return try FeedParser.parse(data).compactMap { item in
            guard let url = URL(string: item.url), url.scheme == "https" || url.scheme == "http" else { return nil }
            let source = SignalSource(title: FeedParser.plainText(item.title), url: url, platform: platform, publishedAt: item.date, fetchedAt: Date(), author: item.author, snippet: String(FeedParser.plainText(item.content).prefix(3000)), official: official)
            return SignalClassifier.classify(source)
        }
    }
}
public struct GitHubCodexSource: ResetSignalSource {
    public let name = "GitHub · openai/codex"
    public init() {}
    public func fetchSignals() async throws -> [ResetSignal] {
        let day = Date().addingTimeInterval(-86400).formatted(.iso8601.year().month().day().dateSeparator(.dash))
        var components = URLComponents(string: "https://api.github.com/search/issues")!
        components.queryItems = [.init(name: "q", value: "repo:openai/codex reset created:>=\(day)"), .init(name: "sort", value: "created"), .init(name: "per_page", value: "50")]
        let data = try await HTTPClient.shared.get(components.url!)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let items = root?["items"] as? [[String: Any]] else { throw SentinelError.unavailable("GitHub search schema changed.") }
        return items.compactMap { item in
            guard let title = item["title"] as? String, let link = item["html_url"] as? String, let url = URL(string: link) else { return nil }
            let source = SignalSource(title: title, url: url, platform: "GitHub", publishedAt: (item["created_at"] as? String).flatMap(DateParsing.parse), fetchedAt: Date(), author: (item["user"] as? [String: Any])?["login"] as? String, snippet: String((item["body"] as? String ?? "").prefix(4000)), official: false)
            // Being in an OpenAI-owned repository does not make a user issue official.
            return SignalClassifier.classify(source)
        }
    }
}
public struct RedditSource: ResetSignalSource {
    public let subreddit: String
    public var name: String { "Reddit · r/" + subreddit }
    public init(subreddit: String = "codex") { self.subreddit = subreddit }
    public func fetchSignals() async throws -> [ResetSignal] {
        try await RSSSignalSource(name: name, url: URL(string: "https://www.reddit.com/r/\(subreddit)/search.rss?q=reset&restrict_sr=on&sort=new&t=day")!, platform: "Reddit", official: false).fetchSignals()
    }
}
public struct OpenAIStatusSource: ResetSignalSource {
    public let name = "OpenAI Status"
    public init() {}
    public func fetchSignals() async throws -> [ResetSignal] {
        let data = try await HTTPClient.shared.get(URL(string: "https://status.openai.com/api/v2/incidents.json")!)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let items = root?["incidents"] as? [[String: Any]] else { throw SentinelError.unavailable("Status schema changed.") }
        return items.compactMap { item in
            let body = (item["incident_updates"] as? [[String: Any]] ?? []).compactMap { $0["body"] as? String }.joined(separator: " ")
            guard let title = item["name"] as? String, let link = item["shortlink"] as? String, let url = URL(string: link) else { return nil }
            return SignalClassifier.classify(SignalSource(title: title, url: url, platform: "OpenAI Status", publishedAt: (item["created_at"] as? String).flatMap(DateParsing.parse), fetchedAt: Date(), author: "OpenAI", snippet: String(body.prefix(4000)), official: true))
        }
    }
}
public struct OpenAIHelpCenterSource: ResetSignalSource {
    public var name: String
    public var url: URL
    public func fetchSignals() async throws -> [ResetSignal] {
        let data = try await HTTPClient.shared.get(url)
        guard let html = String(data: data, encoding: .utf8) else { throw SentinelError.unavailable("Invalid help document.") }
        // Evergreen help text is a reference, not a dated announcement. Monitor version changes
        // separately and require an explicit current publication timestamp for alert eligibility.
        let pattern = #""dateModified"\s*:\s*"([^"]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)), let range = Range(match.range(at: 1), in: html), let date = DateParsing.parse(String(html[range])), Date().timeIntervalSince(date) <= 86400 else { return [] }
        let plain = FeedParser.plainText(html)
        guard let range = plain.range(of: #"(?i)(global reset|one-time reset|complimentary reset|limits have been reset|limits were reset)"#, options: .regularExpression) else { return [] }
        let start = plain.index(range.lowerBound, offsetBy: -150, limitedBy: plain.startIndex) ?? plain.startIndex
        let end = plain.index(range.upperBound, offsetBy: 500, limitedBy: plain.endIndex) ?? plain.endIndex
        let snippet = String(plain[start..<end])
        // A definition such as 'an automatic reset is...' is not confirmation of an event.
        guard snippet.range(of: #"(?i)(we (have |are |will )?(reset|refresh)|on (september|october|november|december|january|february|march|april|may|june|july|august)|today|rollout|announc)"#, options: .regularExpression) != nil else { return [] }
        var source = SignalSource(title: name + " · recently updated announcement", url: url, platform: "OpenAI Help Center", publishedAt: nil, fetchedAt: Date(), author: "OpenAI", snippet: snippet, official: true)
        source.modifiedAt = date
        return SignalClassifier.classify(source).map { [$0] } ?? []
    }
}
public struct OpenAIReleaseNotesSource: ResetSignalSource {
    public let name = "OpenAI · Codex changelog"
    public init() {}
    public func fetchSignals() async throws -> [ResetSignal] {
        try await RSSSignalSource(name: name, url: URL(string: "https://developers.openai.com/codex/changelog/rss.xml")!, platform: "OpenAI Release Notes", official: true).fetchSignals()
    }
}
public struct HackerNewsSource: ResetSignalSource {
    public let name = "Hacker News"
    public init() {}
    public func fetchSignals() async throws -> [ResetSignal] {
        let data = try await HTTPClient.shared.get(URL(string: "https://hn.algolia.com/api/v1/search_by_date?query=codex%20reset&tags=story&hitsPerPage=30")!)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let items = root?["hits"] as? [[String: Any]] else { throw SentinelError.unavailable("HN schema changed.") }
        return items.compactMap { item in
            guard let id = item["objectID"] as? String, let title = item["title"] as? String else { return nil }
            return SignalClassifier.classify(SignalSource(title: title, url: URL(string: "https://news.ycombinator.com/item?id=\(id)")!, platform: "Hacker News", publishedAt: (item["created_at"] as? String).flatMap(DateParsing.parse), fetchedAt: Date(), author: item["author"] as? String, snippet: FeedParser.plainText(item["story_text"] as? String ?? ""), official: false))
        }
    }
}
public struct XSource: ResetSignalSource {
    public let name = "X · not configured"
    public init() {}
    public func fetchSignals() async throws -> [ResetSignal] {
        throw SentinelError.unavailable("X requires an authorized API/feed. No scraping, cookies or unofficial proxy is used. Adapter reserved.")
    }
}
public enum SourceCatalog {
    public static func enabled(_ settings: AppSettings) -> [any ResetSignalSource] {
        var sources: [any ResetSignalSource] = []
        if settings.official {
            sources += [OpenAIStatusSource(), OpenAIReleaseNotesSource(), RSSSignalSource(name: "OpenAI News", url: URL(string: "https://openai.com/news/rss.xml")!, platform: "OpenAI News", official: true),
                OpenAIHelpCenterSource(name: "OpenAI Help · usage", url: URL(string: "https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan")!),
                OpenAIHelpCenterSource(name: "OpenAI Help · banked resets", url: URL(string: "https://help.openai.com/en/articles/20001498-how-banked-codex-resets-work")!),
                OpenAIHelpCenterSource(name: "ChatGPT Release Notes", url: URL(string: "https://help.openai.com/en/articles/6825453-chatgpt-release-notes")!)]
        }
        if settings.github { sources.append(GitHubCodexSource()) }
        if settings.reddit { sources += [RedditSource(), RedditSource(subreddit: "OpenaiCodex")] }
        if settings.watchResets { sources += [CodexResetsSource(), TiboRadarSource()] }
        if settings.hackerNews { sources.append(HackerNewsSource()) }
        return sources
    }
}
