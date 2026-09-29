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
            AlmanacEyebrow(text: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            Text("Today")
                .font(AlmanacTypography.font(.screenTitle))
                .foregroundStyle(AlmanacPalette.textPrimary)
            Text(greeting)
                .font(AlmanacTypography.font(.body))
                .foregroundStyle(AlmanacPalette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// The one object Today is about, so it is the one panel with a filled
    /// surface; everything below it is a ruled area of the page.
    private var readinessCard: some View {
        let outcome = model.outcome
        let isFinal = outcome?.state == .final

        return AlmanacCard(prominent: true) {
            VStack(alignment: .leading, spacing: 18) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        AlmanacEyebrow(text: "Readiness")
                        readinessValue(outcome)
                        if let confidence = outcome?.confidence {
                            AlmanacStatusMark(
                                text: AlmanacReadinessPresentation.confidenceLabel(confidence),
                                tone: AlmanacReadinessPresentation.confidenceTone(confidence)
                            )
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 18) {
                        VStack(alignment: .leading, spacing: 4) {
                            AlmanacEyebrow(text: readinessStateLabel(outcome))
                            readinessValue(outcome)
                        }

                        Spacer(minLength: 12)

                        if let confidence = outcome?.confidence {
                            AlmanacStatusMark(
                                text: AlmanacReadinessPresentation.confidenceLabel(confidence),
                                tone: AlmanacReadinessPresentation.confidenceTone(confidence)
                            )
                            .multilineTextAlignment(.trailing)
                        }
                    }
                }

                AlmanacRule()

                VStack(alignment: .leading, spacing: 8) {
                    Text(readinessHeadline(outcome))
                        .font(AlmanacTypography.font(.sectionTitle))
                        .foregroundStyle(AlmanacPalette.textPrimary)
                    Text(readinessDetail(outcome))
                        .font(AlmanacTypography.font(.body))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // A failed read belongs here rather than below the card,
                    // because the detail line above gives *advice* — "connect
                    // Apple Health or log your check-in" — that is worse than
                    // useless when the actual problem is that the read failed.
                    if let problem = model.readProblem {
                        AlmanacProblemNote(text: problem)
                    }
                    if let problem = model.saveProblem {
                        AlmanacProblemNote(text: problem)
                    }
                    // §9.8's "limited comparable shift data" / "Ramadan
                    // context — calibrating". Below the problem notes because
                    // it is a caveat about the number above, not a fault, and a
                    // user should read the caveat *after* the reading.
                    if let notice = model.baselineNotice {
                        Text(notice.text)
                            .font(AlmanacTypography.font(.caption))
                            .foregroundStyle(AlmanacPalette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("readiness-baseline-notice")
                    }
                }

                if let outcome {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            AlmanacStatusMark(text: isFinal ? "Final" : "Provisional", tone: isFinal ? .good : .neutral)
                            if let day = model.calibrationDay {
                                AlmanacStatusMark(text: "Preliminary · day \(day) of 21", tone: .neutral)
                            }
                            if !outcome.missingInputs.isEmpty {
                                Text("\(outcome.missingInputs.count) input\(outcome.missingInputs.count == 1 ? "" : "s") missing")
                                    .font(AlmanacTypography.font(.caption))
                                    .foregroundStyle(AlmanacPalette.textSecondary)
                            }
                        }
                    } else {
                        HStack(spacing: 10) {
                            AlmanacStatusMark(text: isFinal ? "Final" : "Provisional", tone: isFinal ? .good : .neutral)
                            if let day = model.calibrationDay {
                                AlmanacStatusMark(text: "Day \(day) of 21", tone: .neutral)
                            }
                            if !outcome.missingInputs.isEmpty {
                                Text("\(outcome.missingInputs.count) input\(outcome.missingInputs.count == 1 ? "" : "s") missing")
                                    .font(AlmanacTypography.font(.caption))
                                    .foregroundStyle(AlmanacPalette.textSecondary)
                            }
                        }
                    }
                }
            }
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
                    AlmanacRule(inset: AlmanacRule.metricTextInset)
                    AlmanacMetricRow(
                        icon: AlmanacIcon.hydration,
                        title: "Hydration",
                        value: "\(AlmanacNumber.compact(hydrationModel.todayTotal.value)) mL",
                        detail: "of \(AlmanacNumber.compact(hydrationGoal)) mL",
                        tone: hydrationTone
                    )
                    AlmanacRule(inset: AlmanacRule.metricTextInset)
                    AlmanacMetricRow(
                        icon: AlmanacIcon.nutrition,
                        title: "Nutrition",
                        value: nutritionValue,
                        detail: nutritionDetail,
                        // Keyed on the day's energy, not on `todaysTotals`: a
                        // drinks-only day has no food totals, and keying on
                        // those put a "minus.circle" nothing-here badge beside
                        // a real calorie figure.
                        tone: todaysEnergy == nil ? .neutral : nil
                    )
                    AlmanacRule(inset: AlmanacRule.metricTextInset)
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
        AlmanacCard(padding: 20) {
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
        }
    }

    private var inputRows: some View {
        VStack(spacing: 0) {
            inputRow("Sleep", value: model.sleepDurationMinutes.map(durationLabel), missingValue: "Not available")
            AlmanacRule()
            inputRow("Resting heart rate", value: model.latestRHR.map { "\(AlmanacNumber.compact($0)) bpm" }, missingValue: "Not available")
            AlmanacRule()
            inputRow("HRV", value: model.latestHRV.map { "\(AlmanacNumber.compact($0)) ms" }, missingValue: "Not available")
            AlmanacRule()
            inputRow("Mood", value: model.todayMood.map { "\($0.score)/10" }, missingValue: "Not logged")
            AlmanacRule()
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
                            inputRow("Tonnage", value: "\(AlmanacNumber.compact(tonnage)) kg", missingValue: nil)
                        }
                        if let distance = summary.totalDistanceMeters {
                            AlmanacRule()
                            inputRow("Distance", value: "\(AlmanacNumber.compact(distance)) m", missingValue: nil)
                        }
                        if let duration = summary.totalDurationSeconds {
                            AlmanacRule()
                            inputRow("Time", value: durationLabel(Int(duration.rounded())), missingValue: nil)
                        }
                        if let reps = summary.totalReps {
                            AlmanacRule()
                            inputRow("Reps", value: "\(reps)", missingValue: nil)
                        }
                        if let rounds = summary.totalRounds {
                            AlmanacRule()
                            inputRow("Rounds", value: "\(rounds)", missingValue: nil)
                        }
                        if let rpe = summary.averageRPE {
                            AlmanacRule()
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

    /// Food and drinks as one figure, or nil when neither was logged.
    ///
    /// Guarded on the combined total rather than on `mealsCounted > 0`, because
    /// a day of nothing but a logged drink is a real reading: keeping the food
    /// guard here would render an em dash and discard it.
    private var todaysEnergy: DayEnergy? {
        DayEnergy.total(food: nutritionModel.todaysTotals,
                        drinks: hydrationModel.todaysDrinkEnergy)
    }

    private var nutritionValue: String {
        guard let energy = todaysEnergy else { return "—" }
        return "\(AlmanacNumber.compact(energy.kcal)) kcal"
    }

    private var nutritionDetail: String {
        todaysEnergy?.summary ?? "No nutrition logged yet"
    }

    private var trainingValue: String {
        guard let summary = trainingModel.todaysSummary else { return "—" }
        if let duration = summary.totalDurationSeconds { return durationLabel(Int(duration.rounded())) }
        if let rounds = summary.totalRounds { return "\(rounds) rounds" }
        if let tonnage = summary.totalTonnageKg { return "\(AlmanacNumber.compact(tonnage)) kg" }
        if let distance = summary.totalDistanceMeters { return "\(AlmanacNumber.compact(distance)) m" }
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
        // The display face is reserved for a real reading. With no score there
        // is nothing to give it to, and the state is already stated by the
        // eyebrow above and the headline below, so the value slot stays empty
        // rather than repeating it in grey.
        if let score = outcome?.score {
            Text("\(score)")
                .font(AlmanacTypography.font(.display).monospacedDigit())
                .foregroundStyle(AlmanacPalette.textPrimary)
                .contentTransition(.numericText(value: Double(score)))
                .accessibilityIdentifier("readiness-score")
        }
    }

    /// The state of the reading, in words. Joining two words with a middle dot
    /// is a meta-string tic; the state is simply stated, and the card already
    /// says "Readiness" directly above it.
    private func readinessStateLabel(_ outcome: ReadinessOutcome?) -> String {
        guard let outcome, outcome.score != nil else { return "Waiting on signals" }
        return outcome.state == .final ? "Final" : "Provisional"
    }

    private func readinessHeadline(_ outcome: ReadinessOutcome?) -> String {
        guard let outcome else { return "Readiness is waiting" }
        if outcome.score == nil { return "More signals are needed" }
        return outcome.textDescription ?? "Today’s readiness assessment"
    }

    private func readinessDetail(_ outcome: ReadinessOutcome?) -> String {
        // A read failure produces no outcome, so without this the user is told
        // to connect Health or log a check-in — advice for a different problem,
        // given because a failed read and a missing baseline look identical from
        // here. The note below carries the real reason; this line stops giving
        // instructions that cannot help.
        if model.readProblem != nil {
            return "The signals below could not be read just now."
        }
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

    private func durationLabel(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
    }
}
