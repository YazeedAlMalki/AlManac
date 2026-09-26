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
                // The "/10" readout above is a sibling, not a label, so
                // VoiceOver reached the control as an unnamed "adjustable"
                // element with no way to say where it was. Both are stated
                // on the slider itself instead.
                .accessibilityLabel("Overall soreness")
                .accessibilityValue("\(overallScore) of 10")
            }
            TextField("Notes (optional)", text: $notes, axis: .vertical)
        }
        Section("Where?") {
            // The count is the only feedback a sighted reader gets that the
            // grid is multi-select. Without it a selection is invisible
            // outside the chip's own fill, which is the same information
            // VoiceOver gets from the selected trait.
            Text(selectedAreas.isEmpty
                 ? "Tap any areas that feel sore."
                 : "\(selectedAreas.count) of \(sorenessBodyAreas.count) selected")
                .foregroundStyle(.secondary)
                .font(AlmanacTypography.font(.caption))
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
                // A real `Button`, not `Text` + `.onTapGesture`. The tap-gesture
                // version was announced as a static text, carried no selected
                // state, and could only be hit on the glyph bounds — the
                // capsule around it was not part of the target. A button is
                // the whole capsule and the selection is a trait, which is
                // also what lets the grid be skipped as a single group.
                Button {
                    if isOn { selected.remove(area) } else { selected.insert(area) }
                } label: {
                    Text(area)
                        .font(AlmanacTypography.font(.body))
                        .foregroundStyle(isOn ? AlmanacPalette.onAccent : AlmanacPalette.textPrimary)
                        .padding(.horizontal, 12)
                        // The design system's own control floor, not a new
                        // number: `.subheadline` plus 6pt of padding came to
                        // ~31pt, under the 44pt minimum.
                        .frame(minHeight: AlmanacMetrics.minimumControl)
                        .background(isOn ? AlmanacPalette.accent : AlmanacPalette.surfaceMuted,
                                    in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(area)
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Body areas")
    }
}
