import SwiftUI
import Charts
import AlmanacCore

/// The two progress graphs of one exercise, and Decision 1's variant toggle.
///
/// **Two graphs, not one.** "Is this getting heavier" and "am I doing more work"
/// are different questions that a single axis answers badly: a user adding reps at
/// a lower weight is doing more and lifting less, and one line cannot say both.
/// `EquipmentVariantGraph` produces both from one query each, and this is the
/// surface for it.
///
/// **Separate/combined is a read, not a setting.** The toggle changes how the same
/// logged bouts are drawn — it never rewrites anything, and it applies to *both*
/// graphs because a graph that disagreed with the one above it would be asking the
/// same question twice with different answers. Combined mode carries
/// `EquipmentVariant.combinedModeFootnote` underneath, because a dumbbell fly and a
/// cable fly drawn as one line invite exactly the comparison the note warns
/// against.
///
/// **Each graph is individually hideable.** Some exercises only ever have one of
/// the two measures — a hold has no reps to count, a bodyweight movement has no
/// load — so a screen that always reserved space for both would show an empty axis
/// as if it were a failed read.
struct ExerciseProgressGraphsView: View {
    let db: Database?
    let exercise: ExerciseCatalogEntry

    @State private var mode: EquipmentVariantDisplay = .separate
    @State private var showsWeight = true
    @State private var showsVolume = true
    @State private var weight: [ProgressGraphSeries] = []
    @State private var volume: [ProgressGraphSeries] = []
    @State private var loaded = false
    @State private var readProblem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AlmanacMetrics.sectionGap) {
            controls

            if let readProblem {
                AlmanacProblemNote(text: readProblem, action: String(localized: "The graphs below may be incomplete."))
            }

            if !loaded {
                ProgressView("Reading history").frame(maxWidth: .infinity)
            } else {
                if showsWeight { graph(.weight, series: weight) }
                if showsVolume { graph(.volume, series: volume) }
            }

            if mode.showsComparabilityFootnote {
                Text(EquipmentVariant.combinedModeFootnote)
                    .font(AlmanacTypography.font(.caption))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            }
        }
        .task { load() }
        .onChange(of: mode) { _, _ in load() }
    }

    // MARK: - Controls

    /// The radio, and the two visibility switches. The switches are separate from
    /// the radio on purpose: the radio answers "how are variants drawn", the
    /// switches answer "which questions am I looking at", and folding them into one
    /// control would make hiding the volume graph look like a fifth variant mode.
    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Equipment variants", selection: $mode) {
                ForEach(EquipmentVariantDisplay.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("variant-mode")

            HStack(spacing: 20) {
                Toggle("Load", isOn: $showsWeight)
                    .accessibilityIdentifier("show-weight-graph")
                Toggle("Reps performed", isOn: $showsVolume)
                    .accessibilityIdentifier("show-volume-graph")
            }
            .font(AlmanacTypography.font(.label))
        }
    }

    // MARK: - A graph

    @ViewBuilder
    private func graph(_ which: ProgressGraph, series: [ProgressGraphSeries]) -> some View {
        let points = series.reduce(0) { $0 + $1.points.count }
        VStack(alignment: .leading, spacing: 12) {
            AlmanacSectionHeader(title: title(which), detail: points == 0 ? nil : "\(points) logged")
            if points == 0 {
                Text(which == .weight
                     ? "No logged load for this exercise. A bodyweight movement has none to plot."
                     : "No logged sets and reps for this exercise to count.")
                    .font(AlmanacTypography.font(.body))
                    .foregroundStyle(AlmanacPalette.textSecondary)
            } else {
                chart(which, series: series)
                if points < 2 {
                    Text("One session logged so far — a line needs at least two to show a trend.")
                        .font(AlmanacTypography.font(.caption))
                        .foregroundStyle(AlmanacPalette.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(which == .weight ? "weight-graph" : "volume-graph")
    }

    /// **One ink, distinguished by symbol.** The design system has one measured
    /// colour (`accent`) and three status colours, and status colours are the only
    /// colours allowed to carry judgement — so a variant line drawn in `.warning`
    /// would say "something is wrong with the dumbbell", which is not a claim this
    /// screen can make. Variants are told apart by their legend symbol and named in
    /// the legend, which is enough for the two or three lines this graph ever has.
    private func chart(_ which: ProgressGraph, series: [ProgressGraphSeries]) -> some View {
        Chart {
            ForEach(series) { line in
                ForEach(line.points) { point in
                    LineMark(
                        x: .value("Session", point.date),
                        y: .value(axisTitle(which), point.value)
                    )
                    .foregroundStyle(AlmanacPalette.accent)
                    .symbol(by: .value("Equipment", line.displayName))
                    PointMark(
                        x: .value("Session", point.date),
                        y: .value(axisTitle(which), point.value)
                    )
                    .foregroundStyle(AlmanacPalette.accent)
                    .symbol(by: .value("Equipment", line.displayName))
                }
            }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        // A one-entry legend names the only line there is and adds nothing. In
        // combined mode the legend is hidden outright, because there is one series
        // by construction and the footnote underneath is the caveat that matters.
        .chartLegend(mode == .separate && series.count > 1 ? .visible : .hidden)
        .frame(height: 180)
    }

    // MARK: - Data

    private func load() {
        guard let db else {
            loaded = true
            return
        }
        let store = EquipmentVariantGraph(db: db)
        do {
            weight = try store.points(for: exercise.id, mode: mode, graph: .weight)
            volume = try store.points(for: exercise.id, mode: mode, graph: .volume)
            readProblem = nil
        } catch {
            readProblem = "Could not read this exercise's history."
        }
        loaded = true
    }

    // MARK: - Text

    private func title(_ which: ProgressGraph) -> String {
        which == .weight ? String(localized: "Load") : String(localized: "Reps performed")
    }

    private func axisTitle(_ which: ProgressGraph) -> String {
        which == .weight ? String(localized: "Load (kg)") : String(localized: "Reps (sets × reps)")
    }
}