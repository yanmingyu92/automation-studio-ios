import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreManager.self) private var store

    private let features: [(icon: String, title: String, detail: String)] = [
        ("map.fill", "All 190 Journey gardens", "Every garden of the Terrace, Orchard and Estate packs, from 7×7 to 9×9."),
        ("infinity", "Endless mode", "Fresh, uniquely solvable gardens in any size and difficulty."),
        ("calendar", "The whole daily archive", "Replay every earlier daily garden, not only the last two."),
        ("hand.raised.fill", "Still no ads, no tracking", "One purchase. No subscription. Everything stays on your device.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Spacer(minLength: 64)
                        Text("The Full Garden")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                        Text("Pay once, keep it forever.")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NightSky())
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)

                    ForEach(features, id: \.title) { feature in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: feature.icon)
                                .font(.title3)
                                .frame(width: 32)
                                .foregroundStyle(Color.accentColor)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title).font(.headline)
                                Text(feature.detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }

                    purchaseArea

                    if let error = store.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Palette.conflict)
                    }
                    if let status = store.statusMessage {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button("Restore purchase") {
                        Task { await store.restorePurchases() }
                    }
                    .disabled(store.isPurchasing)

                    Text("Made by a solo developer. No ads, ever. The daily garden, the last two days and the free Journey gardens stay free.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .fontDesign(.rounded)
    }

    @ViewBuilder
    private var purchaseArea: some View {
        if store.isPro {
            Label("The Full Garden is unlocked.", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(Color.accentColor)
        } else if store.isLoading {
            HStack(spacing: 10) {
                ProgressView()
                Text("Contacting the App Store…").foregroundStyle(.secondary)
            }
        } else if store.products.isEmpty {
            Button("Check the App Store again") {
                Task { await store.loadProducts() }
            }
            .buttonStyle(.bordered)
        } else {
            ForEach(store.products) { product in
                Button {
                    Task { await store.purchase(product) }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(product.displayName).font(.headline)
                            Text("One-time purchase").font(.caption)
                        }
                        Spacer()
                        if store.isPurchasing {
                            ProgressView()
                        } else {
                            Text(product.displayPrice).font(.headline)
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isPurchasing)
                .accessibilityLabel("Buy \(product.displayName) for \(product.displayPrice), one-time purchase")
            }
        }
    }
}
