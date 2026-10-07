import SwiftUI
import Translation

/// Translates the public excerpt only. Never replaces source evidence or scoring input.
struct SourceTranslationView: View {
    let source: SignalSource
    @EnvironmentObject var store: SentinelStore
    var body: some View {
        if #available(macOS 15.0, *) {
            OnDeviceSourceTranslation(source: source, target: store.settings.language.rawValue)
                .id(source.id + store.settings.language.rawValue)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                Text(source.snippet).font(.caption).textSelection(.enabled)
                if !source.isAccountEvidence { WebTranslationLink(source: source, target: store.settings.language.rawValue) }
            }
        }
    }
}

@available(macOS 15.0, *)
private struct OnDeviceSourceTranslation: View {
    let source: SignalSource
    let target: String
    @State private var configuration: TranslationSession.Configuration?
    @State private var translated = ""
    @State private var busy = false
    @State private var failed = false
    @State private var showingTranslation = true
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(source.snippet).font(.caption).textSelection(.enabled)
            HStack {
                Button(L10n.t("Translate source")) {
                    failed = false; busy = true; showingTranslation = true
                    if configuration == nil { configuration = .init(source: nil, target: Locale.Language(identifier: target == "zh-Hant" ? "zh-TW" : target == "zh-Hans" ? "zh" : target)) }
                    else { configuration?.invalidate() }
                }.disabled(busy)
                if busy { ProgressView().controlSize(.small) }
                if !translated.isEmpty { Button(L10n.t(showingTranslation ? "Hide translation" : "Show translation")) { showingTranslation.toggle() } }
            }.font(.caption)
            if !translated.isEmpty && showingTranslation {
                Text(L10n.t("Translation · original evidence retained")).font(.caption2).foregroundStyle(.secondary)
                Text(translated).font(.callout).textSelection(.enabled)
            }
            if failed {
                Text(L10n.t("On-device translation unavailable. Download the language when prompted, or use web translation for this public excerpt.")).font(.caption).foregroundStyle(.secondary)
                if !source.isAccountEvidence { WebTranslationLink(source: source, target: target) }
            }
        }.translationTask(configuration) { session in
            do {
                try await session.prepareTranslation()
                let result = try await session.translate(String((source.title + "\n" + source.snippet).prefix(8000)))
                translated = result.targetText
            } catch { failed = true }
            busy = false
        }
    }
}

private struct WebTranslationLink: View {
    let source: SignalSource
    let target: String
    private var url: URL? {
        var parts = URLComponents(string: "https://translate.google.com/")!
        parts.queryItems = [URLQueryItem(name: "sl", value: "auto"), URLQueryItem(name: "tl", value: target == "zh-Hant" ? "zh-TW" : target == "zh-Hans" ? "zh-CN" : target), URLQueryItem(name: "text", value: String((source.title + "\n" + source.snippet).prefix(8000))), URLQueryItem(name: "op", value: "translate")]
        return parts.url
    }
    var body: some View {
        if let url {
            VStack(alignment: .leading, spacing: 3) {
                Link(L10n.t("Translate this public excerpt in Google Translate ↗"), destination: url).font(.caption)
                Text(L10n.t("Only this public title and excerpt are sent after you click. No account usage or credentials.")).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
