import SwiftUI

struct PhotoDetailView: View {
    @Bindable var photo: FindingPhoto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let image = LocalFileStore.loadImage(fileName: photo.fileName) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityLabel(photo.caption.isEmpty ? "Inspection photo" : photo.caption)
                } else {
                    ContentUnavailableView("Photo unavailable", systemImage: "photo.badge.exclamationmark", description: Text("The image file is no longer available on this device."))
                }
                TextField("Photo caption", text: $photo.caption, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
                    .padding()
                    .background(.bar)
            }
            .background(.black)
            .navigationTitle("Inspection photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
