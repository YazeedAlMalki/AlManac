import SwiftUI
import Charts
import AlmanacCore

/// One exercise's logged history over time.
///
/// `ExerciseProgressStore` has been a core-layer query since 2026-09-18 with
/// nothing in the app reaching it; this is the view that consumes it.
///
/// Scope note, because it decides what this screen is allowed to claim: the
/// specs never define an exercise-progress chart. `ExerciseDetailScreen` is
/// "view exercise info", PRs are deferred "Owner decision" (`brd-v1_6.md`), and
/// the only chart in the screen map is the metric-scoped Trends tab. So this
/// exists because the owner asked for it (2026-09-26), and it deliberately
/// plots only what the store actually returns — `actual*` fields, never
/// prescribed ones (`docs/features/training.md` §2) — with no personal-record
/// claim and no per-type "bigger is better" framing. The spec warns that two
/// prescription types progress in *opposite* directions on the same clock
/// (`almanac-tech-spec-v1_0.md` §types), which is exactly the trap a naive
/// "is this going up?" chart falls into.
struct ExerciseProgressView: View {
    let model: TrainingModel
    let exercise: ExerciseCatalogEntry

    @State private var history: [ExerciseProgressPoint] = []
    @State private var loaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AlmanacMetrics.sectionGap) {
                header

                if !loaded {
                    ProgressView("Loading history").frame(maxWidth: .infinity)
                } else if history.isEmpty {
                    emptyState
                } else {
                    chart
                    figures
                    AlmanacSectionHeader(title: "Logged", detail: "\(history.count) sessions")
                    AlmanacCard {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(history.enumerated()), id: \.element.boutId) { index, point in
                                row(point)
                                if index < history.count - 1 {
                                    Rectangle().fill(AlmanacPalette.divider).frame(height: 1)
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, AlmanacMetrics.screenInset)
            .padding(.vertical, AlmanacMetrics.cardPadding)
        }
        .scrollIndicators(.hidden)
        .almanacModuleSurface()
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            history = model.progress(for: exercise.id)
            loaded = true
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            AlmanacEyebrow(text: "What you actually logged")
            Text(exercise.name)
                .font(AlmanacTypography.font(.screenTitle))
                .foregroundStyle(AlmanacPalette.textPrimary)
            Text("Every set recorded against this exercise, oldest first. Prescribed numbers are not shown — only what you did.")
                .font(AlmanacTypography.font(.body))
                .foregroundStyle(AlmanacPalette.textSecondary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No history yet")
                .font(AlmanacTypography.font(.sectionTitle))
                .foregroundStyle(AlmanacPalette.textPrimary)
            Text("Log this exercise and its load, reps and sets start charting here. Nothing is charted until you record something.")
                .font(AlmanacTypography.font(.body))
                .foregroundStyle(AlmanacPalette.textSecondary)
        }
        .padding(AlmanacMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AlmanacPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: AlmanacMetrics.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AlmanacMetrics.cardRadius, style: .continuous)
                .stroke(AlmanacPalette.divider, lineWidth: 1)
        }
    }

    /// Load per set over time. Load is the axis rather than volume because
    /// volume needs a set and rep count that a `reps_bodyweight` bout has no
    /// meaningful value for, and a chart that silently omits half an exercise's
    /// history is worse than one that plots the number that is always present.
    @ViewBuilder
    private var chart: some View {
        let points = loadSeries
        if points.count >= 2 {
            VStack(alignment: .leading, spacing: 12) {
                AlmanacSectionHeader(title: "Load per set")
                Chart(points, id: \.id) { point in
                    LineMark(x: .value("Session", point.date),
                             y: .value("Load (kg)", point.loadKg))
                        .foregroundStyle(AlmanacPalette.accent)
                    PointMark(x: .value("Session", point.date),
                              y: .value("Load (kg)", point.loadKg))
                        .foregroundStyle(AlmanacPalette.accent)
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 180)
            }
        } else {
            Text("One session logged so far — a line needs at least two to show a trend.")
                .font(AlmanacTypography.font(.caption))
                .foregroundStyle(AlmanacPalette.textSecondary)
        }
    }

    private struct LoadPoint: Identifiable {
        let id: Int64
        let date: String
        let loadKg: Double
    }

    private var loadSeries: [LoadPoint] {
        history.compactMap { point in
            guard let load = point.actualLoadKg else { return nil }
            return LoadPoint(id: point.boutId, date: point.date, loadKg: load)
        }
    }

    /// Heaviest load and the largest single-session tonnage, stated as maxima
    /// rather than as progress. "Heaviest set" and "most work" are facts about
    /// two specific sessions; they are not claims that either beat the other,
    /// which the spec's opposing-progression warning makes important. Nil —
    /// never zero — when the exercise has no load to multiply, so a bodyweight
    /// exercise does not claim "0 kg".
    @ViewBuilder
    private var figures: some View {
        let heaviest = loadSeries.map(\.loadKg).max()
        let bestTonnage = tonnageSeries.max(by: { $0.value < $1.value })
        if heaviest != nil || bestTonnage != nil {
            AlmanacCard {
                VStack(alignment: .leading, spacing: 0) {
                    if let heaviest {
                        figure("Heaviest load", "\(AlmanacNumber.compact(heaviest)) kg")
                    }
                    if let best = bestTonnage {
                        figure("Most work in a session", "\(AlmanacNumber.compact(best.value)) kg")
                        if let session = best.session {
                            Text("on \(session)").font(AlmanacTypography.font(.caption))
                                .foregroundStyle(AlmanacPalette.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private func figure(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(AlmanacTypography.font(.body))
            Spacer(minLength: 12)
            Text(value).font(AlmanacTypography.font(.data).monospacedDigit())
        }
        .padding(.vertical, 8)
    }

    private struct TonnagePoint {
        let value: Double
        let session: String?
    }

    private var tonnageSeries: [TonnagePoint] {
        history.compactMap { point in
            guard let load = point.actualLoadKg,
                  let sets = point.actualSets,
                  let reps = point.actualReps else { return nil }
            return TonnagePoint(value: Double(sets * reps) * load, session: point.date)
        }
    }

    private func row(_ point: ExerciseProgressPoint) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(point.date)
                .font(AlmanacTypography.font(.body))
                .foregroundStyle(AlmanacPalette.textPrimary)
            Spacer(minLength: 12)
            Text(detail(point))
                .font(AlmanacTypography.font(.data).monospacedDigit())
                .foregroundStyle(AlmanacPalette.textSecondary)
        }
        .padding(.vertical, 12)
    }

    private func detail(_ point: ExerciseProgressPoint) -> String {
        let sets = point.actualSets.map(String.init) ?? "—"
        let reps = point.actualReps.map(String.init) ?? "—"
        let load = point.actualLoadKg.map { "\(AlmanacNumber.compact($0)) kg" } ?? "—"
        return "\(sets) × \(reps) @ \(load)"
    }
}
