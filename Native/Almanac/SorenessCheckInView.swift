import SwiftUI

/// Fixed picklist for body-area tagging. `SorenessLogStore.bodyAreas` is a
/// freeform `[String]` — nothing in AlmanacCore constrains the values — so
/// this list is a UI-layer decision, not a schema one.
let sorenessBodyAreas = [
    "Neck", "Shoulders", "Upper back", "Lower back", "Chest",
    "Biceps", "Triceps", "Forearms", "Abs",
    "Glutes", "Quads", "Hamstrings", "Calves", "Knees", "Ankles"
]

/// The soreness half of the combined check-in screen
/// (`MoodSorenessCheckInView`). Spec §17 scopes this to "1-10 sliders + body
/// area tagging" — an overall score plus which areas are sore, not a score
/// per area (`soreness_log` has no column for that; see §5.20/Migration014).
struct SorenessCheckInView: View {
    @Binding var overallScore: Int
    @Binding var selectedAreas: Set<String>
    @Binding var notes: String

    var body: some View {
        Section("Soreness") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Overall soreness")
                    Spacer()
                    Text("\(overallScore)/10").font(.headline).monospacedDigit()
                }
                Slider(value: Binding(get: { Double(overallScore) }, set: { overallScore = Int($0.rounded()) }),
                       in: 1...10, step: 1)
            }
            TextField("Notes (optional)", text: $notes, axis: .vertical)
        }
        Section("Where?") {
            if selectedAreas.isEmpty {
                Text("Tap any areas that feel sore.").foregroundStyle(.secondary).font(.caption)
            }
            AreaFlowGrid(areas: sorenessBodyAreas, selected: $selectedAreas)
        }
    }
}

/// A simple wrapping chip grid — no third-party layout dependency, just
/// fixed-column rows since the area list is short and static.
private struct AreaFlowGrid: View {
    let areas: [String]
    @Binding var selected: Set<String>
    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(areas, id: \.self) { area in
                let isOn = selected.contains(area)
                Text(area)
                    .font(.subheadline)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(isOn ? Color.accentColor : Color.secondary.opacity(0.15),
                                in: Capsule())
                    .foregroundStyle(isOn ? Color.white : Color.primary)
                    .onTapGesture {
                        if isOn { selected.remove(area) } else { selected.insert(area) }
                    }
            }
        }
    }
}
