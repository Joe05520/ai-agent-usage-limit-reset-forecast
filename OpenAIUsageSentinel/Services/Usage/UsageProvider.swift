import Foundation

public protocol UsageProvider: Sendable {
    var name: String { get }
    func fetchUsage() async throws -> UsageState
}
public struct ManualUsageProvider: UsageProvider {
    public let name = "Manual (user entered)"
    public var state: UsageState?
    public func fetchUsage() async throws -> UsageState {
        guard let state else { throw SentinelError.unavailable("Enter an explicit manual snapshot in Settings.") }
        return state
    }
}
// Reserved integration point. No invented endpoint is called.
public struct OfficialUsageAPIProvider: UsageProvider {
    public let name = "Official usage API (not configured)"
    public func fetchUsage() async throws -> UsageState {
        throw SentinelError.unavailable("No configured official personal ChatGPT usage API. Use local Codex app-server.")
    }
}
