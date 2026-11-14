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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onEdit: () -> Void

    var body: some View {
        Group {
            if timer.endDate != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = timer.remaining(at: context.date)
                    let stacked = dynamicTypeSize.isAccessibilitySize
                    let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 14))
                    layout {
                        HStack(spacing: 14) {
                            Image(systemName: remaining > 0 ? "timer" : "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.mint)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading) {
                                Text(remaining > 0 ? "Resting" : "Rest complete")
                                    .font(.headline)
                                Text(remaining.clockString)
                                    .font(.title3.monospacedDigit().weight(.bold))
                                    .contentTransition(.numericText())
                            }
                        }
                        .accessibilityElement(children: .combine)
                        if !stacked { Spacer(minLength: 0) }
                        // Borderless so each button has its own tap target; default-style buttons
                        // sharing one List row all fire when the row is tapped.
                        HStack(spacing: 14) {
                            Button("Change", action: onEdit)
                            Button("Stop", role: .destructive) { timer.stop() }
                        }
                        .buttonStyle(.borderless)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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
