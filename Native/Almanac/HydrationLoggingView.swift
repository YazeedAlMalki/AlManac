import SwiftUI
import AlmanacCore

private let presets: [Double] = [250, 500, 750]

@MainActor
struct HydrationLoggingView: View {
    @ObservedObject var model: HydrationModel
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var note = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Amount") {
                    HStack {
                        ForEach(presets, id: \.self) { preset in
                            Button("\(Int(preset)) mL") { amountText = String(Int(preset)) }
                                .buttonStyle(.bordered)
                        }
                    }
                    TextField("Custom amount, in mL", text: $amountText)
                        .keyboardType(.numberPad)
                }
                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Log water")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Log", action: save) }
            }
            .editorError($error)
        }
    }

    private func save() {
        do {
            guard let amount = Double(amountText), amount > 0 else {
                throw EditorFailure(message: "Enter an amount greater than zero.")
            }
            try model.log(amount: Milliliters(amount), note: optionalText(note))
            dismiss()
        } catch { self.error = String(describing: error) }
    }
}
