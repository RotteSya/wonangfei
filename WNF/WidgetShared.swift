import Foundation
import WidgetKit

enum WNFShared {
    static let appGroupID = "group.com.wonangfei.app"
    static let widgetSnapshotKey = "wnf.widget.wage.snapshot.v1"
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
    var hidesSensitiveInfo: Bool

    var earnedTodayText: String {
        hidesSensitiveInfo ? "¥•••.••" : String(format: "¥%.2f", earnedToday)
    }

    init(
        schemaVersion: Int = Self.schemaVersion,
        capturedAt: Date,
        earnedToday: Double,
        elapsedPaidMinutes: Int,
        workStartMinute: Int,
        workEndMinute: Int,
        statusLabel: String,
        hidesSensitiveInfo: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.capturedAt = capturedAt
        self.earnedToday = earnedToday
        self.elapsedPaidMinutes = elapsedPaidMinutes
        self.workStartMinute = workStartMinute
        self.workEndMinute = workEndMinute
        self.statusLabel = statusLabel
        self.hidesSensitiveInfo = hidesSensitiveInfo
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case capturedAt
        case earnedToday
        case elapsedPaidMinutes
        case workStartMinute
        case workEndMinute
        case statusLabel
        case hidesSensitiveInfo
    }

    /// `Equatable` includes `capturedAt`, so a strict `==` between successive
    /// writes always differs even when nothing meaningful changed. This helper
    /// compares only the fields the widget actually renders — the gate used
    /// by `WNFWidgetSnapshotWriter.write` to suppress redundant disk writes
    /// + timeline reloads.
    func hasSameContent(as other: WNFWidgetSnapshot) -> Bool {
        schemaVersion == other.schemaVersion
            && earnedToday == other.earnedToday
            && elapsedPaidMinutes == other.elapsedPaidMinutes
            && workStartMinute == other.workStartMinute
            && workEndMinute == other.workEndMinute
            && statusLabel == other.statusLabel
            && hidesSensitiveInfo == other.hidesSensitiveInfo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        capturedAt = try container.decode(Date.self, forKey: .capturedAt)
        earnedToday = try container.decode(Double.self, forKey: .earnedToday)
        elapsedPaidMinutes = try container.decode(Int.self, forKey: .elapsedPaidMinutes)
        workStartMinute = try container.decode(Int.self, forKey: .workStartMinute)
        workEndMinute = try container.decode(Int.self, forKey: .workEndMinute)
        statusLabel = try container.decode(String.self, forKey: .statusLabel)
        hidesSensitiveInfo = try container.decodeIfPresent(Bool.self, forKey: .hidesSensitiveInfo) ?? false
    }
}

enum WNFWidgetSnapshotWriter {
    /// Returns `true` when a new snapshot was actually persisted. The caller
    /// uses this to decide whether to schedule a widget timeline reload —
    /// rapid privacy toggles or fg/bg swaps would otherwise re-encode the
    /// same content multiple times per second.
    @discardableResult
    static func write(
        day: WageDay,
        workStartMinute: Int,
        workEndMinute: Int,
        statusLabel: String,
        hidesSensitiveInfo: Bool
    ) -> Bool {
        guard let userDefaults = UserDefaults(suiteName: WNFShared.appGroupID) else { return false }
        let snapshot = WNFWidgetSnapshot(
            capturedAt: Date(),
            earnedToday: day.earnedToday,
            elapsedPaidMinutes: day.elapsedPaidMinutes,
            workStartMinute: workStartMinute,
            workEndMinute: workEndMinute,
            statusLabel: statusLabel,
            hidesSensitiveInfo: hidesSensitiveInfo
        )

        if let existingData = userDefaults.data(forKey: WNFShared.widgetSnapshotKey),
           let existing = try? JSONDecoder().decode(WNFWidgetSnapshot.self, from: existingData),
           existing.hasSameContent(as: snapshot) {
            return false
        }

        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        userDefaults.set(data, forKey: WNFShared.widgetSnapshotKey)
        return true
    }
}

@MainActor
enum WNFWidgetReloader {
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
