import SwiftUI
import AlmanacCore

/// What HealthKit has actually given Almanac, newest value first.
///
/// This screen exists because the other three bridges wrote rows that nothing
/// read: sleep, heart rate, HRV and steps already surface on the Today
/// dashboard, but energy and body composition had nowhere to appear at all. It
/// reports only what has been synced — it is a view of the sync, not a second
/// source of truth.
struct HealthView: View {
    @ObservedObject var model: HealthModel

    var body: some View {
        List {
            Section {
                Button {
                    Task { await model.syncNow() }
                } label: {
                    HStack {
                        Text("Sync now")
                        if model.isSyncing { Spacer(); ProgressView() }
                    }
                }
                .disabled(model.isSyncing)

                if let lastSynced = model.lastSynced {
                    Text("Last synced \(lastSynced.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let problem = model.problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Synced data") {
                if model.summaries.isEmpty {
                    // "Nothing yet" rather than zeros: a zero would claim the
                    // user did nothing, when the truth is that Health has not
                    // been read yet.
                    ContentUnavailableView {
                        Label("No health data yet", systemImage: "heart.text.square")
                    } description: {
                        Text("Connect to Health in Settings, then sync. Sleep, heart rate, steps and body composition will appear here.")
                    }
                } else {
                    ForEach(model.summaries) { summary in
                        row(summary)
                    }
                }
            }
        }
        .navigationTitle("Health")
    }

    private func row(_ summary: HealthSummary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title)
                // The count is what makes the window legible: a resting heart
                // rate and a step total both read as "a number" otherwise.
                Text(summary.count == 1 ? "1 reading, last 30 days" : "\(summary.count) readings, last 30 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let value = summary.latestValue {
                Text(verbatim: Self.format(value, unit: summary.unit))
                    .font(.body.monospacedDigit())
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Trimmed so a step count reads "8,421" rather than "8421.0", and an energy
    /// total reads as a whole number of calories.
    private static func format(_ value: Double, unit: String) -> String {
        let number: String
        switch unit {
        case "count": number = String(Int(value.rounded()))
        case "kcal", "min": number = String(Int(value.rounded()))
        case "%": number = String(format: "%.1f", value)
        default: number = String(Int(value.rounded()))
        }
        let grouped = number.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            .first!
            .replacingOccurrences(of: "(?<=[0-9])(?=[0-9]{3})", with: ",", options: .regularExpression)
        return grouped + (number.contains(".") ? number.suffix(from: number.firstIndex(of: ".")!) : "")
            + " " + unit
    }
}
