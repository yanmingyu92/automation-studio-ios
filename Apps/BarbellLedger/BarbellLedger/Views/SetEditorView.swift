import SwiftUI

struct SetEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultWeightUnit") private var unit: WeightUnit = .kilograms
    @Bindable var set: WorkoutSet
    let onSave: (WorkoutSet) -> Void

    @State private var weightText: String
    @State private var repsText: String
    @State private var distanceText: String
    @State private var durationText: String
    @State private var hasRPE: Bool
    @State private var rpe: Double
    @State private var kind: SetKind
    @State private var note: String
    @State private var isCompleted: Bool
    @State private var showCardio = false
    @State private var validationError: String?

    /// `markCompleted` pre-enables the Completed toggle when the editor was opened by trying to complete an empty set.
    init(set: WorkoutSet, markCompleted: Bool = false, onSave: @escaping (WorkoutSet) -> Void) {
        self.set = set
        self.onSave = onSave
        let storedUnit = WeightUnit(rawValue: UserDefaults.standard.string(forKey: "defaultWeightUnit") ?? "kg") ?? .kilograms
        _weightText = State(initialValue: storedUnit.fromKilograms(set.weightKilograms).cleanString)
        _repsText = State(initialValue: set.reps == 0 ? "" : String(set.reps))
        _distanceText = State(initialValue: set.distanceMeters == 0 ? "" : set.distanceMeters.cleanString)
        _durationText = State(initialValue: set.durationSeconds == 0 ? "" : set.durationSeconds.clockString)
        _hasRPE = State(initialValue: set.rpe != nil)
        _rpe = State(initialValue: set.rpe ?? 8)
        _kind = State(initialValue: set.kind)
        _note = State(initialValue: set.note)
        _isCompleted = State(initialValue: set.isCompleted || markCompleted)
        _showCardio = State(initialValue: set.distanceMeters > 0 || set.durationSeconds > 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Load and effort") {
                    LabeledContent("Weight (\(unit.label))") {
                        TextField("0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Reps") {
                        TextField("0", text: $repsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("Set type", selection: $kind) {
                        ForEach(SetKind.allCases) { kind in Text(kind.label).tag(kind) }
                    }
                    Toggle("Log RPE", isOn: $hasRPE)
                    if hasRPE {
                        VStack(alignment: .leading) {
                            Slider(value: $rpe, in: 4...10, step: 0.5) {
                                Text("RPE")
                            }
                            .accessibilityValue("\(rpe.cleanString) out of 10")
                            Text("RPE \(rpe.cleanString) · perceived effort, not a health assessment")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Grip, tempo, technique, or anything useful", text: $note, axis: .vertical)
                }

                Section {
                    DisclosureGroup("Distance and duration (optional)", isExpanded: $showCardio) {
                        LabeledContent("Distance (m)") {
                            TextField("0", text: $distanceText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("Time (mm:ss)") {
                            TextField("0:00", text: $durationText)
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section {
                    Toggle("Completed", isOn: $isCompleted)
                        .accessibilityHint("Completed sets count toward volume and records")
                }

                if let validationError {
                    Section { Text(validationError).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Edit Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
        }
    }

    private func save() {
        // Blank weight or reps means zero (bodyweight, distance-only, or time-only sets).
        let isBlank: (String) -> Bool = { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let weight = isBlank(weightText) ? 0 : NumberParsing.double(weightText), weight.isFinite, weight >= 0, weight <= 10_000_000 else {
            validationError = "Enter a valid, non-negative weight."
            return
        }
        guard let reps = isBlank(repsText) ? 0 : NumberParsing.double(repsText), reps.isFinite, reps >= 0, reps <= 1_000_000, reps.rounded() == reps else {
            validationError = "Enter a whole number of repetitions."
            return
        }
        let distance = isBlank(distanceText) ? 0 : NumberParsing.double(distanceText)
        guard let distance, distance.isFinite, distance >= 0 else {
            validationError = "Enter a valid, non-negative distance in meters."
            return
        }
        let duration = durationText.isEmpty ? 0 : NumberParsing.duration(durationText)
        guard let duration, duration.isFinite, duration >= 0 else {
            validationError = "Enter duration as seconds, mm:ss, or hh:mm:ss."
            return
        }
        guard weight > 0 || reps > 0 || distance > 0 || duration > 0 else {
            validationError = "Enter a weight, reps, distance, or duration."
            return
        }
        set.weightKilograms = unit.toKilograms(weight)
        set.reps = Int(reps)
        set.rpe = hasRPE ? rpe : nil
        set.kind = kind
        set.note = note
        set.isCompleted = isCompleted
        set.distanceMeters = distance
        set.durationSeconds = duration
        set.completedAt = isCompleted ? (set.completedAt ?? .now) : nil
        if !isCompleted { set.personalRecordLabels = [] }
        onSave(set)
        dismiss()
    }
}

struct RestTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RestTimerManager.self) private var timer
    @AppStorage("defaultRestSeconds") private var defaultRestSeconds = 90
    @State private var seconds = 90

    var body: some View {
        NavigationStack {
            Form {
                Section("Rest duration") {
                    Picker("Duration", selection: $seconds) {
                        ForEach([30, 60, 90, 120, 180, 240, 300], id: \.self) { value in
                            Text(value.clockString).tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .accessibilityLabel("Rest duration")
                    Stepper("Custom: \(seconds.clockString)", value: $seconds, in: 5...1800, step: 5)
                }
                Section {
                    Button(timer.isRunning ? "Restart Timer" : "Start Timer") {
                        Task {
                            await timer.start(seconds: TimeInterval(seconds))
                            defaultRestSeconds = seconds
                            dismiss()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    if timer.endDate != nil {
                        Button("Cancel Current Timer", role: .destructive) {
                            timer.stop()
                            dismiss()
                        }
                    }
                }
                Section("Background alerts") {
                    Text("BarbellLedger schedules a local notification when you start a rest. Keep the app open if notification permission is disabled. Cancelling also removes the pending notification.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if timer.authorizationStatus == .denied {
                        Button("Open Notification Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                    }
                }
            }
            .navigationTitle("Rest Timer")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onAppear {
                seconds = timer.isRunning ? max(5, Int(timer.remaining())) : defaultRestSeconds
                Task { await timer.refreshPermission() }
            }
        }
    }
}
