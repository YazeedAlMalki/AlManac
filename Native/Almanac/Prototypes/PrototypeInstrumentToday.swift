import SwiftUI
import AlmanacCore

// ============================================================================
// PROTOTYPE 1 — "INSTRUMENT"
// ============================================================================
//
// Thesis: Almanac is a *measuring device*. A device has no greeting, no cards,
// no ceremony — it has a scale, a set of channels, and a log. The screen is a
// strict left-aligned column: a fixed label gutter, tabular figures, and one
// hairline between every pair of things. Colour appears only on a channel that
// carries a judgement, and the accent (ink-blue) appears only where Almanac
// itself recorded a value.
//
// What it deliberately gives up: warmth, and any sense that a person reads
// this over breakfast. That is the trade being tested.

@MainActor
struct PrototypeInstrumentToday: View {
    let data: PrototypeTodayData
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                rule
                channels
                rule
                if let recommendation = data.recommendation {
                    recommendationBlock(recommendation)
                    rule
                }
                inputs
                rule
                footer
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, AlmanacMetrics.screenInset)
            .padding(.top, 20)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .almanacScreen()
    }

    // The header is a header, not a masthead: the date is a timestamp, the
    // score is the instrument's own reading, and both sit on the same
    // baseline grid as everything below.
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(data.dateLine.uppercased())
                .font(.almanacScaled(11, weight: .medium, design: .monospaced, relativeTo: .caption))
                .tracking(1.4)
                .foregroundStyle(AlmanacPalette.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let score = data.score {
                    Text("\(score)")
                        .font(.almanacScaled(84, weight: .light, relativeTo: .largeTitle))
                        .monospacedDigit()
                        .foregroundStyle(AlmanacPalette.textPrimary)
                        .contentTransition(.numericText(value: Double(score)))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                } else {
                    Text("—")
                        .font(.almanacScaled(84, weight: .light, relativeTo: .largeTitle))
                        .foregroundStyle(AlmanacPalette.divider)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(data.stateLabel)
                        .font(.almanacScaled(13, weight: .semibold, relativeTo: .caption))
                        .foregroundStyle(AlmanacPalette.textPrimary)
                    Text("Readiness")
                        .font(.almanacScaled(12, weight: .regular, relativeTo: .caption))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                }
                .layoutPriority(1)

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 2) {
                    if let confidence = data.confidence {
                        Text(AlmanacReadinessPresentation.confidenceLabel(confidence))
                            .font(.almanacScaled(12, weight: .regular, relativeTo: .caption))
                            .foregroundStyle(AlmanacReadinessPresentation.confidenceTone(confidence).color)
                    }
                    if let day = data.calibrationDay {
                        Text("calibration \(day)/21")
                            .font(.almanacScaled(12, weight: .regular, design: .monospaced, relativeTo: .caption))
                            .foregroundStyle(AlmanacPalette.textSecondary)
                    } else if data.missingInputCount > 0 {
                        Text("\(data.missingInputCount) inputs missing")
                            .font(.almanacScaled(12, weight: .regular, design: .monospaced, relativeTo: .caption))
                            .foregroundStyle(AlmanacPalette.textSecondary)
                    }
                }
                .layoutPriority(1)
            }

            Text(data.headline)
                .font(.almanacScaled(17, weight: .medium, relativeTo: .body))
                .foregroundStyle(AlmanacPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let problem = data.readProblem {
                AlmanacProblemNote(text: problem)
            } else if let problem = data.saveProblem {
                AlmanacProblemNote(text: problem)
            } else {
                Text(data.detail)
                    .font(.almanacScaled(13, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let notice = data.baselineNotice {
                Text(notice)
                    .font(.almanacScaled(12, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 18)
    }

    // Every channel is a row of the same instrument: signal name in a gutter,
    // reading right-aligned in tabular figures, unit in a third column. No
    // icons — an icon per row is six little pictures doing one word's work.
    private var channels: some View {
        VStack(spacing: 0) {
            channel(name: "Sleep", value: sleepValue, unit: "", tone: nil)
            channel(name: "Resting HR", value: data.rhr.map { AlmanacNumber.compact($0) }, unit: "bpm", tone: nil)
            channel(name: "HRV", value: data.hrv.map { AlmanacNumber.compact($0) }, unit: "ms", tone: nil)
            channel(name: "Water", value: AlmanacNumber.compact(data.hydrationMilliliters), unit: "mL", tone: data.hydrationTone, detail: "of \(AlmanacNumber.compact(data.hydrationGoal))")
            channel(name: "Food & drink", value: foodValue, unit: "", tone: nil, detail: data.nutritionDetail)
            channel(name: "Training", value: data.trainingValue, unit: "", tone: nil, detail: data.trainingDetail)
            channel(name: "Mood", value: data.mood.map { "\($0)/10" }, unit: "", tone: nil)
            channel(name: "Soreness", value: data.soreness.map { "\($0)/10" }, unit: "", tone: nil)
        }
    }

    private func channel(name: String, value: String?, unit: String, tone: AlmanacStatusTone?, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(name)
                    .font(.almanacScaled(14, weight: .regular, relativeTo: .body))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                    .frame(width: 118, alignment: .leading)

                Text(value ?? "—")
                    .font(.almanacScaled(17, weight: .medium, design: .monospaced, relativeTo: .body))
                    .foregroundStyle(value == nil ? AlmanacPalette.divider : (tone?.color ?? AlmanacPalette.textPrimary))
                    .frame(maxWidth: .infinity, alignment: .trailing)

                Text(unit)
                    .font(.almanacScaled(12, weight: .regular, design: .monospaced, relativeTo: .caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                    .frame(width: 34, alignment: .leading)
            }
            .frame(minHeight: 40)

            if let detail {
                Text(detail)
                    .font(.almanacScaled(12, weight: .regular, relativeTo: .caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                    .padding(.leading, 130)
                    .padding(.bottom, 6)
            }

            rule
        }
    }

    /// The cycle's one instruction, set apart by whitespace and a heavier rule
    /// above it rather than by a tinted panel.
    private func recommendationBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("For this cycle")
                .font(.almanacScaled(11, weight: .medium, design: .monospaced, relativeTo: .caption))
                .tracking(1.2)
                .foregroundStyle(AlmanacPalette.textSecondary)
            Text(text)
                .font(.almanacScaled(17, weight: .regular, relativeTo: .body))
                .foregroundStyle(AlmanacPalette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 18)
    }

    private var inputs: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Recovery day")
                    .font(.almanacScaled(15, weight: .medium, relativeTo: .body))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                Text(data.isRecoveryDay ? "Declared for today" : "Not declared")
                    .font(.almanacScaled(12, weight: .regular, design: .monospaced, relativeTo: .caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: Binding(
                get: { data.isRecoveryDay },
                set: { data.setRecoveryDay($0) }
            ))
            .labelsHidden()
            .tint(AlmanacPalette.accent)
        }
        .frame(minHeight: AlmanacMetrics.minimumControl)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        Text(data.greeting)
            .font(.almanacScaled(12, weight: .regular, relativeTo: .caption))
            .foregroundStyle(AlmanacPalette.textSecondary)
            .padding(.top, 16)
    }

    private var sleepValue: String? {
        data.sleepMinutes.map { PrototypeTodayFactory.durationLabel($0) }
    }

    private var foodValue: String? { data.nutritionValue }

    private var rule: some View {
        AlmanacRule()
    }
}

#Preview("Instrument · dark") {
    PrototypeTodayPreview()
        .preferredColorScheme(.dark)
}
