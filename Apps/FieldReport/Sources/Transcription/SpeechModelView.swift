import SwiftUI

struct SpeechModelView: View {
    @EnvironmentObject private var transcription: TranscriptionManager
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemoval = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("On-device speech recognition", systemImage: "waveform.badge.mic")
                            .font(.title2.bold())
                            .foregroundStyle(Color.fieldInk)
                        Text("WhisperKit converts your recordings to text locally. Manual notes and PDF export work without a model.")
                            .foregroundStyle(.secondary)
                    }

                    Picker("Model", selection: $transcription.selectedModel) {
                        ForEach(SpeechModel.allCases) { model in
                            Text(model.title).tag(model)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(transcription.setupState.isBusy || transcription.setupState == .ready)
                    Text(transcription.selectedModel.detail + ". Download size and processing time vary by device and model.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Picker("Spoken language", selection: $transcription.language) {
                        ForEach(TranscriptionLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .disabled(transcription.isTranscribing)

                    statusCard

                    if case .ready = transcription.setupState {
                        Button("Remove downloaded model", role: .destructive) { confirmRemoval = true }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(transcription.isTranscribing)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Label("A network connection is needed only for the initial model download.", systemImage: "arrow.down.circle")
                        Label("Long recordings are read in bounded 120-second chunks with a two-chunk buffer.", systemImage: "square.stack.3d.up")
                        Label("Keep the app open while transcribing. Background transcription is not guaranteed.", systemImage: "iphone")
                        Label("Review every transcript before using it in a report.", systemImage: "checkmark.bubble")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .background(Color.fieldCanvas)
            .navigationTitle("Transcription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .alert("Remove speech model?", isPresented: $confirmRemoval) {
                Button("Remove model", role: .destructive) { transcription.removeModel() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Transcription will be unavailable until you download and load a model again. Your projects and recordings are not affected.")
            }
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch transcription.setupState {
            case .notDownloaded:
                Label("Model not downloaded", systemImage: "arrow.down.circle")
                    .font(.headline)
                Text("Choose a model, then explicitly download it from the public WhisperKit model repository.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Download & prepare model") { transcription.prepareModel() }
                    .buttonStyle(PrimaryButtonStyle())
            case .downloading(let fraction):
                Label("Downloading model", systemImage: "arrow.down.circle.fill")
                    .font(.headline)
                ProgressView(value: fraction) {
                    Text("\(Int(fraction * 100))% downloaded")
                        .font(.subheadline)
                }
                Button("Cancel download", role: .cancel) { transcription.cancelSetup() }
                    .buttonStyle(SecondaryButtonStyle())
            case .downloaded:
                Label("Model downloaded", systemImage: "externaldrive.badge.checkmark")
                    .font(.headline)
                Text("Load the model to prepare it for this device. This may take a moment on first use.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Load model") { transcription.prepareModel() }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Remove downloaded model", role: .destructive) { confirmRemoval = true }
            case .loading:
                Label("Preparing on this device", systemImage: "gearshape.2")
                    .font(.headline)
                ProgressView()
                Button("Cancel setup", role: .cancel) { transcription.cancelSetup() }
                    .buttonStyle(SecondaryButtonStyle())
            case .ready:
                Label("Ready for offline transcription", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Color.fieldTeal)
                Text("The \(transcription.selectedModel.title) model is loaded. You can transcribe from any finding with a recording.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .failed(let message):
                Label("Model setup failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text("Check your network connection and free storage. You can retry or continue with manual findings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Try again") { transcription.prepareModel() }
                    .buttonStyle(PrimaryButtonStyle())
                if transcription.hasDownloadedModel {
                    Button("Remove downloaded model", role: .destructive) { confirmRemoval = true }
                }
            }
            if !transcription.statusMessage.isEmpty {
                Text(transcription.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
    }
}
