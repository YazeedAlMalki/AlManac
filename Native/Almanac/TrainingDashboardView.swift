import SwiftUI
import AlmanacCore

@MainActor
struct TrainingDashboardView: View {
    @ObservedObject var model: TrainingModel
    @State private var logging = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let summary = model.todaysSummary {
                    Section("Today's Load") {
                        summaryRows(summary)
                    }
                }
                Section("Today") {
                    if model.todaysBouts.isEmpty {
                        Text("Nothing logged yet today.").foregroundStyle(.secondary)
                    }
                    ForEach(model.todaysBouts) { bout in
                        boutRow(bout)
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Training")
            .toolbar { Button("Log training", systemImage: "plus") { logging = true } }
            .sheet(isPresented: $logging) { LogBoutView(model: model) }
            .task { model.refresh() }
            .refreshable { model.refresh() }
            .editorError($error)
        }
    }

    @ViewBuilder
    private func summaryRows(_ summary: WorkoutLoadSummary) -> some View {
        if let tonnage = summary.totalTonnageKg {
            summaryRow("Tonnage", value: "\(Int(tonnage.rounded())) kg")
        }
        if let distance = summary.totalDistanceMeters {
            summaryRow("Distance", value: "\(Int(distance.rounded())) m")
        }
        if let duration = summary.totalDurationSeconds {
            summaryRow("Time under load", value: durationLabel(duration))
        }
        if let reps = summary.totalReps {
            summaryRow("Reps", value: "\(reps)")
        }
        if let rounds = summary.totalRounds {
            summaryRow("Rounds", value: "\(rounds)")
        }
        if let rpe = summary.averageRPE {
            summaryRow("Average RPE", value: String(format: "%.1f/10", rpe))
        }
    }

    private func summaryRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func boutRow(_ bout: WorkoutBoutEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.exerciseName(for: bout.exerciseCatalogId))
            Text(boutDetailLabel(bout)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func boutDetailLabel(_ bout: WorkoutBoutEntry) -> String {
        switch bout.prescriptionType {
        case "reps_load":
            let sets = bout.actualSets ?? bout.prescribedSets
            let reps = bout.actualReps ?? bout.prescribedReps
            let load = bout.actualLoadKg ?? bout.prescribedLoadKg
            return "\(sets.map(String.init) ?? "?") x \(reps.map(String.init) ?? "?") @ \(load.map { "\(Int($0)) kg" } ?? "?")"
        case "reps_bodyweight":
            let sets = bout.actualSets ?? bout.prescribedSets
            let reps = bout.actualReps ?? bout.prescribedReps
            return "\(sets.map(String.init) ?? "?") x \(reps.map(String.init) ?? "?")"
        case "distance":
            let distance = bout.actualDistanceMeters ?? bout.prescribedDistanceMeters
            return distance.map { "\(Int($0)) m" } ?? readable(bout.prescriptionType)
        case "duration", "time_under_load", "hold_stretch":
            let duration = bout.actualDurationSeconds ?? bout.prescribedDurationSeconds
            return duration.map(durationLabel) ?? readable(bout.prescriptionType)
        case "work_in_time", "rounds_for_time":
            let rounds = bout.actualRounds ?? bout.prescribedRounds
            return rounds.map { "\($0) rounds" } ?? readable(bout.prescriptionType)
        default:
            return readable(bout.prescriptionType)
        }
    }

    private func durationLabel(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let secs = total % 60
        return minutes > 0 ? "\(minutes)m \(secs)s" : "\(secs)s"
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            do { try model.deleteBout(id: model.todaysBouts[index].id) }
            catch { self.error = String(describing: error) }
        }
    }
}
