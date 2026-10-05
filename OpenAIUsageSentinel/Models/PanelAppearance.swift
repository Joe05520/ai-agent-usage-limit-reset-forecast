import Foundation

public enum PanelMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case professional, intuitive, compact
    public var id: String { rawValue }
    public var label: String { L10n.t(rawValue == "professional" ? "Professional" : rawValue == "intuitive" ? "Intuitive" : "Compact") }
}
public enum QuotaVisualStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case ring, battery
    public var id: String { rawValue }
    public var label: String { L10n.t(rawValue == "ring" ? "Quota ring" : "Quota battery") }
}
public struct PanelAppearance: Codable, Equatable, Sendable {
    public var mode: PanelMode = .professional
    public var visualStyle: QuotaVisualStyle = .ring
    public var animations = true
    public init() {}
}
