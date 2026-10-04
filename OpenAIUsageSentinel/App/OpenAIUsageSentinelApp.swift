import SwiftUI

@main
struct OpenAIUsageSentinelApp: App {
    @NSApplicationDelegateAdaptor(SentinelAppDelegate.self) private var delegate
    @StateObject private var store: SentinelStore
    private let coordinator: WindowCoordinator
    init() {
        let model = SentinelStore()
        let windows = WindowCoordinator()
        coordinator = windows
        model.openWindow = { [weak model] page in if let model { windows.show(page, store: model) } }
        _store = StateObject(wrappedValue: model)
        delegate.onReopen = { [weak model] in model?.openWindow?("settings") }
        if ProcessInfo.processInfo.arguments.contains("--show-settings") {
            Task { @MainActor in windows.show("settings", store: model) }
        }
    }
    var body: some Scene {
        MenuBarExtra { MenuView().environmentObject(store).environment(\.locale, store.settings.language.locale) } label: {
            Text(store.menuTitle).monospacedDigit().help(store.menuTooltip).accessibilityLabel(store.menuTooltip)
        }.menuBarExtraStyle(.window)
    }
}

@MainActor
final class SentinelAppDelegate: NSObject, NSApplicationDelegate {
    var onReopen: (() -> Void)?
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        onReopen?(); return true
    }
}
