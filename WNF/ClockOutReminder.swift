import Foundation
import OSLog
import UserNotifications

@MainActor
final class ClockOutReminderService {
    static let shared = ClockOutReminderService()

    private static let logger = Logger(subsystem: "com.wonangfei.app", category: "ClockOutReminder")
    private static let notificationIdPrefix = "wnf.clockout.weekday."

    private let center: UNUserNotificationCenter

    private init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// Current system-level notification authorization status. Settings UI uses this to
    /// decide whether the in-app toggle should expose a system-Settings hint.
    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Request authorization with alert + sound. Used when the user flips the toggle on.
    /// Returns whether the user granted the permission. `provisional` is also treated as granted
    /// for scheduling purposes.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        let status = await currentAuthorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                Self.logger.error("Notification authorization request failed: \(String(describing: error), privacy: .public)")
                return false
            }
        @unknown default:
            return false
        }
    }

    /// Idempotent reconcile: cancels any previously scheduled clock-out notifications and
    /// re-schedules a per-weekday repeating notification at workEnd if the feature is enabled
    /// and the user has granted authorization. Safe to call from app lifecycle events as well
    /// as setting changes.
    func reconcile(
        enabled: Bool,
        workEnd: DateComponents,
        selectedWeekdays: Set<Int>
    ) async {
        await cancelAllClockOutNotifications()

        guard enabled, !selectedWeekdays.isEmpty else { return }

        let status = await currentAuthorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            Self.logger.info("Skipping clock-out reminder scheduling because authorization status is \(String(describing: status), privacy: .public)")
            return
        }

        let hour = max(0, min(23, workEnd.hour ?? 18))
        let minute = max(0, min(59, workEnd.minute ?? 30))

        for appWeekday in selectedWeekdays.sorted() {
            guard let iosWeekday = Self.appWeekdayToiOSWeekday(appWeekday) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "今天可以结算窝囊费啦"
            content.body = "点开 App 看看今天的窝囊战绩。"
            content.sound = .default

            var dateComponents = DateComponents()
            dateComponents.hour = hour
            dateComponents.minute = minute
            dateComponents.weekday = iosWeekday

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let identifier = "\(Self.notificationIdPrefix)\(appWeekday)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

            do {
                try await center.add(request)
            } catch {
                Self.logger.error("Failed to schedule clock-out reminder \(identifier, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }

        Self.logger.info("Scheduled clock-out reminders for weekdays=\(selectedWeekdays.sorted(), privacy: .public) at \(hour, privacy: .public):\(minute, privacy: .public)")
    }

    private func cancelAllClockOutNotifications() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.notificationIdPrefix) }
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// App stores weekday as 0=Monday … 6=Sunday (matching `WageState.weekdayIndex`).
    /// `UNCalendarNotificationTrigger` uses Gregorian weekday 1=Sunday … 7=Saturday.
    static func appWeekdayToiOSWeekday(_ appWeekday: Int) -> Int? {
        switch appWeekday {
        case 0: return 2  // Mon
        case 1: return 3  // Tue
        case 2: return 4  // Wed
        case 3: return 5  // Thu
        case 4: return 6  // Fri
        case 5: return 7  // Sat
        case 6: return 1  // Sun
        default: return nil
        }
    }
}
