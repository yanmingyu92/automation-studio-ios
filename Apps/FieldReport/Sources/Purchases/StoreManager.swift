import StoreKit
import SwiftUI

@MainActor
final class StoreManager: ObservableObject {
    static let productIDs = [
        "fieldreport.pro.monthly",
        "fieldreport.pro.yearly",
        "fieldreport.pro.lifetime"
    ]

    enum StoreError: LocalizedError {
        case unverifiedPurchase

        var errorDescription: String? {
            "Apple could not verify this purchase. No Pro access was granted. Try again or restore purchases."
        }
    }

    @Published private(set) var products: [Product] = []
    @Published private(set) var isPro = false
    @Published private(set) var isLoading = false
    @Published private(set) var purchasingProductID: String?
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    private var transactionUpdates: Task<Void, Never>?

    init() {
        transactionUpdates = Task { [weak self] in
            await self?.listenForTransactions()
        }
        Task { [weak self] in
            // Launching offline must not raise an unprompted error; the paywall reports load failures.
            await self?.loadProducts(reportErrors: false)
            await self?.refreshEntitlements()
        }
    }

    deinit {
        transactionUpdates?.cancel()
    }

    func loadProducts(reportErrors: Bool = true) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            products = Self.productIDs.compactMap { id in loaded.first(where: { $0.id == id }) }
        } catch {
            guard reportErrors else { return }
            errorMessage = "App Store products could not be loaded. \(error.localizedDescription)"
        }
    }

    func purchase(_ product: Product) async {
        guard purchasingProductID == nil else { return }
        purchasingProductID = product.id
        defer { purchasingProductID = nil }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verifiedTransaction(from: verification)
                await transaction.finish()
                await refreshEntitlements()
                if Self.productIDs.contains(transaction.productID) {
                    infoMessage = "FieldReport Pro is active. Thank you."
                }
            case .pending:
                infoMessage = "The purchase is pending Apple approval. Pro will activate after it is approved."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            infoMessage = isPro ? "Your Pro purchase was restored." : "No active FieldReport Pro purchase was found for this Apple Account."
        } catch StoreKitError.userCancelled {
            // The Apple Account sign-in prompt was dismissed; nothing failed.
        } catch {
            errorMessage = "Purchases could not be restored. \(error.localizedDescription)"
        }
    }

    func refreshEntitlements() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verifiedTransaction(from: result) else { continue }
            if Self.productIDs.contains(transaction.productID), transaction.revocationDate == nil {
                entitled = true
            }
        }
        isPro = entitled
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard let transaction = try? verifiedTransaction(from: result) else { continue }
            await transaction.finish()
            if Self.productIDs.contains(transaction.productID) {
                await refreshEntitlements()
            }
        }
    }

    private func verifiedTransaction(from result: VerificationResult<StoreKit.Transaction>) throws -> StoreKit.Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified:
            throw StoreError.unverifiedPurchase
        }
    }
}
