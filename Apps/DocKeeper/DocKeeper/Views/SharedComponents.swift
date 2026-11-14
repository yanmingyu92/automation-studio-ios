import SwiftUI

struct DocumentThumbnail: View {
    let data: Data?
    let category: DocumentCategory
    var width: CGFloat = 58
    var height: CGFloat = 76

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color(.secondarySystemBackground)
                    Image(systemName: category.systemImage)
                        .font(.title2)
                        .foregroundStyle(.tint)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

struct ExpiryBadge: View {
    let date: Date
    let label: String

    private var state: (text: String, color: Color) {
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0
        if days < 0 { return ("Expired", .red) }
        if days == 0 { return ("Due today", .orange) }
        if days <= 30 { return ("\(days) days left", .orange) }
        return (label, .secondary)
    }

    var body: some View {
        Text(state.text)
            .font(.caption.weight(.medium))
            .foregroundStyle(state.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(state.color.opacity(0.1), in: Capsule())
    }
}

struct OptionalDateRow: View {
    let title: String
    @Binding var isIncluded: Bool
    @Binding var date: Date
    var range: ClosedRange<Date>? = nil

    var body: some View {
        Toggle(title, isOn: $isIncluded)
        if isIncluded {
            if let range {
                DatePicker(title, selection: $date, in: range, displayedComponents: .date)
            } else {
                DatePicker(title, selection: $date, displayedComponents: .date)
            }
        }
    }
}

struct ProcessingOverlay: View {
    let message: String
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            VStack(spacing: 18) {
                ProgressView()
                    .controlSize(.large)
                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Text recognition stays on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Cancel", role: .cancel, action: onCancel)
            }
            .padding(28)
            .frame(maxWidth: 330)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message)
        .accessibilityAddTraits(.isModal)
    }
}

struct MetadataRow: View {
    let title: String
    let value: String

    var body: some View {
        LabeledContent(title) {
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}
