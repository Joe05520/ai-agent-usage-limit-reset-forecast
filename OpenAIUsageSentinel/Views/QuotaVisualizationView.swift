import SwiftUI

struct QuotaVisualizationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let bucket: UsageBucket
    let appearance: PanelAppearance
    var preview = false
    private var value: Double { min(100, max(0, bucket.remainingPercent)) }
    private var color: Color { value < 5 ? .red : value < 20 ? .orange : value <= 50 ? .yellow : .accentColor }
    private var status: String { L10n.t(value < 5 ? "Almost empty" : value < 20 ? "Running low" : value <= 50 ? "Keep an eye on usage" : "Plenty remaining") }
    var body: some View {
        Group {
            switch appearance.mode {
            case .professional:
                VStack(alignment: .leading, spacing: 5) {
                    BucketRow(bucket: bucket)
                    HStack {
                        Text(L10n.t("Used") + " \(Int(bucket.usedPercent))%")
                        Spacer()
                        Text(bucket.source).lineLimit(1).truncationMode(.middle)
                    }.font(.caption2).foregroundStyle(.secondary)
                }
            case .compact:
                HStack {
                    VStack(alignment: .leading) {
                        Text(L10n.t(bucket.name)).font(.subheadline.weight(.medium))
                        Text(DateParsing.countdown(bucket.resetAt)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Int(value))%").font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(color)
                }.accessibilityElement(children: .combine)
            case .intuitive:
                HStack(spacing: 16) {
                    ZStack {
                        if appearance.visualStyle == .ring {
                            Circle().stroke(color.opacity(0.15), lineWidth: 9)
                            Circle().trim(from: 0, to: value / 100).stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                        } else {
                            RoundedRectangle(cornerRadius: 9).stroke(color.opacity(0.35), lineWidth: 2)
                            GeometryReader { geometry in
                                RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.25)).frame(width: max(0, (geometry.size.width - 8) * value / 100), height: geometry.size.height - 8).padding(4)
                            }
                        }
                        Text("\(Int(value))%").font(.title3.monospacedDigit().weight(.bold))
                    }.frame(width: 70, height: appearance.visualStyle == .ring ? 70 : 44).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.t(bucket.name)).font(.subheadline.weight(.semibold))
                        Label(status, systemImage: value < 20 ? "exclamationmark.circle" : "checkmark.circle").font(.caption).foregroundStyle(.primary)
                        Text(DateParsing.countdown(bucket.resetAt)).font(.caption).foregroundStyle(.secondary)
                        if let reset = bucket.resetAt { Text(reset, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption2).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                }.padding(.vertical, 3).accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.t(bucket.name) + ", " + L10n.f("%@%% left", String(Int(value))) + ", " + status + ", " + DateParsing.countdown(bucket.resetAt))
            }
        }
        .animation(appearance.animations && !reduceMotion ? .easeInOut(duration: 0.45) : nil, value: value)
        .animation(appearance.animations && !reduceMotion ? .easeInOut(duration: 0.2) : nil, value: appearance.mode)
    }
}

struct PanelAppearanceControls: View {
    @Binding var appearance: PanelAppearance
    var body: some View {
        Picker(L10n.t("Panel mode"), selection: $appearance.mode) {
            ForEach(PanelMode.allCases) { mode in Text(mode.label).tag(mode) }
        }.pickerStyle(.segmented)
        if appearance.mode == .intuitive {
            Picker(L10n.t("Visualization"), selection: $appearance.visualStyle) {
                ForEach(QuotaVisualStyle.allCases) { style in Text(style.label).tag(style) }
            }
        }
    }
}
