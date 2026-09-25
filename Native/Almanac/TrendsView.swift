import SwiftUI
import Charts
import AlmanacCore

@MainActor
struct TrendsView: View {
    private enum Range: Int, CaseIterable, Identifiable {
        case thirty = 30
        case ninety = 90
        case year = 365

        var id: Int { rawValue }
        var title: String { "\(rawValue) days" }
    }

    private struct Point: Identifiable {
        let record: StoredReadinessRecord
        let date: Date
        let score: Int
        var id: String { record.anchorDate }
    }

    let db: Database?
    @State private var range: Range = .ninety
    @State private var records: [StoredReadinessRecord] = []
    @State private var selectedDate: Date?
    @State private var error: String?

    private var points: [Point] {
        records.compactMap { record in
            guard let score = record.score, let date = Self.date(from: record.anchorDate) else { return nil }
            return Point(record: record, date: date, score: score)
        }
    }

    private var selectedPoint: Point? {
        guard let selectedDate else { return points.last }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var snapshot: TrendSnapshot? {
        TrendEngine.snapshot(of: points.map { Double($0.score) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AlmanacMetrics.sectionGap) {
                    header

                    Picker("Range", selection: $range) {
                        ForEach(Range.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: range) { _, _ in load() }

                    if let error {
                        AlmanacCard {
                            VStack(alignment: .leading, spacing: 12) {
                                AlmanacStatusMark(text: "Could not load trends", tone: .critical)
                                Text(error)
                                    .font(AlmanacTypography.font(.body))
                                    .foregroundStyle(AlmanacPalette.textSecondary)
                                Button("Try again", action: load)
                                    .buttonStyle(AlmanacSecondaryButtonStyle())
                            }
                        }
                    } else if points.isEmpty {
                        emptyState
                    } else {
                        summary
                        chart
                        selectedRecord
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, AlmanacMetrics.screenInset)
                .padding(.top, 18)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .refreshable { load() }
            .task { load() }
            .toolbarBackground(AlmanacPalette.canvas, for: .navigationBar)
            .almanacScreen()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PATTERNS, NOT NOISE")
                .font(AlmanacTypography.font(.label))
                .tracking(1.2)
                .foregroundStyle(AlmanacPalette.textSecondary)
            Text("Trends")
                .font(AlmanacTypography.font(.screenTitle))
                .foregroundStyle(AlmanacPalette.textPrimary)
            Text("Readiness history stays descriptive. It does not infer causes.")
                .font(AlmanacTypography.font(.body))
                .foregroundStyle(AlmanacPalette.textSecondary)
        }
    }

    private var emptyState: some View {
        AlmanacCard {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: AlmanacIcon.trends)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(AlmanacPalette.accent)
                Text("Your trend starts with the first scored day")
                    .font(AlmanacTypography.font(.sectionTitle))
                    .foregroundStyle(AlmanacPalette.textPrimary)
                Text("Scores appear here after Almanac has enough sleep and vitals data. Missing days stay missing rather than becoming zero.")
                    .font(AlmanacTypography.font(.body))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
        }
    }

    private var summary: some View {
        let snapshot = snapshot
        return AlmanacCard(padding: 0) {
            HStack(spacing: 0) {
                summaryCell("Average", snapshot.map { AlmanacNumber.compact($0.average) } ?? "—")
                Divider().frame(height: 52)
                summaryCell("Low", snapshot.map { AlmanacNumber.compact($0.minimum) } ?? "—")
                Divider().frame(height: 52)
                summaryCell("Direction", snapshot.map { directionLabel($0.direction) } ?? "—")
            }
            .padding(.vertical, 18)
        }
    }

    private func summaryCell(_ title: String, _ value: String) -> some View {
        VStack(spacing: 5) {
            Text(title.uppercased())
                .font(AlmanacTypography.font(.caption))
                .tracking(0.8)
                .foregroundStyle(AlmanacPalette.textSecondary)
            Text(value)
                .font(AlmanacTypography.font(.data).monospacedDigit())
                .foregroundStyle(AlmanacPalette.textPrimary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var chart: some View {
        AlmanacCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                AlmanacSectionHeader(title: "Readiness", detail: "0–100")
                Chart {
                    RuleMark(y: .value("Reference band", ReadinessFormula.compromisedThreshold))
                        .foregroundStyle(AlmanacPalette.warning.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    RuleMark(y: .value("Reference band", ReadinessFormula.readyThreshold))
                        .foregroundStyle(AlmanacPalette.good.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    ForEach(points) { point in
                        LineMark(
                            x: .value("Day", point.date),
                            y: .value("Readiness", point.score)
                        )
                        .foregroundStyle(AlmanacPalette.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.linear)

                        PointMark(
                            x: .value("Day", point.date),
                            y: .value("Readiness", point.score)
                        )
                        .foregroundStyle(AlmanacPalette.accent)
                        .symbolSize(42)
                    }

                    if let selectedPoint {
                        RuleMark(x: .value("Selected day", selectedPoint.date))
                            .foregroundStyle(AlmanacPalette.textSecondary.opacity(0.55))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                                Text("\(selectedPoint.score)")
                                    .font(AlmanacTypography.font(.data).monospacedDigit())
                                    .foregroundStyle(AlmanacPalette.textPrimary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(AlmanacPalette.surfaceMuted)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXSelection(value: $selectedDate)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(AlmanacPalette.divider)
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .foregroundStyle(AlmanacPalette.textSecondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine().foregroundStyle(AlmanacPalette.divider)
                        AxisValueLabel {
                            if let score = value.as(Int.self) {
                                Text("\(score)")
                                    .font(AlmanacTypography.font(.caption).monospacedDigit())
                                    .foregroundStyle(AlmanacPalette.textSecondary)
                            }
                        }
                    }
                }
                .chartLegend(.hidden)
                .frame(height: 250)
                .accessibilityLabel("Readiness trend chart")
                .accessibilityHint("Drag across the chart to inspect individual days.")

                Text("Reference bands: below \(ReadinessFormula.compromisedThreshold) compromised · \(ReadinessFormula.compromisedThreshold)–\(ReadinessFormula.readyThreshold - 1) moderate · \(ReadinessFormula.readyThreshold)+ ready. Provisional and final observations share the scale; gaps remain visible.")
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var selectedRecord: some View {
        if let point = selectedPoint {
            AlmanacCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(point.date.formatted(date: .complete, time: .omitted))
                                .font(AlmanacTypography.font(.sectionTitle))
                                .foregroundStyle(AlmanacPalette.textPrimary)
                            Text(point.record.state == .final ? "Final check-in" : "Provisional estimate")
                                .font(AlmanacTypography.font(.label))
                                .foregroundStyle(AlmanacPalette.accent)
                        }
                        Spacer()
                        Text("\(point.score)")
                            .font(AlmanacTypography.font(.display))
                            .foregroundStyle(AlmanacPalette.textPrimary)
                            .monospacedDigit()
                    }
                    if let text = point.record.textDescription {
                        Text(text)
                            .font(AlmanacTypography.font(.body))
                            .foregroundStyle(AlmanacPalette.textSecondary)
                    }
                    if let recommendation = point.record.recommendation {
                        Text(recommendation)
                            .font(AlmanacTypography.font(.body))
                            .foregroundStyle(AlmanacPalette.textPrimary)
                    }
                    AlmanacStatusMark(
                        text: AlmanacReadinessPresentation.confidenceLabel(point.record.confidence),
                        tone: AlmanacReadinessPresentation.confidenceTone(point.record.confidence)
                    )
                }
            }
        }
    }

    private func load() {
        selectedDate = nil
        guard let db else {
            records = []
            error = "Trends are temporarily unavailable. Pull to try again."
            return
        }
        do {
            records = try ReadinessRecordStore(db: db).records(limit: range.rawValue)
            error = nil
        } catch {
            records = []
            #if DEBUG
            print("Almanac Trends load failed: \(error)")
            #endif
            self.error = "Trends are temporarily unavailable. Pull to try again."
        }
    }

    private static func date(from text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: text)
    }

    private func directionLabel(_ direction: TrendDirection) -> String {
        switch direction {
        case .up: return "Rising"
        case .down: return "Easing"
        case .flat: return "Steady"
        }
    }
}
