import SwiftUI

struct PlateCalculatorView: View {
    @AppStorage("defaultWeightUnit") private var unit: WeightUnit = .kilograms
    @State private var targetText = "60"
    @State private var barText = "20"
    @State private var selectedPlates: Set<Double> = [25, 20, 15, 10, 5, 2.5, 1.25, 0.5]

    private var plates: [Double] {
        unit == .kilograms ? [25, 20, 15, 10, 5, 2.5, 1.25, 0.5] : [45, 35, 25, 10, 5, 2.5, 1.25]
    }

    private var calculation: (plates: [Double], remainder: Double, target: Double, bar: Double)? {
        guard let target = NumberParsing.double(targetText), let bar = NumberParsing.double(barText), target.isFinite, bar.isFinite, target >= bar, target >= 0, target <= 10_000, bar >= 0, bar <= 10_000 else { return nil }
        var remaining = (target - bar) / 2
        var result: [Double] = []
        for plate in plates.filter({ selectedPlates.contains($0) }).sorted(by: >) {
            while remaining + 0.0001 >= plate {
                result.append(plate)
                remaining -= plate
            }
        }
        return (result, max(0, remaining), target, bar)
    }

    var body: some View {
        Form {
            Section("Target") {
                Picker("Units", selection: $unit) {
                    ForEach(WeightUnit.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Total weight (\(unit.label))") {
                    TextField("Target", text: $targetText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Bar weight (\(unit.label))") {
                    TextField("Bar", text: $barText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section("Available plates · each side") {
                ForEach(plates, id: \.self) { plate in
                    Toggle("\(plate.cleanString) \(unit.label)", isOn: Binding(get: { selectedPlates.contains(plate) }, set: { enabled in
                        if enabled { selectedPlates.insert(plate) } else { selectedPlates.remove(plate) }
                    }))
                }
            }

            if let calculation {
                Section("Load each side") {
                    if calculation.plates.isEmpty {
                        Text(calculation.remainder < 0.001 ? "Use the empty bar." : "No selected plate combination reaches this target.")
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(alignment: .center, spacing: 3) {
                            RoundedRectangle(cornerRadius: 3).fill(.secondary).frame(width: 30, height: 8)
                            ForEach(Array(calculation.plates.enumerated()), id: \.offset) { _, plate in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(plateColor(plate))
                                    .frame(width: max(8, min(24, plate / 2)), height: max(28, min(76, plate * 2.4)))
                                    .accessibilityHidden(true)
                            }
                            Spacer()
                        }
                        .frame(minHeight: 82)
                        .accessibilityElement()
                        .accessibilityLabel("Plates on one side")
                        .accessibilityValue(calculation.plates.map { "\($0.cleanString) \(unit.label)" }.joined(separator: ", "))
                        ForEach(Array(calculation.plates.enumerated()), id: \.offset) { _, plate in
                            Text("\(plate.cleanString) \(unit.label)")
                        }
                        Text("Bar + both sides: \((calculation.bar + calculation.plates.reduce(0, +) * 2).cleanString) \(unit.label)")
                            .font(.headline)
                    }
                    if calculation.remainder >= 0.001 {
                        Label("A further \(calculation.remainder.cleanString) \(unit.label) per side is needed to reach the exact target. Change the target or available plates.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            } else {
                Section { Text("Enter a finite target from the bar weight up to 10,000 \(unit.label).").foregroundStyle(.secondary) }
            }

            Section {
                Text("The calculator lists plates for one side. Add the same sequence to the other side and use appropriate collars. It does not assess equipment or lifting safety.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Plate Calculator")
        .onChange(of: unit) { oldUnit, newUnit in
            convertValues(from: oldUnit, to: newUnit)
        }
        .onChange(of: plates) { _, available in
            selectedPlates = selectedPlates.intersection(Set(available))
            if selectedPlates.isEmpty { selectedPlates = Set(available) }
        }
    }

    private func convertValues(from old: WeightUnit, to new: WeightUnit) {
        if let target = NumberParsing.double(targetText) {
            targetText = new.fromKilograms(old.toKilograms(target)).cleanString
        } else { targetText = new == .kilograms ? "60" : "135" }
        if let bar = NumberParsing.double(barText) {
            barText = new.fromKilograms(old.toKilograms(bar)).cleanString
        } else { barText = new == .kilograms ? "20" : "45" }
        selectedPlates = Set(plates)
    }

    private func plateColor(_ plate: Double) -> Color {
        switch plate {
        case 25, 45: .red
        case 20, 35: .blue
        case 15: .yellow
        case 10: .green
        default: .secondary
        }
    }
}
