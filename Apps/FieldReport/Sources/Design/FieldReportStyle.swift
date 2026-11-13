import SwiftUI

extension Color {
    static let fieldInk = Color("FieldInk")
    static let fieldTeal = Color("FieldTeal")
    static let fieldAmber = Color("FieldAmber")
    static let fieldCanvas = Color("FieldCanvas")
}

extension Severity {
    var color: Color {
        switch self {
        case .observation: .blue
        case .low: .green
        case .medium: .orange
        case .high: .red
        case .urgent: .purple
        }
    }

    var symbol: String {
        switch self {
        case .observation: "eye"
        case .low: "checkmark.circle"
        case .medium: "exclamationmark.circle"
        case .high: "exclamationmark.triangle"
        case .urgent: "exclamationmark.octagon"
        }
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct StatusPill: View {
    let title: String
    let color: Color
    var symbol: String?

    var body: some View {
        Label(title, systemImage: symbol ?? "circle.fill")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(color)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityLabel(title)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(.white)
            .background(Color.fieldTeal.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 14))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(Color.fieldTeal)
            .background(Color.fieldTeal.opacity(configuration.isPressed ? 0.2 : 0.1), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ErrorAlert: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert("Something needs attention", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }
}

extension View {
    func errorAlert(_ message: Binding<String?>) -> some View {
        modifier(ErrorAlert(message: message))
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let onCompletion: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onCompletion(completed)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
