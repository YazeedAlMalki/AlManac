import SwiftUI
import AlmanacCore
import Foundation

/// Trends, associations and the day's badges, over real data.
///
/// `TrendsView` already existed and showed one series — readiness — by asking
/// `ReadinessRecordStore` and `TrendEngine` directly. It was the *only*
/// consumer of any Insights code, and `CorrelationEngine`,
/// `CorrelationPairStore`, `TrendSnapshotStore`, `AchievementEngine` and
/// `AchievementRecordStore` had no consumer at all, so `correlation_pair`,
/// `trend_snapshot` and `achievement_record` were permanently empty tables.
///
/// **This screen is where the numbers come from, and it says how many.** Every
/// trend states how many days were actually recorded against the window it was
/// asked for, and every association states its paired-day count. A correlation
/// off four days of a fortnight is not a weaker version of one off fourteen —
/// it is not a finding, and the screen says "not enough paired days" rather
/// than printing a number.
///
/// **No prominent card.** Three kinds of summary with no single object among
/// them; a filled panel would rank them falsely. Ruled sections, one per kind.
@MainActor
struct InsightsView: View {
    let db: Database?

    @State private var window: Window = .thirtyDays
    @State private var trends: [TrendSummary] = []
    @State private var correlations: [CorrelationSummary] = []
    @State private var todaysBadges: Set<AchievementBadge> = []
    @State private var error: String?
    @State private var readProblem: String?
    @State private var loaded = false

    private enum Window: Int, CaseIterable, Identifiable {
        case fourteenDays, thirtyDays, ninetyDays
        var id: Int { rawValue }
        var dayCount: Int {
            switch self {
            case .fourteenDays: return 14
            case .thirtyDays: return 30
            case .ninetyDays: return 90
            }
        }
        var title: String { String(localized: "\(dayCount) days") }
    }

    private let timeModel = TimeModel(timeZone: .current)

    var body: some View {
        List {
            if let readProblem {
                Section { AlmanacProblemNote(text: readProblem) }
            }

            Section {
                Picker("Window", selection: $window) {
                    ForEach(Window.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .accessibilityIdentifier("insights-window")
            }

            if let problem = error {
                Section { AlmanacProblemNote(text: problem) }
            }

            if loaded && trends.isEmpty && correlations.isEmpty {
                Section {
                    Text("Nothing recorded in this window yet.")
                        .font(AlmanacTypography.font(.body))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                }
            }

            Section {
                if trends.isEmpty {
                    Text("No trend has enough recorded days to summarize.")
                        .font(AlmanacTypography.font(.body))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                } else {
                    ForEach(trends) { summary in
                        trendRow(summary)
                    }
                }
            } header: {
                AlmanacSectionHeader(title: String(localized: "Trends"))
            } footer: {
                Text("Direction compares the older half of the recorded days to the newer half, so one noisy day does not flip the arrow.")
            }

            Section {
                if correlations.isEmpty {
                    Text("No pairs to compare yet.")
                        .font(AlmanacTypography.font(.body))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                } else {
                    ForEach(correlations) { summary in
                        correlationRow(summary)
                    }
                }
            } header: {
                AlmanacSectionHeader(title: String(localized: "Associations"))
            } footer: {
                // The BRD's guardrail, stated on the screen rather than in a
                // comment. `r` is association; nothing here measures a cause.
                Text("A number below says two measurements move together across the days both were recorded. It does not say one causes the other.")
            }

            Section {
                badgeRow
            } header: {
                AlmanacSectionHeader(title: String(localized: "Today"))
            } footer: {
                Text("Badges are recomputed each time this screen opens. “Perfect log” is not awarded: what a perfect log means is not decided.")
            }
        }
        .listStyle(.insetGrouped)
        .almanacModuleSurface()
        .navigationTitle("Insights")
        .task { reload() }
        .onChange(of: window) { _, _ in reload() }
        .editorError($error)
    }

    // MARK: - Rows

    private func trendRow(_ summary: TrendSummary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.metric.displayName)
                    .font(AlmanacTypography.font(.body))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                Text(coverageText(summary))
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 3) {
                Text(valueText(summary))
                    .font(AlmanacTypography.font(.data).monospacedDigit())
                    .foregroundStyle(AlmanacPalette.textPrimary)
                HStack(spacing: 4) {
                    Image(systemName: directionSymbol(summary.snapshot.direction))
                        .font(.system(size: 11, weight: .semibold))
                    Text(directionText(summary.snapshot.direction))
                }
                .font(AlmanacTypography.font(.caption))
                .foregroundStyle(AlmanacPalette.textSecondary)
            }
        }
        .frame(minHeight: AlmanacMetrics.minimumControl)
        .accessibilityElement(children: .combine)
    }

    private func correlationRow(_ summary: CorrelationSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(summary.metricA.displayName) · \(summary.metricB.displayName)")
                    .font(AlmanacTypography.font(.body))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                Spacer(minLength: 12)
                if let r = summary.rValue {
                    Text(NumberDisplay.localized(String(format: "r %.2f", r)))
                        .font(AlmanacTypography.font(.data).monospacedDigit())
                        .foregroundStyle(AlmanacPalette.textPrimary)
                }
            }
            if summary.isConfident, let direction = summary.direction {
                HStack(spacing: 5) {
                    Image(systemName: direction.symbol)
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(direction.displayName), across \(summary.sampleSize) days")
                }
                .font(AlmanacTypography.font(.caption))
                .foregroundStyle(AlmanacPalette.textSecondary)
            } else {
                // The insufficient state, in words, with the number that would
                // clear it. Not a dash and not a zero.
                AlmanacStatusMark(
                    text: String(localized: "Not enough paired days — \(summary.sampleSize) of \(summary.minimumRequired)"),
                    tone: .neutral)
            }
            // The comparable-day filter, stated rather than applied silently. A
            // number computed from 20 of 24 days reads exactly like one computed
            // from 24 unless the screen says which happened.
            if summary.excludedTransitionDays > 0 {
                Text("\(summary.excludedTransitionDays) days in a schedule change left out")
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
        }
        .frame(minHeight: AlmanacMetrics.minimumControl, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var badgeRow: some View {
        let earned = AchievementBadge.allCases.filter { todaysBadges.contains($0) }
        if earned.isEmpty {
            return AnyView(Text("No badges today.")
                .font(AlmanacTypography.font(.body))
                .foregroundStyle(AlmanacPalette.textSecondary))
        }
        return AnyView(VStack(alignment: .leading, spacing: 6) {
            ForEach(earned, id: \.rawValue) { badge in
                Label(badgeTitle(badge), systemImage: "checkmark.circle.fill")
                    .font(AlmanacTypography.font(.body))
                    .foregroundStyle(AlmanacPalette.good)
            }
        })
    }

    // MARK: - Wording

    /// How much of the requested window was actually recorded.
    ///
    /// Stated on every row, because "sleep fell 40 minutes" and "sleep fell 40
    /// minutes across six recorded days of a fortnight" are different claims
    /// and only one of them is about the user.
    private func coverageText(_ summary: TrendSummary) -> String {
        let unit = summary.metric.unit ?? ""
        let range = unit.isEmpty
            ? "" : " \(unit)"
        let spread = "\(format(summary.snapshot.minimum))–\(format(summary.snapshot.maximum))\(range)"
        return String(localized: "across \(summary.dayCount) of \(summary.windowCount) days · \(spread)")
    }

    private func valueText(_ summary: TrendSummary) -> String {
        let average = format(summary.snapshot.average)
        guard let unit = summary.metric.unit else { return average }
        return String(localized: "\(average) \(unit)")
    }

    private func format(_ value: Double) -> String {
        AlmanacNumber.compact(value)
    }

    /// `forward`, not `right`: the arrow says which way the value moved over
    /// time, and in Arabic time reads right to left. The `forward` symbols
    /// mirror in a right-to-left layout; `arrow.up.right` never does.
    private func directionSymbol(_ direction: TrendDirection) -> String {
        switch direction {
        case .up: return "arrow.up.forward"
        case .down: return "arrow.down.forward"
        case .flat: return "minus"
        }
    }

    private func directionText(_ direction: TrendDirection) -> String {
        switch direction {
        case .up: return String(localized: "rising")
        case .down: return String(localized: "falling")
        case .flat: return String(localized: "steady")
        }
    }

    private func badgeTitle(_ badge: AchievementBadge) -> String {
        switch badge {
        case .stepsTargetMet: return String(localized: "Steps recorded")
        case .highLoadDay: return String(localized: "Heavy training day")
        case .fastedDay: return String(localized: "Dry fast")
        case .nutritionTargetsMet: return String(localized: "Nutrition targets met")
        case .perfectLog: return String(localized: "Perfect log")
        }
    }

    // MARK: - Load

    private func reload() {
        guard let db else { return }
        let query = InsightsQuery(db: db, timeModel: timeModel)
        let days = window.dayCount
        do {
            // Each metric independently, so one that has nothing to say does not
            // take the others down with it — a screen that reports "no trends"
            // because sleep threw would be lying about seven other metrics.
            var built: [TrendSummary] = []
            var firstFailure: Error?
            for metric in InsightMetric.allCases {
                do {
                    if let summary = try query.trend(for: metric, dayCount: days) {
                        built.append(summary)
                    }
                } catch {
                    firstFailure = firstFailure ?? error
                }
            }
            trends = built.sorted { $0.metric.displayName < $1.metric.displayName }
            correlations = try query.allDefaultCorrelations(dayCount: days)
            todaysBadges = try query.recomputeAchievements(for: timeModel.logicalDay(Date()).value)

            readProblem = firstFailure.map { _ in
                "Some figures could not be read and are missing from this window."
            }
            loaded = true
        } catch {
            self.error = String(describing: error)
            readProblem = String(localized: "Could not read your insights.")
            trends = []
            correlations = []
            loaded = true
        }
    }
}
