import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class StoreManager {
    static let productIDs = ["barbellledger.pro.yearly", "barbellledger.pro.lifetime"]

    private(set) var products: [Product] = []
    private(set) var isPro = false
    private(set) var activeProductID: String?
    var isLoading = false
    var isPurchasing = false
    var errorMessage: String?
    var statusMessage: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(transactionResult: result)
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    isolated deinit {
        updatesTask?.cancel()
    }

    func loadProducts() async {
        isLoading = true
        errorMessage = nil
        do {
            products = try await Product.products(for: Self.productIDs).sorted { $0.id < $1.id }
            if products.isEmpty {
                statusMessage = "App Store products are not available yet. Logging and all free features remain available."
            } else {
                statusMessage = nil
            }
        } catch {
            products = []
            errorMessage = "Could not load App Store products: \(error.localizedDescription)"
        }
        isLoading = false
    }

    func refreshEntitlements() async {
        var entitlement: String?
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verified(result),
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            entitlement = transaction.productID
            if transaction.productID == "barbellledger.pro.lifetime" { break }
        }
        activeProductID = entitlement
        isPro = entitlement != nil
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        errorMessage = nil
        statusMessage = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                await transaction.finish()
                await refreshEntitlements()
                statusMessage = "BarbellLedger Pro is active on this Apple Account."
            case .userCancelled:
                statusMessage = "Purchase cancelled."
            case .pending:
                statusMessage = "The purchase is pending approval. BarbellLedger will unlock when Apple confirms it."
            @unknown default:
                statusMessage = "The App Store returned an unrecognized purchase state."
            }
        } catch {
            errorMessage = "Purchase was not completed: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        isPurchasing = true
        errorMessage = nil
        statusMessage = nil
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            statusMessage = isPro ? "Your BarbellLedger Pro purchase was restored." : "No current BarbellLedger Pro entitlement was found for this Apple Account."
        } catch StoreKitError.userCancelled {
            statusMessage = "Restore cancelled."
        } catch {
            errorMessage = "Could not restore purchases: \(error.localizedDescription)"
        }
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard let transaction = try? verified(transactionResult) else { return }
        await transaction.finish()
        await refreshEntitlements()
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error): throw error
        case .verified(let value): return value
        }
    }
}
