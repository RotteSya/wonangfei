import ActivityKit
import Foundation

/// Owns the single 窝囊费 Live Activity. Mirrors the `ClockOutReminderService`
/// pattern: `WageState` calls `reconcile` from every hook that can change
/// whether the activity should exist (scene became active, settings edited,
/// settlement completed, day rolled over); this type decides start/update/end.
@MainActor
enum WNFLiveActivityController {
    private static var minuteRefreshTask: Task<Void, Never>?

    // MARK: Lifecycle hooks

    /// Bring the activity in line with the current wage state.
    static func reconcile(state: WageState, now: Date = Date()) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let dateKey = WNFWidgetDate.dateKey(for: now)
        guard state.liveActivityEnabled, !state.isTodaySettled else {
            endAll()
            return
        }

        let day = state.liveDay(at: now)
        let shouldRun: Bool
        switch day.status {
        case .morning, .lunch, .afternoon, .done:
            shouldRun = true
        case .off, .before:
            shouldRun = false
        }
        guard shouldRun else {
            endAll()
            return
        }

        let content = contentState(state: state, day: day, now: now)
        let stale = staleDate(for: content, now: now)
        Task { await apply(dateKey: dateKey, content: content, staleDate: stale) }
    }

    /// Foreground minute-tick so the money figure never drifts far while the
    /// user can see both the app and the island.
    static func beginMinuteRefresh(state: WageState) {
        endMinuteRefresh()
        minuteRefreshTask = Task { @MainActor [weak state] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                guard !Task.isCancelled, let state else { return }
                reconcile(state: state)
            }
        }
    }

    static func endMinuteRefresh() {
        minuteRefreshTask?.cancel()
        minuteRefreshTask = nil
    }

    static func endAll() {
        Task { await endAllActivities() }
    }

    /// ActivityKit objects are obtained off the main actor so ending/updating
    /// them does not send a MainActor-isolated `Activity` into a concurrent task.
    nonisolated private static func endAllActivities() async {
        for activity in Activity<WNFLiveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    nonisolated private static func apply(
        dateKey: String,
        content: WNFLiveActivityAttributes.ContentState,
        staleDate: Date
    ) async {
        for activity in Activity<WNFLiveActivityAttributes>.activities
        where activity.attributes.dateKey != dateKey {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        let payload = ActivityContent(state: content, staleDate: staleDate)
        if let activity = Activity<WNFLiveActivityAttributes>.activities
            .first(where: { $0.attributes.dateKey == dateKey }) {
            await activity.update(payload)
        } else {
            let attributes = WNFLiveActivityAttributes(dateKey: dateKey)
            _ = try? Activity.request(attributes: attributes, content: payload)
        }
    }

    // MARK: State derivation

    private static func contentState(
        state: WageState,
        day: WageDay,
        now: Date
    ) -> WNFLiveActivityAttributes.ContentState {
        let startOfDay = WNFWidgetDate.calendar.startOfDay(for: now)
        let start = WNFWidgetDate.date(on: startOfDay, minute: day.startMinute) ?? now
        let end = WNFWidgetDate.date(on: startOfDay, minute: day.endMinute) ?? now
        return WNFLiveActivityAttributes.ContentState(
            refDate: now,
            earnedAtRef: day.earnedToday,
            workdayStart: start,
            workdayEnd: end,
            isDone: day.status == .done,
            hidesAmount: state.privacyMode
        )
    }

    private static func staleDate(
        for content: WNFLiveActivityAttributes.ContentState,
        now: Date
    ) -> Date {
        // Once下班, the figure is final — never stale. Mid-day, mark the money
        // stale after 30 minutes without refresh so the system can dim it.
        content.isDone ? now.addingTimeInterval(24 * 60 * 60) : now.addingTimeInterval(30 * 60)
    }
}
