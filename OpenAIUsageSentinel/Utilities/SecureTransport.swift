import Foundation

public enum SafeURL {
    public static func external(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host != nil && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }
}
final class SecureRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let hosts: Set<String>
    init(hosts: Set<String>) { self.hosts = hosts }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.flatMap { SafeURL.external($0) && hosts.contains($0.host!.lowercased()) ? request : nil })
    }
}
public enum SecureTransport {
    public static func read(_ request: URLRequest, limit: Int, redirectHosts: Set<String> = [], resourceTimeout: TimeInterval = 25) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, SafeURL.external(url) else { throw SentinelError.unavailable("HTTPS required") }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false; configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20; configuration.timeoutIntervalForResource = resourceTimeout
        let session = URLSession(configuration: configuration, delegate: SecureRedirectDelegate(hosts: redirectHosts), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.expectedContentLength <= limit else { throw SentinelError.unavailable("Response exceeds size limit") }
        var data = Data(); var chunk = [UInt8](); chunk.reserveCapacity(8192)
        for try await byte in bytes {
            chunk.append(byte)
            guard data.count + chunk.count <= limit else { throw SentinelError.unavailable("Response exceeds size limit") }
            if chunk.count == 8192 { data.append(contentsOf: chunk); chunk.removeAll(keepingCapacity: true) }
        }
        data.append(contentsOf: chunk)
        return (data, http)
    }
}
