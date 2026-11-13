import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

private enum DocumentListFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case expiring = "Expiring soon"
    case expired = "Expired"
    case receipts = "Receipts"
    case contracts = "Contracts"
    case warranties = "Warranties"

    var id: String { rawValue }
}

private enum DocumentSheet: Identifiable {
    case scanner
    case editor(DocumentDraft)
    case pro

    var id: String {
        switch self {
        case .scanner: "scanner"
        case .editor(let draft): draft.id.uuidString
        case .pro: "pro"
        }
    }
}

struct DocumentsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var notifications: NotificationManager
    @Query(sort: [SortDescriptor(\DocumentRecord.updatedAt, order: .reverse)]) private var documents: [DocumentRecord]
    @StateObject private var importer = DocumentImportController()

    @State private var searchText = ""
    @State private var filter: DocumentListFilter = .all
    @State private var sheet: DocumentSheet?
    @State private var photoSelection: PhotosPickerItem?
    @State private var showingFileImporter = false
    @State private var importTask: Task<Void, Never>?
    @State private var activeDraft: DocumentDraft?
    @State private var documentPendingDeletion: DocumentRecord?

    private var filteredDocuments: [DocumentRecord] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let nextMonth = calendar.date(byAdding: .day, value: 30, to: today) ?? today
        return documents.filter { document in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .expiring:
                matchesFilter = document.expiryDate.map { $0 >= today && $0 <= nextMonth } == true
            case .expired: matchesFilter = document.expiryDate.map { $0 < today } == true
            case .receipts: matchesFilter = document.category == .receipt
            case .contracts: matchesFilter = document.category == .contract
            case .warranties: matchesFilter = document.category == .warranty
            }
            guard matchesFilter else { return false }
            if searchText.isEmpty { return true }
            return document.searchableText.localizedStandardContains(searchText)
        }
    }

    @ViewBuilder
    private var libraryList: some View {
        if documents.isEmpty {
            emptyLibrary
        } else {
            List {
                if !store.isPro {
                    Section {
                        HStack {
                            Label(
                                documents.count < StoreManager.freeDocumentLimit
                                    ? "\(documents.count) of \(StoreManager.freeDocumentLimit) free documents used"
                                    : "Free document limit reached",
                                systemImage: "internaldrive"
                            )
                            Spacer()
                            if documents.count >= StoreManager.freeDocumentLimit {
                                Button("View Pro") { sheet = .pro }
                            }
                        }
                        .font(.footnote)
                    }
                }

                if filteredDocuments.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Matching Documents",
                            systemImage: "magnifyingglass",
                            description: Text("Try another search or filter.")
                        )
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(filteredDocuments) { document in
                            NavigationLink {
                                DocumentDetailView(document: document)
                            } label: {
                                DocumentRow(document: document)
                            }
                            .accessibilityHint("Opens details, recognized text, and PDF preview")
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    documentPendingDeletion = document
                                }
                            }
                        }
                        .onDelete { offsets in
                            documentPendingDeletion = offsets.map { filteredDocuments[$0] }.first
                        }
                    } header: {
                        Text(documentCountDescription)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var emptyLibrary: some View {
        ScrollView {
            VStack(spacing: 28) {
                if !store.isPro {
                    HStack {
                        Label(
                            "0 of \(StoreManager.freeDocumentLimit) free documents used",
                            systemImage: "internaldrive"
                        )
                        Spacer()
                    }
                    .font(.footnote)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }

                VStack(spacing: 22) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text("Your private document library")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Scan a receipt, import a warranty PDF, or choose a photo. OCR and storage happen on this device.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: beginScan) {
                        Text("Scan Your First Document")
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .accessibilityHint("Opens the document scanner")
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: 16)
        }
    }

    var body: some View {
        NavigationStack {
            libraryWithToolbar
        }
        .sheet(item: $sheet, onDismiss: abandonUnsavedDraft) { item in
            documentSheet(for: item)
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.pdf, .image],
            onCompletion: handleFileImport
        )
        .onChange(of: photoSelection) { _, selection in
            handlePhotoSelection(selection)
        }
        .onChange(of: importer.draft) { _, draft in
            presentImportedDraft(draft)
        }
        .alert("Document Import", isPresented: errorPresented) {
            Button("OK") { importer.errorMessage = nil }
        } message: {
            Text(importer.errorMessage ?? "")
        }
        .confirmationDialog(
            "Delete this document and its local PDF?",
            isPresented: deletionConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Document", role: .destructive) {
                if let document = documentPendingDeletion { delete(document) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This does not delete a copy already accepted by Paperless-ngx.")
        }
        .overlay {
            if importer.isProcessing {
                ProcessingOverlay(message: importer.processingMessage) {
                    importTask?.cancel()
                }
            }
        }
    }

    private var libraryWithToolbar: some View {
        libraryList
            .navigationTitle("DocKeeper")
            .searchable(text: $searchText, prompt: "Titles, merchants, tags, or OCR text")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Filter", selection: $filter) {
                            ForEach(DocumentListFilter.allCases) { item in
                                Text(item.rawValue).tag(item)
                            }
                        }
                    } label: {
                        Label("Filter", systemImage: filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityValue(filter.rawValue)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Scan Document", systemImage: "doc.viewfinder", action: beginScan)
                        PhotosPicker(selection: $photoSelection, matching: .images, photoLibrary: .shared()) {
                            Label("Choose Photo", systemImage: "photo")
                        }
                        Button("Import PDF or Image", systemImage: "folder") {
                            guardCanAdd { showingFileImporter = true }
                        }
                    } label: {
                        Label("Add Document", systemImage: "plus")
                    }
                }
            }
    }

    @ViewBuilder
    private func documentSheet(for item: DocumentSheet) -> some View {
        switch item {
        case .scanner:
            DocumentScannerView(
                onFinish: { pages in
                    sheet = nil
                    runImport { await importer.importScannedPages(pages) }
                },
                onCancel: { sheet = nil },
                onError: { error in
                    sheet = nil
                    importer.errorMessage = error.localizedDescription
                }
            )
            .ignoresSafeArea()
        case .editor(let draft):
            DocumentEditorView(document: nil, draft: draft, onSaved: {
                activeDraft = nil
                importer.draft = nil
            })
        case .pro:
            ProView()
        }
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            runImport { await importer.importFile(at: url) }
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                importer.errorMessage = error.localizedDescription
            }
        }
    }

    private func handlePhotoSelection(_ selection: PhotosPickerItem?) {
        guard let selection else { return }
        photoSelection = nil
        guardCanAdd {
            runImport {
                do {
                    guard let data = try await selection.loadTransferable(type: Data.self) else {
                        throw DocumentFileStoreError.invalidImage
                    }
                    await importer.importPhoto(data: data)
                } catch {
                    importer.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func presentImportedDraft(_ draft: DocumentDraft?) {
        guard let draft else { return }
        activeDraft = draft
        sheet = .editor(draft)
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { importer.errorMessage != nil },
            set: { if !$0 { importer.errorMessage = nil } }
        )
    }

    private var deletionConfirmationPresented: Binding<Bool> {
        Binding(
            get: { documentPendingDeletion != nil },
            set: { if !$0 { documentPendingDeletion = nil } }
        )
    }

    private var documentCountDescription: String {
        let noun = filteredDocuments.count == 1 ? "document" : "documents"
        return "\(filteredDocuments.count) \(noun)"
    }

    private var canAdd: Bool {
        store.isPro || documents.count < StoreManager.freeDocumentLimit
    }

    private func guardCanAdd(_ action: () -> Void) {
        if canAdd { action() } else { sheet = .pro }
    }

    private func beginScan() {
        guardCanAdd {
            if DocumentScannerView.isSupported {
                sheet = .scanner
            } else {
                importer.errorMessage = "Document scanning is not available on this device or in Simulator. Choose a photo or import a PDF instead."
            }
        }
    }

    private func runImport(_ operation: @escaping @MainActor () async -> Void) {
        importTask?.cancel()
        importTask = Task { await operation() }
    }

    private func abandonUnsavedDraft() {
        guard let draft = activeDraft else { return }
        activeDraft = nil
        importer.draft = nil
        do {
            try DocumentFileStore.deletePDF(forRelativePath: draft.localPDFPath)
        } catch {
            importer.errorMessage = "The canceled draft’s PDF could not be removed: \(error.localizedDescription)"
        }
    }

    private func delete(_ document: DocumentRecord) {
        let pendingDeletion: DocumentFileStore.PendingPDFDeletion
        do {
            pendingDeletion = try DocumentFileStore.beginPDFDeletion(forRelativePath: document.localPDFPath)
        } catch {
            importer.errorMessage = "The document was not deleted: \(error.localizedDescription)"
            return
        }

        modelContext.delete(document)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            do {
                try DocumentFileStore.rollbackPDFDeletion(pendingDeletion)
                importer.errorMessage = "The document was not deleted. Its PDF was restored: \(error.localizedDescription)"
            } catch {
                importer.errorMessage = "The model deletion failed, and the PDF could not be restored automatically. Its private recovery copy is \(pendingDeletion.tombstoneURL?.lastPathComponent ?? "unavailable"): \(error.localizedDescription)"
            }
            return
        }

        notifications.cancelReminders(for: document)
        do {
            try DocumentFileStore.finishPDFDeletion(pendingDeletion)
        } catch {
            importer.errorMessage = "The document was deleted, but its private temporary file could not be removed: \(error.localizedDescription)"
        }
    }
}

private struct DocumentRow: View {
    let document: DocumentRecord

    var body: some View {
        HStack(spacing: 12) {
            DocumentThumbnail(data: document.thumbnailData, category: document.category)
            VStack(alignment: .leading, spacing: 5) {
                Text(document.title)
                    .font(.headline)
                    .lineLimit(2)
                if !document.merchant.isEmpty {
                    Text(document.merchant)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 7) {
                    Label(document.category.title, systemImage: document.category.systemImage)
                    if !document.tags.isEmpty {
                        Text(document.tags.prefix(2).joined(separator: " · "))
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let expiry = document.expiryDate {
                    ExpiryBadge(date: expiry, label: expiry.formatted(date: .abbreviated, time: .omitted))
                } else if let renewal = document.renewalDate {
                    ExpiryBadge(date: renewal, label: "Renews \(renewal.formatted(date: .abbreviated, time: .omitted))")
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
