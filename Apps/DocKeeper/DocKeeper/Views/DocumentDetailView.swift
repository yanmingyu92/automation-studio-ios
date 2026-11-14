import SwiftData
import SwiftUI

struct DocumentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var notifications: NotificationManager
    @Bindable var document: DocumentRecord

    @State private var showingEditor = false
    @State private var showingPro = false
    @State private var confirmingDelete = false
    @State private var isRecognizingText = false
    @State private var isUploading = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    private let ocrService = VisionOCRService()
    private let paperlessService = PaperlessService()

    private var pdfURL: URL? {
        try? DocumentFileStore.url(forRelativePath: document.localPDFPath)
    }

    var body: some View {
        List {
            Section {
                PDFPreviewView(relativePath: document.localPDFPath)
                    .frame(minHeight: 430)
                    .listRowInsets(EdgeInsets())
            }

            Section("Details") {
                MetadataRow(title: "Category", value: document.category.title)
                if !document.merchant.isEmpty {
                    MetadataRow(title: "Merchant / correspondent", value: document.merchant)
                }
                if let date = document.purchaseDate {
                    MetadataRow(title: "Purchased", value: date.formatted(date: .long, time: .omitted))
                }
                if let date = document.expiryDate {
                    LabeledContent("Warranty / expiry") {
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(date.formatted(date: .long, time: .omitted))
                            ExpiryBadge(date: date, label: "Expiry")
                        }
                    }
                }
                if let date = document.renewalDate {
                    LabeledContent("Renewal") {
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(date.formatted(date: .long, time: .omitted))
                            ExpiryBadge(date: date, label: "Renewal")
                        }
                    }
                }
                MetadataRow(title: "Added", value: document.createdAt.formatted(date: .abbreviated, time: .shortened))
                if !document.tags.isEmpty {
                    LabeledContent("Tags") {
                        Text(document.tags.joined(separator: ", "))
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            if !document.notes.isEmpty {
                Section("Notes") {
                    Text(document.notes).textSelection(.enabled)
                }
            }

            Section("Local Reminder") {
                if document.remindersEnabled {
                    Label("\(document.reminderLeadDays) days before each due date", systemImage: "bell.badge")
                    Text("Scheduled for 9:00 AM on this device when that reminder time is still in the future. Edit the document to reschedule or turn reminders off.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Off", systemImage: "bell.slash")
                        .foregroundStyle(.secondary)
                    Button("Set Up in Editor") { showingEditor = true }
                }
            }

            Section("Recognized Text") {
                if document.ocrText.isEmpty {
                    Text("No recognized text. Re-run OCR after adding a readable PDF, or add searchable text in the editor.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(document.ocrText)
                        .textSelection(.enabled)
                        .font(.callout)
                }
                Button {
                    Task { await recognizeTextAgain() }
                } label: {
                    if isRecognizingText {
                        HStack { ProgressView(); Text("Recognizing on this device…") }
                    } else {
                        Label("Run OCR Again", systemImage: "text.viewfinder")
                    }
                }
                .disabled(isRecognizingText || isUploading)
            }

            Section("Paperless-ngx") {
                Label(document.paperlessStatus.title, systemImage: syncIcon)
                    .foregroundStyle(document.paperlessStatus == .failed ? .red : .secondary)
                if let task = document.paperlessTaskID {
                    LabeledContent("Processing task") {
                        Text(task).font(.caption).textSelection(.enabled)
                    }
                    Text("The server accepted this PDF for asynchronous processing. This status does not claim that Paperless has finished indexing it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error = document.lastPaperlessError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
                Button {
                    if store.isPro { Task { await uploadToPaperless() } } else { showingPro = true }
                } label: {
                    if isUploading {
                        HStack { ProgressView(); Text("Uploading…") }
                    } else {
                        Label(
                            document.paperlessStatus == .accepted ? "Upload Again" : "Upload to Paperless",
                            systemImage: "arrow.up.doc"
                        )
                    }
                }
                .disabled(isUploading || isRecognizingText)
                if !store.isPro {
                    Text("Paperless upload is a Pro feature. Local documents and exports are unaffected.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if let pdfURL, FileManager.default.fileExists(atPath: pdfURL.path) {
                    ShareLink(item: pdfURL) {
                        Label("Share or Export PDF", systemImage: "square.and.arrow.up")
                    }
                }
                Button("Delete Document", systemImage: "trash", role: .destructive) {
                    confirmingDelete = true
                }
                // An in-flight OCR or upload writes back to this record when it finishes.
                .disabled(isRecognizingText || isUploading)
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingEditor) {
            DocumentEditorView(document: document, draft: nil)
        }
        .sheet(isPresented: $showingPro) { ProView() }
        .confirmationDialog("Delete this document and its local PDF?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Document", role: .destructive, action: deleteDocument)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A copy already accepted by Paperless-ngx is not deleted.")
        }
        .alert("Document Status", isPresented: messagePresented) {
            Button("OK") {
                errorMessage = nil
                statusMessage = nil
            }
        } message: {
            Text(errorMessage ?? statusMessage ?? "")
        }
    }

    private var syncIcon: String {
        switch document.paperlessStatus {
        case .notSynced: "server.rack"
        case .uploading: "arrow.up.circle"
        case .accepted: "checkmark.circle"
        case .failed: "exclamationmark.circle"
        }
    }

    private var messagePresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil || statusMessage != nil },
            set: { if !$0 { errorMessage = nil; statusMessage = nil } }
        )
    }

    private func recognizeTextAgain() async {
        isRecognizingText = true
        defer { isRecognizingText = false }
        do {
            let data = try DocumentFileStore.pdfData(forRelativePath: document.localPDFPath)
            document.ocrText = try await ocrService.recognizeText(inPDFData: data)
            document.updatedAt = .now
            try modelContext.save()
            statusMessage = document.ocrText.isEmpty ? "OCR finished, but no selectable text was found." : "On-device OCR finished and search has been updated."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uploadToPaperless() async {
        guard store.isPro else { showingPro = true; return }
        isUploading = true
        document.paperlessStatus = .uploading
        document.lastPaperlessAttempt = .now
        document.lastPaperlessError = nil
        defer { isUploading = false }

        let taskID: String
        do {
            guard let serverURL = PaperlessConfiguration.serverURL,
                  let token = try KeychainStore.paperlessToken(),
                  !token.isEmpty else { throw PaperlessError.notConfigured }
            let data = try DocumentFileStore.pdfData(forRelativePath: document.localPDFPath)
            taskID = try await paperlessService.uploadDocument(
                data,
                filename: "\(document.title).pdf",
                title: document.title,
                serverURL: serverURL,
                token: token
            )
        } catch {
            document.paperlessStatus = .failed
            document.lastPaperlessError = error.localizedDescription
            try? modelContext.save()
            errorMessage = error.localizedDescription
            return
        }

        document.paperlessTaskID = taskID
        document.paperlessStatus = .accepted
        document.lastPaperlessError = nil
        do {
            try modelContext.save()
            statusMessage = "Paperless accepted the PDF for processing. Task \(taskID) has been saved; completed indexing has not been assumed."
        } catch {
            document.lastPaperlessError = "The server accepted task \(taskID), but the local status could not be saved: \(error.localizedDescription)"
            statusMessage = document.lastPaperlessError
        }
    }

    private func deleteDocument() {
        // Read the identifier first: a deleted model must not be accessed after the save.
        let documentID = document.id
        let pendingDeletion: DocumentFileStore.PendingPDFDeletion
        do {
            pendingDeletion = try DocumentFileStore.beginPDFDeletion(forRelativePath: document.localPDFPath)
        } catch {
            errorMessage = "The document was not deleted: \(error.localizedDescription)"
            return
        }

        modelContext.delete(document)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            do {
                try DocumentFileStore.rollbackPDFDeletion(pendingDeletion)
                errorMessage = "The document was not deleted. Its PDF was restored: \(error.localizedDescription)"
            } catch {
                errorMessage = "The model deletion failed, and the PDF could not be restored automatically. Its private recovery copy is \(pendingDeletion.tombstoneURL?.lastPathComponent ?? "unavailable"): \(error.localizedDescription)"
            }
            return
        }

        notifications.cancelReminders(forDocumentID: documentID)
        try? DocumentFileStore.finishPDFDeletion(pendingDeletion)
        dismiss()
    }
}
