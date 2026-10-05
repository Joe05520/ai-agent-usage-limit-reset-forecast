import SwiftUI
import AppKit

@MainActor
final class WindowCoordinator {
    private var languageObserver: NSObjectProtocol?
    init() {
        languageObserver = NotificationCenter.default.addObserver(forName: .sentinelLanguageChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refreshTitles() }
        }
    }
    private func refreshTitles() {
        for (page, window) in windows { window.title = "AI Usage Sentinel · " + L10n.t(page == "history" ? "Event History" : page.capitalized) }
    }
    private var windows: [String: NSWindow] = [:]
    func show(_ page: String, store: SentinelStore) {
        if let window = windows[page] { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let content: AnyView
        switch page {
        case "settings": content = AnyView(SettingsView().environmentObject(store))
        case "diagnostics": content = AnyView(DiagnosticsView().environmentObject(store))
        default: content = AnyView(HistoryView().environmentObject(store))
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: page == "settings" ? 1100 : page == "history" ? 900 : 600, height: page == "settings" ? 740 : 540), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        if page == "settings" { window.minSize = NSSize(width: 900, height: 600) }
        window.title = "AI Usage Sentinel · " + L10n.t(page == "history" ? "Event History" : page.capitalized)
        window.contentView = NSHostingView(rootView: LocalizedWindowContent(content: content).environmentObject(store))
        window.isReleasedWhenClosed = false; window.center()
        windows[page] = window
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}

private struct LocalizedWindowContent: View {
    @EnvironmentObject var store: SentinelStore
    let content: AnyView
    var body: some View { content.environment(\.locale, store.settings.language.locale) }
}
