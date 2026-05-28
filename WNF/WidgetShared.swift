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
}

enum WNFWidgetSnapshotWriter {
    static func write(
        day: WageDay,
        workStartMinute: Int,
        workEndMinute: Int,
        statusLabel: String
    ) {
        guard let userDefaults = UserDefaults(suiteName: WNFShared.appGroupID) else { return }
        let snapshot = WNFWidgetSnapshot(
            capturedAt: Date(),
            earnedToday: day.earnedToday,
            elapsedPaidMinutes: day.elapsedPaidMinutes,
            workStartMinute: workStartMinute,
            workEndMinute: workEndMinute,
            statusLabel: statusLabel
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            userDefaults.set(data, forKey: WNFShared.widgetSnapshotKey)
        }
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
