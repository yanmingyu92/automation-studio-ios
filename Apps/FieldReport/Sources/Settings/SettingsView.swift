import SwiftUI

struct SettingsView: View {
    @AppStorage("profile.inspectorName") private var inspectorName = ""
    @AppStorage("profile.companyName") private var companyName = ""
    @AppStorage("profile.companyDetails") private var companyDetails = ""
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var quota: ExportQuota
    @EnvironmentObject private var transcription: TranscriptionManager
    @State private var isShowingPaywall = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Inspector name", text: $inspectorName)
                        .textContentType(.name)
                    TextField("Company name", text: $companyName)
                        .textContentType(.organizationName)
                    TextField("License or contact details", text: $companyDetails, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Default report identity")
                } footer: {
                    Text("These details prefill new projects. Existing projects keep their own report identity.")
                }

                Section("On-device transcription") {
                    NavigationLink {
                        SpeechModelView()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Speech model")
                                Text(modelStatus)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "waveform.badge.mic")
                        }
                    }
                    Text("Model setup requires a one-time download. Transcription itself is local and works offline after the model is loaded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Reports & purchases") {
                    Label {
                        if store.isPro {
                            Text("FieldReport Pro is active")
                        } else {
                            Text("\(quota.remainingExports(isPro: false) ?? 0) of 3 free exports remaining")
                        }
                    } icon: {
                        Image(systemName: store.isPro ? "checkmark.seal.fill" : "doc.richtext")
                    }
                    if !store.isPro {
                        Button("View FieldReport Pro") { isShowingPaywall = true }
                    }
                    Button("Restore purchases") {
                        Task { await store.restorePurchases() }
                    }
                    .disabled(store.isLoading)
                }

                Section("Privacy & data") {
                    NavigationLink("Privacy") {
                        ResourceTextView(title: "Privacy", resource: "Privacy")
                    }
                    NavigationLink("Third-party licenses") {
                        ThirdPartyLicensesView()
                    }
                    Label("Projects, photos, audio, and transcripts are stored locally. No account, analytics, advertising, or FieldReport backend is used.", systemImage: "hand.raised.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Label("Capture and editing work offline. Model downloads and App Store purchases require a connection.", systemImage: "wifi.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $isShowingPaywall) { PaywallView() }
            .alert("Purchase update", isPresented: Binding(
                get: { store.infoMessage != nil },
                set: { if !$0 { store.infoMessage = nil } }
            )) {
                Button("OK") { store.infoMessage = nil }
            } message: {
                Text(store.infoMessage ?? "")
            }
            .errorAlert($store.errorMessage)
        }
    }

    private var modelStatus: String {
        switch transcription.setupState {
        case .notDownloaded: "Not downloaded"
        case .downloading: "Downloading"
        case .downloaded: "Downloaded; load to enable"
        case .loading: "Preparing"
        case .ready: "Ready for offline use"
        case .failed: "Setup needs attention"
        }
    }
}

struct ResourceTextView: View {
    let title: String
    let resource: String
    @State private var text = "Loading…"

    var body: some View {
        ScrollView {
            Text(text)
                .font(.body)
                .foregroundStyle(Color.fieldInk)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(24)
        }
        .background(Color.fieldCanvas)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { loadText() }
    }

    private func loadText() {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "txt"),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            text = "This resource could not be opened from the app bundle."
            return
        }
        text = contents
    }
}

struct ThirdPartyLicensesView: View {
    var body: some View {
        List {
            Section {
                Text("FieldReport uses Argmax WhisperKit for on-device speech recognition. WhisperKit and its bundled attribution notices are reproduced in the following resources.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            NavigationLink("Argmax OSS — MIT License") {
                ResourceTextView(title: "Argmax MIT License", resource: "Argmax-LICENSE")
            }
            NavigationLink("Argmax OSS — Third-Party Notices") {
                ResourceTextView(title: "Third-Party Notices", resource: "Argmax-NOTICES")
            }
            Link("Argmax OSS source repository", destination: URL(string: "https://github.com/argmaxinc/argmax-oss-swift")!)
        }
        .navigationTitle("Third-Party Licenses")
        .navigationBarTitleDisplayMode(.inline)
    }
}
