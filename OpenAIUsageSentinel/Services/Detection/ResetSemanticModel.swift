import Foundation

/// Small, offline CART classifier. Leaf purity is training support, never truth probability.
public enum ResetSemanticModel {
    public struct Assessment {
        public let label: String
        public let factor: Double
        public let reasons: [String]
    }
    private struct Model: Decodable {
        let schema: Int
        let features: [String: String]
        let tree: Node
        let factors: [String: Double]
    }
    private final class Node: Decodable {
        let feature: String?
        let yes: Node?
        let no: Node?
        let label: String?
    }
    private static let model: Model? = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "ResetSemanticModel", withExtension: "json"), let data = try? Data(contentsOf: url), let model = try? JSONDecoder().decode(Model.self, from: data), model.schema == 1 else { return nil }
        return model
    }()
    public static func assess(_ text: String) -> Assessment? {
        guard let model, text.count <= 100_000 else { return nil }
        let text = text.lowercased().replacingOccurrences(of: "’", with: "'")
        let features = model.features.mapValues { text.range(of: $0, options: .regularExpression) != nil }
        // Out-of-vocabulary wording keeps the established rules rather than inventing a prediction.
        guard features.contains(where: { $0.key != "reset" && $0.value }) else { return nil }
        var node = model.tree, reasons: [String] = []
        for _ in 0..<16 {
            guard let feature = node.feature else { break }
            let hit = features[feature] == true
            if hit { reasons.append(feature) }
            guard let next = hit ? node.yes : node.no else { return nil }
            node = next
        }
        guard let label = node.label, let factor = model.factors[label] else { return nil }
        let required = ["forecast": "future", "poll": "poll", "completed": "completed", "accountReport": "completed", "uncertain": "wish", "regular": "regular", "negative": "negative", "irrelevant": "unrelated"]
        guard let feature = required[label], features[feature] == true else { return nil }
        if label == "regular" && features["exception"] == true { return nil }
        return Assessment(label: label, factor: factor, reasons: reasons)
    }
    public static func factor(_ source: SignalSource) -> Double {
        source.isAccountEvidence ? 1 : assess(source.title + " " + source.snippet)?.factor ?? 1
    }
    public static func explanation(_ source: SignalSource) -> String? {
        guard !source.isAccountEvidence, let result = assess(source.title + " " + source.snippet) else { return nil }
        let labelKey = "Semantic " + result.label
        return L10n.t("Local decision tree") + " · " + L10n.t(labelKey) + " · " + L10n.t("Evidence multiplier") + String(format: " ×%.2f", result.factor)
    }
}
