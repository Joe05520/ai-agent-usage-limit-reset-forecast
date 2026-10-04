import Foundation
import CryptoKit
import Darwin

public struct CodexCLIUsageProvider: UsageProvider {
    public let name = "Codex CLI · official app-server"
    public var customPath: String
    public init(customPath: String = "") { self.customPath = customPath }
    public static func executable(customPath: String = "") -> String? {
        let candidates = [customPath,
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/codex").path]
        return candidates.first { !$0.isEmpty && FileManager.default.isExecutableFile(atPath: $0) }
    }
    public func fetchUsage() async throws -> UsageState {
        let customPath = customPath
        return try await Task.detached(priority: .utility) {
            guard let binary = Self.executable(customPath: customPath) else {
                throw SentinelError.unavailable("Codex CLI not found. Install/sign in to official Codex, or choose its executable in Settings.")
            }
            return try Self.request(binary: binary)
        }.value
    }
    static func request(binary: String) throws -> UsageState {
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["app-server", "-c", "analytics.enabled=false"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            try? output.fileHandleForReading.close()
        }
        func send(_ object: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: object)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        let deadline = Date().addingTimeInterval(25)
        var buffer = Data()
        func response(_ id: Int) throws -> [String: Any] {
            while Date() < deadline {
                if let newline = buffer.firstIndex(of: 10) {
                    let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
                    guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any], object["id"] as? Int == id else { continue }
                    if object["error"] != nil { throw SentinelError.unavailable("Codex rejected the usage read. Check official Codex sign-in and Diagnostics. No credential was read by Sentinel.") }
                    guard let result = object["result"] as? [String: Any] else { continue }
                    return result
                }
                var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
                let ready = poll(&descriptor, 1, 250)
                guard ready >= 0 else { throw SentinelError.unavailable("Codex pipe read failed.") }
                if ready == 0 { continue }
                var bytes = [UInt8](repeating: 0, count: 8192)
                let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
                guard count > 0 else { throw SentinelError.unavailable("Codex app-server closed its connection.") }
                buffer.append(contentsOf: bytes.prefix(count))
                guard buffer.count < 2_000_000 else { throw SentinelError.unavailable("Unexpectedly large Codex response.") }
            }
            throw SentinelError.unavailable("Codex usage request timed out after 25 seconds.")
        }
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "openai_usage_sentinel", "title": "Usage Sentinel", "version": "1.0.0"]]])
        _ = try response(1)
        try send(["method": "initialized", "params": [:]])
        try send(["id": 2, "method": "account/rateLimits/read"])
        return try parse(response(2), now: Date())
    }
    public static func parse(_ result: [String: Any], now: Date) throws -> UsageState {
        let snapshots: [String: [String: Any]]
        if let multiple = result["rateLimitsByLimitId"] as? [String: [String: Any]], !multiple.isEmpty { snapshots = multiple }
        else if let single = result["rateLimits"] as? [String: Any] { snapshots = [single["limitId"] as? String ?? "codex": single] }
        else { throw SentinelError.unavailable("Codex returned no quota snapshot.") }
        var buckets: [UsageBucket] = []
        for (limitID, limit) in snapshots.sorted(by: { $0.key < $1.key }) {
            for key in ["primary", "secondary"] {
                guard let window = limit[key] as? [String: Any], let used = (window["usedPercent"] as? NSNumber)?.doubleValue, used.isFinite, used >= 0 else { continue }
                let mins = (window["windowDurationMins"] as? NSNumber)?.doubleValue
                let label: String = mins == 300 ? "5-hour" : mins == 10080 ? "Weekly" : mins.map { "\(Int($0))-minute" } ?? key.capitalized
                let product = limitID == "codex" ? "Codex" : (limit["limitName"] as? String ?? limitID)
                let reset = ((window["resetsAt"] as? NSNumber)?.doubleValue).flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
                buckets.append(UsageBucket(id: "\(limitID).\(key)", name: label, product: product, remainingPercent: max(0, 100-used), usedPercent: used, resetAt: reset, windowDuration: mins.map { $0 * 60 }, source: "Local Codex app-server · account/rateLimits/read", lastUpdated: now))
            }
        }
        guard !buckets.isEmpty else { throw SentinelError.unavailable("No usable percentage windows returned. Missing limits are not zero.") }
        let fingerprint = (result["accountId"] as? String).map { SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() }
        let legacy = result["rateLimits"] as? [String: Any]
        return UsageState(timestamp: now, buckets: buckets, source: "Codex CLI app-server", accountFingerprint: fingerprint, plan: legacy?["planType"] as? String, resetCredits: (result["rateLimitResetCredits"] as? [String: Any])?["availableCount"] as? Int, ordinaryUsageAllowed: result["ordinaryUsageAllowed"] as? Bool)
    }
}
