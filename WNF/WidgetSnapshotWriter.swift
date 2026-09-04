import Foundation
import WidgetKit

enum WNFWidgetSnapshotWriter {
    /// Returns `true` when a new snapshot was actually persisted. The caller
    /// uses this to decide whether to schedule a widget timeline reload.
    @discardableResult
    static func write(
        day: WageDay,
        workStartMinute: Int,
        workEndMinute: Int,
        lunchStartMinute: Int,
        lunchEndMinute: Int,
        hasLunchBreak: Bool,
        selectedWeekdays: Set<Int>,
        statusLabel: String,
        hidesSensitiveInfo: Bool,
        overtimeEnd: Date? = nil,
        overtimeSeconds: Int = 0
    ) -> Bool {
        guard let userDefaults = UserDefaults(suiteName: WNFShared.appGroupID) else { return false }
        let capturedAt = Date()
        let snapshot = WNFWidgetSnapshot(
            dateKey: WNFWidgetDate.dateKey(for: capturedAt),
            capturedAt: capturedAt,
            earnedToday: day.earnedToday,
            elapsedPaidMinutes: day.elapsedPaidMinutes,
            workStartMinute: workStartMinute,
            workEndMinute: workEndMinute,
            lunchStartMinute: lunchStartMinute,
            lunchEndMinute: lunchEndMinute,
            hasLunchBreak: hasLunchBreak,
            includeOvertime: false,
            workdayMinutes: day.workdayMinutes,
            earningPerSecond: day.hourlyRate / 3600,
            selectedWeekdays: selectedWeekdays.sorted(),
            statusLabel: statusLabel,
            hidesSensitiveInfo: hidesSensitiveInfo,
            overtimeEnd: overtimeEnd,
            overtimeSeconds: overtimeSeconds
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
