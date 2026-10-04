import Foundation

public actor HTTPClient {
    public static let shared = HTTPClient()
    private struct Entry: Codable { var data: Data; var etag: String?; var modified: String?; var savedAt: Date }
    private var cache: [String: Entry] = [:]
    private var failures: [String: Int] = [:]
    private var blockedUntil: [String: Date] = [:]
    private let session: URLSession
    private let cacheURL: URL
    public init(cacheURL: URL? = nil) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 25
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        session = URLSession(configuration: config)
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OpenAIUsageSentinel")
        self.cacheURL = cacheURL ?? root.appendingPathComponent("public-cache.json")
        if let data = try? Data(contentsOf: self.cacheURL), let value = try? JSONDecoder().decode([String: Entry].self, from: data) { cache = value }
    }
    public func get(_ url: URL) async throws -> Data {
        let key = url.absoluteString
        if let until = blockedUntil[key], until > Date() { throw SentinelError.unavailable("Backoff until \(until.formatted(date: .omitted, time: .shortened)).") }
        var request = URLRequest(url: url)
        request.setValue("OpenAIUsageSentinel/1.0 (macOS; public reset monitor)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json, application/atom+xml, application/rss+xml, text/html", forHTTPHeaderField: "Accept")
        if let entry = cache[key] {
            if let etag = entry.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            if let modified = entry.modified { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SentinelError.unavailable("Invalid HTTP response.") }
            if http.statusCode == 304, let saved = cache[key] { failures[key] = 0; blockedUntil[key] = nil; return saved.data }
            guard http.statusCode == 200 else {
                if http.statusCode == 429 || http.statusCode == 403 || http.statusCode == 503 {
                    let retry = http.value(forHTTPHeaderField: "Retry-After")
                    let seconds = retry.flatMap(Double.init) ?? retry.flatMap(DateParsing.parse).map { max(60, $0.timeIntervalSinceNow) } ?? (http.statusCode == 403 ? 1800 : 600)
                    blockedUntil[key] = Date().addingTimeInterval(seconds)
                }
                throw SentinelError.unavailable(http.statusCode == 429 ? "Rate limited (HTTP 429). Retry-After/backoff respected." : "HTTP \(http.statusCode). Source unavailable; no bypass attempted.")
            }
            guard data.count <= 5_000_000 else { throw SentinelError.unavailable("Source response exceeds 5 MB limit.") }
            failures[key] = 0; blockedUntil[key] = nil
            cache[key] = Entry(data: data, etag: http.value(forHTTPHeaderField: "ETag"), modified: http.value(forHTTPHeaderField: "Last-Modified"), savedAt: Date())
            cache = cache.filter { $0.value.savedAt > Date().addingTimeInterval(-7*86400) }
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            if let encoded = try? JSONEncoder().encode(cache) { try? encoded.write(to: cacheURL, options: .atomic); try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path) }
            return data
        } catch {
            let count = (failures[key] ?? 0) + 1; failures[key] = count
            if blockedUntil[key] == nil { blockedUntil[key] = Date().addingTimeInterval(min(1800, 30 * pow(2, Double(min(count, 6))))) }
            throw error
        }
    }
}
