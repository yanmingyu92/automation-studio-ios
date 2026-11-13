import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreManager.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 52))
                            .foregroundStyle(.orange)
                            .accessibilityHidden(true)
                        Text("Progress with a plan")
                            .font(.largeTitle.weight(.bold))
                        Text("BarbellLedger Pro adds transparent periodized progression and deeper analytics. Fast workout logging, routines, CSV migration, rest timers, and plate calculations stay free.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        FeatureRow(icon: "arrow.up.forward.circle.fill", title: "Rule-based progression", detail: "Configure rep ranges, RPE ceilings, weekly increases, and deload blocks. Every suggestion explains its inputs and can be overridden.")
                        FeatureRow(icon: "chart.xyaxis.line", title: "Advanced analytics", detail: "Explore working-volume trends, estimated one-rep max by exercise, and personal-record frequency.")
                        FeatureRow(icon: "iphone.and.arrow.forward.inward", title: "Private by design", detail: "No account, ads, analytics SDK, social feed, or workout-data server.")
                    }

                    if store.isPro {
                        Label("BarbellLedger Pro is active", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                        if let activeProductID = store.activeProductID {
                            Text(activeProductID == "barbellledger.pro.lifetime" ? "Lifetime entitlement" : "Yearly subscription entitlement")
                                .foregroundStyle(.secondary)
                        }
                    } else if store.isLoading && store.products.isEmpty {
                        HStack { ProgressView(); Text("Loading App Store products…") }
                    } else if store.products.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Purchases are not available yet", systemImage: "exclamationmark.icloud")
                                .font(.headline)
                            Text("BarbellLedger could not find its live App Store Connect products. No simulated purchase will be offered. You can keep using every free feature and retry later.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Button("Retry Loading Products") { Task { await store.loadProducts() } }
                                .buttonStyle(.bordered)
                        }
                    } else {
                        VStack(spacing: 12) {
                            ForEach(store.products) { product in
                                Button {
                                    Task { await store.purchase(product) }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(product.id == "barbellledger.pro.lifetime" ? "Lifetime" : "Yearly")
                                                .font(.headline)
                                            Text(product.description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .multilineTextAlignment(.leading)
                                        }
                                        Spacer()
                                        if store.isPurchasing { ProgressView() }
                                        Text(product.displayPrice).font(.headline)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                                }
                                .buttonStyle(.plain)
                                .disabled(store.isPurchasing)
                                .accessibilityHint("Starts an App Store purchase. Confirmation is required.")
                            }
                        }
                    }

                    if let statusMessage = store.statusMessage {
                        Label(statusMessage, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let errorMessage = store.errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button("Restore Purchases") { Task { await store.restorePurchases() } }
                        .disabled(store.isPurchasing)
                        .frame(maxWidth: .infinity)
                    Text("Purchases and restoration are handled by Apple with your Apple Account. An active, unrevoked entitlement is required for Pro features. No health or coaching outcome is promised.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("BarbellLedger Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { await store.refreshEntitlements() }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
