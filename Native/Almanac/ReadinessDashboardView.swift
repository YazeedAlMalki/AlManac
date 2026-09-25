import SwiftUI
import AlmanacCore

@MainActor
struct ReadinessDashboardView: View {
    @ObservedObject var model: ReadinessModel
    @ObservedObject var trainingModel: TrainingModel
    @ObservedObject var trackingModel: TrackingCalendarModel
    @State private var checkingIn = false

    var body: some View {
        NavigationStack {
            List {
                FeedbackPromptView(model: model)

                Section {
                    scoreHeader
                }

                Section("Tracking calendar") {
                    TrackingCalendarView(model: trackingModel)
                }

                if let outcome = model.outcome {
                    if let recommendation = outcome.recommendation {
                        Section("Recommendation") {
                            Text(recommendation)
                        }
                    }
                    Section("Inputs used") {
                        inputRows(outcome)
                    }
                }

                if let training = trainingModel.todaysSummary {
                    Section("Training") {
                        trainingRows(training)
                    }
                }

                Section {
                    Button {
                        checkingIn = true
                    } label: {
                        Label(model.outcome?.state == .final ? "Edit mood & soreness"
                                                              : "Log mood & soreness to finalize",
                              systemImage: "checkmark.circle")
                    }
                }
            }
            .navigationTitle("Hi, \(model.displayName)")
            .sheet(isPresented: $checkingIn) {
                MoodSorenessCheckInView(model: model) {
                    trackingModel.refresh()
                }
            }
            .task {
                model.refresh()
                trainingModel.refresh()
                trackingModel.refresh()
            }
            .refreshable {
                model.refresh()
                trainingModel.refresh()
                trackingModel.refresh()
            }
        }
    }

    @ViewBuilder
    private var scoreHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                if let score = model.outcome?.score {
                    Text("\(score)").font(.system(size: 48, weight: .bold, design: .rounded))
                } else {
                    Text("—").font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Circle().fill(color(for: model.outcome?.color ?? .none)).frame(width: 14, height: 14)
                Spacer()
                if let confidence = model.outcome?.confidence {
                    Text(confidenceLabel(confidence))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let text = model.outcome?.textDescription {
                Text(text).font(.subheadline)
            } else {
                Text("Not enough data yet to score readiness.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func inputRows(_ outcome: ReadinessOutcome) -> some View {
        if let minutes = model.sleepDurationMinutes {
            inputRow("Sleep", value: durationLabel(minutes), missing: false)
        } else {
            inputRow("Sleep", value: "Not available", missing: true)
        }
        if let rhr = model.latestRHR {
            inputRow("Resting heart rate", value: "\(Int(rhr.rounded())) bpm", missing: outcome.missingInputs.contains(.rhr))
        } else {
            inputRow("Resting heart rate", value: "Not available", missing: true)
        }
        if let hrv = model.latestHRV {
            inputRow("HRV", value: "\(Int(hrv.rounded())) ms", missing: outcome.missingInputs.contains(.hrv))
        } else {
            inputRow("HRV", value: "Not available", missing: true)
        }
        if let mood = model.todayMood?.score {
            inputRow("Mood", value: "\(mood)/10", missing: false)
        } else {
            inputRow("Mood", value: "Not logged yet", missing: true)
        }
        if let soreness = model.todaySoreness?.overallScore {
            inputRow("Soreness", value: "\(soreness)/10", missing: false)
        } else {
            inputRow("Soreness", value: "Not logged yet", missing: true)
        }
    }

    @ViewBuilder
    private func trainingRows(_ summary: WorkoutLoadSummary) -> some View {
        if let tonnage = summary.totalTonnageKg {
            inputRow("Tonnage", value: "\(Int(tonnage.rounded())) kg", missing: false)
        }
        if let distance = summary.totalDistanceMeters {
            inputRow("Distance", value: "\(Int(distance.rounded())) m", missing: false)
        }
        if let rounds = summary.totalRounds {
            inputRow("Rounds", value: "\(rounds)", missing: false)
        }
        if let rpe = summary.averageRPE {
            inputRow("Average RPE", value: String(format: "%.1f/10", rpe), missing: false)
        }
    }

    private func inputRow(_ label: String, value: String, missing: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(missing ? .secondary : .primary)
        }
    }

    private func durationLabel(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m"
    }

    private func color(for grade: ReadinessColor) -> Color {
        switch grade {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        case .none: return .gray
        }
    }

    private func confidenceLabel(_ confidence: ReadinessConfidence) -> String {
        switch confidence {
        case .high: return "High confidence"
        case .medium: return "Medium confidence"
        case .low: return "Low confidence"
        case .veryLow: return "Very low confidence"
        case .insufficient: return "Insufficient data"
        }
    }
}
