import Foundation
import StoreKit
import UIKit

enum PremiumStoreError: LocalizedError, Equatable {
    case productUnavailable
    case timedOut
    case paymentNotAllowed
    case verificationFailed(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .productUnavailable: "商品暂不可用"
        case .timedOut: "加载失败，请点击重试"
        case .paymentNotAllowed: "此设备或账户已限制 App 内购买"
        case .verificationFailed: "购买未能验证"
        case .unknown: "购买失败，请稍后再试"
        }
    }
}

enum PremiumPurchaseOutcome {
    case success(PremiumTransactionPayload)
    case pending
    case userCancelled
}

enum PremiumRefundRequestStatus {
    case success
    case userCancelled
    case error(String)
}

protocol PremiumStoreKitClient {
    func canMakePayments() async -> Bool
    func products(for productIDs: [String]) async throws -> [PremiumStoreProduct]
    func purchase(productID: String, appAccountToken: UUID?) async throws -> PremiumPurchaseOutcome
    func restorePurchases() async throws
    func currentEntitlements() async -> [PremiumTransactionPayload]
    func unfinishedTransactions() async -> [PremiumTransactionPayload]
    func transactionUpdates() -> AsyncStream<PremiumTransactionPayload>
    func beginRefundRequest(productID: String, in scene: UIWindowScene) async -> PremiumRefundRequestStatus
}

actor StoreKitPremiumClient: PremiumStoreKitClient {
    private var productsByID: [String: Product] = [:]

    func canMakePayments() async -> Bool {
        AppStore.canMakePayments
    }

    func products(for productIDs: [String]) async throws -> [PremiumStoreProduct] {
        let products = try await Product.products(for: productIDs)
        for product in products {
            productsByID[product.id] = product
        }
        return products.map {
            PremiumStoreProduct(
                id: $0.id,
                displayName: $0.displayName,
                description: $0.description,
                displayPrice: $0.displayPrice
            )
        }
    }

    func purchase(productID: String, appAccountToken: UUID? = nil) async throws -> PremiumPurchaseOutcome {
        let product = try await product(for: productID)
        let result: Product.PurchaseResult
        if let appAccountToken {
            result = try await product.purchase(options: [.appAccountToken(appAccountToken)])
        } else {
            result = try await product.purchase()
        }

        switch result {
        case .success(let verification):
            return .success(Self.payload(from: verification))
        case .pending:
            return .pending
        case .userCancelled:
            return .userCancelled
        @unknown default:
            throw PremiumStoreError.unknown("Unknown StoreKit purchase result")
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
    }

    func currentEntitlements() async -> [PremiumTransactionPayload] {
        var payloads: [PremiumTransactionPayload] = []
        for await result in Transaction.currentEntitlements {
            payloads.append(Self.payload(from: result))
        }
        return payloads
    }

    func unfinishedTransactions() async -> [PremiumTransactionPayload] {
        var payloads: [PremiumTransactionPayload] = []
        for await result in Transaction.unfinished {
            payloads.append(Self.payload(from: result))
        }
        return payloads
    }

    nonisolated func transactionUpdates() -> AsyncStream<PremiumTransactionPayload> {
        AsyncStream { continuation in
            let task = Task.detached {
                for await result in Transaction.updates {
                    continuation.yield(Self.payload(from: result))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func beginRefundRequest(productID: String, in scene: UIWindowScene) async -> PremiumRefundRequestStatus {
        guard let latest = await Transaction.latest(for: productID) else {
            return .error("No transaction found")
        }

        switch latest {
        case .verified(let transaction):
            do {
                let status = try await transaction.beginRefundRequest(in: scene)
                switch status {
                case .success:
                    return .success
                case .userCancelled:
                    return .userCancelled
                @unknown default:
                    return .error("Unknown refund status")
                }
            } catch {
                return .error(String(describing: error))
            }
        case .unverified(_, let error):
            return .error(String(describing: error))
        }
    }

    private func product(for id: String) async throws -> Product {
        if let product = productsByID[id] {
            return product
        }
        let products = try await Product.products(for: [id])
        guard let product = products.first else {
            throw PremiumStoreError.productUnavailable
        }
        productsByID[id] = product
        return product
    }

    private nonisolated static func payload(from result: VerificationResult<Transaction>) -> PremiumTransactionPayload {
        switch result {
        case .verified(let transaction):
            let ownership: PremiumOwnershipType
            switch transaction.ownershipType {
            case .purchased:
                ownership = .purchased
            case .familyShared:
                ownership = .familyShared
            default:
                ownership = .unknown
            }
            let verified = PremiumVerifiedTransaction(
                id: String(transaction.id),
                productID: transaction.productID,
                ownershipType: ownership,
                revocationDate: transaction.revocationDate,
                expirationDate: transaction.expirationDate,
                purchasedAt: transaction.purchaseDate
            )
            return .verified(verified) {
                await transaction.finish()
            }
        case .unverified(let transaction, let error):
            return .unverified(productID: transaction.productID, reason: String(describing: error))
        }
    }
}

@MainActor
final class PremiumEntitlementStore: ObservableObject {
    @Published private(set) var productState: PremiumProductLoadState = .idle
    @Published private(set) var accessState: PremiumAccessState = .locked
    @Published private(set) var canMakePayments = true
    @Published private(set) var statusMessage: String?
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    @Published private(set) var isRequestingRefund = false
    @Published var activeNotice: PremiumNoticeKind?
    @Published private(set) var refundRequestedAt: Date?

    private let client: PremiumStoreKitClient
    private let verifier: EntitlementVerifier
    private let userDefaults: UserDefaults
    private let appGroupDefaults: UserDefaults?
    private var updatesTask: Task<Void, Never>?
    private let productLoadTimeoutNanoseconds: UInt64 = 8_000_000_000

    var isPremiumUnlocked: Bool {
        accessState == .unlocked
    }

    var displayPrice: String {
        productState.product?.displayPrice ?? PremiumProductID.fallbackDisplayPrice
    }

    init(
        client: PremiumStoreKitClient = StoreKitPremiumClient(),
        verifier: EntitlementVerifier = PassThroughEntitlementVerifier(),
        userDefaults: UserDefaults = .standard,
        appGroupDefaults: UserDefaults? = UserDefaults(suiteName: WNFShared.appGroupID),
        startsAutomatically: Bool = true
    ) {
        self.client = client
        self.verifier = verifier
        self.userDefaults = userDefaults
        self.appGroupDefaults = appGroupDefaults
        refundRequestedAt = userDefaults.object(forKey: WNFShared.refundRequestedAtKey) as? Date
        writeSnapshot(.locked)
        if startsAutomatically {
            startTransactionListener()
            Task { @MainActor in
                await startupRefresh()
            }
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    func handleSceneBecameActive() {
        Task { @MainActor in
            await refreshPaymentCapability()
            await refreshEntitlements()
            await loadProducts()
        }
    }

    func loadProducts() async {
        productState = .loading
        let startedAt = Date()
        do {
            let products = try await productsWithTimeout()
            let elapsed = Date().timeIntervalSince(startedAt)
            if let product = products.first(where: { $0.id == PremiumProductID.lifetime }) {
                productState = .loaded(product)
                premiumLogger.info("product_loaded productID=\(product.id, privacy: .public) elapsed=\(elapsed, privacy: .private)")
            } else {
                productState = .unavailable
                statusMessage = "王牌打工人 · 即将开放"
                premiumLogger.warning("product_loaded empty productID=\(PremiumProductID.lifetime, privacy: .public)")
            }
        } catch PremiumStoreError.timedOut {
            productState = .failed("加载失败，点击重试")
        } catch {
            productState = .failed("加载失败，点击重试")
            premiumLogger.error("product_loaded failed error=\(String(describing: error), privacy: .private)")
        }
    }

    func purchaseLifetime() async {
        guard !isPurchasing else { return }
        guard canMakePayments else {
            statusMessage = PremiumStoreError.paymentNotAllowed.errorDescription
            return
        }
        guard productState.product != nil else {
            if case .unavailable = productState {
                statusMessage = "王牌打工人 · 即将开放"
            } else {
                await loadProducts()
            }
            guard productState.product != nil else { return }
            return
        }

        isPurchasing = true
        statusMessage = nil
        premiumLogger.info("purchase_tapped productID=\(PremiumProductID.lifetime, privacy: .public)")
        do {
            switch try await client.purchase(productID: PremiumProductID.lifetime, appAccountToken: nil) {
            case .success(let payload):
                userDefaults.set(false, forKey: WNFShared.pendingApprovalKey)
                await process(payload, shouldFinish: true, source: "purchase")
                if isPremiumUnlocked {
                    activeNotice = .purchaseCompleted
                    premiumLogger.info("purchase_success productID=\(PremiumProductID.lifetime, privacy: .public)")
                }
            case .pending:
                accessState = .pendingApproval
                userDefaults.set(true, forKey: WNFShared.pendingApprovalKey)
                statusMessage = "等待 Apple ID 批准购买"
                premiumLogger.info("purchase_pending productID=\(PremiumProductID.lifetime, privacy: .public)")
            case .userCancelled:
                premiumLogger.info("purchase_cancelled productID=\(PremiumProductID.lifetime, privacy: .public)")
            }
        } catch PremiumStoreError.paymentNotAllowed {
            statusMessage = PremiumStoreError.paymentNotAllowed.errorDescription
        } catch PremiumStoreError.productUnavailable {
            productState = .unavailable
            statusMessage = "王牌打工人 · 即将开放"
        } catch {
            statusMessage = "购买失败，请稍后再试"
            premiumLogger.error("purchase_failed productID=\(PremiumProductID.lifetime, privacy: .public) error=\(String(describing: error), privacy: .private)")
        }
        isPurchasing = false
    }

    func restorePurchases() async {
        guard !isRestoring else { return }
        isRestoring = true
        statusMessage = nil
        premiumLogger.info("restore_tapped productID=\(PremiumProductID.lifetime, privacy: .public)")
        do {
            try await client.restorePurchases()
            let wasUnlocked = isPremiumUnlocked
            await refreshEntitlements()
            if isPremiumUnlocked {
                if !wasUnlocked {
                    activeNotice = .purchaseCompleted
                }
                premiumLogger.info("restore_success productID=\(PremiumProductID.lifetime, privacy: .public)")
            } else {
                activeNotice = .restoreEmpty
                statusMessage = "未找到可恢复的购买。请确认使用的是购买时的 Apple ID。"
                premiumLogger.info("restore_empty productID=\(PremiumProductID.lifetime, privacy: .public)")
            }
        } catch {
            statusMessage = "恢复购买失败，请稍后再试"
            premiumLogger.error("restore_failed error=\(String(describing: error), privacy: .private)")
        }
        isRestoring = false
    }

    func requestRefund(in scene: UIWindowScene?) async {
        guard !isRequestingRefund else { return }
        guard let scene else {
            activeNotice = .refundFailed
            return
        }
        isRequestingRefund = true
        let status = await client.beginRefundRequest(productID: PremiumProductID.lifetime, in: scene)
        applyRefundRequestStatus(status)
        isRequestingRefund = false
    }

    func applyRefundRequestStatus(_ status: PremiumRefundRequestStatus, submittedAt: Date = Date()) {
        switch status {
        case .success:
            refundRequestedAt = submittedAt
            userDefaults.set(submittedAt, forKey: WNFShared.refundRequestedAtKey)
            activeNotice = .refundSubmitted
            premiumLogger.info("refund_requested productID=\(PremiumProductID.lifetime, privacy: .public)")
        case .userCancelled:
            activeNotice = .refundCancelled
        case .error(let message):
            activeNotice = .refundFailed
            premiumLogger.error("refund_request_failed error=\(message, privacy: .private)")
        }
    }

    func applyPaymentCapability(_ isAllowed: Bool) {
        canMakePayments = isAllowed
        if !isAllowed {
            statusMessage = PremiumStoreError.paymentNotAllowed.errorDescription
        }
    }

    private func startupRefresh() async {
        await drainUnfinishedTransactions()
        await refreshEntitlements()
        await refreshPaymentCapability()
        await loadProducts()
    }

    private func startTransactionListener() {
        guard updatesTask == nil else { return }
        let updates = client.transactionUpdates()
        updatesTask = Task { @MainActor in
            for await payload in updates {
                await process(payload, shouldFinish: true, source: "updates")
            }
        }
    }

    private func drainUnfinishedTransactions() async {
        for payload in await client.unfinishedTransactions() {
            await process(payload, shouldFinish: true, source: "unfinished")
        }
    }

    private func refreshEntitlements() async {
        var acceptedTransaction: PremiumVerifiedTransaction?
        var sawPending = userDefaults.bool(forKey: WNFShared.pendingApprovalKey)

        for payload in await client.currentEntitlements() {
            switch payload {
            case .verified(let transaction, _):
                if let accepted = await acceptedEntitlement(from: transaction) {
                    acceptedTransaction = newest(acceptedTransaction, accepted)
                }
            case .unverified(let productID, let reason):
                premiumLogger.warning("entitlement_unverified productID=\(productID, privacy: .public) reason=\(reason, privacy: .private)")
            }
        }

        if let acceptedTransaction {
            accessState = .unlocked
            refundRequestedAt = nil
            userDefaults.removeObject(forKey: WNFShared.refundRequestedAtKey)
            if sawPending {
                activeNotice = .purchaseCompleted
                userDefaults.set(false, forKey: WNFShared.pendingApprovalKey)
                sawPending = false
            }
            writeSnapshot(snapshot(for: acceptedTransaction, unlocked: true, revocationReason: nil))
        } else if sawPending {
            accessState = .pendingApproval
            writeSnapshot(.locked)
        } else {
            if isPremiumUnlocked {
                activeNotice = .purchaseRevoked
            }
            accessState = .locked
            writeSnapshot(.locked)
        }
    }

    private func refreshPaymentCapability() async {
        applyPaymentCapability(await client.canMakePayments())
    }

    private func process(_ payload: PremiumTransactionPayload, shouldFinish: Bool, source: String) async {
        switch payload {
        case .verified(let transaction, let finish):
            if transaction.revocationDate != nil {
                accessState = .refundedOrRevoked
                userDefaults.set(false, forKey: WNFShared.pendingApprovalKey)
                writeSnapshot(snapshot(for: transaction, unlocked: false, revocationReason: "revoked"))
                activeNotice = .purchaseRevoked
                premiumLogger.info("entitlement_revoked productID=\(transaction.productID, privacy: .public)")
                if shouldFinish { await finish() }
                return
            }

            if let accepted = await acceptedEntitlement(from: transaction) {
                let wasUnlocked = isPremiumUnlocked
                accessState = .unlocked
                refundRequestedAt = nil
                userDefaults.removeObject(forKey: WNFShared.refundRequestedAtKey)
                writeSnapshot(snapshot(for: accepted, unlocked: true, revocationReason: nil))
                if !wasUnlocked || userDefaults.bool(forKey: WNFShared.pendingApprovalKey) {
                    activeNotice = .purchaseCompleted
                }
                userDefaults.set(false, forKey: WNFShared.pendingApprovalKey)
            }
            if shouldFinish {
                await finish()
            }
            premiumLogger.info("transaction_processed source=\(source, privacy: .public) productID=\(transaction.productID, privacy: .public)")
        case .unverified(let productID, let reason):
            statusMessage = "购买未能验证"
            premiumLogger.warning("transaction_unverified source=\(source, privacy: .public) productID=\(productID, privacy: .public) reason=\(reason, privacy: .private)")
        }
    }

    private func acceptedEntitlement(from transaction: PremiumVerifiedTransaction) async -> PremiumVerifiedTransaction? {
        guard transaction.productID == PremiumProductID.lifetime else { return nil }
        guard transaction.ownershipType == .purchased else {
            premiumLogger.info("family_shared_ignored productID=\(transaction.productID, privacy: .public)")
            return nil
        }
        guard transaction.revocationDate == nil else { return nil }
        if let expirationDate = transaction.expirationDate, expirationDate <= Date() {
            return nil
        }

        switch await verifier.verify(transaction) {
        case .accepted(let verified):
            return verified
        case .rejected(let reason):
            statusMessage = "购买未能验证"
            premiumLogger.warning("entitlement_rejected productID=\(transaction.productID, privacy: .public) reason=\(reason, privacy: .private)")
            return nil
        }
    }

    private func productsWithTimeout() async throws -> [PremiumStoreProduct] {
        try await withThrowingTaskGroup(of: [PremiumStoreProduct].self) { group in
            group.addTask {
                try await self.client.products(for: [PremiumProductID.lifetime])
            }
            group.addTask {
                try await Task.sleep(nanoseconds: self.productLoadTimeoutNanoseconds)
                throw PremiumStoreError.timedOut
            }
            guard let products = try await group.next() else {
                throw PremiumStoreError.unknown("No product load result")
            }
            group.cancelAll()
            return products
        }
    }

    private func newest(_ lhs: PremiumVerifiedTransaction?, _ rhs: PremiumVerifiedTransaction) -> PremiumVerifiedTransaction {
        guard let lhs else { return rhs }
        return lhs.purchasedAt >= rhs.purchasedAt ? lhs : rhs
    }

    private func snapshot(
        for transaction: PremiumVerifiedTransaction,
        unlocked: Bool,
        revocationReason: String?
    ) -> PremiumEntitlementSnapshot {
        PremiumEntitlementSnapshot(
            unlocked: unlocked,
            productID: transaction.productID,
            lastVerifiedAt: Date(),
            ownershipType: transaction.ownershipType,
            revocationReason: revocationReason
        )
    }

    private func writeSnapshot(_ snapshot: PremiumEntitlementSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        appGroupDefaults?.set(data, forKey: WNFShared.premiumSnapshotKey)
        PremiumWidgetBridge.scheduleReload()
    }
}

extension UIApplication {
    var currentActiveWindowScene: UIWindowScene? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
}
