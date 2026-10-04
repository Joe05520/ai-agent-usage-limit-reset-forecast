// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "SentinelCore", platforms: [.macOS(.v14)], products: [.library(name: "SentinelCore", targets: ["SentinelCore"])], targets: [.target(name: "SentinelCore", path: "OpenAIUsageSentinel", exclude: ["App", "Views", "Services/Notifications", "Utilities/SentinelStore.swift", "Info.plist"], resources: [.process("Resources")], linkerSettings: [.linkedLibrary("sqlite3")]), .testTarget(name: "SentinelCoreTests", dependencies: ["SentinelCore"], path: "Tests")])
