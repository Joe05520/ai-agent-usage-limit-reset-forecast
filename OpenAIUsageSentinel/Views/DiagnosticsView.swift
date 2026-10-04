import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject var store: SentinelStore
    @State private var deliverySummary = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.t("Diagnostics")).font(.title2.bold())
            Text(L10n.t("Notification permission: ") + L10n.t(store.permission)).font(.callout)
            ScrollView { Text(store.diagnosticsText).font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            Text(deliverySummary).font(.caption).foregroundStyle(.secondary)
            if let error = store.errorMessage { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Button(L10n.t("Refresh All")) { Task { await store.refreshAll() } }
                Button(L10n.t("Copy Diagnostics")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(store.diagnosticsText, forType: .string) }
                Button(L10n.t("Send Test Notification")) { Task { do { try await store.notifications.test(); deliverySummary = await store.notifications.deliverySummary() } catch { store.errorMessage = error.localizedDescription } } }
            }
        }.padding(24).frame(width: 700, height: 500).task(id: store.settings.language) { deliverySummary = await store.notifications.deliverySummary() }
    }
}
