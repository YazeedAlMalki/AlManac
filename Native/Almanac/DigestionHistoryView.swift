import SwiftUI
import Charts
import AlmanacCore

/// The read side of BRD §6.3: what was recorded over 7, 30 or 90 days.
///
/// **It shows what was recorded and never interprets it.** Counts by Bristol
/// type, by colour name and by urine grade are tallies, in scale order, with no
/// row singled out — `docs/features/digestion.md` §3 holds the advisory back
/// for clinician review, and a history that highlighted "black" or grade 8
/// would be that advisory arriving without the review.
///
/// **Every grade and colour carries words** (BRD §6.20). Rows read "Type 4,
/// Smooth, soft sausage" and "Colour grade 8 of 8, Grade 8 — dark brown"; the
/// chart's bars are one neutral colour and say what they count in their
/// accessibility labels, so nothing on this screen depends on seeing a colour.
@MainActor
struct DigestionHistoryView: View {
    let db: Database?

    @State private var span: Span = .week
    @State private var history: DigestionHistory?
    @State private var readProblem: String?

    private let timeModel = TimeModel(timeZone: .current)

    enum Span: Int, CaseIterable, Identifiable {
        case week = 7, month = 30, quarter = 90
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .week: return String(localized: "7 days")
            case .month: return String(localized: "30 days")
            case .quarter: return String(localized: "90 days")
            }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Range", selection: $span) {
                    ForEach(Span.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("digestion.history.range")
            } footer: {
                Text("Almanac records what you saw and does not interpret it.")
            }

            if let readProblem {
                Section { AlmanacProblemNote(text: readProblem) }
            }

            if let history {
                summarySection(history)
                if history.isEmpty {
                    Section {
                        Text("Nothing recorded in this range.")
                            .foregroundStyle(AlmanacPalette.textSecondary)
                            .accessibilityIdentifier("digestion.history.empty")
                    }
                } else {
                    chartSection(history)
                    bristolSection(history)
                    colourSection(history)
                    gradeSection(history)
                    daySections(history)
                }
            }
        }
        .listStyle(.insetGrouped)
        .almanacModuleSurface()
        .navigationTitle("Digestion")
        .task(id: span) { reload() }
    }

    // MARK: - Sections

    private func summarySection(_ history: DigestionHistory) -> some View {
        Section {
            AlmanacCard(prominent: true) {
                VStack(alignment: .leading, spacing: 8) {
                    AlmanacEyebrow(text: span.title)
                    Text("\(history.bowelMovementCount) bowel movements · \(history.urinationCount) urinations")
                        .font(AlmanacTypography.font(.sectionTitle))
                        .foregroundStyle(AlmanacPalette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("digestion.history.totals")
                }
            }
        }
    }

    private func chartSection(_ history: DigestionHistory) -> some View {
        Section {
            Chart {
                ForEach(history.dailyCounts) { day in
                    BarMark(x: .value("Day", day.logicalDay),
                            y: .value("Count", day.bowelMovements))
                        .foregroundStyle(by: .value("Kind", String(localized: "Bowel movements")))
                        .position(by: .value("Kind", String(localized: "Bowel movements")))
                        .accessibilityLabel(day.logicalDay)
                        .accessibilityValue(String(localized: "\(day.bowelMovements) bowel movements"))
                    BarMark(x: .value("Day", day.logicalDay),
                            y: .value("Count", day.urinations))
                        .foregroundStyle(by: .value("Kind", String(localized: "Urinations")))
                        .position(by: .value("Kind", String(localized: "Urinations")))
                        .accessibilityLabel(day.logicalDay)
                        .accessibilityValue(String(localized: "\(day.urinations) urinations"))
                }
            }
            .chartXAxis(.hidden)
            .chartLegend(position: .bottom)
            .frame(height: 160)
            .accessibilityIdentifier("digestion.history.chart")
        } header: {
            AlmanacSectionHeader(title: String(localized: "Entries per day"))
        }
    }

    private func bristolSection(_ history: DigestionHistory) -> some View {
        Section {
            ForEach(history.bristolCounts, id: \.type) { row in
                countRow(label: row.type.accessibilityLabel, count: row.count)
                    .accessibilityIdentifier("digestion.history.bristol.\(row.type.rawValue)")
            }
        } header: {
            AlmanacSectionHeader(title: String(localized: "By Bristol type"))
        }
    }

    @ViewBuilder
    private func colourSection(_ history: DigestionHistory) -> some View {
        if !history.colourCounts.isEmpty {
            Section {
                ForEach(history.colourCounts, id: \.colour) { row in
                    countRow(label: row.colour.displayName, count: row.count)
                }
            } header: {
                AlmanacSectionHeader(title: String(localized: "By colour"))
            }
        }
    }

    private func gradeSection(_ history: DigestionHistory) -> some View {
        Section {
            ForEach(history.urinationGradeCounts, id: \.grade) { row in
                countRow(label: row.grade.accessibilityLabel, count: row.count)
                    .accessibilityIdentifier("digestion.history.grade.\(row.grade.rawValue)")
            }
        } header: {
            AlmanacSectionHeader(title: String(localized: "By urine colour grade"))
        }
    }

    @ViewBuilder
    private func daySections(_ history: DigestionHistory) -> some View {
        ForEach(history.days) { day in
            Section {
                ForEach(day.bowelMovements) { entry in
                    entryRow(time: entry.timestamp,
                             text: bowelText(entry))
                }
                ForEach(day.urinations) { entry in
                    entryRow(time: entry.timestamp,
                             text: String(localized: "Urination · \(entry.colorGrade.accessibilityLabel)"))
                }
            } header: {
                AlmanacSectionHeader(title: day.logicalDay)
            }
        }
    }

    // MARK: - Rows

    private func countRow(label: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text(NumberDisplay.localized(String(count)))
                .font(.body.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }

    private func entryRow(time: Date, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text).fixedSize(horizontal: false, vertical: true)
            Text(time.almanacFormatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(AlmanacPalette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// The facts as recorded, in words. Blood is stated as the user recorded
    /// it, with no judgement attached.
    private func bowelText(_ entry: BowelMovementEntry) -> String {
        var parts = [entry.bristolType.accessibilityLabel,
                     DigestionColourTally(stored: entry.color).displayName]
        if entry.bloodPresent {
            parts.append(String(localized: "blood recorded"))
        }
        return parts.joined(separator: " · ")
    }

    private func reload() {
        guard let db else { return }
        do {
            let today = timeModel.logicalDay(Date()).value
            history = try DigestionHistoryReader(db: db).history(endingOn: today, days: span.rawValue)
            readProblem = nil
        } catch {
            history = nil
            readProblem = String(localized: "Digestion history could not be read.")
        }
    }
}
