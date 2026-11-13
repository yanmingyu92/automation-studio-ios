import SwiftUI

struct EmptyState: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let systemImage: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(value)
                .font(.title2.weight(.bold))
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

struct LockedFeature: View {
    let title: String
    let message: String
    let action: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "lock.open.fill")
        } description: {
            Text(message)
        } actions: {
            Button("View BarbellLedger Pro", action: action)
                .buttonStyle(.borderedProminent)
        }
    }
}

struct PRLabel: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "trophy.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .accessibilityLabel("Personal record: \(text)")
    }
}

struct RestTimerBanner: View {
    @Environment(RestTimerManager.self) private var timer
    let onEdit: () -> Void

    var body: some View {
        Group {
            if timer.endDate != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 14) {
                        Image(systemName: timer.isRunning ? "timer" : "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.mint)
                        VStack(alignment: .leading) {
                            Text(timer.isRunning ? "Resting" : "Rest complete")
                                .font(.headline)
                            Text(timer.remaining(at: context.date).clockString)
                                .font(.title3.monospacedDigit().weight(.bold))
                                .contentTransition(.numericText())
                        }
                        Spacer()
                        Button("Change", action: onEdit)
                        Button("Stop", role: .destructive) { timer.stop() }
                    }
                    .padding()
                    .background(.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityElement(children: .contain)
                }
            }
            if let message = timer.message {
                Label(message, systemImage: "bell.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension SetKind {
    var color: Color {
        switch self {
        case .working: .accentColor
        case .warmup: .blue
        case .drop: .purple
        case .failure: .red
        }
    }
}
