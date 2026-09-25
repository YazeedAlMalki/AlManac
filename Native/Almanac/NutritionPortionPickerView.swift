import SwiftUI
import AlmanacCore

/// Chooses how much of a selected food to log, and previews the energy and
/// macros that amount would add before it is logged.
///
/// Tapping an imported or saved household portion fills the grams and quantity
/// fields rather than replacing them. Most foods have no listed measure, so the
/// fields stay directly editable instead of switching the view between modes.
@MainActor
struct NutritionPortionPickerView: View {
    let model: NutritionModel
    let foodRef: SourceIdentifier
    @Binding var gramsText: String
    @Binding var quantityText: String

    @State private var portions: [NutritionPortion] = []

    var body: some View {
        Group {
            ForEach(portions, id: \.id) { portion in
                Button {
                    select(portion)
                } label: {
                    Text(label(for: portion)).foregroundStyle(.primary)
                }
            }
            TextField("Amount, in grams", text: $gramsText)
                .keyboardType(.decimalPad)
            TextField("Quantity as you'd say it (e.g. \"2 cups\")", text: $quantityText)
            if let grams = Double(gramsText), grams > 0,
               let preview = model.macroPreview(for: foodRef, grams: grams) {
                previewRow(preview)
            }
        }
        .task(id: foodRef) { load() }
    }

    private func load() {
        portions = (try? model.portions(for: foodRef)) ?? []
    }

    private func select(_ portion: NutritionPortion) {
        gramsText = formatted(portion.gramWeight)
        quantityText = quantityLabel(for: portion)
    }

    private func label(for portion: NutritionPortion) -> String {
        "\(quantityLabel(for: portion)) (\(Int(portion.gramWeight.rounded())) g)"
    }

    private func quantityLabel(for portion: NutritionPortion) -> String {
        var text = "\(formatted(portion.amount)) \(portion.unitText)"
        if let modifier = portion.modifierText, !modifier.isEmpty { text += ", \(modifier)" }
        return text
    }

    private func formatted(_ amount: Double) -> String {
        amount.rounded() == amount ? String(Int(amount)) : String(amount)
    }

    private func previewRow(_ preview: MacroPreview) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let kcal = preview.kilocalories {
                Text("\(Int(kcal.rounded())) kcal")
            }
            HStack(spacing: 12) {
                if let protein = preview.proteinGrams {
                    Text("\(formattedGrams(protein))g protein")
                }
                if let carbs = preview.carbohydrateGrams {
                    Text("\(formattedGrams(carbs))g carbs")
                }
                if let fat = preview.fatGrams {
                    Text("\(formattedGrams(fat))g fat")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func formattedGrams(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
