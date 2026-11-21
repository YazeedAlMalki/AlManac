import SwiftUI
import AlmanacCore

// ============================================================================
// PROTOTYPE 3 — "NATIVE CONSOLE"
// ============================================================================
//
// Thesis: the fastest-reading iOS health surface is the large-title screen with
// a hero value and a compact two-column grid of tiles — but done with Almanac's
// restraint rather than a template's. No gradients, no glass, no glow: the tiles
// are hairlines on the page, the hero is the one filled panel, and the grid is
// sized so a whole day fits above the fold on the smallest phone.
//
// This is the most "iOS-native" of the three, and the one closest to a
// recognisable modern health app — which is both its strength (immediate
// familiarity, fast scanning) and its risk (the category's visual clichés).

@MainActor
struct PrototypeNativeConsoleToday: View {
    let data: PrototypeTodayData
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AlmanacMetrics.sectionGap) {
                hero
                if let recommendation = data.recommendation {
                    recommendationRow(recommendation)
                }
                console
                inputsStrip
                recoveryRow
            }
            .frame(maxWidth: 700, alignment: .leading)
            .padding(.horizontal, AlmanacMetrics.screenInset)
            .padding(.top, 12)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .almanacScreen()
    }

    // The hero: the one filled surface, holding the score at large-title scale
    // and the sentence that reads it, laid out on one baseline where it fits and
    // stacked where it does not.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(AlmanacTypography.font(.screenTitle))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                Spacer(minLength: 12)
                Text(data.dateLine)
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }

            HStack(alignment: .center, spacing: 18) {
                if let score = data.score {
                    Text("\(score)")
                        .font(AlmanacTypography.font(.display).monospacedDigit())
                        .foregroundStyle(AlmanacPalette.textPrimary)
                        .contentTransition(.numericText(value: Double(score)))
                        .frame(minWidth: 96, alignment: .leading)
                } else {
                    Text("—")
                        .font(AlmanacTypography.font(.display))
                        .foregroundStyle(AlmanacPalette.divider)
                        .frame(minWidth: 96, alignment: .leading)
                }

                Rectangle()
                    .fill(AlmanacPalette.divider)
                    .frame(width: AlmanacMetrics.ruleWeight)
                    .frame(height: 72)

                VStack(alignment: .leading, spacing: 6) {
                    Text(data.headline)
                        .font(AlmanacTypography.font(.sectionTitle))
                        .foregroundStyle(AlmanacPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let confidence = data.confidence {
                        AlmanacStatusMark(
                            text: AlmanacReadinessPresentation.confidenceLabel(confidence),
                            tone: AlmanacReadinessPresentation.confidenceTone(confidence)
                        )
                    } else {
                        Text(data.stateLabel)
                            .font(AlmanacTypography.font(.label))
                            .foregroundStyle(AlmanacPalette.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AlmanacPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: AlmanacMetrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AlmanacMetrics.cardRadius, style: .continuous)
                .inset(by: AlmanacMetrics.ruleWeight / 2)
                .stroke(AlmanacPalette.divider, lineWidth: AlmanacMetrics.ruleWeight)
        }
    }

    private func recommendationRow(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AlmanacEyebrow(text: String(localized: "For this cycle"))
            Text(text)
                .font(AlmanacTypography.font(.body))
                .foregroundStyle(AlmanacPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The console proper: a two-column grid of tiles. Each tile is a ruled
    /// area, not a filled card — the grid reads as one instrument panel divided
    /// into cells rather than four separate boxes.
    private var console: some View {
        VStack(alignment: .leading, spacing: 12) {
            AlmanacSectionHeader(title: String(localized: "Signals"), detail: signalDetail)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) { tiles }.padding(.horizontal, 16)
                    .overlay(panelBorder)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0) {
                    tiles
                }
                .padding(.horizontal, 16)
                .overlay(panelBorder)
            }
        }
    }

    @ViewBuilder
    private var tiles: some View {
        tile(icon: AlmanacIcon.hydration, label: "Water",
             value: "\(AlmanacNumber.compact(data.hydrationMilliliters)) mL",
             note: "of \(AlmanacNumber.compact(data.hydrationGoal))",
             tone: data.hydrationTone,
             fraction: min(data.hydrationMilliliters / max(data.hydrationGoal, 1), 1))
        tile(icon: AlmanacIcon.sleep, label: "Sleep",
             value: data.sleepMinutes.map { PrototypeTodayFactory.durationLabel($0) } ?? "—",
             note: data.sleepMinutes == nil ? "none available" : "primary episode",
             tone: nil, fraction: nil)
        tile(icon: AlmanacIcon.nutrition, label: "Food & drink",
             value: data.nutritionValue ?? "—",
             note: data.nutritionDetail, tone: nil, fraction: nil)
        tile(icon: AlmanacIcon.training, label: "Training",
             value: data.trainingValue ?? "—",
             note: data.trainingDetail, tone: nil, fraction: nil)
    }

    private func tile(icon: String, label: String, value: String, note: String,
                      tone: AlmanacStatusTone?, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.almanacScaled(12, weight: .semibold, relativeTo: .caption2))
                    .foregroundStyle(tone?.color ?? AlmanacPalette.textSecondary)
                Text(label)
                    .font(AlmanacTypography.font(.label))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
            Text(value)
                .font(AlmanacTypography.font(.sectionTitle).monospacedDigit())
                .foregroundStyle(tone?.color ?? AlmanacPalette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(note)
                .font(AlmanacTypography.font(.caption))
                .foregroundStyle(AlmanacPalette.textSecondary)
                .lineLimit(1)
            if let fraction {
                AlmanacMeter(fraction: fraction, tone: tone ?? .neutral)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
        .padding(.horizontal, 4)
    }

    private var panelBorder: some View {
        RoundedRectangle(cornerRadius: AlmanacMetrics.cardRadius, style: .continuous)
            .inset(by: AlmanacMetrics.ruleWeight / 2)
            .stroke(AlmanacPalette.divider, lineWidth: AlmanacMetrics.ruleWeight)
    }

    /// The readiness inputs, as one horizontal strip of fields rather than a
    /// disclosure the user has to open — the four numbers the score is waiting
    /// on should be visible without a tap.
    private var inputsStrip: some View {
        VStack(alignment: .leading, spacing: 12) {
            AlmanacSectionHeader(title: String(localized: "Inputs"))
            HStack(spacing: 0) {
                input(id: "readiness-input-rhr", label: "Resting HR",
                      value: data.rhr.map { AlmanacNumber.compact($0) }, unit: "bpm")
                Rectangle().fill(AlmanacPalette.divider).frame(width: AlmanacMetrics.ruleWeight, height: 44)
                input(id: "readiness-input-hrv", label: "HRV",
                      value: data.hrv.map { AlmanacNumber.compact($0) }, unit: "ms")
                Rectangle().fill(AlmanacPalette.divider).frame(width: AlmanacMetrics.ruleWeight, height: 44)
                input(id: nil, label: "Mood", value: data.mood.map { "\($0)" }, unit: "/10")
                Rectangle().fill(AlmanacPalette.divider).frame(width: AlmanacMetrics.ruleWeight, height: 44)
                input(id: nil, label: "Soreness", value: data.soreness.map { "\($0)" }, unit: "/10")
            }
            .frame(minHeight: 64)
            .overlay(panelBorder)

            if data.missingInputCount > 0 {
                Text("\(data.missingInputCount) inputs missing")
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
            if let notice = data.baselineNotice {
                Text(notice)
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let circadian = data.circadianLine {
                Text(circadian)
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func input(id: String?, label: String, value: String?, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(AlmanacTypography.font(.caption))
                .foregroundStyle(AlmanacPalette.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value ?? "—")
                    .font(AlmanacTypography.font(.bodyMedium).monospacedDigit())
                    .foregroundStyle(value == nil ? AlmanacPalette.divider : AlmanacPalette.textPrimary)
                Text(unit)
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .accessibilityIdentifier(id ?? "")
    }

    private var recoveryRow: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Recovery day")
                    .font(AlmanacTypography.font(.bodyMedium))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                Text("Changes the advice, not the score.")
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: Binding(
                get: { data.isRecoveryDay },
                set: { data.setRecoveryDay($0) }
            ))
            .labelsHidden()
            .tint(AlmanacPalette.accent)
            .accessibilityIdentifier("recovery-day-toggle")
        }
        .frame(minHeight: AlmanacMetrics.minimumControl)
    }

    private var signalDetail: String {
        data.missingInputCount > 0 ? String(localized: "\(data.missingInputCount) missing") : String(localized: "All present")
    }
}

#Preview("Native console · dark") {
    PrototypeTodayPreview()
        .preferredColorScheme(.dark)
}
