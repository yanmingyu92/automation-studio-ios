import Foundation
import StoreKit
import SwiftUI

enum DocKeeperStoreError: LocalizedError {
    case failedVerification

    var errorDescription: String? {
        "The App Store transaction could not be verified."
    }
}

@MainActor
final class StoreManager: ObservableObject {
    static let yearlyProductID = "dockeeper.pro.yearly"
    static let lifetimeProductID = "dockeeper.pro.lifetime"
    static let freeDocumentLimit = 30

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro = false
    @Published private(set) var isLoading = false
    @Published private(set) var purchasingProductID: String?
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.updateEntitlements()
            }
        }
        Task {
            await loadProducts()
            await updateEntitlements()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: [Self.yearlyProductID, Self.lifetimeProductID])
                .sorted { $0.id == Self.yearlyProductID && $1.id != Self.yearlyProductID }
            errorMessage = nil
        } catch {
            products = []
            errorMessage = "App Store products could not be loaded: \(error.localizedDescription)"
        }
    }

    func updateEntitlements() async {
        var activePurchase = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.yearlyProductID || transaction.productID == Self.lifetimeProductID,
                  transaction.revocationDate == nil else { continue }
            activePurchase = true
        }
        isPro = activePurchase
    }

    func purchase(_ product: Product) async {
        purchasingProductID = product.id
        errorMessage = nil
        statusMessage = nil
        defer { purchasingProductID = nil }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    throw DocKeeperStoreError.failedVerification
                }
                await transaction.finish()
                await updateEntitlements()
                statusMessage = "DocKeeper Pro is active. Thank you."
            case .userCancelled:
                break
            case .pending:
                statusMessage = "The purchase is pending approval. Pro activates after the App Store approves it."
            @unknown default:
                errorMessage = "The App Store returned an unknown purchase result."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await updateEntitlements()
            statusMessage = isPro ? "Your Pro purchase was restored." : "No active DocKeeper Pro purchase was found."
        } catch StoreKitError.userCancelled {
            // The user dismissed the App Store sign-in prompt; this is not an error.
        } catch {
            errorMessage = "Purchases could not be restored: \(error.localizedDescription)"
        }
    }
}
