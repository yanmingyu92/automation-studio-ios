import StoreKit
import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var quota: ExportQuota
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 42))
                            .foregroundStyle(Color.fieldTeal)
                            .accessibilityHidden(true)
                        Text("Keep every site moving")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Color.fieldInk)
                        Text((quota.canExport(isPro: false) ? "" : "You have used the three free report exports. ") + "FieldReport Pro unlocks unlimited professional PDFs while keeping capture, transcription, and editing on your device.")
                            .fixedSize(horizontal: false, vertical: true)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Label("Unlimited PDF report exports", systemImage: "doc.richtext")
                        Label("Monthly, yearly, or one-time purchase", systemImage: "creditcard")
                        Label("Restore across devices with your Apple Account", systemImage: "arrow.clockwise")
                    }
                    .font(.headline)
                    .foregroundStyle(Color.fieldInk)

                    if store.isLoading && store.products.isEmpty {
                        ProgressView("Loading App Store products…")
                            .frame(maxWidth: .infinity)
                    } else if store.products.isEmpty {
                        ContentUnavailableView(
                            "Products unavailable",
                            systemImage: "storefront",
                            description: Text("FieldReport Pro products are not currently available from the App Store. Purchases cannot be made until the configured App Store Connect products are available.")
                        )
                        Button("Check again") {
                            Task { await store.loadProducts() }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    } else {
                        VStack(spacing: 12) {
                            ForEach(store.products) { product in
                                Button {
                                    Task { await store.purchase(product) }
                                } label: {
                                    HStack(alignment: .center) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(product.displayName)
                                                .foregroundStyle(Color.fieldInk)
                                            Text(product.description)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        .fixedSize(horizontal: false, vertical: true)
                                        Spacer()
                                        if store.purchasingProductID == product.id {
                                            ProgressView()
                                        } else {
                                            Text(priceText(for: product))
                                                .font(.headline)
                                                .multilineTextAlignment(.trailing)
                                        }
                                    }
                                    .padding(16)
                                    .frame(maxWidth: .infinity, minHeight: 64)
                                    .background(.background, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.fieldTeal.opacity(0.35)))
                                }
                                .buttonStyle(.plain)
                                .disabled(store.purchasingProductID != nil)
                                .accessibilityHint("Purchases \(product.displayName) through the App Store")
                            }
                        }
                    }

                    Button("Restore purchases") {
                        Task { await store.restorePurchases() }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(store.isLoading || store.purchasingProductID != nil)

                    Text("Payment is handled by Apple. Paid subscriptions renew automatically unless cancelled in your Apple Account settings. Prices and availability come directly from the App Store.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link("Terms of Use (Apple Standard EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                        .font(.footnote)
                    Link("Privacy Policy", destination: URL(string: "https://yanmingyu92.github.io/automation-studio-ios/fieldreport/privacy.html")!)
                        .font(.footnote)
                }
                .padding(24)
            }
            .background(Color.fieldCanvas)
            .navigationTitle("FieldReport Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                if store.products.isEmpty { await store.loadProducts() }
                await store.refreshEntitlements()
            }
            .onChange(of: store.isPro) { _, isPro in
                if isPro { dismiss() }
            }
            .alert("Purchase update", isPresented: Binding(
                get: { store.infoMessage != nil },
                set: { if !$0 { store.infoMessage = nil } }
            )) {
                Button("OK") { store.infoMessage = nil }
            } message: {
                Text(store.infoMessage ?? "")
            }
            .errorAlert($store.errorMessage)
        }
    }

    /// App Store price, with the billing period for auto-renewing subscriptions.
    private func priceText(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return product.displayPrice }
        let unit: String
        switch period.unit {
        case .day: unit = "day"
        case .week: unit = "week"
        case .month: unit = "month"
        case .year: unit = "year"
        @unknown default: return product.displayPrice
        }
        return period.value == 1
            ? "\(product.displayPrice) / \(unit)"
            : "\(product.displayPrice) / \(period.value) \(unit)s"
    }
}
