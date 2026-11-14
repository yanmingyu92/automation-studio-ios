import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class StoreManager {
    static let productIDs = ["lanternfold.garden.lifetime"]

    private(set) var products: [Product] = []
    private(set) var isPro = false
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
            // Entitlements are local; check them first so a purchase unlocks even while offline.
            await refreshEntitlements()
            await loadProducts()
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
                statusMessage = "The Full Garden purchase is not available from the App Store yet. Daily puzzles and the free Journey packs remain playable."
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
        var owned = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verified(result),
                  Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            owned = true
        }
        isPro = owned
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
                statusMessage = "The Full Garden is unlocked on this Apple Account."
            case .userCancelled:
                statusMessage = "Purchase cancelled."
            case .pending:
                statusMessage = "The purchase is pending approval. Lanternfold will unlock when Apple confirms it."
            @unknown default:
                statusMessage = "The App Store returned an unrecognized purchase state."
            }
        } catch {
            errorMessage = "Purchase was not completed: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        errorMessage = nil
        statusMessage = nil
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            statusMessage = isPro ? "Your Full Garden purchase was restored." : "No Full Garden purchase was found for this Apple Account."
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
