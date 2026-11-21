import SwiftUI
import AlmanacCore

// ============================================================================
// PROTOTYPE 2 — "DAY PAGE"
// ============================================================================
//
// Thesis: a physical almanac has a page per day. The page is *set*, not laid
// out with cards: a serif display title, a wide reading measure, and entries
// that read as printed lines with hanging labels. The score is a folio number
// in the margin, not a dashboard gauge.
//
// This leans hardest on the bundled Fraunces face and on typography alone for
// hierarchy — there is no surface fill anywhere on the screen. The risk it
// carries is density: an editorial page is calm to read and slow to scan.

@MainActor
struct PrototypeDayPageToday: View {
    let data: PrototypeTodayData

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                dateline
                title
                if data.readProblem != nil || data.saveProblem != nil {
                    problemLine
                }
                folioReading
                if let recommendationText = data.recommendation {
                    recommendation(recommendationText)
                }
                entriesHeading
                entries
                marginalia
                colophon
            }
            .frame(maxWidth: 600, alignment: .leading)
            .padding(.horizontal, 26)
            .padding(.top, 18)
            .padding(.bottom, 48)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .almanacScreen()
    }

    /// The top rule and dateline, as a title page carries its imprint.
    private var dateline: some View {
        VStack(alignment: .leading, spacing: 8) {
            AlmanacRule()
            Text(data.dateLine)
                .font(.almanacScaled(12, weight: .medium, design: .serif, relativeTo: .caption2))
                .italic()
                .foregroundStyle(AlmanacPalette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.bottom, 22)
    }

    /// The page's title, in the display face and at display scale. "Today" here
    /// is a chapter title, and the greeting is the epigraph under it.
    private var title: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Today")
                .font(AlmanacTypography.font(.screenTitle))
                .foregroundStyle(AlmanacPalette.textPrimary)
            Text(data.greeting)
                .font(.almanacScaled(15, weight: .regular, design: .serif, relativeTo: .caption))
                .italic()
                .foregroundStyle(AlmanacPalette.textSecondary)
        }
        .padding(.bottom, 26)
    }

    private var problemLine: some View {
        Group {
            if let problem = data.readProblem {
                AlmanacProblemNote(text: problem)
            } else if let problem = data.saveProblem {
                AlmanacProblemNote(text: problem)
            }
        }
        .padding(.bottom, 20)
    }

    /// The reading, set as a folio: a large serif numeral for the score, then
    /// the prose that interprets it, in a wide measure.
    private var folioReading: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 2) {
                if let score = data.score {
                    Text("\(score)")
                        .font(AlmanacTypography.font(.display).monospacedDigit())
                        .foregroundStyle(AlmanacPalette.textPrimary)
                        .contentTransition(.numericText(value: Double(score)))
                } else {
                    Text("—")
                        .font(AlmanacTypography.font(.display))
                        .foregroundStyle(AlmanacPalette.divider)
                }
                Text(data.stateLabel.lowercased())
                    .font(.almanacScaled(12, weight: .regular, design: .serif, relativeTo: .caption2))
                    .italic()
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }

            Rectangle()
                .fill(AlmanacPalette.divider)
                .frame(width: AlmanacMetrics.ruleWeight)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 10) {
                Text(data.headline)
                    .font(.almanacScaled(20, weight: .medium, design: .serif, relativeTo: .title2))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(data.detail)
                    .font(.almanacScaled(15, weight: .regular, design: .serif, relativeTo: .caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                confidenceLine
            }
        }
        .padding(.bottom, 30)
    }

    @ViewBuilder
    private var confidenceLine: some View {
        HStack(spacing: 14) {
            if let confidence = data.confidence {
                HStack(spacing: 5) {
                    Circle()
                        .fill(AlmanacReadinessPresentation.confidenceTone(confidence).color)
                        .frame(width: 6, height: 6)
                    Text(AlmanacReadinessPresentation.confidenceLabel(confidence))
                        .font(.almanacScaled(12, weight: .regular, design: .serif, relativeTo: .caption2))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                }
            }
            if let day = data.calibrationDay {
                Text("day \(day) of 21")
                    .font(.almanacScaled(12, weight: .regular, design: .serif, relativeTo: .caption2))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
            if data.missingInputCount > 0 {
                Text("\(data.missingInputCount) inputs missing")
                    .font(.almanacScaled(12, weight: .regular, design: .serif, relativeTo: .caption2))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
        }
    }

    private func recommendation(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AlmanacRule()
            Text("For this cycle")
                .font(.almanacScaled(12, weight: .medium, design: .serif, relativeTo: .caption2))
                .italic()
                .foregroundStyle(AlmanacPalette.textSecondary)
                .padding(.top, 14)
            Text(text)
                .font(.almanacScaled(17, weight: .regular, design: .serif, relativeTo: .body))
                .foregroundStyle(AlmanacPalette.textPrimary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 28)
    }

    private var entriesHeading: some View {
        Text("The day's record")
            .font(.almanacScaled(12, weight: .medium, design: .serif, relativeTo: .caption2))
            .italic()
            .foregroundStyle(AlmanacPalette.textSecondary)
            .padding(.bottom, 12)
    }

    /// Entries as printed lines: a hanging label, a leader of whitespace, the
    /// value in tabular figures, and a footnote for the qualification.
    private var entries: some View {
        VStack(spacing: 0) {
            entry(label: "Sleep", value: data.sleepMinutes.map { PrototypeTodayFactory.durationLabel($0) },
                  note: data.sleepMinutes == nil ? "no primary episode" : nil)
            entry(label: "Water", value: "\(AlmanacNumber.compact(data.hydrationMilliliters)) mL",
                  note: "of \(AlmanacNumber.compact(data.hydrationGoal))", tone: data.hydrationTone)
            entry(label: "Food & drink", value: data.nutritionValue, note: data.nutritionDetail)
            entry(label: "Training", value: data.trainingValue, note: data.trainingDetail)
            inputLine(label: "Resting HR", value: data.rhr.map { "\(AlmanacNumber.compact($0)) bpm" })
            inputLine(label: "HRV", value: data.hrv.map { "\(AlmanacNumber.compact($0)) ms" })
            inputLine(label: "Mood", value: data.mood.map { "\($0)/10" })
            inputLine(label: "Soreness", value: data.soreness.map { "\($0)/10" })
        }
    }

    private func entry(label: String, value: String?, note: String?, tone: AlmanacStatusTone? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(label)
                    .font(.almanacScaled(15, weight: .regular, design: .serif, relativeTo: .caption))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                Spacer(minLength: 12)
                Text(value ?? "—")
                    .font(.almanacScaled(16, weight: .medium, design: .serif, relativeTo: .body).monospacedDigit())
                    .foregroundStyle(value == nil ? AlmanacPalette.textSecondary : (tone?.color ?? AlmanacPalette.textPrimary))
            }
            if let note {
                Text(note)
                    .font(.almanacScaled(12, weight: .regular, design: .serif, relativeTo: .caption2))
                    .italic()
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
            AlmanacRule().padding(.top, 8)
        }
        .padding(.bottom, 8)
    }

    private func inputLine(label: String, value: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.almanacScaled(15, weight: .regular, design: .serif, relativeTo: .caption))
                .foregroundStyle(AlmanacPalette.textSecondary)
            Spacer(minLength: 12)
            Text(value ?? "not available")
                .font(.almanacScaled(15, design: .serif, relativeTo: .body).monospacedDigit())
                .italic(value == nil)
                .foregroundStyle(AlmanacPalette.textSecondary)
        }
        .frame(minHeight: 38)
    }

    private var marginalia: some View {
        VStack(alignment: .leading, spacing: 14) {
            AlmanacRule().padding(.top, 12)
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recovery day")
                        .font(.almanacScaled(15, weight: .regular, design: .serif, relativeTo: .caption))
                        .foregroundStyle(AlmanacPalette.textPrimary)
                    Text("changes the advice, not the score")
                        .font(.almanacScaled(12, weight: .regular, design: .serif, relativeTo: .caption2))
                        .italic()
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

            if let notice = data.baselineNotice {
                Text(notice)
                    .font(.almanacScaled(12, weight: .regular, design: .serif, relativeTo: .caption2))
                    .italic()
                    .foregroundStyle(AlmanacPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let circadian = data.circadianLine {
                Text(circadian)
                    .font(.almanacScaled(12, weight: .regular, design: .serif, relativeTo: .caption2))
                    .italic()
                    .foregroundStyle(AlmanacPalette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 16)
    }

    private var colophon: some View {
        Text("Almanac · a private record")
            .font(.almanacScaled(11, weight: .regular, design: .serif, relativeTo: .caption2))
            .italic()
            .foregroundStyle(AlmanacPalette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 34)
    }
}

#Preview("Day page · light") {
    PrototypeTodayPreview()
}
