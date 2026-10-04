import Foundation
import CryptoKit

public enum SignalClassifier {
    public static func classify(_ source: SignalSource) -> ResetSignal? {
        let text = (source.title + " " + source.snippet).lowercased()
        let context = ["claude", "gemini", "grok", "codex", "chatgpt", "openai", "astra", "work", "quota", "usage", "allowance", "weekly", "limit"].contains { text.contains($0) }
        let negative = ["password reset", "reset password", "factory reset", "doesn't reset", "didn't reset", "not reset", "did not reset", "never reset", "no reset", "hasn't reset", "when does", "when will", "how do i reset", "how to reset"].contains { text.contains($0) }
        guard context && !negative else { return nil }
        let explicitlyRegular = ["scheduled reset", "regular reset", "usual weekly reset", "resets every week"].contains { text.contains($0) }
        let exception = ["unexpected", "early reset", "global reset", "automatic reset", "banked", "purchased", "complimentary", "one-time", "suddenly"].contains { text.contains($0) }
        if explicitlyRegular && !exception { return nil }
        let irregular = ["global reset", "automatic reset", "one-time reset", "complimentary reset", "free reset", "banked reset", "purchased reset", "paid reset", "quota reset", "quota refreshed", "usage refreshed", "limit refreshed", "weekly limit reset", "got reset", "got a reset", "quota returned", "back to 100%", "suddenly 100%", "quota just reset", "my quota reset", "anyone else got reset", "usage back to 100", "limits have been reset", "limits were reset", "allowance restored", "limits restored", "usage restored", "quota restored", "quota refreshed", "limit unexpectedly increased"].contains { text.contains($0) }
        guard irregular else { return nil }
        let title = source.title.lowercased()
        let globalMention = title.contains("global reset") || title.contains("automatic reset")
        let type: ResetEventType = globalMention ? (source.official ? .automaticGlobal : .suspectedGlobal) : text.contains("banked") ? .banked : (text.contains("purchased reset") || text.contains("paid reset")) ? .purchased : text.contains("complimentary") || text.contains("one-time") || text.contains("free reset") ? .complimentary : source.official ? .automaticGlobal : .suspectedGlobal
        let product = text.contains("claude") ? "Claude" : text.contains("gemini") ? "Gemini" : text.contains("grok") ? "Grok" : text.contains("codex") ? "Codex" : text.contains("chatgpt work") ? "ChatGPT Work" : text.contains("astra") ? "Astra" : text.contains("chatgpt") ? "ChatGPT" : "OpenAI (unspecified)"
        let model = ["astra", "terra", "sol"].first { text.range(of: "\\b" + $0 + "\\b", options: .regularExpression) != nil }
        let plan = ["plus", "pro", "business", "free"].first { text.range(of: "\\b" + $0 + "\\b", options: .regularExpression) != nil }
        let deniedAccountReset = ["did not reach", "not to have been applied", "not applied", "never received", "did not receive", "not reset"].contains { text.contains($0) }
        let firsthand = !deniedAccountReset && ["my ", "i got", "mine ", "just reset", "returned to", "back to 100", "suddenly", "anyone else"].contains { text.contains($0) }
        var enriched = source
        enriched.reportedPlan = plan; enriched.reportedModel = model
        return ResetSignal(source: enriched, product: product, model: model, plan: plan, behavior: type, isFirsthand: firsthand)
    }
    public static func normalized(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression).replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
    public static func digest(_ text: String) -> String { SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined() }
}
