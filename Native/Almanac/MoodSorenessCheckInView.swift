import SwiftUI
import AlmanacCore

/// Spec §17's `MoodSorenessScreen` — mood and soreness are logged together
/// against the same cycle, so they're one sheet, not two separate check-in
/// screens each requiring its own visit.
@MainActor
struct MoodSorenessCheckInView: View {
    @ObservedObject var model: ReadinessModel
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var moodScore = 5
    @State private var moodNotes = ""
    @State private var sorenessScore = 5
    @State private var selectedAreas: Set<String> = []
    @State private var sorenessNotes = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                MoodCheckInView(score: $moodScore, notes: $moodNotes)
                SorenessCheckInView(overallScore: $sorenessScore, selectedAreas: $selectedAreas, notes: $sorenessNotes)
            }
            .navigationTitle("Mood & Soreness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear(perform: prefillFromToday)
            .editorError($error)
        }
    }

    private func prefillFromToday() {
        if let mood = model.todayMood {
            moodScore = mood.score
            moodNotes = mood.notes ?? ""
        }
        if let soreness = model.todaySoreness {
            sorenessScore = soreness.overallScore
            selectedAreas = Set(soreness.bodyAreas)
            sorenessNotes = soreness.notes ?? ""
        }
    }

    private func save() {
        do {
            try model.logMoodAndSoreness(
                moodScore: moodScore, moodNotes: optionalText(moodNotes),
                sorenessScore: sorenessScore, bodyAreas: Array(selectedAreas), sorenessNotes: optionalText(sorenessNotes))
            onSaved()
            dismiss()
        } catch { self.error = String(describing: error) }
    }
}
