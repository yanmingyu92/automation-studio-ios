import SwiftData
import SwiftUI

struct ProjectEditorView: View {
    enum Mode {
        case new
        case edit(InspectionProject)
    }

    let mode: Mode
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("profile.inspectorName") private var defaultInspector = ""
    @AppStorage("profile.companyName") private var defaultCompany = ""
    @AppStorage("profile.companyDetails") private var defaultCompanyDetails = ""

    @State private var title = ""
    @State private var customerName = ""
    @State private var customerContact = ""
    @State private var siteAddress = ""
    @State private var inspectorName = ""
    @State private var companyName = ""
    @State private var companyDetails = ""
    @State private var reportNotes = ""
    @State private var inspectionDate = Date.now
    @State private var errorMessage: String?

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !siteAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Report title", text: $title)
                    TextField("Site address", text: $siteAddress, axis: .vertical)
                    DatePicker("Inspection date", selection: $inspectionDate, displayedComponents: .date)
                } header: {
                    Text("Project")
                } footer: {
                    Text("A report title and site address are required.")
                }
                Section("Customer") {
                    TextField("Customer name", text: $customerName)
                    TextField("Phone or email", text: $customerContact)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                }
                Section("Inspector and company") {
                    TextField("Inspector name", text: $inspectorName)
                        .textContentType(.name)
                    TextField("Company name", text: $companyName)
                        .textContentType(.organizationName)
                    TextField("License or contact details", text: $companyDetails, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section("Report notes") {
                    TextField("Scope, access, weather, or general notes", text: $reportNotes, axis: .vertical)
                        .lineLimit(4...10)
                }
            }
            .navigationTitle(isNew ? "New project" : "Project details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Create" : "Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
            .errorAlert($errorMessage)
        }
    }

    private var isNew: Bool {
        if case .new = mode { return true }
        return false
    }

    private func load() {
        switch mode {
        case .new:
            guard title.isEmpty else { return }
            inspectorName = defaultInspector
            companyName = defaultCompany
            companyDetails = defaultCompanyDetails
        case .edit(let project):
            title = project.title
            customerName = project.customerName
            customerContact = project.customerContact
            siteAddress = project.siteAddress
            inspectorName = project.inspectorName
            companyName = project.companyName
            companyDetails = project.companyDetails
            reportNotes = project.reportNotes
            inspectionDate = project.inspectionDate
        }
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanSite = siteAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch mode {
            case .new:
                let project = InspectionProject(
                    title: cleanTitle,
                    customerName: customerName,
                    customerContact: customerContact,
                    siteAddress: cleanSite,
                    inspectorName: inspectorName,
                    companyName: companyName,
                    companyDetails: companyDetails,
                    reportNotes: reportNotes,
                    inspectionDate: inspectionDate
                )
                modelContext.insert(project)
                try modelContext.save()
            case .edit(let project):
                project.title = cleanTitle
                project.customerName = customerName
                project.customerContact = customerContact
                project.siteAddress = cleanSite
                project.inspectorName = inspectorName
                project.companyName = companyName
                project.companyDetails = companyDetails
                project.reportNotes = reportNotes
                project.inspectionDate = inspectionDate
                project.updatedAt = .now
                try modelContext.save()
            }
            dismiss()
        } catch {
            errorMessage = "The project could not be saved. \(error.localizedDescription)"
        }
    }
}
