import SwiftUI

/// The mood half of the combined check-in screen (`MoodSorenessCheckInView`).
/// A plain `Slider` + notes field over caller-owned state — no store access
/// of its own, so it can be reused standalone or embedded.
struct MoodCheckInView: View {
    @Binding var score: Int
    @Binding var notes: String

    var body: some View {
        Section("Mood") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("How are you feeling?")
                    Spacer()
                    Text("\(score)/10").font(.headline).monospacedDigit()
                }
                Slider(value: Binding(get: { Double(score) }, set: { score = Int($0.rounded()) }),
                       in: 1...10, step: 1)
                // The "/10" readout above is a sibling, not a label, so
                // VoiceOver reached this as an unnamed "adjustable" element.
                .accessibilityLabel("Mood")
                .accessibilityValue("\(score) of 10")
            }
            TextField("Notes (optional)", text: $notes, axis: .vertical)
        }
    }
}
