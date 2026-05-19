import Foundation
import OSLog
import SwiftUI
import WidgetKit

let premiumLogger = Logger(subsystem: "com.wonangfei.app", category: "Premium")

enum PremiumProductID {
    static let lifetime = "com.wonangfei.app.premium.lifetime"
    static let fallbackDisplayPrice = "¥18 / ¥19 一次买断"
}

enum WNFShared {
    static let appGroupID = "group.com.wonangfei.app"
    static let premiumSnapshotKey = "wnf.premium.entitlement.snapshot.v1"
    static let widgetSnapshotKey = "wnf.widget.wage.snapshot.v1"
    static let refundRequestedAtKey = "wnf.premium.refundRequestedAt"
    static let pendingApprovalKey = "wnf.premium.pendingApproval"
    static let purchaseCompletionNoticeKey = "wnf.premium.notice.purchaseCompleted"
    static let revocationNoticeKey = "wnf.premium.notice.revoked"
    static let selectedThemeKey = "wnf.premium.preferences.selectedTheme"
    static let selectedShareTemplateKey = "wnf.premium.preferences.selectedShareTemplate"
    static let lockScreenShowsAmountKey = "wnf.premium.preferences.lockScreenShowsAmount"
}

enum PremiumFeature: String, CaseIterable, Identifiable, Codable {
    case widgets
    case themeSkins
    case shareTemplates
    case dataExport

    var id: String { rawValue }

    var title: String {
        switch self {
        case .widgets: "桌面 / 锁屏小组件"
        case .themeSkins: "主题皮肤"
        case .shareTemplates: "截图分享模板"
        case .dataExport: "历史记录导出"
        }
    }

    var subtitle: String {
        switch self {
        case .widgets: "把今天的窝囊费放到桌面和锁屏。"
        case .themeSkins: "切换更丧萌、更清爽或更醒目的界面色。"
        case .shareTemplates: "用不同口吻生成今日战报图。"
        case .dataExport: "导出 CSV / JSON，保留完整金额和工时。"
        }
    }

    var symbol: String {
        switch self {
        case .widgets: "rectangle.on.rectangle"
        case .themeSkins: "paintpalette"
        case .shareTemplates: "square.and.arrow.up"
        case .dataExport: "square.and.arrow.down"
        }
    }
}

enum PremiumOwnershipType: String, Codable {
    case purchased
    case familyShared
    case unknown
}

struct PremiumStoreProduct: Equatable {
    var id: String
    var displayName: String
    var description: String
    var displayPrice: String
}

enum PremiumProductLoadState: Equatable {
    case idle
    case loading
    case loaded(PremiumStoreProduct)
    case unavailable
    case failed(String)

    var product: PremiumStoreProduct? {
        if case .loaded(let product) = self { return product }
        return nil
    }
}

enum PremiumAccessState: Equatable {
    case locked
    case unlocked
    case pendingApproval
    case refundedOrRevoked
}

struct PremiumVerifiedTransaction: Equatable {
    var id: String
    var productID: String
    var ownershipType: PremiumOwnershipType
    var revocationDate: Date?
    var expirationDate: Date?
    var purchasedAt: Date
}

enum PremiumTransactionPayload {
    case verified(PremiumVerifiedTransaction, finish: () async -> Void)
    case unverified(productID: String, reason: String)
}

enum EntitlementVerifierDecision: Equatable {
    case accepted(PremiumVerifiedTransaction)
    case rejected(String)
}

protocol EntitlementVerifier {
    func verify(_ transaction: PremiumVerifiedTransaction) async -> EntitlementVerifierDecision
}

struct PassThroughEntitlementVerifier: EntitlementVerifier {
    func verify(_ transaction: PremiumVerifiedTransaction) async -> EntitlementVerifierDecision {
        .accepted(transaction)
    }
}

struct PremiumEntitlementSnapshot: Codable, Equatable {
    static let schemaVersion = 1

    var schemaVersion: Int = Self.schemaVersion
    var unlocked: Bool
    var productID: String?
    var lastVerifiedAt: Date?
    var ownershipType: PremiumOwnershipType
    var revocationReason: String?

    static let locked = PremiumEntitlementSnapshot(
        unlocked: false,
        productID: nil,
        lastVerifiedAt: nil,
        ownershipType: .unknown,
        revocationReason: nil
    )
}

enum PremiumNoticeKind: String, Identifiable {
    case purchaseCompleted
    case purchaseRevoked
    case restoreEmpty
    case refundSubmitted
    case refundCancelled
    case refundFailed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .purchaseCompleted: "Premium 已解锁"
        case .purchaseRevoked: "Premium 已恢复锁定"
        case .restoreEmpty: "未找到可恢复的购买"
        case .refundSubmitted: "退款请求已提交"
        case .refundCancelled: "未提交退款请求"
        case .refundFailed: "退款请求失败"
        }
    }

    var message: String {
        switch self {
        case .purchaseCompleted:
            "购买已完成，Premium 功能已经解锁。"
        case .purchaseRevoked:
            "购买已退款或撤销，Premium 功能已恢复锁定。"
        case .restoreEmpty:
            "请确认使用的是购买时的 Apple ID。"
        case .refundSubmitted:
            "退款审核中，Apple 处理完成后权益会自动更新。"
        case .refundCancelled:
            "你关闭了退款申请窗口，当前购买状态保持不变。"
        case .refundFailed:
            "暂时无法发起退款请求，请稍后再试。"
        }
    }
}

enum PremiumPaywallSource: Equatable {
    case settings
    case feature(PremiumFeature)
    case shareTemplate(PremiumShareTemplateID)
    case historyExport
    case widget
    case deepLink
}

@MainActor
final class PremiumPaywallController: ObservableObject {
    @Published var isPresented = false
    @Published private(set) var source: PremiumPaywallSource = .settings

    func present(_ source: PremiumPaywallSource = .settings) {
        self.source = source
        isPresented = true
        premiumLogger.info("paywall_view source=\(String(describing: source), privacy: .public)")
    }

    func dismiss() {
        isPresented = false
    }
}

struct PremiumSettingsCardPresentation: Equatable {
    struct FeatureRow: Identifiable, Equatable {
        var feature: PremiumFeature
        var isLocked: Bool

        var id: PremiumFeature { feature }
    }

    struct ThemeOption: Identifiable, Equatable {
        var theme: PremiumThemeID
        var title: String
        var isSelected: Bool
        var isLocked: Bool

        var id: PremiumThemeID { theme }

        var accessibilityLabel: String {
            isLocked ? "\(title)，Premium 专属，可预览" : title
        }
    }

    struct ShareTemplateOption: Identifiable, Equatable {
        var template: PremiumShareTemplateID
        var title: String
        var isSelected: Bool
        var isLocked: Bool

        var id: PremiumShareTemplateID { template }
    }

    var isUnlocked: Bool
    var isPending: Bool
    var subtitle: String
    var primaryActionTitle: String
    var primaryActionIsUnlocked: Bool
    var refundActionIsUnlocked: Bool
    var inlineMessage: String?
    var exportTrailingSymbol: String

    init(
        accessState: PremiumAccessState,
        displayPrice: String,
        statusMessage: String?,
        refundRequestedAt: Date?,
        canMakePayments: Bool = true,
        refundDateFormatter: (Date) -> String = { $0.formatted(date: .abbreviated, time: .omitted) }
    ) {
        isUnlocked = accessState == .unlocked
        isPending = accessState == .pendingApproval
        subtitle = isUnlocked
            ? "小组件、主题、模板和导出已解锁"
            : "一次买断，解锁桌面小组件、主题、分享模板和历史导出。"
        primaryActionTitle = isUnlocked ? "已解锁" : displayPrice
        primaryActionIsUnlocked = isUnlocked
        refundActionIsUnlocked = isUnlocked
        exportTrailingSymbol = isUnlocked ? "arrow.right" : "lock.fill"

        if isPending {
            inlineMessage = "等待 Apple ID 批准购买。批准后 Premium 会自动解锁。"
        } else if let refundRequestedAt {
            inlineMessage = "退款审核中（提交于 \(refundDateFormatter(refundRequestedAt))）。"
        } else if let statusMessage {
            inlineMessage = statusMessage
        } else if !canMakePayments {
            inlineMessage = PremiumStoreError.paymentNotAllowed.errorDescription
        } else {
            inlineMessage = nil
        }
    }

    func featureRows() -> [FeatureRow] {
        PremiumFeature.allCases.map {
            FeatureRow(feature: $0, isLocked: !isUnlocked)
        }
    }

    func themeOptions(activeTheme: PremiumThemeID) -> [ThemeOption] {
        PremiumThemeID.allCases.map {
            ThemeOption(
                theme: $0,
                title: $0.title,
                isSelected: activeTheme == $0,
                isLocked: $0.isPremium && !isUnlocked
            )
        }
    }

    func shareTemplateOptions(selectedTemplate: PremiumShareTemplateID) -> [ShareTemplateOption] {
        PremiumShareTemplateID.allCases.map {
            ShareTemplateOption(
                template: $0,
                title: $0.title,
                isSelected: selectedTemplate == $0,
                isLocked: $0.isPremium && !isUnlocked
            )
        }
    }
}

struct PremiumThemePalette: Equatable {
    var bg: Color
    var bgWarm: Color
    var surfaceSoft: Color
    var yellow: Color
    var gold: Color
    var ink: Color
    var inkSoft: Color
    var muted: Color
    var cyan: Color
    var cyanSoft: Color
    var coral: Color
    var coralSoft: Color
}

enum PremiumThemeID: String, CaseIterable, Identifiable, Codable {
    case classic
    case nightShift
    case mintReceipt
    case punchCard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "默认金币"
        case .nightShift: "加班夜色"
        case .mintReceipt: "薄荷小票"
        case .punchCard: "打卡珊瑚"
        }
    }

    var isPremium: Bool { self != .classic }

    var palette: PremiumThemePalette {
        switch self {
        case .classic:
            PremiumThemePalette(
                bg: Color(red: 1.0, green: 0.9647, blue: 0.8980),
                bgWarm: Color(red: 0.9882, green: 0.9176, blue: 0.7176),
                surfaceSoft: Color(red: 1.0, green: 0.9451, blue: 0.8235),
                yellow: Color(red: 1.0, green: 0.7843, blue: 0.2392),
                gold: Color(red: 1.0, green: 0.8235, blue: 0.3020),
                ink: Color(red: 0.0510, green: 0.0510, blue: 0.0510),
                inkSoft: Color(red: 0.2275, green: 0.2078, blue: 0.1882),
                muted: Color(red: 0.6039, green: 0.5765, blue: 0.5412),
                cyan: Color(red: 0.0, green: 0.8980, blue: 1.0),
                cyanSoft: Color(red: 0.7137, green: 0.9608, blue: 0.9843),
                coral: Color(red: 1.0, green: 0.3608, blue: 0.3412),
                coralSoft: Color(red: 1.0, green: 0.8431, blue: 0.8235)
            )
        case .nightShift:
            PremiumThemePalette(
                bg: Color(red: 0.95, green: 0.94, blue: 0.88),
                bgWarm: Color(red: 0.16, green: 0.18, blue: 0.24),
                surfaceSoft: Color(red: 0.89, green: 0.87, blue: 0.78),
                yellow: Color(red: 0.94, green: 0.78, blue: 0.30),
                gold: Color(red: 0.98, green: 0.64, blue: 0.24),
                ink: Color(red: 0.08, green: 0.10, blue: 0.14),
                inkSoft: Color(red: 0.25, green: 0.27, blue: 0.32),
                muted: Color(red: 0.48, green: 0.47, blue: 0.43),
                cyan: Color(red: 0.28, green: 0.76, blue: 0.84),
                cyanSoft: Color(red: 0.75, green: 0.92, blue: 0.92),
                coral: Color(red: 0.94, green: 0.34, blue: 0.30),
                coralSoft: Color(red: 0.97, green: 0.78, blue: 0.72)
            )
        case .mintReceipt:
            PremiumThemePalette(
                bg: Color(red: 0.94, green: 0.98, blue: 0.94),
                bgWarm: Color(red: 0.78, green: 0.93, blue: 0.82),
                surfaceSoft: Color(red: 0.86, green: 0.96, blue: 0.86),
                yellow: Color(red: 0.72, green: 0.86, blue: 0.36),
                gold: Color(red: 0.56, green: 0.78, blue: 0.34),
                ink: Color(red: 0.08, green: 0.16, blue: 0.12),
                inkSoft: Color(red: 0.25, green: 0.34, blue: 0.28),
                muted: Color(red: 0.48, green: 0.58, blue: 0.50),
                cyan: Color(red: 0.06, green: 0.66, blue: 0.62),
                cyanSoft: Color(red: 0.74, green: 0.93, blue: 0.89),
                coral: Color(red: 0.96, green: 0.38, blue: 0.32),
                coralSoft: Color(red: 0.99, green: 0.82, blue: 0.78)
            )
        case .punchCard:
            PremiumThemePalette(
                bg: Color(red: 1.00, green: 0.94, blue: 0.90),
                bgWarm: Color(red: 1.00, green: 0.80, blue: 0.69),
                surfaceSoft: Color(red: 1.00, green: 0.89, blue: 0.82),
                yellow: Color(red: 1.00, green: 0.70, blue: 0.32),
                gold: Color(red: 0.94, green: 0.54, blue: 0.25),
                ink: Color(red: 0.12, green: 0.08, blue: 0.08),
                inkSoft: Color(red: 0.32, green: 0.22, blue: 0.20),
                muted: Color(red: 0.62, green: 0.46, blue: 0.42),
                cyan: Color(red: 0.00, green: 0.70, blue: 0.82),
                cyanSoft: Color(red: 0.80, green: 0.94, blue: 0.96),
                coral: Color(red: 1.00, green: 0.30, blue: 0.28),
                coralSoft: Color(red: 1.00, green: 0.78, blue: 0.73)
            )
        }
    }
}

enum PremiumThemeRuntime {
    @MainActor static var currentTheme: PremiumThemeID = .classic

    @MainActor static var palette: PremiumThemePalette {
        currentTheme.palette
    }
}

enum PremiumShareTemplateID: String, CaseIterable, Identifiable, Codable {
    case classic
    case overtimeReceipt
    case survivalBadge
    case quietLedger

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "默认战报"
        case .overtimeReceipt: "加班小票"
        case .survivalBadge: "幸存徽章"
        case .quietLedger: "低调账本"
        }
    }

    var isPremium: Bool { self != .classic }
}

@MainActor
final class PremiumPreferencesStore: ObservableObject {
    @Published private(set) var selectedTheme: PremiumThemeID
    @Published var previewTheme: PremiumThemeID? {
        didSet {
            applyThemeRuntime()
        }
    }
    @Published private(set) var selectedShareTemplate: PremiumShareTemplateID
    @Published var lockScreenWidgetShowsAmount: Bool {
        didSet {
            userDefaults.set(lockScreenWidgetShowsAmount, forKey: WNFShared.lockScreenShowsAmountKey)
            PremiumWidgetBridge.scheduleReload()
        }
    }

    private let userDefaults: UserDefaults

    var activeTheme: PremiumThemeID {
        previewTheme ?? selectedTheme
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        selectedTheme = PremiumThemeID(rawValue: userDefaults.string(forKey: WNFShared.selectedThemeKey) ?? "") ?? .classic
        selectedShareTemplate = PremiumShareTemplateID(rawValue: userDefaults.string(forKey: WNFShared.selectedShareTemplateKey) ?? "") ?? .classic
        lockScreenWidgetShowsAmount = userDefaults.object(forKey: WNFShared.lockScreenShowsAmountKey) == nil
            ? true
            : userDefaults.bool(forKey: WNFShared.lockScreenShowsAmountKey)
        applyThemeRuntime()
    }

    func preview(_ theme: PremiumThemeID) {
        previewTheme = theme
    }

    func clearPreview() {
        previewTheme = nil
    }

    func selectTheme(_ theme: PremiumThemeID, isPremiumUnlocked: Bool) -> Bool {
        guard !theme.isPremium || isPremiumUnlocked else {
            preview(theme)
            return false
        }
        selectedTheme = theme
        previewTheme = nil
        userDefaults.set(theme.rawValue, forKey: WNFShared.selectedThemeKey)
        applyThemeRuntime()
        PremiumWidgetBridge.scheduleReload()
        return true
    }

    func selectShareTemplate(_ template: PremiumShareTemplateID, isPremiumUnlocked: Bool) -> Bool {
        guard !template.isPremium || isPremiumUnlocked else {
            return false
        }
        selectedShareTemplate = template
        userDefaults.set(template.rawValue, forKey: WNFShared.selectedShareTemplateKey)
        return true
    }

    private func applyThemeRuntime() {
        PremiumThemeRuntime.currentTheme = activeTheme
        objectWillChange.send()
    }
}

struct WNFWidgetSnapshot: Codable, Equatable {
    static let schemaVersion = 1

    var schemaVersion: Int = Self.schemaVersion
    var capturedAt: Date
    var earnedToday: Double
    var elapsedPaidMinutes: Int
    var workStartMinute: Int
    var workEndMinute: Int
    var statusLabel: String
    var isPremiumUnlocked: Bool
    var selectedTheme: PremiumThemeID
    var lockScreenShowsAmount: Bool
}

enum WNFWidgetSnapshotWriter {
    static func write(
        day: WageDay,
        workStartMinute: Int,
        workEndMinute: Int,
        statusLabel: String,
        isPremiumUnlocked: Bool,
        selectedTheme: PremiumThemeID,
        lockScreenShowsAmount: Bool
    ) {
        guard let userDefaults = UserDefaults(suiteName: WNFShared.appGroupID) else { return }
        let snapshot = WNFWidgetSnapshot(
            capturedAt: Date(),
            earnedToday: day.earnedToday,
            elapsedPaidMinutes: day.elapsedPaidMinutes,
            workStartMinute: workStartMinute,
            workEndMinute: workEndMinute,
            statusLabel: statusLabel,
            isPremiumUnlocked: isPremiumUnlocked,
            selectedTheme: selectedTheme,
            lockScreenShowsAmount: lockScreenShowsAmount
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            userDefaults.set(data, forKey: WNFShared.widgetSnapshotKey)
        }
    }
}

@MainActor
enum PremiumWidgetBridge {
    private static var reloadTask: Task<Void, Never>?

    static func scheduleReload(after delay: TimeInterval = 0.8) {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor in
            let nanoseconds = UInt64((delay * 1_000_000_000).rounded())
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

struct HistoryExportService {
    struct ExportEnvelope: Codable {
        var schemaVersion = 1
        var exportedAt: Date
        var records: [DailyWageRecord]
    }

    static func makeExportItems(state: WageState) throws -> [URL] {
        let now = Date()
        let liveRecord = state.dailyRecord(for: now, includingLiveToday: true)
        var recordsByKey = state.dailyRecords
        if let liveRecord {
            recordsByKey[liveRecord.dateKey] = liveRecord
        }
        let records = recordsByKey.keys.sorted().compactMap { recordsByKey[$0] }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WNFExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let csvURL = directory.appendingPathComponent("wonangfei-history.csv")
        let jsonURL = directory.appendingPathComponent("wonangfei-history.json")
        try csvString(records: records).write(to: csvURL, atomically: true, encoding: .utf8)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(ExportEnvelope(exportedAt: now, records: records))
        try jsonData.write(to: jsonURL, options: .atomic)
        premiumLogger.info("export_completed recordCount=\(records.count, privacy: .public)")
        return [csvURL, jsonURL]
    }

    private static func csvString(records: [DailyWageRecord]) -> String {
        let formatter = ISO8601DateFormatter()
        var rows = ["\u{FEFF}date,earned_today,target_today,elapsed_paid_minutes,workday_minutes,hourly_rate,monthly_salary,workdays_per_month,captured_at,source"]
        rows += records.map { record in
            [
                record.dateKey,
                decimal(record.earnedToday),
                decimal(record.targetToday),
                "\(record.elapsedPaidMinutes)",
                "\(record.workdayMinutes)",
                decimal(record.hourlyRate),
                decimal(record.monthlySalary),
                "\(record.workdaysPerMonth)",
                formatter.string(from: record.capturedAt),
                record.source.rawValue
            ].joined(separator: ",")
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private static func decimal(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

enum PremiumDeepLink {
    static func isPremiumRoute(_ url: URL) -> Bool {
        if url.scheme == "wonangfei", url.host == "premium" || url.path == "/premium" {
            return true
        }
        if url.scheme == "https", url.host == "wonangfei.app", url.path == "/premium" {
            return true
        }
        return false
    }
}
