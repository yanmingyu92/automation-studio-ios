import SwiftUI

struct PaperlessSettingsView: View {
    @State private var serverString: String
    @State private var token = ""
    @State private var hasSavedToken: Bool
    @State private var isTesting = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private let service = PaperlessService()

    init() {
        _serverString = State(initialValue: PaperlessConfiguration.serverURL?.absoluteString ?? "")
        _hasSavedToken = State(initialValue: (try? KeychainStore.paperlessToken()) != nil)
    }

    var body: some View {
        Form {
            Section {
                Label("Optional Integration", systemImage: "server.rack")
                    .font(.headline)
                Text("DocKeeper works fully offline. Paperless is contacted only when you test this connection or explicitly upload a document.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Server") {
                TextField("https://paperless.example.com", text: $serverString)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Paperless server URL")
                SecureField(hasSavedToken ? "Saved token; enter to replace" : "API token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Paperless API token")
                Text("The token is stored only in this device’s Keychain. Use HTTPS; HTTP is accepted only for local-network addresses and is never enabled globally.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    Task { await saveAndTest() }
                } label: {
                    if isTesting {
                        HStack { ProgressView(); Text("Testing connection…") }
                    } else {
                        Label("Save and Test Connection", systemImage: "network")
                    }
                }
                .disabled(isTesting || serverString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (!hasSavedToken && token.isEmpty))
            }

            if let configured = PaperlessConfiguration.serverURL {
                Section("Saved Connection") {
                    LabeledContent("Server") {
                        Text(configured.absoluteString).multilineTextAlignment(.trailing)
                    }
                    Label("API token saved in Keychain", systemImage: "key.fill")
                    Button("Disconnect and Remove Token", role: .destructive, action: disconnect)
                }
            }

            if let statusMessage {
                Section { Label(statusMessage, systemImage: "checkmark.circle").foregroundStyle(.green) }
            }
            if let errorMessage {
                Section { Label(errorMessage, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }

            Section("Upload Behavior") {
                Text("Upload sends only the selected PDF and its title using Paperless-ngx’s public post_document REST endpoint. A successful response records the processing task ID. It does not imply that consumption or indexing has finished.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Paperless-ngx")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func saveAndTest() async {
        isTesting = true
        statusMessage = nil
        errorMessage = nil
        defer { isTesting = false }
        do {
            let url = try PaperlessService.validatedServerURL(from: serverString)
            let savedToken = try KeychainStore.paperlessToken()
            guard let resolvedToken = token.isEmpty ? savedToken : token, !resolvedToken.isEmpty else {
                throw PaperlessError.notConfigured
            }
            try await service.testConnection(serverURL: url, token: resolvedToken)
            try KeychainStore.savePaperlessToken(resolvedToken)
            PaperlessConfiguration.saveServerURL(url)
            hasSavedToken = true
            token = ""
            serverString = url.absoluteString
            statusMessage = "Connection succeeded. Paperless returned an authenticated document-list response."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func disconnect() {
        do {
            try KeychainStore.deletePaperlessToken()
            PaperlessConfiguration.clear()
            hasSavedToken = false
            token = ""
            serverString = ""
            statusMessage = "The saved server and Keychain token were removed. Local documents were not changed."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
