import SwiftData
import SwiftUI

struct DocumentEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var notifications: NotificationManager

    private let draft: DocumentDraft?
    private let onSaved: (() -> Void)?
    @State private var workingDocument: DocumentRecord?
    @State private var title: String
    @State private var merchant: String
    @State private var category: DocumentCategory
    @State private var purchaseDate: Date
    @State private var expiryDate: Date
    @State private var renewalDate: Date
    @State private var includesPurchaseDate: Bool
    @State private var includesExpiryDate: Bool
    @State private var includesRenewalDate: Bool
    @State private var notes: String
    @State private var tagsText: String
    @State private var ocrText: String
    @State private var remindersEnabled: Bool
    @State private var reminderLeadDays: Int
    @State private var processingWarning: String?
    @State private var errorMessage: String?
    @State private var showingPro = false
    @State private var isSaving = false

    init(document: DocumentRecord?, draft: DocumentDraft?, onSaved: (() -> Void)? = nil) {
        self.draft = draft
        self.onSaved = onSaved
        _workingDocument = State(initialValue: document)
        _title = State(initialValue: document?.title ?? draft?.suggestedTitle ?? "")
        _merchant = State(initialValue: document?.merchant ?? "")
        _category = State(initialValue: document?.category ?? .other)
        _purchaseDate = State(initialValue: document?.purchaseDate ?? .now)
        _expiryDate = State(initialValue: document?.expiryDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now)
        _renewalDate = State(initialValue: document?.renewalDate ?? Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now)
        _includesPurchaseDate = State(initialValue: document?.purchaseDate != nil)
        _includesExpiryDate = State(initialValue: document?.expiryDate != nil)
        _includesRenewalDate = State(initialValue: document?.renewalDate != nil)
        _notes = State(initialValue: document?.notes ?? "")
        _tagsText = State(initialValue: document?.tags.joined(separator: ", ") ?? "")
        _ocrText = State(initialValue: document?.ocrText ?? draft?.ocrText ?? "")
        _remindersEnabled = State(initialValue: document?.remindersEnabled ?? false)
        _reminderLeadDays = State(initialValue: document?.reminderLeadDays ?? 7)
        _processingWarning = State(initialValue: draft?.processingWarning)
    }

    private var pdfPath: String? {
        workingDocument?.localPDFPath ?? draft?.localPDFPath
    }

    private var hasReminderDate: Bool {
        includesExpiryDate || includesRenewalDate
    }

    var body: some View {
        NavigationStack {
            Form {
                if let processingWarning {
                    Section {
                        Label(processingWarning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                }

                Section("Document") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.words)
                    TextField("Merchant / correspondent", text: $merchant)
                        .textInputAutocapitalization(.words)
                    Picker("Category", selection: $category) {
                        ForEach(DocumentCategory.allCases) { category in
                            Label(category.title, systemImage: category.systemImage).tag(category)
                        }
                    }
                    TextField("Tags, separated by commas", text: $tagsText, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let pdfPath {
                        NavigationLink("Preview PDF") {
                            PDFPreviewView(relativePath: pdfPath)
                                .navigationTitle("PDF Preview")
                                .navigationBarTitleDisplayMode(.inline)
                        }
                    }
                }

                Section("Important Dates") {
                    OptionalDateRow(title: "Purchase date", isIncluded: $includesPurchaseDate, date: $purchaseDate)
                    OptionalDateRow(title: "Warranty / expiry date", isIncluded: $includesExpiryDate, date: $expiryDate)
                    OptionalDateRow(title: "Renewal date", isIncluded: $includesRenewalDate, date: $renewalDate)
                }

                Section("Local Reminders") {
                    Toggle("Expiry and renewal reminders", isOn: $remindersEnabled)
                        .disabled(!hasReminderDate)
                    if remindersEnabled {
                        Stepper("\(reminderLeadDays) days before", value: $reminderLeadDays, in: 0...365)
                        Text("Notifications are scheduled on this device for 9:00 AM. Dates whose reminder time has already passed are not scheduled.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if !hasReminderDate {
                        Text("Add an expiry or renewal date to enable reminders.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                        .accessibilityLabel("Document notes")
                }

                Section("Recognized Text") {
                    Text("Vision OCR is editable. Correct any recognition errors to improve search.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $ocrText)
                        .frame(minHeight: 150)
                        .accessibilityLabel("Recognized document text")
                }
            }
            .navigationTitle(workingDocument == nil ? "New Document" : "Edit Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", action: save)
                            .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .disabled(isSaving)
            .sheet(isPresented: $showingPro) { ProView() }
            .alert("Couldn’t Save", isPresented: errorPresented) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: includesExpiryDate) { _, _ in updateReminderAvailability() }
            .onChange(of: includesRenewalDate) { _, _ in updateReminderAvailability() }
            .onChange(of: remindersEnabled) { _, enabled in
                guard enabled else { return }
                Task {
                    if await !notifications.requestPermission() {
                        remindersEnabled = false
                        errorMessage = ReminderError.permissionDenied.localizedDescription
                    }
                }
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func updateReminderAvailability() {
        if !hasReminderDate { remindersEnabled = false }
    }

    private func save() {
        isSaving = true

        if workingDocument == nil && !store.isPro {
            let descriptor = FetchDescriptor<DocumentRecord>()
            let count = (try? modelContext.fetchCount(descriptor)) ?? StoreManager.freeDocumentLimit
            if count >= StoreManager.freeDocumentLimit {
                isSaving = false
                showingPro = true
                return
            }
        }

        let isNewDocument = workingDocument == nil
        let tags = tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let document: DocumentRecord
        if let existing = workingDocument {
            document = existing
        } else if let draft {
            document = DocumentRecord(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                localPDFPath: draft.localPDFPath,
                thumbnailData: draft.thumbnailData
            )
            modelContext.insert(document)
            workingDocument = document
        } else {
            isSaving = false
            errorMessage = "The imported PDF is no longer available."
            return
        }

        let wantsReminders = remindersEnabled && hasReminderDate
        document.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        document.merchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        document.category = category
        document.purchaseDate = includesPurchaseDate ? purchaseDate : nil
        document.expiryDate = includesExpiryDate ? expiryDate : nil
        document.renewalDate = includesRenewalDate ? renewalDate : nil
        document.notes = notes
        document.tags = tags
        document.ocrText = ocrText
        document.remindersEnabled = false
        document.reminderLeadDays = reminderLeadDays
        document.updatedAt = .now

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            if isNewDocument { workingDocument = nil }
            isSaving = false
            errorMessage = error.localizedDescription
            return
        }

        onSaved?()
        Task {
            if wantsReminders {
                document.remindersEnabled = true
                do {
                    try await notifications.rescheduleReminders(for: document)
                    try modelContext.save()
                } catch {
                    notifications.cancelReminders(for: document)
                    modelContext.rollback()
                    remindersEnabled = false
                    isSaving = false
                    errorMessage = "The document was saved with reminders off because scheduling did not complete: \(error.localizedDescription)"
                    return
                }
            } else {
                notifications.cancelReminders(for: document)
            }
            isSaving = false
            dismiss()
        }
    }
}
