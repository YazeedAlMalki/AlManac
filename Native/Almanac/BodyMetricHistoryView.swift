import SwiftUI
import Charts
import AlmanacCore

/// One body-composition metric over the last year (BRD §6.6): a line, and the
/// readings beneath it. A reading the person typed can be corrected or
/// deleted; an imported one says where it came from and stays as Health or the
/// device sent it (§5.6).
@MainActor
struct BodyMetricHistoryView: View {
    let db: Database?
    let metric: BodyMetric
    var onChanged: () -> Void = {}

    @State private var readings: [BodyCompositionMeasurement] = []
    @State private var correcting: BodyCompositionMeasurement?
    @State private var error: String?

    var body: some View {
        List {
            if readings.isEmpty {
                Text("No \(metric.title.lowercased()) readings in the last year.")
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("body-history-empty")
            } else {
                Section {
                    Chart(readings) { reading in
                        LineMark(x: .value("Date", reading.timestamp),
                                 y: .value(metric.title, reading.value))
                            .foregroundStyle(AlmanacPalette.accent)
                        PointMark(x: .value("Date", reading.timestamp),
                                  y: .value(metric.title, reading.value))
                            .foregroundStyle(AlmanacPalette.accent)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 200)
                    .accessibilityIdentifier("body-history-chart")
                }
                Section("Readings") {
                    ForEach(readings.reversed()) { reading in
                        row(reading)
                    }
                }
            }
        }
        .navigationTitle(metric.title)
        .almanacModuleSurface()
        .task { reload() }
        .sheet(item: $correcting) { reading in
            BodyReadingCorrectionEditor(db: db, reading: reading, metric: metric) {
                reload()
                onChanged()
            }
        }
        .editorError($error)
    }

    private func row(_ reading: BodyCompositionMeasurement) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(reading.timestamp.almanacFormatted(date: .abbreviated, time: .shortened))
                Text("\(readable(reading.source)) · \(readable(reading.conditions))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(AlmanacNumber.compact(reading.value)) \(metric.displayUnit)")
                .font(.body.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("body-reading-\(reading.id)")
        .swipeActions {
            if reading.source == "manual" {
                Button("Delete", role: .destructive) { delete(reading) }
                Button("Edit") { correcting = reading }
            }
        }
        .contextMenu {
            if reading.source == "manual" {
                Button("Edit") { correcting = reading }
                Button("Delete", role: .destructive) { delete(reading) }
            }
        }
    }

    private func reload() {
        guard let db else { return }
        let timeModel = TimeModel(timeZone: .current)
        let today = timeModel.logicalDay(Date())
        let range = LogicalDayRange(endingOn: today.value, days: 366)
        do {
            readings = try BodyCompositionMeasurementStore(db: db)
                .records(metric: metric.rawValue, from: range.from, to: range.to)
        } catch {
            self.error = String(describing: error)
        }
    }

    private func delete(_ reading: BodyCompositionMeasurement) {
        guard let db else { return }
        do {
            try BodyCompositionMeasurementStore(db: db).delete(id: reading.id)
            reload()
            onChanged()
        } catch {
            self.error = String(describing: error)
        }
    }
}

@MainActor
private struct BodyReadingCorrectionEditor: View {
    let db: Database?
    let reading: BodyCompositionMeasurement
    let metric: BodyMetric
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var conditions = "unknown"
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Text(metric.title)
                Text(reading.timestamp.almanacFormatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
                TextField("Value", text: $value)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("body-correction-value")
                Picker("Conditions", selection: $conditions) {
                    Text("Unknown").tag("unknown")
                    Text("Fasted").tag("fasted")
                    Text("Not fasted").tag("non_fasted")
                }
                Text("A reading already sent to Apple Health keeps its Health copy as it was.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Correct reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear {
                value = AlmanacNumber.compact(reading.value)
                conditions = reading.conditions
            }
            .editorError($error)
        }
    }

    private func save() {
        guard let db, let number = Double(userInput: value) else {
            error = String(localized: "Enter a positive measurement value.")
            return
        }
        do {
            try BodyCompositionMeasurementStore(db: db).correct(id: reading.id, value: number, conditions: conditions)
            onSaved()
            dismiss()
        } catch BodyCompositionMeasurementStoreError.invalidValue {
            error = String(localized: "Enter a positive measurement value.")
        } catch {
            self.error = String(describing: error)
        }
    }
}
