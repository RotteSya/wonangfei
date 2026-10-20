import Foundation

enum ClockOutPhase: Equatable {
    case working
    case decisionDue(deadline: Date, revision: Int)
    case promptDismissed(deadline: Date, revision: Int)
    case overtimeRunning(until: Date, revision: Int)
    case settled
    case offDay
}

struct ClockOutRuntimeState: Codable, Equatable {
    var dateKey: String
    var baseWorkEndMinute: Int
    var overtimeEnd: Date?
    var revision: Int
    var dismissedRevision: Int?
}

enum WNFClock {
    static let nowArgument = "-wnf.test.now"
    static let suppressClockOutArgument = "-wnf.test.suppressClockOut"

    nonisolated(unsafe) private static var sessionOverride: Date?

    static var isLaunchFrozen: Bool {
        launchArgumentDate() != nil
    }

    static var isOverridden: Bool {
        sessionOverride != nil || isLaunchFrozen
    }

    static var now: Date {
        sessionOverride ?? launchArgumentDate() ?? Date()
    }

    static func displayNow(_ timelineDate: Date) -> Date {
        isOverridden ? now : timelineDate
    }

    static func setOverride(_ date: Date) {
        sessionOverride = date
    }

    static func resetOverride() {
        sessionOverride = nil
    }

    static func shouldSuppressClockOutPrompt() -> Bool {
        ProcessInfo.processInfo.arguments.contains(suppressClockOutArgument)
    }

    static func launchArgumentDate() -> Date? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: nowArgument),
              arguments.indices.contains(index + 1)
        else {
            return nil
        }
        return parse(arguments[index + 1])
    }

    static func parse(_ raw: String) -> Date? {
        let local = DateFormatter()
        local.calendar = Calendar(identifier: .gregorian)
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .autoupdatingCurrent
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            local.dateFormat = format
            if let date = local.date(from: raw) {
                return date
            }
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) {
            return date
        }

        iso.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        iso.timeZone = .autoupdatingCurrent
        return iso.date(from: raw)
    }
}

/// UI tests pass `-wnf.test.stateID` so wage settings and daily records stay
/// out of the standard defaults and the App Group database.
enum WNFUITestIsolation {
    static let stateIDArgument = "-wnf.test.stateID"

    struct Resolved {
        var defaults: UserDefaults
        var databaseURL: URL?
    }

    @MainActor
    static func resolved(fallingBack defaults: UserDefaults) -> Resolved {
        guard let stateID = normalizedStateID(from: ProcessInfo.processInfo.arguments),
              let suite = UserDefaults(suiteName: "wnf.uitest.\(stateID)")
        else {
            return Resolved(defaults: defaults, databaseURL: nil)
        }
        return Resolved(defaults: suite, databaseURL: databaseURL(for: stateID))
    }

    static func normalizedStateID(from arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: stateIDArgument),
              arguments.indices.contains(index + 1)
        else {
            return nil
        }
        let raw = arguments[index + 1]
        guard (1...64).contains(raw.count), raw.hasPrefix("-") == false else { return nil }
        let scalars = raw.unicodeScalars
        let letters = CharacterSet.alphanumerics
        guard scalars.allSatisfy({ $0.isASCII && (letters.contains($0) || $0 == "-") }),
              scalars.contains(where: { letters.contains($0) })
        else {
            return nil
        }
        return raw
    }

    static func databaseURL(for stateID: String) -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("WNFUITest", isDirectory: true)
            .appendingPathComponent(stateID, isDirectory: true)
            .appendingPathComponent("DailyRecords.sqlite")
    }
}

enum ClockOutRuntimeEngine {
    static let overtimeStep: TimeInterval = 15 * 60
    static let defaultOvertimeDuration: TimeInterval = 60 * 60

    static func phase(
        isPaidWorkday: Bool,
        isSettled: Bool,
        runtime: ClockOutRuntimeState?,
        now: Date,
        startOfDay: Date
    ) -> ClockOutPhase {
        if isPaidWorkday == false {
            return .offDay
        }
        if isSettled {
            return .settled
        }
        guard let runtime else {
            return .working
        }

        let baseEnd = workEndDate(startOfDay: startOfDay, minute: runtime.baseWorkEndMinute)
        let deadline = runtime.overtimeEnd ?? baseEnd

        if let overtimeEnd = runtime.overtimeEnd, now < overtimeEnd {
            return .overtimeRunning(until: overtimeEnd, revision: runtime.revision)
        }

        if now < baseEnd {
            return .working
        }

        if runtime.dismissedRevision == runtime.revision {
            return .promptDismissed(deadline: deadline, revision: runtime.revision)
        }
        return .decisionDue(deadline: deadline, revision: runtime.revision)
    }

    static func makeTodaySnapshot(
        dateKey: String,
        workEndMinute: Int
    ) -> ClockOutRuntimeState {
        ClockOutRuntimeState(
            dateKey: dateKey,
            baseWorkEndMinute: workEndMinute,
            overtimeEnd: nil,
            revision: 0,
            dismissedRevision: nil
        )
    }

    static func dismiss(_ runtime: ClockOutRuntimeState) -> ClockOutRuntimeState {
        var next = runtime
        next.dismissedRevision = runtime.revision
        return next
    }

    static func beginOvertime(
        runtime: ClockOutRuntimeState,
        duration: TimeInterval,
        now: Date,
        startOfDay: Date
    ) -> ClockOutRuntimeState {
        let remaining = remainingOvertimeAllowance(now: now, startOfDay: startOfDay)
        let clampedDuration = max(0, min(duration, remaining))
        var next = runtime
        next.overtimeEnd = now.addingTimeInterval(clampedDuration)
        next.revision += 1
        next.dismissedRevision = nil
        return next
    }

    static func workEndDate(startOfDay: Date, minute: Int) -> Date {
        let calendar = DateComponents.calendar
        let clampedMinute = min(max(minute, 0), 23 * 60 + 59)
        return calendar.date(byAdding: .minute, value: clampedMinute, to: startOfDay) ?? startOfDay
    }

    static func endOfDay(for startOfDay: Date) -> Date {
        DateComponents.calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay)
            ?? startOfDay.addingTimeInterval(86_399)
    }

    static func remainingOvertimeAllowance(now: Date, startOfDay: Date) -> TimeInterval {
        max(0, endOfDay(for: startOfDay).timeIntervalSince(now))
    }

    static func overtimeDurationOptions(now: Date, startOfDay: Date) -> [TimeInterval] {
        let remaining = remainingOvertimeAllowance(now: now, startOfDay: startOfDay)
        guard remaining > 0 else { return [] }

        var options: [TimeInterval] = []
        var cursor = overtimeStep
        while cursor <= remaining + 0.5 {
            options.append(cursor)
            cursor += overtimeStep
        }

        if let last = options.last {
            if remaining - last > 1 {
                options.append(remaining)
            }
        } else {
            options.append(remaining)
        }
        return options
    }

    static func defaultOvertimeSelection(in options: [TimeInterval]) -> TimeInterval {
        if options.contains(defaultOvertimeDuration) {
            return defaultOvertimeDuration
        }
        return options.last(where: { $0 <= defaultOvertimeDuration }) ?? options.last ?? defaultOvertimeDuration
    }

    static func durationLabel(for duration: TimeInterval) -> String {
        let totalMinutes = max(1, Int((duration / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 {
            return "\(minutes) 分钟"
        }
        if minutes == 0 {
            return "\(hours) 小时"
        }
        return "\(hours) 小时 \(minutes) 分钟"
    }

    static func clockText(for date: Date) -> String {
        let components = DateComponents.calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}
