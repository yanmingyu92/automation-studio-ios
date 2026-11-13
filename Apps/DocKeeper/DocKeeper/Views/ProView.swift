import StoreKit
import SwiftUI

struct ProView: View {
    @EnvironmentObject private var store: StoreManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 14) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        Text("Keep every important document")
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                        Text("Pro removes the 30-document limit and enables optional Paperless-ngx uploads. Local OCR, search, PDF export, and reminders work without a server.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }

                if store.isPro {
                    Section {
                        Label("DocKeeper Pro is active", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else {
                    Section("Choose Pro") {
                        if store.isLoading && store.products.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView("Loading App Store products…")
                                Spacer()
                            }
                        }
                        ForEach(store.products) { product in
                            Button {
                                Task { await store.purchase(product) }
                            } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(product.displayName).font(.headline)
                                        Text(product.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if store.purchasingProductID == product.id {
                                        ProgressView()
                                    } else {
                                        Text(product.displayPrice).font(.headline)
                                    }
                                }
                            }
                            .disabled(store.purchasingProductID != nil)
                            .accessibilityHint("Purchases this product through the App Store")
                        }
                        if !store.isLoading && store.products.isEmpty {
                            Text("Pro products are not available yet. They must be configured in App Store Connect before purchases can be offered. No payment has been taken.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Button("Restore Purchases") {
                            Task { await store.restorePurchases() }
                        }
                        .disabled(store.isLoading || store.purchasingProductID != nil)
                    }
                }

                if let message = store.statusMessage {
                    Section { Text(message).foregroundStyle(.secondary) }
                }
                if let message = store.errorMessage {
                    Section { Text(message).foregroundStyle(.red) }
                }

                Section {
                    Text("Your documents are never deleted or locked because you do not subscribe. Existing documents remain available if a subscription ends.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("DocKeeper Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await store.updateEntitlements() }
        }
    }
}
