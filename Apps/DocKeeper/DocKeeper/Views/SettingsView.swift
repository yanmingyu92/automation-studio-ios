import SwiftData
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var notifications: NotificationManager
    @Query(sort: [SortDescriptor(\DocumentRecord.createdAt, order: .forward)]) private var documents: [DocumentRecord]

    @State private var showingPro = false
    @State private var exportURL: URL?
    @State private var isExporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Storage and Pro") {
                    LabeledContent("Local documents", value: "\(documents.count)")
                    if store.isPro {
                        Label("DocKeeper Pro active", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            showingPro = true
                        } label: {
                            LabeledContent("DocKeeper Pro") {
                                Text("\(documents.count)/\(StoreManager.freeDocumentLimit) free")
                            }
                        }
                    }
                    Text("Your library is stored in the app’s private container. Reaching the free limit never deletes or locks existing documents.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Reminders") {
                    LabeledContent("System permission", value: notificationStatusTitle)
                    if notifications.authorizationStatus == .notDetermined {
                        Button("Allow Local Notifications") {
                            Task {
                                if await !notifications.requestPermission() {
                                    errorMessage = ReminderError.permissionDenied.localizedDescription
                                }
                            }
                        }
                    } else if notifications.authorizationStatus == .denied {
                        Button("Open Notification Settings", systemImage: "gear", action: openSystemSettings)
                    }
                    Text("Expiry and renewal reminders are configured per document and scheduled locally. No server is used.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Optional Server") {
                    NavigationLink {
                        PaperlessSettingsView()
                    } label: {
                        Label("Paperless-ngx", systemImage: "server.rack")
                    }
                    if PaperlessConfiguration.serverURL != nil {
                        Label("Server configured; uploads are explicit", systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not configured. All local features remain available.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Data Export") {
                    Button {
                        Task { prepareExport() }
                    } label: {
                        if isExporting {
                            HStack { ProgressView(); Text("Preparing archive…") }
                        } else {
                            Label("Prepare Portable Archive", systemImage: "shippingbox")
                        }
                    }
                    .disabled(documents.isEmpty || isExporting)
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share Export Archive", systemImage: "square.and.arrow.up")
                        }
                    }
                    Text("The JSON archive includes every record, OCR text, thumbnail, and full PDF data encoded for portability. Individual PDFs can also be shared from their document. The archive contains no API tokens.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Privacy and About") {
                    NavigationLink {
                        PrivacyView()
                    } label: {
                        Label("Privacy", systemImage: "hand.raised")
                    }
                    NavigationLink {
                        ThirdPartyNoticesView()
                    } label: {
                        Label("Third-Party Notices", systemImage: "doc.plaintext")
                    }
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingPro) { ProView() }
            .alert("Settings", isPresented: errorPresented) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task { await notifications.refreshAuthorization() }
        }
    }

    private var notificationStatusTitle: String {
        switch notifications.authorizationStatus {
        case .notDetermined: "Not requested"
        case .denied: "Denied"
        case .authorized: "Allowed"
        case .provisional: "Provisional"
        case .ephemeral: "Ephemeral"
        @unknown default: "Unknown"
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func prepareExport() {
        isExporting = true
        defer { isExporting = false }
        do {
            exportURL = try DocumentExportService.makeArchive(for: documents)
        } catch {
            errorMessage = "Export stopped: \(error.localizedDescription)"
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct PrivacyView: View {
    var body: some View {
        List {
            Section("Local by Design") {
                Label("No account, advertising, or analytics", systemImage: "person.crop.circle.badge.checkmark")
                Text("Document records, PDFs, thumbnails, tags, dates, and OCR text remain in DocKeeper’s private app storage. DocKeeper has no DocKeeper-operated backend and does not sell or share document data.")
            }
            Section("Camera, Photos, and Files") {
                Text("The camera is used only after you start a VisionKit scan. Photo access uses the system picker so only selected items are provided. File imports copy only the selected PDF or image. Canceling a scan creates no document.")
            }
            Section("On-Device OCR") {
                Text("Apple Vision performs text recognition on the device. Recognized text is editable and is used for local search. OCR results are not represented as perfect transcriptions.")
            }
            Section("Notifications") {
                Text("Warranty and renewal reminders are scheduled with the system notification service on this device. Turning off or deleting a document cancels its pending reminders. No remote push service is used.")
            }
            Section("Paperless-ngx") {
                Text("This integration is optional and off until configured. Testing a connection sends your API token to the server URL you enter. Uploading sends the selected PDF and title only after your explicit action. The token is kept in Keychain, never in exports or source code. TLS is required except for supported local-network HTTP addresses; App Transport Security is not globally disabled.")
            }
            Section("Purchases and Export") {
                Text("StoreKit communicates with Apple only when loading products, purchasing, restoring, or checking entitlements. Portable archives and PDF shares leave the app only through a destination you choose in the system share sheet. Archives contain document data and should be protected accordingly.")
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ThirdPartyNoticesView: View {
    var body: some View {
        List {
            Section("Apple Platform Technologies") {
                Text("DocKeeper uses SwiftUI, SwiftData, Vision, VisionKit, PDFKit, PhotosUI, StoreKit, UserNotifications, Security, and Uniform Type Identifiers from the Apple operating system. These frameworks and SF Symbols are subject to Apple’s SDK and platform agreements; no system framework source code is bundled.")
            }
            Section("Open-Source Dependencies") {
                Text("DocKeeper bundles no third-party open-source packages, analytics SDKs, advertising SDKs, or copied GPL/AGPL application code. XcodeGen is a development-time project generator and is not included in the application binary.")
            }
            Section("Paperless-ngx") {
                Text("DocKeeper communicates with Paperless-ngx through its documented public REST API. Paperless-ngx is a separate self-hosted product and is not embedded in DocKeeper. No Paperless-ngx application source code is included.")
            }
        }
        .navigationTitle("Third-Party Notices")
        .navigationBarTitleDisplayMode(.inline)
    }
}
