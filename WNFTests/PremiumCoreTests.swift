import Foundation
import SwiftUI
import Testing
import UIKit
@testable import WNF

private final class FakePremiumClient: PremiumStoreKitClient {
    var canPay = true
    var products: [PremiumStoreProduct] = [
        PremiumStoreProduct(
            id: PremiumProductID.lifetime,
            displayName: "WNF Premium",
            description: "Unlock Premium",
            displayPrice: "¥18.00"
        )
    ]
    var current: [PremiumTransactionPayload] = []
    var unfinished: [PremiumTransactionPayload] = []
    var purchaseOutcome: PremiumPurchaseOutcome = .userCancelled
    var productsError: Error?
    var purchaseError: Error?
    var restoreError: Error?
    var refundStatus: PremiumRefundRequestStatus = .success
    var didRestore = false

    func canMakePayments() async -> Bool { canPay }
    func products(for productIDs: [String]) async throws -> [PremiumStoreProduct] {
        if let productsError { throw productsError }
        return products
    }
    func purchase(productID: String, appAccountToken: UUID?) async throws -> PremiumPurchaseOutcome {
        if let purchaseError { throw purchaseError }
        return purchaseOutcome
    }
    func restorePurchases() async throws {
        didRestore = true
        if let restoreError { throw restoreError }
    }
    func currentEntitlements() async -> [PremiumTransactionPayload] { current }
    func unfinishedTransactions() async -> [PremiumTransactionPayload] { unfinished }
    func transactionUpdates() -> AsyncStream<PremiumTransactionPayload> {
        AsyncStream { _ in }
    }
    func beginRefundRequest(productID: String, in scene: UIWindowScene) async -> PremiumRefundRequestStatus {
        refundStatus
    }
}

private struct RejectingVerifier: EntitlementVerifier {
    func verify(_ transaction: PremiumVerifiedTransaction) async -> EntitlementVerifierDecision {
        .rejected("server rejected")
    }
}

private func payload(
    productID: String = PremiumProductID.lifetime,
    ownership: PremiumOwnershipType = .purchased,
    revoked: Bool = false,
    finishCount: UnsafeMutablePointer<Int>? = nil
) -> PremiumTransactionPayload {
    let transaction = PremiumVerifiedTransaction(
        id: UUID().uuidString,
        productID: productID,
        ownershipType: ownership,
        revocationDate: revoked ? Date() : nil,
        expirationDate: nil,
        purchasedAt: Date()
    )
    return .verified(transaction) {
        finishCount?.pointee += 1
    }
}

@Suite("Premium entitlement")
struct PremiumEntitlementTests {
    @MainActor
    @Test("Purchased lifetime entitlement unlocks after restore")
    func purchasedEntitlementUnlocks() async throws {
        let client = FakePremiumClient()
        let appGroupDefaults = isolatedDefaults()
        client.current = [payload()]
        let store = PremiumEntitlementStore(
            client: client,
            userDefaults: isolatedDefaults(),
            appGroupDefaults: appGroupDefaults,
            startsAutomatically: false
        )

        await store.restorePurchases()

        #expect(store.isPremiumUnlocked)
        #expect(client.didRestore)
        let data = try #require(appGroupDefaults.data(forKey: WNFShared.premiumSnapshotKey))
        let snapshot = try data.decoded(as: PremiumEntitlementSnapshot.self)
        #expect(snapshot.unlocked)
        #expect(snapshot.productID == PremiumProductID.lifetime)
    }

    @MainActor
    @Test("Family-shared transaction does not unlock v1")
    func familySharedDoesNotUnlock() async {
        let client = FakePremiumClient()
        client.current = [payload(ownership: .familyShared)]
        let store = PremiumEntitlementStore(client: client, userDefaults: isolatedDefaults(), startsAutomatically: false)

        await store.restorePurchases()

        #expect(!store.isPremiumUnlocked)
        #expect(store.activeNotice == .restoreEmpty)
    }

    @MainActor
    @Test("Empty product list is treated as unavailable")
    func emptyProductsAreUnavailable() async {
        let client = FakePremiumClient()
        client.products = []
        let store = PremiumEntitlementStore(client: client, userDefaults: isolatedDefaults(), startsAutomatically: false)

        await store.loadProducts()

        if case .unavailable = store.productState {
            #expect(true)
        } else {
            Issue.record("Expected unavailable product state")
        }
    }

    @MainActor
    @Test("Unfinished verified transactions are finished after processing")
    func unfinishedTransactionsFinish() async {
        let client = FakePremiumClient()
        var finishCount = 0
        client.unfinished = [payload(finishCount: &finishCount)]
        client.current = [payload()]
        let store = PremiumEntitlementStore(client: client, userDefaults: isolatedDefaults())

        await store.restorePurchases()
        try? await Task.sleep(nanoseconds: 50_000_000)

        #expect(store.isPremiumUnlocked)
        #expect(finishCount >= 1)
    }

    @MainActor
    @Test("Verifier rejection keeps Premium locked")
    func verifierRejectionLocks() async {
        let client = FakePremiumClient()
        client.current = [payload()]
        let store = PremiumEntitlementStore(
            client: client,
            verifier: RejectingVerifier(),
            userDefaults: isolatedDefaults(),
            startsAutomatically: false
        )

        await store.restorePurchases()

        #expect(!store.isPremiumUnlocked)
        #expect(store.statusMessage == "未找到可恢复的购买。请确认使用的是购买时的 Apple ID。")
    }

    @MainActor
    @Test("Wrong product entitlement does not unlock")
    func wrongProductDoesNotUnlock() async {
        let client = FakePremiumClient()
        client.current = [payload(productID: "com.wonangfei.app.other")]
        let store = PremiumEntitlementStore(client: client, userDefaults: isolatedDefaults(), startsAutomatically: false)

        await store.restorePurchases()

        #expect(!store.isPremiumUnlocked)
        #expect(store.activeNotice == .restoreEmpty)
    }

    @MainActor
    @Test("Product loading error is retryable failed state")
    func productLoadErrorIsFailed() async {
        let client = FakePremiumClient()
        client.productsError = PremiumStoreError.unknown("network")
        let store = PremiumEntitlementStore(client: client, userDefaults: isolatedDefaults(), startsAutomatically: false)

        await store.loadProducts()

        if case .failed(let message) = store.productState {
            #expect(message == "加载失败，点击重试")
        } else {
            Issue.record("Expected failed product state")
        }
    }

    @MainActor
    @Test("Purchase success unlocks and finishes")
    func purchaseSuccessUnlocksAndFinishes() async {
        let client = FakePremiumClient()
        var finishCount = 0
        client.purchaseOutcome = .success(payload(finishCount: &finishCount))
        let store = PremiumEntitlementStore(client: client, userDefaults: isolatedDefaults(), startsAutomatically: false)

        await store.loadProducts()
        await store.purchaseLifetime()

        #expect(store.isPremiumUnlocked)
        #expect(store.activeNotice == .purchaseCompleted)
        #expect(finishCount == 1)
    }

    @MainActor
    @Test("Purchase pending enters Ask to Buy state")
    func purchasePendingSetsPendingApproval() async {
        let defaults = isolatedDefaults()
        let client = FakePremiumClient()
        client.purchaseOutcome = .pending
        let store = PremiumEntitlementStore(client: client, userDefaults: defaults, startsAutomatically: false)

        await store.loadProducts()
        await store.purchaseLifetime()

        #expect(store.accessState == .pendingApproval)
        #expect(defaults.bool(forKey: WNFShared.pendingApprovalKey))
        #expect(store.statusMessage == "等待 Apple ID 批准购买")
    }

    @MainActor
    @Test("Purchase cancellation stays silent and locked")
    func purchaseCancelStaysSilent() async {
        let client = FakePremiumClient()
        client.purchaseOutcome = .userCancelled
        let store = PremiumEntitlementStore(client: client, userDefaults: isolatedDefaults(), startsAutomatically: false)

        await store.loadProducts()
        await store.purchaseLifetime()

        #expect(!store.isPremiumUnlocked)
        #expect(store.statusMessage == nil)
    }

    @MainActor
    @Test("Payment restriction blocks purchase")
    func paymentRestrictionBlocksPurchase() async {
        let client = FakePremiumClient()
        let store = PremiumEntitlementStore(client: client, userDefaults: isolatedDefaults(), startsAutomatically: false)

        await store.loadProducts()
        store.applyPaymentCapability(false)
        await store.purchaseLifetime()

        #expect(!store.isPremiumUnlocked)
        #expect(store.statusMessage == PremiumStoreError.paymentNotAllowed.errorDescription)
    }

    @MainActor
    @Test("Product unavailable during purchase downgrades paywall")
    func purchaseUnavailableDowngradesPaywall() async {
        let client = FakePremiumClient()
        client.purchaseError = PremiumStoreError.productUnavailable
        let store = PremiumEntitlementStore(client: client, userDefaults: isolatedDefaults(), startsAutomatically: false)

        await store.loadProducts()
        await store.purchaseLifetime()

        if case .unavailable = store.productState {
            #expect(true)
        } else {
            Issue.record("Expected unavailable product state")
        }
        #expect(store.statusMessage == "王牌打工人 · 即将开放")
    }

    @MainActor
    @Test("Unverified purchase is not finished and remains locked")
    func unverifiedPurchaseStaysLocked() async {
        let client = FakePremiumClient()
        client.purchaseOutcome = .success(.unverified(productID: PremiumProductID.lifetime, reason: "bad jws"))
        let store = PremiumEntitlementStore(client: client, userDefaults: isolatedDefaults(), startsAutomatically: false)

        await store.loadProducts()
        await store.purchaseLifetime()

        #expect(!store.isPremiumUnlocked)
        #expect(store.statusMessage == "购买未能验证")
    }

    @MainActor
    @Test("Revoked transaction locks Premium and finishes")
    func revokedTransactionLocksAndFinishes() async {
        let client = FakePremiumClient()
        var finishCount = 0
        client.purchaseOutcome = .success(payload(revoked: true, finishCount: &finishCount))
        let store = PremiumEntitlementStore(client: client, userDefaults: isolatedDefaults(), startsAutomatically: false)

        await store.loadProducts()
        await store.purchaseLifetime()

        #expect(store.accessState == .refundedOrRevoked)
        #expect(store.activeNotice == .purchaseRevoked)
        #expect(finishCount == 1)
    }

    @Test("Snapshot schema round trips")
    func snapshotRoundTrips() throws {
        let snapshot = PremiumEntitlementSnapshot(
            unlocked: true,
            productID: PremiumProductID.lifetime,
            lastVerifiedAt: Date(),
            ownershipType: .purchased,
            revocationReason: nil
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PremiumEntitlementSnapshot.self, from: data)

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.productID == PremiumProductID.lifetime)
        #expect(decoded.unlocked)
    }

    @MainActor
    @Test("Refund success is the only state that persists refund request date")
    func refundStatusPersistence() {
        let defaults = isolatedDefaults()
        let store = PremiumEntitlementStore(client: FakePremiumClient(), userDefaults: defaults, startsAutomatically: false)
        let submittedAt = Date(timeIntervalSince1970: 1_800_000_000)

        store.applyRefundRequestStatus(.userCancelled, submittedAt: submittedAt)
        #expect(store.refundRequestedAt == nil)
        #expect(defaults.object(forKey: WNFShared.refundRequestedAtKey) == nil)
        #expect(store.activeNotice == .refundCancelled)

        store.applyRefundRequestStatus(.error("network"), submittedAt: submittedAt)
        #expect(store.refundRequestedAt == nil)
        #expect(defaults.object(forKey: WNFShared.refundRequestedAtKey) == nil)
        #expect(store.activeNotice == .refundFailed)

        store.applyRefundRequestStatus(.success, submittedAt: submittedAt)
        #expect(store.refundRequestedAt == submittedAt)
        #expect(defaults.object(forKey: WNFShared.refundRequestedAtKey) as? Date == submittedAt)
        #expect(store.activeNotice == .refundSubmitted)
    }
}

@Suite("Premium preferences")
struct PremiumPreferencesTests {
    @MainActor
    @Test("Premium theme preview does not persist while locked")
    func lockedThemeOnlyPreviews() {
        let defaults = isolatedDefaults()
        let preferences = PremiumPreferencesStore(userDefaults: defaults)

        let saved = preferences.selectTheme(.nightShift, isPremiumUnlocked: false)

        #expect(!saved)
        #expect(preferences.activeTheme == .nightShift)
        #expect(defaults.string(forKey: WNFShared.selectedThemeKey) == nil)
    }

    @MainActor
    @Test("Premium share template cannot be saved while locked")
    func lockedShareTemplateNotSaved() {
        let defaults = isolatedDefaults()
        let preferences = PremiumPreferencesStore(userDefaults: defaults)

        let saved = preferences.selectShareTemplate(.quietLedger, isPremiumUnlocked: false)

        #expect(!saved)
        #expect(preferences.selectedShareTemplate == .classic)
    }

    @MainActor
    @Test("Unlocked theme and share template persist")
    func unlockedPreferencesPersist() {
        let defaults = isolatedDefaults()
        let preferences = PremiumPreferencesStore(userDefaults: defaults)

        #expect(preferences.selectTheme(.mintReceipt, isPremiumUnlocked: true))
        #expect(preferences.selectShareTemplate(.survivalBadge, isPremiumUnlocked: true))

        let reloaded = PremiumPreferencesStore(userDefaults: defaults)
        #expect(reloaded.selectedTheme == .mintReceipt)
        #expect(reloaded.selectedShareTemplate == .survivalBadge)
    }

    @MainActor
    @Test("Lock screen widget amount preference defaults true and persists false")
    func lockScreenWidgetAmountPreferencePersists() {
        let defaults = isolatedDefaults()
        let preferences = PremiumPreferencesStore(userDefaults: defaults)

        #expect(preferences.lockScreenWidgetShowsAmount)
        preferences.lockScreenWidgetShowsAmount = false

        let reloaded = PremiumPreferencesStore(userDefaults: defaults)
        #expect(!reloaded.lockScreenWidgetShowsAmount)
    }
}

@Suite("Premium settings presentation")
struct PremiumSettingsPresentationTests {
    @Test("Locked card shows price, locked rows, and export lock")
    func lockedCardPresentation() {
        let presentation = PremiumSettingsCardPresentation(
            accessState: .locked,
            displayPrice: "¥18.00",
            statusMessage: nil,
            refundRequestedAt: nil
        )

        #expect(!presentation.isUnlocked)
        #expect(!presentation.isPending)
        #expect(presentation.subtitle == "一次买断，解锁桌面小组件、主题、分享模板和历史导出。")
        #expect(presentation.primaryActionTitle == "¥18.00")
        #expect(!presentation.primaryActionIsUnlocked)
        #expect(!presentation.refundActionIsUnlocked)
        #expect(presentation.inlineMessage == nil)
        #expect(presentation.exportTrailingSymbol == "lock.fill")
        #expect(presentation.featureRows().allSatisfy { $0.isLocked })
    }

    @Test("Unlocked card shows unlocked copy and export arrow")
    func unlockedCardPresentation() {
        let presentation = PremiumSettingsCardPresentation(
            accessState: .unlocked,
            displayPrice: "¥18.00",
            statusMessage: "ignored",
            refundRequestedAt: nil
        )

        #expect(presentation.isUnlocked)
        #expect(presentation.subtitle == "小组件、主题、模板和导出已解锁")
        #expect(presentation.primaryActionTitle == "已解锁")
        #expect(presentation.primaryActionIsUnlocked)
        #expect(presentation.refundActionIsUnlocked)
        #expect(presentation.inlineMessage == "ignored")
        #expect(presentation.exportTrailingSymbol == "arrow.right")
        #expect(presentation.featureRows().allSatisfy { !$0.isLocked })
    }

    @Test("Pending approval message has priority over refund and status")
    func pendingMessagePriority() {
        let presentation = PremiumSettingsCardPresentation(
            accessState: .pendingApproval,
            displayPrice: "¥18.00",
            statusMessage: "network",
            refundRequestedAt: Date(timeIntervalSince1970: 1_800_000_000),
            refundDateFormatter: { _ in "2026/01/15" }
        )

        #expect(presentation.isPending)
        #expect(presentation.inlineMessage == "等待 Apple ID 批准购买。批准后王牌打工人会自动解锁。")
    }

    @Test("Refund message uses injected date formatter")
    func refundMessageUsesFormatter() {
        let presentation = PremiumSettingsCardPresentation(
            accessState: .locked,
            displayPrice: "¥18.00",
            statusMessage: "ignored",
            refundRequestedAt: Date(timeIntervalSince1970: 1_800_000_000),
            refundDateFormatter: { _ in "2026/01/15" }
        )

        #expect(presentation.inlineMessage == "退款审核中（提交于 2026/01/15）。")
    }

    @Test("Payment restriction fallback appears when no explicit status exists")
    func paymentRestrictionFallback() {
        let presentation = PremiumSettingsCardPresentation(
            accessState: .locked,
            displayPrice: "¥18.00",
            statusMessage: nil,
            refundRequestedAt: nil,
            canMakePayments: false
        )

        #expect(presentation.inlineMessage == PremiumStoreError.paymentNotAllowed.errorDescription)
    }

    @Test("Theme option state captures selection and premium lock")
    func themeOptionState() throws {
        let locked = PremiumSettingsCardPresentation(
            accessState: .locked,
            displayPrice: "¥18.00",
            statusMessage: nil,
            refundRequestedAt: nil
        )
        let options = locked.themeOptions(activeTheme: .mintReceipt)
        let classic = try #require(options.first { $0.theme == .classic })
        let mint = try #require(options.first { $0.theme == .mintReceipt })

        #expect(!classic.isLocked)
        #expect(!classic.isSelected)
        #expect(mint.isLocked)
        #expect(mint.isSelected)
        #expect(mint.accessibilityLabel == "薄荷小票，王牌打工人专属，可预览")

        let unlocked = PremiumSettingsCardPresentation(
            accessState: .unlocked,
            displayPrice: "¥18.00",
            statusMessage: nil,
            refundRequestedAt: nil
        )
        #expect(unlocked.themeOptions(activeTheme: .mintReceipt).allSatisfy { !$0.isLocked })
    }

    @Test("Share template options capture selection and premium lock")
    func shareTemplateOptionState() throws {
        let locked = PremiumSettingsCardPresentation(
            accessState: .locked,
            displayPrice: "¥18.00",
            statusMessage: nil,
            refundRequestedAt: nil
        )
        let options = locked.shareTemplateOptions(selectedTemplate: .quietLedger)
        let classic = try #require(options.first { $0.template == .classic })
        let quiet = try #require(options.first { $0.template == .quietLedger })

        #expect(!classic.isLocked)
        #expect(quiet.isLocked)
        #expect(quiet.isSelected)
        #expect(quiet.title == "低调账本")

        let unlocked = PremiumSettingsCardPresentation(
            accessState: .unlocked,
            displayPrice: "¥18.00",
            statusMessage: nil,
            refundRequestedAt: nil
        )
        #expect(unlocked.shareTemplateOptions(selectedTemplate: .quietLedger).allSatisfy { !$0.isLocked })
    }
}

@Suite("Premium export and links")
struct PremiumExportAndLinkTests {
    @MainActor
    @Test("History export writes UTF-8 BOM CSV and JSON envelope")
    func historyExportWritesCSVAndJSON() throws {
        let defaults = isolatedDefaults()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let yesterdayKey = WageState.dateKey(for: yesterday)
        let record = DailyWageRecord(
            dateKey: yesterdayKey,
            earnedToday: 123.45,
            targetToday: 456.78,
            elapsedPaidSeconds: 7_200,
            workdayMinutes: 480,
            hourlyRate: 56.78,
            monthlySalary: 18_000,
            workdaysPerMonth: 22,
            capturedAt: yesterday,
            source: .observed
        )
        let data = try JSONEncoder().encode(DailyRecordStorageEnvelope(records: [yesterdayKey: record]))
        defaults.set(data, forKey: StorageKey.dailyRecords)
        let state = WageState(userDefaults: defaults)

        let urls = try HistoryExportService.makeExportItems(state: state)

        #expect(urls.count == 2)
        let csvURL = try #require(urls.first { $0.lastPathComponent == "wonangfei-history.csv" })
        let csvData = try Data(contentsOf: csvURL)
        #expect(Array(csvData.prefix(3)) == [0xEF, 0xBB, 0xBF])
        let csv = try #require(String(data: csvData, encoding: .utf8))
        #expect(csv.contains(yesterdayKey))
        #expect(csv.contains("123.45"))

        let jsonData = try Data(contentsOf: #require(urls.first { $0.lastPathComponent == "wonangfei-history.json" }))
        let envelope = try JSONDecoder.iso8601.decode(HistoryExportService.ExportEnvelope.self, from: jsonData)
        #expect(envelope.schemaVersion == 1)
        #expect(envelope.records.contains { $0.dateKey == yesterdayKey })
    }

    @Test("Premium deep links accept universal link and fallback scheme")
    func premiumDeepLinks() throws {
        #expect(PremiumDeepLink.isPremiumRoute(try #require(URL(string: "https://wonangfei.app/premium"))))
        #expect(PremiumDeepLink.isPremiumRoute(try #require(URL(string: "wonangfei://premium"))))
        #expect(PremiumDeepLink.isPremiumRoute(try #require(URL(string: "wonangfei:/premium"))))
        #expect(!PremiumDeepLink.isPremiumRoute(try #require(URL(string: "https://wonangfei.app/terms"))))
    }
}

@Suite("Wage calculator")
struct WageCalculatorTests {
    @Test("Workday with lunch computes status, earned amount, and progress")
    func workdayWithLunchComputesExpectedValues() {
        let day = WageCalculator.compute(
            monthlySalary: 22_000,
            workdaysPerMonth: 22,
            workStart: .minuteInDay(9 * 60),
            workEnd: .minuteInDay(18 * 60),
            lunchStart: .minuteInDay(12 * 60),
            lunchEnd: .minuteInDay(13 * 60),
            hasLunchBreak: true,
            now: DateComponents(hour: 15, minute: 0)
        )

        #expect(day.workdayMinutes == 480)
        #expect(day.elapsedPaidMinutes == 300)
        #expect(day.status == .afternoon)
        #expect(abs(day.targetToday - 1000) < 0.01)
        #expect(abs(day.earnedToday - 625) < 0.01)
        #expect(abs(day.progress - 0.625) < 0.001)
    }

    @Test("No-lunch day removes lunch gap and reaches done at end")
    func noLunchDayComputesContinuousWork() {
        let day = WageCalculator.compute(
            monthlySalary: 18_000,
            workdaysPerMonth: 18,
            workStart: .minuteInDay(10 * 60),
            workEnd: .minuteInDay(19 * 60),
            lunchStart: .minuteInDay(12 * 60),
            lunchEnd: .minuteInDay(13 * 60),
            hasLunchBreak: false,
            now: DateComponents(hour: 19, minute: 10)
        )

        #expect(day.workdayMinutes == 540)
        #expect(day.elapsedPaidMinutes == 540)
        #expect(day.status == .done)
        #expect(day.progress == 1)
        #expect(abs(day.targetToday - 1000) < 0.01)
    }

    @Test("DateComponents minuteInDay clamps out-of-range values")
    func minuteInDayClamps() {
        #expect(DateComponents.minuteInDay(-10).minutesInDay == 0)
        #expect(DateComponents.minuteInDay(24 * 60 + 30).minutesInDay == 23 * 60 + 59)
        #expect(DateComponents(hour: 7, minute: 5).clockText == "07:05")
    }
}

@Suite("Presentation helpers")
struct PresentationHelperTests {
    @Test("Money and duration formatting handles privacy and compact units")
    func moneyAndDurationFormatting() {
        #expect(WNFFormat.money(1234.49, privacy: false) == "¥1,234")
        #expect(WNFFormat.money(1234.50, privacy: false) == "¥1,235")
        #expect(WNFFormat.money(1234, privacy: true) == "¥••••")
        #expect(WNFFormat.moneyDecimal(12.345, privacy: false) == "¥12.35")
        #expect(WNFFormat.moneyDecimal(12.345, privacy: true) == "¥•••.••")
        #expect(WNFFormat.duration(0) == "0min")
        #expect(WNFFormat.duration(45) == "45min")
        #expect(WNFFormat.duration(60) == "1h")
        #expect(WNFFormat.duration(135) == "2h15min")
    }

    @Test("Work status presentation maps all states")
    func workStatusPresentationMapsAllStates() {
        #expect(WorkStatusPresentation(status: .before).label == "尚未开工")
        #expect(WorkStatusPresentation(status: .morning).label == "上午搬砖中")
        #expect(WorkStatusPresentation(status: .lunch).label == "午休回血")
        #expect(WorkStatusPresentation(status: .afternoon).label == "下午挺挺")
        #expect(WorkStatusPresentation(status: .done).label == "今日通关")
        #expect(WorkStatusPresentation(status: .done).mascotAssetName == "CowThreeQ")
    }

    @Test("Share card copy random excludes current copy when alternatives exist")
    func shareCardRandomCopyExcludesCurrent() {
        for _ in 0..<20 {
            #expect(ShareCardCopy.random(excluding: .default) != .default)
        }
        #expect(ShareCardCopy.pool.contains(.default))
        #expect(ShareCardCopy.pool.count >= 2)
    }

    @Test("Premium theme and share template metadata preserves free vs paid contract")
    func premiumMetadataPreservesFreePaidContract() {
        #expect(!PremiumThemeID.classic.isPremium)
        #expect(PremiumThemeID.nightShift.isPremium)
        #expect(PremiumThemeID.mintReceipt.title == "薄荷小票")
        #expect(PremiumThemeID.punchCard.title == "打卡珊瑚")
        #expect(!PremiumShareTemplateID.classic.isPremium)
        #expect(PremiumShareTemplateID.overtimeReceipt.isPremium)
        #expect(PremiumShareTemplateID.survivalBadge.title == "幸存徽章")
        #expect(PremiumShareTemplateID.quietLedger.title == "低调账本")
    }
}

@Suite("Wage state storage")
struct WageStateStorageTests {
    @MainActor
    @Test("Editable settings normalize and persist on init")
    func editableSettingsNormalizeAndPersist() {
        let defaults = isolatedDefaults()
        defaults.set(500_000.0, forKey: StorageKey.monthlySalary)
        defaults.set(99, forKey: StorageKey.workdaysPerMonth)
        defaults.set(-50, forKey: StorageKey.workStartMinute)
        defaults.set(2_000, forKey: StorageKey.workEndMinute)
        defaults.set([0, 2, 9, -1, 6], forKey: StorageKey.selectedWeekdays)

        let state = WageState(userDefaults: defaults)

        #expect(state.monthlySalary == 100_000)
        #expect(defaults.double(forKey: StorageKey.monthlySalary) == 100_000)
        #expect(state.workdaysPerMonth == 31)
        #expect(defaults.integer(forKey: StorageKey.workdaysPerMonth) == 31)
        #expect(state.workStart.minutesInDay == 0)
        #expect(state.workEnd.minutesInDay == 23 * 60 + 59)
        #expect(state.selectedWeekdays == [0, 2, 6])
        #expect(defaults.array(forKey: StorageKey.selectedWeekdays) as? [Int] == [0, 2, 6])
        state.pauseCalendarDayTimer()
    }

    @MainActor
    @Test("Salary, workday, and weekday edits persist through UserDefaults")
    func editsPersist() {
        let defaults = isolatedDefaults()
        let state = WageState(userDefaults: defaults)

        state.setMonthlySalary(-12)
        state.adjustMonthlySalary(by: 18_500)
        state.setWorkdaysPerMonth(0)
        state.adjustWorkdaysPerMonth(by: 12)
        state.toggleWeekday(5)
        state.toggleWeekday(99)

        #expect(state.monthlySalary == 18_500)
        #expect(defaults.double(forKey: StorageKey.monthlySalary) == 18_500)
        #expect(state.workdaysPerMonth == 13)
        #expect(defaults.integer(forKey: StorageKey.workdaysPerMonth) == 13)
        #expect(state.selectedWeekdays.contains(5))
        #expect(!state.selectedWeekdays.contains(99))
        state.pauseCalendarDayTimer()
    }

    @MainActor
    @Test("Time and boolean settings persist through UserDefaults")
    func timeAndBooleanSettingsPersist() {
        let defaults = isolatedDefaults()
        let state = WageState(userDefaults: defaults)
        let startDate = DateComponents.calendar.date(from: DateComponents(hour: 8, minute: 15))!
        let endDate = DateComponents.calendar.date(from: DateComponents(hour: 17, minute: 45))!
        let lunchStartDate = DateComponents.calendar.date(from: DateComponents(hour: 11, minute: 50))!
        let lunchEndDate = DateComponents.calendar.date(from: DateComponents(hour: 12, minute: 35))!

        state.updateTime(\.workStart, date: startDate)
        state.updateTime(\.workEnd, date: endDate)
        state.updateTime(\.lunchStart, date: lunchStartDate)
        state.updateTime(\.lunchEnd, date: lunchEndDate)
        state.hasLunchBreak = false
        state.includeOvertime = false
        state.privacyMode = true

        #expect(defaults.integer(forKey: StorageKey.workStartMinute) == 8 * 60 + 15)
        #expect(defaults.integer(forKey: StorageKey.workEndMinute) == 17 * 60 + 45)
        #expect(defaults.integer(forKey: StorageKey.lunchStartMinute) == 11 * 60 + 50)
        #expect(defaults.integer(forKey: StorageKey.lunchEndMinute) == 12 * 60 + 35)
        #expect(defaults.bool(forKey: StorageKey.hasLunchBreak) == false)
        #expect(defaults.bool(forKey: StorageKey.includeOvertime) == false)
        #expect(defaults.bool(forKey: StorageKey.privacyMode) == true)
        #expect(state.workStart.minutesInDay == 8 * 60 + 15)
        #expect(state.bindingForTime(\.workStart) == startDate)
        state.pauseCalendarDayTimer()
    }

    @Test("Daily record envelope loads from primary storage")
    func dailyRecordEnvelopeLoads() throws {
        let defaults = isolatedDefaults()
        let record = sampleDailyRecord(dateKey: "2026-05-01")
        let data = try JSONEncoder().encode(DailyRecordStorageEnvelope(records: [record.dateKey: record]))
        defaults.set(data, forKey: StorageKey.dailyRecords)

        let result = WageState.loadDailyRecords(from: defaults)

        #expect(result.records[record.dateKey] == record)
        if case .primaryWritable = result.storageMode {
            #expect(true)
        } else {
            Issue.record("Expected primary writable storage")
        }
    }

    @Test("Legacy bare daily record dictionary migrates to schema envelope")
    func legacyDailyRecordsMigrate() throws {
        let defaults = isolatedDefaults()
        let record = sampleDailyRecord(dateKey: "2026-05-02")
        let legacyData = try JSONEncoder().encode([record.dateKey: record])
        defaults.set(legacyData, forKey: StorageKey.dailyRecords)

        let result = WageState.loadDailyRecords(from: defaults)

        #expect(result.records[record.dateKey] == record)
        #expect(defaults.data(forKey: StorageKey.dailyRecordsLegacyRawBackup) == legacyData)
        let migratedData = try #require(defaults.data(forKey: StorageKey.dailyRecords))
        let envelope = try migratedData.decoded(as: DailyRecordStorageEnvelope.self)
        #expect(envelope.schemaVersion == DailyRecordStorageEnvelope.currentSchemaVersion)
        #expect(envelope.records[record.dateKey] == record)
    }

    @Test("Corrupt primary daily records are preserved and switch to decode recovery writes")
    func corruptDailyRecordsSwitchToRecovery() {
        let defaults = isolatedDefaults()
        let corruptData = Data("not-json".utf8)
        defaults.set(corruptData, forKey: StorageKey.dailyRecords)

        let result = WageState.loadDailyRecords(from: defaults)

        #expect(result.records.isEmpty)
        #expect(defaults.data(forKey: StorageKey.dailyRecordsDecodeFailedRawBackup) == corruptData)
        #expect(defaults.string(forKey: StorageKey.dailyRecordsActiveRecoveryKey) == StorageKey.dailyRecordsDecodeFailedRecovery)
        if case .recoveryWritesOnly(let key) = result.storageMode {
            #expect(key == StorageKey.dailyRecordsDecodeFailedRecovery)
        } else {
            Issue.record("Expected decode-failed recovery writes")
        }
    }

    @Test("Unsupported future schema is preserved and writes to unsupported recovery")
    func unsupportedFutureSchemaSwitchesToRecovery() throws {
        let defaults = isolatedDefaults()
        let record = sampleDailyRecord(dateKey: "2026-05-03")
        let data = try JSONEncoder().encode(DailyRecordStorageEnvelope(schemaVersion: 99, records: [record.dateKey: record]))
        defaults.set(data, forKey: StorageKey.dailyRecords)

        let result = WageState.loadDailyRecords(from: defaults)

        #expect(result.records[record.dateKey] == record)
        #expect(defaults.data(forKey: StorageKey.dailyRecordsUnsupportedRawBackup) == data)
        if case .recoveryWritesOnly(let key) = result.storageMode {
            #expect(key == StorageKey.dailyRecordsUnsupportedRecovery)
        } else {
            Issue.record("Expected unsupported-schema recovery writes")
        }
    }

    @Test("Recovery daily records are loaded when primary payload is corrupt")
    func recoveryRecordsLoadWhenPrimaryCorrupt() throws {
        let defaults = isolatedDefaults()
        let record = sampleDailyRecord(dateKey: "2026-05-04")
        let recoveryData = try JSONEncoder().encode(DailyRecordStorageEnvelope(records: [record.dateKey: record]))
        defaults.set(Data("broken".utf8), forKey: StorageKey.dailyRecords)
        defaults.set(recoveryData, forKey: StorageKey.dailyRecordsDecodeFailedRecovery)

        let result = WageState.loadDailyRecords(from: defaults)

        #expect(result.records[record.dateKey] == record)
        #expect(defaults.string(forKey: StorageKey.dailyRecordsActiveRecoveryKey) == StorageKey.dailyRecordsDecodeFailedRecovery)
        if case .recoveryWritesOnly(let key) = result.storageMode {
            #expect(key == StorageKey.dailyRecordsDecodeFailedRecovery)
        } else {
            Issue.record("Expected active recovery storage")
        }
    }

    @MainActor
    @Test("Persist current-day snapshot writes daily record envelope")
    func persistCurrentDaySnapshotWritesEnvelope() throws {
        let defaults = isolatedDefaults()
        defaults.set(Array(0...6), forKey: StorageKey.selectedWeekdays)
        let state = WageState(userDefaults: defaults)

        state.persistCurrentDaySnapshot()

        let data = try #require(defaults.data(forKey: StorageKey.dailyRecords))
        let envelope = try data.decoded(as: DailyRecordStorageEnvelope.self)
        #expect(envelope.schemaVersion == DailyRecordStorageEnvelope.currentSchemaVersion)
        #expect(envelope.records[state.currentDateKey] != nil)
        state.pauseCalendarDayTimer()
    }
}

@Suite("SwiftUI render coverage")
struct SwiftUIRenderCoverageTests {
    @MainActor
    @Test("Render SettingsView in locked and unlocked states")
    func renderSettingsViewStates() async {
        let lockedState = WageState(userDefaults: isolatedDefaults())
        let lockedPremium = PremiumEntitlementStore(client: FakePremiumClient(), userDefaults: isolatedDefaults(), startsAutomatically: false)
        let lockedPreferences = PremiumPreferencesStore(userDefaults: isolatedDefaults())
        await renderForCoverage(
            SettingsView()
                .environmentObject(lockedState)
                .environmentObject(lockedPremium)
                .environmentObject(lockedPreferences)
                .environmentObject(PremiumPaywallController())
        )
        lockedState.pauseCalendarDayTimer()

        let unlockedState = WageState(userDefaults: isolatedDefaults())
        let client = FakePremiumClient()
        client.current = [payload()]
        let unlockedPremium = PremiumEntitlementStore(client: client, userDefaults: isolatedDefaults(), startsAutomatically: false)
        await unlockedPremium.restorePurchases()
        let unlockedPreferences = PremiumPreferencesStore(userDefaults: isolatedDefaults())
        _ = unlockedPreferences.selectTheme(.mintReceipt, isPremiumUnlocked: true)
        _ = unlockedPreferences.selectShareTemplate(.quietLedger, isPremiumUnlocked: true)

        await renderForCoverage(
            SettingsView()
                .environmentObject(unlockedState)
                .environmentObject(unlockedPremium)
                .environmentObject(unlockedPreferences)
                .environmentObject(PremiumPaywallController())
        )
        unlockedState.pauseCalendarDayTimer()
    }

    @MainActor
    @Test("Render PremiumPaywallView product states")
    func renderPaywallStates() async {
        let loadedClient = FakePremiumClient()
        let loadedPremium = PremiumEntitlementStore(client: loadedClient, userDefaults: isolatedDefaults(), startsAutomatically: false)
        await loadedPremium.loadProducts()
        await renderForCoverage(
            PremiumPaywallView()
                .environmentObject(loadedPremium)
                .environmentObject(PremiumPaywallController())
        )

        let unavailableClient = FakePremiumClient()
        unavailableClient.products = []
        let unavailablePremium = PremiumEntitlementStore(client: unavailableClient, userDefaults: isolatedDefaults(), startsAutomatically: false)
        await unavailablePremium.loadProducts()
        await renderForCoverage(
            PremiumPaywallView()
                .environmentObject(unavailablePremium)
                .environmentObject(PremiumPaywallController())
        )

        let failedClient = FakePremiumClient()
        failedClient.productsError = PremiumStoreError.unknown("network")
        let failedPremium = PremiumEntitlementStore(client: failedClient, userDefaults: isolatedDefaults(), startsAutomatically: false)
        await failedPremium.loadProducts()
        await renderForCoverage(
            PremiumPaywallView()
                .environmentObject(failedPremium)
                .environmentObject(PremiumPaywallController())
        )
    }

    @MainActor
    @Test("Render RecordsView with persisted history")
    func renderRecordsView() async throws {
        let defaults = isolatedDefaults()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let yesterdayKey = WageState.dateKey(for: yesterday)
        let data = try JSONEncoder().encode(DailyRecordStorageEnvelope(records: [
            yesterdayKey: sampleDailyRecord(dateKey: yesterdayKey)
        ]))
        defaults.set(data, forKey: StorageKey.dailyRecords)
        let state = WageState(userDefaults: defaults)

        await renderForCoverage(RecordsView().environmentObject(state))

        state.pauseCalendarDayTimer()
    }

    @MainActor
    @Test("Render OnboardingView")
    func renderOnboardingView() async {
        let state = WageState(userDefaults: isolatedDefaults())

        for page in 0..<4 {
            await renderForCoverage(
                OnboardingView(initialPage: page) {}
                    .environmentObject(state),
                size: CGSize(width: 430, height: 932)
            )
        }

        state.pauseCalendarDayTimer()
    }

    @MainActor
    @Test("Render share cards across premium templates")
    func renderShareCardTemplates() async {
        let day = sampleWageDay()
        for template in PremiumShareTemplateID.allCases {
            await renderForCoverage(
                WonangfeiShareCard(
                    day: day,
                    copy: .default,
                    template: template,
                    hidesSensitiveInfo: template == .quietLedger,
                    showsControls: true,
                    isPreparingShare: template == .overtimeReceipt,
                    canUsePremiumTemplates: true,
                    onTogglePrivacy: {},
                    onShare: {},
                    onDismiss: {}
                ),
                size: CGSize(width: 390, height: 700)
            )
        }
    }

    @MainActor
    @Test("Render root view shell with onboarding completed")
    func renderRootViewShell() async {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: "wnf.onboarding.completed")
        let state = WageState(userDefaults: defaults)
        let premium = PremiumEntitlementStore(client: FakePremiumClient(), userDefaults: isolatedDefaults(), startsAutomatically: false)

        await renderForCoverage(
            RootView()
                .environment(\.defaultMinListRowHeight, 1)
                .environmentObject(state)
                .environmentObject(premium)
                .environmentObject(PremiumPreferencesStore(userDefaults: isolatedDefaults()))
                .environmentObject(PremiumPaywallController()),
            size: CGSize(width: 430, height: 932)
        )

        state.pauseCalendarDayTimer()
    }
}

private func isolatedDefaults() -> UserDefaults {
    let suiteName = "wnf.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
private func renderForCoverage<V: View>(
    _ view: V,
    size: CGSize = CGSize(width: 430, height: 932)
) async {
    let controller = UIHostingController(rootView: view)
    let window = UIWindow(frame: CGRect(origin: .zero, size: size))
    window.rootViewController = controller
    window.makeKeyAndVisible()
    controller.view.frame = window.bounds
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()
    try? await Task.sleep(nanoseconds: 60_000_000)
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()
    _ = controller.view.snapshotView(afterScreenUpdates: false)
    window.isHidden = true
}

private func sampleDailyRecord(dateKey: String) -> DailyWageRecord {
    DailyWageRecord(
        dateKey: dateKey,
        earnedToday: 123.45,
        targetToday: 456.78,
        elapsedPaidSeconds: 7_200,
        workdayMinutes: 480,
        hourlyRate: 56.78,
        monthlySalary: 18_000,
        workdaysPerMonth: 22,
        capturedAt: Date(timeIntervalSince1970: 1_777_000_000),
        source: .observed
    )
}

private func sampleWageDay() -> WageDay {
    WageCalculator.compute(
        monthlySalary: 18_000,
        workdaysPerMonth: 22,
        workStart: .minuteInDay(9 * 60 + 30),
        workEnd: .minuteInDay(18 * 60 + 30),
        lunchStart: .minuteInDay(12 * 60),
        lunchEnd: .minuteInDay(13 * 60),
        hasLunchBreak: true,
        now: DateComponents(hour: 15, minute: 24, second: 0)
    )
}

private extension Data {
    func decoded<T: Decodable>(as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: self)
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
