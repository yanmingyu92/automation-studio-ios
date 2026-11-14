import PDFKit
import SwiftUI

struct ReportExportView: View {
    let project: InspectionProject
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var quota: ExportQuota
    @Environment(\.dismiss) private var dismiss
    @State private var pdfURL: URL?
    @State private var document: PDFDocument?
    @State private var errorMessage: String?
    @State private var isGenerating = true
    @State private var isSharing = false
    @State private var isShowingPaywall = false
    @State private var exportStatusMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isGenerating {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Building your inspection report…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let document {
                    PDFPreview(document: document)
                } else {
                    ContentUnavailableView {
                        Label("Report unavailable", systemImage: "doc.badge.exclamationmark")
                    } description: {
                        Text(errorMessage ?? "The PDF could not be created.")
                    } actions: {
                        Button("Try again") {
                            Task { await generateReport() }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
            .background(Color.fieldCanvas)
            .navigationTitle("Report preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: prepareShare) {
                        Label("Share PDF", systemImage: "square.and.arrow.up")
                    }
                    .disabled(pdfURL == nil)
                }
            }
            .task {
                if pdfURL == nil { await generateReport() }
            }
            .sheet(isPresented: $isSharing) {
                if let pdfURL {
                    ShareSheet(items: [pdfURL], onCompletion: handleShareCompletion)
                        .presentationDetents([.medium, .large])
                }
            }
            .sheet(isPresented: $isShowingPaywall) {
                PaywallView()
            }
            .alert("Export status", isPresented: Binding(
                get: { exportStatusMessage != nil },
                set: { if !$0 { exportStatusMessage = nil } }
            )) {
                Button("OK") { exportStatusMessage = nil }
            } message: {
                Text(exportStatusMessage ?? "")
            }
            .onDisappear {
                if let pdfURL { try? FileManager.default.removeItem(at: pdfURL) }
            }
        }
    }

    @MainActor
    private func generateReport() async {
        isGenerating = true
        errorMessage = nil
        do {
            let snapshot = ReportSnapshot(project: project)
            let url = try ReportRenderer.render(snapshot)
            guard let pdfDocument = PDFDocument(url: url) else { throw ReportRenderer.RenderError.exportFailed }
            pdfURL = url
            document = pdfDocument
        } catch {
            errorMessage = error.localizedDescription
        }
        isGenerating = false
    }

    private func prepareShare() {
        guard pdfURL != nil else { return }
        if quota.canExport(isPro: store.isPro) {
            isSharing = true
        } else {
            isShowingPaywall = true
        }
    }

    private func handleShareCompletion(_ completed: Bool) {
        guard completed else {
            exportStatusMessage = "Sharing was cancelled. No export was counted."
            return
        }
        quota.recordSuccessfulExport(isPro: store.isPro)
        if let remaining = quota.remainingExports(isPro: store.isPro) {
            exportStatusMessage = "Report exported. \(remaining) free export\(remaining == 1 ? "" : "s") remaining."
        } else {
            exportStatusMessage = "Report exported."
        }
    }
}
