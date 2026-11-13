import SwiftData
import SwiftUI

struct NewFindingView: View {
    let project: InspectionProject
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var category = IssueCategory.general
    @State private var severity = Severity.medium
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("What did you inspect?") {
                    TextField("Finding title", text: $title, axis: .vertical)
                    Picker("Category", selection: $category) {
                        ForEach(IssueCategory.allCases) { category in
                            Label(category.rawValue, systemImage: category.symbol).tag(category)
                        }
                    }
                    Picker("Severity", selection: $severity) {
                        ForEach(Severity.allCases) { severity in
                            Text(severity.rawValue).tag(severity)
                        }
                    }
                    Text(severity.reportDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Text("You can add observations, recommendations, photos, and a voice transcript on the next screen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New finding")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add finding") { create() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .errorAlert($errorMessage)
        }
    }

    private func create() {
        let finding = Finding(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            severity: severity,
            sortOrder: project.findings.count
        )
        finding.project = project
        project.updatedAt = .now
        modelContext.insert(finding)
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "The finding could not be added. \(error.localizedDescription)"
        }
    }
}
