import Foundation
import CryptoKit

public struct ServiceConfiguration: Codable, Sendable {
    public var schema: Int
    public var analyticsEndpoint: String?
    public var updatePublicKey: String
    public static let bundled: ServiceConfiguration = {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "ServiceConfig", withExtension: "json"), let data = try? Data(contentsOf: url), let config = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self(schema: 1, analyticsEndpoint: nil, updatePublicKey: "")
        }
        return config
    }()
    public var telemetryURL: URL? {
        guard let analyticsEndpoint, let url = URL(string: analyticsEndpoint), SafeURL.external(url), url.path.isEmpty || url.path == "/" else { return nil }; return url
    }
}
public struct ReleaseAsset: Codable, Equatable, Sendable {
    public var platform: String
    public var url: String
    public var sha256: String
    public var size: Int
}
public struct UpdateManifest: Codable, Equatable, Sendable {
    public var schema: Int
    public var version: String
    public var channel: String
    public var releaseURL: String
    public var assets: [ReleaseAsset]
    public static func versionParts(_ value: String) -> [Int]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.count <= 3 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }) else { return nil }
        return parts.compactMap { Int($0) }
    }
    public func isNewer(than current: String) -> Bool {
        guard let left = Self.versionParts(version), let right = Self.versionParts(current) else { return false }
        return right.lexicographicallyPrecedes(left)
    }
    public static func verified(data: Data, signature: Data, publicKey: String, channel: String) throws -> Self {
        guard data.count < 100_000, let keyData = Data(base64Encoded: publicKey), let signatureData = Data(base64Encoded: String(decoding: signature, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData), key.isValidSignature(signatureData, for: data) else { throw SentinelError.unavailable("Update signature invalid") }
        let manifest = try JSONDecoder().decode(Self.self, from: data)
        guard manifest.schema == 1, manifest.channel == channel, ["stable", "preview"].contains(channel), versionParts(manifest.version) != nil,
              manifest.releaseURL == "https://github.com/Joe05520/usage-sentinel/releases/tag/v\(manifest.version)", manifest.assets.count == 3,
              Set(manifest.assets.map(\.platform)) == Set(["macOS", "Windows", "Linux"]) else { throw SentinelError.unavailable("Invalid update manifest") }
        for asset in manifest.assets {
            let suffix = asset.platform == "macOS" ? "macOS-universal.zip" : asset.platform == "Windows" ? "Windows-x64.zip" : "Linux-x64.tar.gz"
            guard asset.url == "https://github.com/Joe05520/usage-sentinel/releases/download/v\(manifest.version)/UsageSentinel-\(manifest.version)-\(suffix)",
                  asset.sha256.count == 64, asset.sha256.allSatisfy({ $0.isASCII && $0.isHexDigit }), asset.size > 1_000_000, asset.size <= 250_000_000 else { throw SentinelError.unavailable("Invalid update asset") }
        }
        return manifest
    }
}
public enum UpdateService {
    public static func check(preview: Bool) async throws -> UpdateManifest? {
        let channel = preview ? "preview" : "stable"
        let base = "https://joe05520.github.io/usage-sentinel/updates/\(channel).json"
        let (data, response) = try await SecureTransport.read(URLRequest(url: URL(string: base)!), limit: 100_000)
        if response.statusCode == 404 { return nil }
        guard response.statusCode == 200 else { throw SentinelError.unavailable("Update server unavailable") }
        let (signature, signatureResponse) = try await SecureTransport.read(URLRequest(url: URL(string: base + ".sig")!), limit: 1024)
        guard signatureResponse.statusCode == 200 else { throw SentinelError.unavailable("Update signature unavailable") }
        return try UpdateManifest.verified(data: data, signature: signature, publicKey: ServiceConfiguration.bundled.updatePublicKey, channel: channel)
    }
    public static func download(_ manifest: UpdateManifest, directory: URL) async throws -> URL {
        guard let asset = manifest.assets.first(where: { $0.platform == "macOS" }), let url = URL(string: asset.url) else { throw SentinelError.unavailable("No macOS update") }
        let (data, response) = try await SecureTransport.read(URLRequest(url: url), limit: asset.size, redirectHosts: ["release-assets.githubusercontent.com", "objects.githubusercontent.com", "github.com"], resourceTimeout: 180)
        guard response.statusCode == 200, data.count == asset.size,
              SHA256.hash(data: data).map({ String(format:"%02x",$0) }).joined() == asset.sha256.lowercased() else { throw SentinelError.unavailable("Update checksum or size mismatch") }
        let target = directory.appendingPathComponent(url.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: target.path) else { throw SentinelError.unavailable("Update file already exists; choose or remove the prior download first") }
        let temporary = directory.appendingPathComponent(".sentinel-update-" + UUID().uuidString + ".part")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        try FileManager.default.linkItem(at: temporary, to: target)
        return target
    }
}
