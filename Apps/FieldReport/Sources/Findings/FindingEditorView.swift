import AVFoundation
import PhotosUI
import SwiftData
import SwiftUI

struct FindingEditorView: View {
    @Bindable var finding: Finding
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var transcription: TranscriptionManager
    @StateObject private var player = AudioPlayer()

    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var isCameraPresented = false
    @State private var isCameraAccessDenied = false
    @State private var isPhotoPickerPresented = false
    @State private var didDeleteFinding = false
    @State private var isRecordingPresented = false
    @State private var isModelPresented = false
    @State private var selectedPhoto: FindingPhoto?
    @State private var photoToDelete: FindingPhoto?
    @State private var confirmRecordingReplacement = false
    @State private var confirmAudioDeletion = false
    @State private var confirmFindingDeletion = false
    @State private var confirmTranscriptReplacement = false
    @State private var errorMessage: String?
    @State private var infoMessage: String?
    @State private var transcriptionTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Finding") {
                TextField("Title", text: $finding.title, axis: .vertical)
                Picker("Category", selection: categoryBinding) {
                    ForEach(IssueCategory.allCases) { category in
                        Label(category.rawValue, systemImage: category.symbol).tag(category)
                    }
                }
                Picker("Severity", selection: severityBinding) {
                    ForEach(Severity.allCases) { severity in
                        Text(severity.rawValue).tag(severity)
                    }
                }
                Label(finding.severity.reportDescription, systemImage: finding.severity.symbol)
                    .font(.footnote)
                    .foregroundStyle(finding.severity.color)
            }

            Section {
                if finding.sortedPhotos.isEmpty {
                    Label("No photos attached", systemImage: "photo")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(finding.sortedPhotos) { photo in
                                VStack(spacing: 6) {
                                    Button { selectedPhoto = photo } label: {
                                        if let image = LocalFileStore.loadImage(fileName: photo.thumbnailFileName, thumbnail: true) {
                                            Image(uiImage: image)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 144, height: 112)
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                        } else {
                                            ContentUnavailableView("Unavailable", systemImage: "photo.badge.exclamationmark")
                                                .frame(width: 144, height: 112)
                                                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                                        }
                                    }
                                    .accessibilityLabel(photo.caption.isEmpty ? "View inspection photo" : "View photo: \(photo.caption)")
                                    .overlay(alignment: .topTrailing) {
                                        Button(role: .destructive) { photoToDelete = photo } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.title3)
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, .red)
                                        }
                                        .accessibilityLabel("Delete photo")
                                        .padding(5)
                                    }
                                    TextField("Caption", text: Binding(
                                        get: { photo.caption },
                                        set: { photo.caption = $0 }
                                    ))
                                    .font(.caption)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 144)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Menu {
                    Button {
                        photoSelection = []
                        requestCamera()
                    } label: {
                        Label("Take photo", systemImage: "camera")
                    }
                    Button {
                        isPhotoPickerPresented = true
                    } label: {
                        Label("Choose from library", systemImage: "photo.on.rectangle")
                    }
                } label: {
                    Label("Add photos", systemImage: "plus")
                }
                .accessibilityHint("Capture or import inspection evidence")
            } header: {
                Text("Photo evidence")
            } footer: {
                Text("Photos are resized for practical storage and kept on this device. Captions appear in the PDF.")
            }

            Section("Voice note") {
                if let fileName = finding.audioFileName, let url = try? LocalFileStore.audioURL(fileName: fileName) {
                    HStack(spacing: 14) {
                        Button { player.toggle(url: url) } label: {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 38))
                        }
                        .accessibilityLabel(player.isPlaying ? "Pause voice note" : "Play voice note")
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Recorded audio")
                                .font(.headline)
                            Text("\(formattedDuration(player.isPlaying || player.currentTime > 0 ? player.currentTime : finding.audioDuration)) / \(formattedDuration(finding.audioDuration))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) { confirmAudioDeletion = true } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete voice note")
                    }
                } else {
                    Label("No voice note recorded", systemImage: "mic")
                        .foregroundStyle(.secondary)
                }

                Button {
                    player.stop()
                    if finding.audioFileName == nil {
                        isRecordingPresented = true
                    } else {
                        confirmRecordingReplacement = true
                    }
                } label: {
                    Label(finding.audioFileName == nil ? "Record voice note" : "Replace voice note", systemImage: "mic.fill")
                }

                if finding.audioFileName != nil {
                    if transcription.isTranscribing && transcription.activeFindingID == finding.id {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Transcribing locally…", systemImage: "waveform")
                                .font(.headline)
                            ProgressView()
                            if !transcription.partialTranscript.isEmpty {
                                Text(transcription.partialTranscript)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(4)
                            }
                            Button("Cancel transcription", role: .cancel) {
                                transcription.cancelTranscription()
                                transcriptionTask?.cancel()
                            }
                        }
                    } else {
                        Button {
                            requestTranscription()
                        } label: {
                            Label(
                                transcription.setupState == .ready ? "Transcribe on this device" : "Set up on-device transcription",
                                systemImage: "text.badge.checkmark"
                            )
                        }
                        .disabled(transcription.isTranscribing)
                    }
                }
            }

            Section {
                TextField("Transcribed speech will appear here. You can also type or edit it.", text: $finding.transcript, axis: .vertical)
                    .lineLimit(5...16)
                if !finding.transcript.isEmpty {
                    Button("Insert transcript into observations") {
                        let text = finding.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                        finding.notes = finding.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? text
                            : finding.notes + "\n\n" + text
                        do {
                            try saveChanges()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .accessibilityHint("Copies the exact transcript without summarizing it")
                }
            } header: {
                Text("Voice transcript")
            } footer: {
                Text("Transcription can contain mistakes. Review it before inserting it into observations or exporting the report.")
            }

            Section("Observations") {
                TextField("Condition, measurements, location, and other findings", text: $finding.notes, axis: .vertical)
                    .lineLimit(6...16)
            }

            Section("Recommendation") {
                TextField("Repair, monitoring, or further evaluation recommended by you", text: $finding.recommendation, axis: .vertical)
                    .lineLimit(4...12)
            }

            Section {
                Button("Delete finding", role: .destructive) { confirmFindingDeletion = true }
            }
        }
        .navigationTitle(finding.title.isEmpty ? "Edit finding" : finding.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    do {
                        try saveChanges()
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            photoSelection = []
            Task { await importPhotos(items) }
        }
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $photoSelection, maxSelectionCount: 6, matching: .images)
        .onDisappear {
            player.stop()
            // Writing to a model after it was deleted and saved is a SwiftData fault.
            guard !didDeleteFinding else { return }
            finding.updatedAt = .now
            finding.project?.updatedAt = .now
            try? modelContext.save()
        }
        .sheet(isPresented: $isRecordingPresented) {
            RecordingSheet(onSaved: saveRecording)
        }
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraPicker { data in
                do {
                    try addPhoto(data: data)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $selectedPhoto) { photo in
            PhotoDetailView(photo: photo)
        }
        .sheet(isPresented: $isModelPresented) {
            SpeechModelView()
        }
        .alert("Replace this transcript?", isPresented: $confirmTranscriptReplacement) {
            Button("Replace transcript", role: .destructive) { startTranscription() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your edited transcript will be replaced by the new on-device transcription.")
        }
        .alert("Replace voice note?", isPresented: $confirmRecordingReplacement) {
            Button("Record replacement", role: .destructive) { isRecordingPresented = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The previous audio file will be deleted after the new recording is saved. The transcript will remain until you choose to replace it.")
        }
        .alert("Delete voice note?", isPresented: $confirmAudioDeletion) {
            Button("Delete recording", role: .destructive) { deleteAudio() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The audio file will be permanently deleted. The written transcript will remain.")
        }
        .alert("Delete photo?", isPresented: Binding(
            get: { photoToDelete != nil },
            set: { if !$0 { photoToDelete = nil } }
        )) {
            Button("Delete photo", role: .destructive) {
                if let photoToDelete { deletePhoto(photoToDelete) }
            }
            Button("Cancel", role: .cancel) { photoToDelete = nil }
        }
        .alert("Delete finding?", isPresented: $confirmFindingDeletion) {
            Button("Delete finding", role: .destructive) { deleteFinding() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes the finding, its photos, and its recording.")
        }
        .alert("Camera access is off", isPresented: $isCameraAccessDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Allow camera access for FieldReport in Settings to take inspection photos. You can still choose photos from your library.")
        }
        .alert("Update", isPresented: Binding(
            get: { infoMessage != nil },
            set: { if !$0 { infoMessage = nil } }
        )) {
            Button("OK") { infoMessage = nil }
        } message: {
            Text(infoMessage ?? "")
        }
        .errorAlert($errorMessage)
        .errorAlert($player.errorMessage)
    }

    private var categoryBinding: Binding<IssueCategory> {
        Binding(get: { finding.category }, set: { finding.category = $0 })
    }

    private var severityBinding: Binding<Severity> {
        Binding(get: { finding.severity }, set: { finding.severity = $0 })
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw LocalFileStore.StoreError.invalidImage
                }
                try addPhoto(data: data)
            } catch {
                errorMessage = "A photo could not be imported. \(error.localizedDescription)"
            }
        }
    }

    private func requestCamera() {
        guard CameraPicker.isAvailable else {
            errorMessage = "This device does not have an available camera. You can choose photos from your library instead."
            return
        }
        // The system camera shows only a black preview when access is denied, so check before presenting it.
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isCameraPresented = true
        case .notDetermined:
            Task {
                if await AVCaptureDevice.requestAccess(for: .video) {
                    isCameraPresented = true
                } else {
                    isCameraAccessDenied = true
                }
            }
        default:
            isCameraAccessDenied = true
        }
    }

    private func addPhoto(data: Data) throws {
        let stored = try LocalFileStore.persistImage(data: data)
        let photo = FindingPhoto(fileName: stored.fileName, thumbnailFileName: stored.thumbnailFileName)
        photo.finding = finding
        modelContext.insert(photo)
        do {
            try saveChanges()
        } catch {
            modelContext.delete(photo)
            LocalFileStore.deletePhoto(photo)
            throw error
        }
    }

    private func saveRecording(_ audio: RecordedAudio) {
        // The previous file is about to be deleted: release it from playback and any running transcription.
        player.stop()
        if transcription.activeFindingID == finding.id { transcription.cancelTranscription() }
        let oldFileName = finding.audioFileName
        let oldDuration = finding.audioDuration
        finding.audioFileName = audio.fileName
        finding.audioDuration = audio.duration
        do {
            try saveChanges()
            LocalFileStore.deleteAudio(fileName: oldFileName)
        } catch {
            finding.audioFileName = oldFileName
            finding.audioDuration = oldDuration
            LocalFileStore.deleteAudio(fileName: audio.fileName)
            errorMessage = "The recording could not be attached. \(error.localizedDescription)"
        }
    }

    private func requestTranscription() {
        guard transcription.setupState == .ready else {
            isModelPresented = true
            return
        }
        if finding.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            startTranscription()
        } else {
            confirmTranscriptReplacement = true
        }
    }

    private func startTranscription() {
        transcriptionTask?.cancel()
        transcriptionTask = Task { [finding] in
            do {
                let text = try await transcription.transcribe(audioFileName: finding.audioFileName, findingID: finding.id)
                // The finding or its project may have been deleted while the transcription ran.
                guard !Task.isCancelled, !didDeleteFinding, !finding.isDeleted, finding.modelContext != nil else { return }
                if text.isEmpty {
                    infoMessage = "No speech was detected in this recording. Try a clearer recording or type the finding manually."
                } else {
                    finding.transcript = text
                    try saveChanges()
                }
            } catch is CancellationError {
                infoMessage = "Transcription was cancelled. Your existing transcript was not changed."
            } catch {
                errorMessage = "Transcription failed. \(error.localizedDescription)"
            }
        }
    }

    private func deleteAudio() {
        player.stop()
        if transcription.activeFindingID == finding.id { transcription.cancelTranscription() }
        let oldFileName = finding.audioFileName
        let oldDuration = finding.audioDuration
        finding.audioFileName = nil
        finding.audioDuration = 0
        do {
            try saveChanges()
            LocalFileStore.deleteAudio(fileName: oldFileName)
        } catch {
            finding.audioFileName = oldFileName
            finding.audioDuration = oldDuration
            errorMessage = "The recording could not be deleted. \(error.localizedDescription)"
        }
    }

    private func deletePhoto(_ photo: FindingPhoto) {
        let fileName = photo.fileName
        let thumbnailFileName = photo.thumbnailFileName
        modelContext.delete(photo)
        do {
            try saveChanges()
            if let url = try? LocalFileStore.photoURL(fileName: fileName) {
                try? FileManager.default.removeItem(at: url)
            }
            if let url = try? LocalFileStore.photoURL(fileName: thumbnailFileName, thumbnail: true) {
                try? FileManager.default.removeItem(at: url)
            }
        } catch {
            errorMessage = "The photo could not be deleted. \(error.localizedDescription)"
        }
        photoToDelete = nil
    }

    private func deleteFinding() {
        player.stop()
        if transcription.activeFindingID == finding.id { transcription.cancelTranscription() }
        let audioFileName = finding.audioFileName
        let media = finding.photos.map { ($0.fileName, $0.thumbnailFileName) }
        modelContext.delete(finding)
        do {
            try modelContext.save()
            didDeleteFinding = true
            LocalFileStore.deleteAudio(fileName: audioFileName)
            for (fileName, thumbnailFileName) in media {
                if let url = try? LocalFileStore.photoURL(fileName: fileName) {
                    try? FileManager.default.removeItem(at: url)
                }
                if let url = try? LocalFileStore.photoURL(fileName: thumbnailFileName, thumbnail: true) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
            dismiss()
        } catch {
            errorMessage = "The finding could not be deleted. \(error.localizedDescription)"
        }
    }

    private func saveChanges() throws {
        finding.updatedAt = .now
        finding.project?.updatedAt = .now
        try modelContext.save()
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
