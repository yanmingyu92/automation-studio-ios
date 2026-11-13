import SwiftUI

struct RecordingSheet: View {
    let onSaved: (RecordedAudio) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = AudioRecorder()

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                VStack(spacing: 8) {
                    Text(recorder.isRecording ? "Recording inspection note" : "Voice inspection note")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(recorder.isRecording ? "Describe the location, condition, and recommended next step." : "Start when you are ready. Your audio stays on this device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal)

                Text(formattedDuration(recorder.duration))
                    .font(.system(.largeTitle, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Color.fieldInk)
                    .accessibilityLabel("Recording duration \(formattedDuration(recorder.duration))")

                HStack(alignment: .center, spacing: 5) {
                    ForEach(0..<25, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.fieldTeal)
                            .frame(width: 5, height: barHeight(index))
                            .animation(.easeOut(duration: 0.08), value: recorder.audioLevel)
                    }
                }
                .frame(height: 84)
                .accessibilityHidden(true)

                if recorder.isRecording {
                    Button {
                        do {
                            let audio = try recorder.stop()
                            onSaved(audio)
                            dismiss()
                        } catch {
                            recorder.errorMessage = error.localizedDescription
                        }
                    } label: {
                        Label("Stop & save", systemImage: "stop.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 32)
                    Button("Discard recording", role: .destructive) {
                        recorder.cancel()
                        dismiss()
                    }
                } else {
                    Button {
                        Task { await recorder.start() }
                    } label: {
                        Label("Start recording", systemImage: "record.circle")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 32)
                }

                if recorder.permissionDenied {
                    Link("Open microphone settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                        .font(.headline)
                }

                Label("Keep FieldReport open. Recording stops and saves if the app is interrupted or moves to the background. Maximum recording length is two hours.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                Spacer()
            }
            .padding(.top, 32)
            .padding(.bottom)
            .background(Color.fieldCanvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        recorder.cancel()
                        dismiss()
                    }
                }
            }
            .onAppear {
                recorder.onAutomaticFinish = { result in
                    if case .success(let audio) = result {
                        onSaved(audio)
                        dismiss()
                    }
                }
            }
            .onDisappear { recorder.cancel() }
            .errorAlert($recorder.errorMessage)
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(recorder.isRecording)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        let shape = 0.35 + 0.65 * abs(sin(Double(index) * 1.37))
        return 10 + CGFloat(recorder.audioLevel) * 68 * shape
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
