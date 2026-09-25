import SwiftUI
import AlmanacCore

@MainActor
struct ReadinessDashboardView: View {
    @ObservedObject var model: ReadinessModel
    @ObservedObject var trainingModel: TrainingModel
    @ObservedObject var hydrationModel: HydrationModel
    @ObservedObject var nutritionModel: NutritionModel
    @ObservedObject var trackingModel: TrackingCalendarModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var checkingIn = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AlmanacMetrics.sectionGap) {
                    masthead
                    readinessCard
                    recommendation

                    Button {
                        checkingIn = true
                    } label: {
                        Label(
                            model.outcome?.state == .final ? "Edit mood & soreness" : "Complete today’s check-in",
                            systemImage: model.outcome?.state == .final ? AlmanacIcon.edit : AlmanacIcon.check
                        )
                    }
                    .buttonStyle(AlmanacPrimaryButtonStyle())

                    dailyRecord
                    inputs

                    VStack(alignment: .leading, spacing: 14) {
                        AlmanacSectionHeader(title: "Rhythm", detail: "Month to date")
                        EditorialRhythmCalendarView(model: trackingModel)
                    }

                    if trainingModel.todaysSummary != nil {
                        trainingDetailCard
                    }

                    FeedbackPromptView(model: model)
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, AlmanacMetrics.screenInset)
                .padding(.top, 22)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .refreshable { refresh() }
            .task { refresh() }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $checkingIn) {
                MoodSorenessCheckInView(model: model) {
                    trackingModel.refresh()
                }
            }
            .almanacScreen()
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                .font(AlmanacTypography.font(.label))
                .tracking(1.2)
                .foregroundStyle(AlmanacPalette.textSecondary)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            Text("Today")
                .font(AlmanacTypography.font(.screenTitle))
                .foregroundStyle(AlmanacPalette.textPrimary)
            Text(greeting)
                .font(AlmanacTypography.font(.body))
                .foregroundStyle(AlmanacPalette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var readinessCard: some View {
        let outcome = model.outcome
        let isFinal = outcome?.state == .final
        let tone = readinessTone(outcome?.color ?? .none)

        return AlmanacCard {
            VStack(alignment: .leading, spacing: 18) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("READINESS")
                            .font(AlmanacTypography.font(.label))
                            .tracking(1.1)
                            .foregroundStyle(AlmanacPalette.accent)
                            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        readinessValue(outcome)
                        if let confidence = outcome?.confidence {
                            AlmanacStatusMark(
                                text: confidenceLabel(confidence),
                                tone: confidenceTone(confidence)
                            )
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(readinessStateLabel(outcome))
                                .font(AlmanacTypography.font(.label))
                                .tracking(1.1)
                                .foregroundStyle(AlmanacPalette.accent)
                            readinessValue(outcome)
                        }

                        Spacer(minLength: 12)

                        if let confidence = outcome?.confidence {
                            AlmanacStatusMark(
                                text: confidenceLabel(confidence),
                                tone: confidenceTone(confidence)
                            )
                            .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Rectangle()
                    .fill(AlmanacPalette.divider)
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text(readinessHeadline(outcome))
                        .font(AlmanacTypography.font(.sectionTitle))
                        .foregroundStyle(AlmanacPalette.textPrimary)
                    Text(readinessDetail(outcome))
                        .font(AlmanacTypography.font(.body))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let outcome {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            AlmanacStatusMark(text: isFinal ? "Final" : "Provisional", tone: isFinal ? .good : .neutral)
                            if !outcome.missingInputs.isEmpty {
                                Text("\(outcome.missingInputs.count) input\(outcome.missingInputs.count == 1 ? "" : "s") missing")
                                    .font(AlmanacTypography.font(.caption))
                                    .foregroundStyle(AlmanacPalette.textSecondary)
                            }
                        }
                    } else {
                        HStack(spacing: 10) {
                            AlmanacStatusMark(text: isFinal ? "Final" : "Provisional", tone: isFinal ? .good : .neutral)
                            if !outcome.missingInputs.isEmpty {
                                Text("•")
                                    .foregroundStyle(AlmanacPalette.textSecondary)
                                Text("\(outcome.missingInputs.count) input\(outcome.missingInputs.count == 1 ? "" : "s") missing")
                                    .font(AlmanacTypography.font(.caption))
                                    .foregroundStyle(AlmanacPalette.textSecondary)
                            }
                        }
                    }
                }
            }
        }
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(tone.color)
                .frame(width: 3)
                .padding(.vertical, 18)
                .clipShape(Capsule())
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.45), value: model.outcome?.score)
    }

    @ViewBuilder
    private var recommendation: some View {
        if let recommendation = model.outcome?.recommendation, !recommendation.isEmpty {
            AlmanacCard {
                VStack(alignment: .leading, spacing: 10) {
                    AlmanacSectionHeader(title: "For this cycle")
                    Text(recommendation)
                        .font(AlmanacTypography.font(.body))
                        .foregroundStyle(AlmanacPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var dailyRecord: some View {
        VStack(alignment: .leading, spacing: 14) {
            AlmanacSectionHeader(title: "Today’s record")
            AlmanacCard(padding: 0) {
                VStack(spacing: 0) {
                    AlmanacMetricRow(
                        icon: AlmanacIcon.sleep,
                        title: "Sleep",
                        value: model.sleepDurationMinutes.map(durationLabel) ?? "—",
                        detail: model.sleepDurationMinutes == nil ? "No primary sleep episode available" : "Primary sleep",
                        tone: model.sleepDurationMinutes == nil ? .neutral : nil
                    )
                    Divider().overlay(AlmanacPalette.divider).padding(.leading, 62)
                    AlmanacMetricRow(
                        icon: AlmanacIcon.hydration,
                        title: "Hydration",
                        value: "\(number(hydrationModel.todayTotal.value)) mL",
                        detail: "of \(number(hydrationGoal)) mL",
                        tone: hydrationTone
                    )
                    Divider().overlay(AlmanacPalette.divider).padding(.leading, 62)
                    AlmanacMetricRow(
                        icon: AlmanacIcon.nutrition,
                        title: "Nutrition",
                        value: nutritionValue,
                        detail: nutritionDetail,
                        tone: nutritionModel.todaysTotals == nil ? .neutral : nil
                    )
                    Divider().overlay(AlmanacPalette.divider).padding(.leading, 62)
                    AlmanacMetricRow(
                        icon: AlmanacIcon.training,
                        title: "Training",
                        value: trainingValue,
                        detail: trainingDetailText,
                        tone: trainingModel.todaysSummary == nil ? .neutral : nil
                    )
                }
            }
        }
    }

    private var inputs: some View {
        DisclosureGroup {
            VStack(spacing: 0) {
                inputRows
            }
            .padding(.top, 14)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Inputs used")
                        .font(AlmanacTypography.font(.bodyMedium))
                        .foregroundStyle(AlmanacPalette.textPrimary)
                    Text("What shaped today’s estimate")
                        .font(AlmanacTypography.font(.caption))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                }
                Spacer()
            }
        }
        .font(AlmanacTypography.font(.body))
        .tint(AlmanacPalette.accent)
        .padding(20)
        .background(AlmanacPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: AlmanacMetrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AlmanacMetrics.cardRadius, style: .continuous)
                .stroke(AlmanacPalette.divider, lineWidth: 1)
        }
    }

    private var inputRows: some View {
        VStack(spacing: 0) {
            inputRow("Sleep", value: model.sleepDurationMinutes.map(durationLabel), missingValue: "Not available")
            Divider().overlay(AlmanacPalette.divider)
            inputRow("Resting heart rate", value: model.latestRHR.map { "\(number($0)) bpm" }, missingValue: "Not available")
            Divider().overlay(AlmanacPalette.divider)
            inputRow("HRV", value: model.latestHRV.map { "\(number($0)) ms" }, missingValue: "Not available")
            Divider().overlay(AlmanacPalette.divider)
            inputRow("Mood", value: model.todayMood.map { "\($0.score)/10" }, missingValue: "Not logged")
            Divider().overlay(AlmanacPalette.divider)
            inputRow("Soreness", value: model.todaySoreness.map { "\($0.overallScore)/10" }, missingValue: "Not logged")
        }
    }

    private var trainingDetailCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            AlmanacSectionHeader(title: "Training detail")
            AlmanacCard(padding: 0) {
                VStack(spacing: 0) {
                    if let summary = trainingModel.todaysSummary {
                        if let tonnage = summary.totalTonnageKg {
                            inputRow("Tonnage", value: "\(number(tonnage)) kg", missingValue: nil)
                            Divider().overlay(AlmanacPalette.divider)
                        }
                        if let distance = summary.totalDistanceMeters {
                            inputRow("Distance", value: "\(number(distance)) m", missingValue: nil)
                            Divider().overlay(AlmanacPalette.divider)
                        }
                        if let duration = summary.totalDurationSeconds {
                            inputRow("Time", value: durationLabel(Int(duration.rounded())), missingValue: nil)
                            Divider().overlay(AlmanacPalette.divider)
                        }
                        if let reps = summary.totalReps {
                            inputRow("Reps", value: "\(reps)", missingValue: nil)
                            Divider().overlay(AlmanacPalette.divider)
                        }
                        if let rounds = summary.totalRounds {
                            inputRow("Rounds", value: "\(rounds)", missingValue: nil)
                            Divider().overlay(AlmanacPalette.divider)
                        }
                        if let rpe = summary.averageRPE {
                            inputRow("Average RPE", value: String(format: "%.1f/10", rpe), missingValue: nil)
                        }
                    }
                }
            }
        }
    }

    private func inputRow(_ label: String, value: String?, missingValue: String?) -> some View {
        HStack {
            Text(label)
                .font(AlmanacTypography.font(.body))
                .foregroundStyle(AlmanacPalette.textPrimary)
            Spacer(minLength: 12)
            Text(value ?? missingValue ?? "—")
                .font(AlmanacTypography.font(.body).monospacedDigit())
                .foregroundStyle(value == nil ? AlmanacPalette.textSecondary : AlmanacPalette.textPrimary)
        }
        .padding(.vertical, 10)
    }

    private var hydrationGoal: Double {
        hydrationModel.hydrationSettings?.dailyGoalMilliliters ?? 2_000
    }

    private var hydrationTone: AlmanacStatusTone {
        guard hydrationModel.todayTotal.value >= hydrationGoal else { return .neutral }
        return .good
    }

    private var nutritionValue: String {
        guard let totals = nutritionModel.todaysTotals, totals.mealsCounted > 0 else { return "—" }
        return "\(number(totals.kcal)) kcal"
    }

    private var nutritionDetail: String {
        guard let totals = nutritionModel.todaysTotals, totals.mealsCounted > 0 else {
            return "No nutrition logged yet"
        }
        return totals.isComplete ? "\(totals.mealsCounted) foods counted" : "Partial total — some values are unavailable"
    }

    private var trainingValue: String {
        guard let summary = trainingModel.todaysSummary else { return "—" }
        if let duration = summary.totalDurationSeconds { return durationLabel(Int(duration.rounded())) }
        if let rounds = summary.totalRounds { return "\(rounds) rounds" }
        if let tonnage = summary.totalTonnageKg { return "\(number(tonnage)) kg" }
        if let distance = summary.totalDistanceMeters { return "\(number(distance)) m" }
        return "Logged"
    }

    private var trainingDetailText: String? {
        guard trainingModel.todaysSummary != nil else { return "No session logged yet" }
        return "Session recorded today"
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let salutation: String
        switch hour {
        case 5..<12: salutation = "Good morning"
        case 12..<17: salutation = "Good afternoon"
        default: salutation = "Good evening"
        }
        return "\(salutation), \(model.displayName)"
    }

    private func refresh() {
        model.refresh()
        trainingModel.refresh()
        hydrationModel.refresh()
        nutritionModel.refresh()
        trackingModel.refresh()
    }

    @ViewBuilder
    private func readinessValue(_ outcome: ReadinessOutcome?) -> some View {
        if let score = outcome?.score {
            Text("\(score)")
                .font(AlmanacTypography.font(.display).monospacedDigit())
                .foregroundStyle(AlmanacPalette.textPrimary)
                .contentTransition(.numericText(value: Double(score)))
                .accessibilityIdentifier("readiness-score")
        } else {
            Text("Waiting")
                .font(AlmanacTypography.font(.screenTitle))
                .foregroundStyle(AlmanacPalette.textPrimary)
                .accessibilityIdentifier("readiness-score")
        }
    }

    private func readinessStateLabel(_ outcome: ReadinessOutcome?) -> String {
        guard let outcome else { return "READINESS · WAITING" }
        if outcome.score == nil { return "READINESS · WAITING" }
        return outcome.state == .final ? "READINESS · FINAL" : "READINESS · PROVISIONAL"
    }

    private func readinessHeadline(_ outcome: ReadinessOutcome?) -> String {
        guard let outcome else { return "Readiness is waiting" }
        if outcome.score == nil { return "More signals are needed" }
        return outcome.textDescription ?? "Today’s readiness assessment"
    }

    private func readinessDetail(_ outcome: ReadinessOutcome?) -> String {
        guard let outcome else {
            return "Connect Apple Health or log today’s check-in. Almanac will not replace missing readings with zero."
        }
        if outcome.score == nil {
            let missing = missingInputNames(outcome.missingInputs)
            return missing.isEmpty
                ? "Almanac could not produce a defensible score from the available signals."
                : "Still needed: \(missing.joined(separator: ", "))."
        }
        return "This assessment combines the signals below. It describes today; it does not diagnose or prescribe."
    }

    private func missingInputNames(_ inputs: [ReadinessInputKind]) -> [String] {
        inputs.map {
            switch $0 {
            case .sleep: return "sleep"
            case .sleepQuality: return "sleep quality"
            case .rhr: return "resting heart rate"
            case .hrv: return "HRV"
            case .mood: return "mood"
            case .soreness: return "soreness"
            }
        }
    }

    private func readinessTone(_ grade: ReadinessColor) -> AlmanacStatusTone {
        switch grade {
        case .green: return .good
        case .yellow: return .warning
        case .red: return .critical
        case .none: return .neutral
        }
    }

    private func confidenceTone(_ confidence: ReadinessConfidence) -> AlmanacStatusTone {
        switch confidence {
        case .high, .medium: return .good
        case .low, .veryLow: return .warning
        case .insufficient: return .neutral
        }
    }

    private func confidenceLabel(_ confidence: ReadinessConfidence) -> String {
        switch confidence {
        case .high: return "High confidence"
        case .medium: return "Medium confidence"
        case .low: return "Low confidence"
        case .veryLow: return "Very low confidence"
        case .insufficient: return "Insufficient data"
        }
    }

    private func durationLabel(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
    }

    private func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }
}
