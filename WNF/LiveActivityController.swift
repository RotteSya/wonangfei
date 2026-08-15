import ActivityKit
import Foundation

/// Owns the single 窝囊费 Live Activity. Mirrors the `ClockOutReminderService`
/// pattern: `WageState` calls `reconcile` from every hook that can change
/// whether the activity should exist (scene became active, settings edited,
/// settlement completed, day rolled over); this type decides start/update/end.
@MainActor
enum WNFLiveActivityController {
    private static var minuteRefreshTimer: Timer?

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

        // A stale activity from an earlier day can't be updated into today —
        // end it and start fresh.
        for activity in Activity<WNFLiveActivityAttributes>.activities
        where activity.attributes.dateKey != dateKey {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }

        if let activity = Activity<WNFLiveActivityAttributes>.activities
            .first(where: { $0.attributes.dateKey == dateKey }) {
            Task {
                await activity.update(ActivityContent(state: content, staleDate: staleDate(for: content, now: now)))
            }
        } else {
            let attributes = WNFLiveActivityAttributes(dateKey: dateKey)
            _ = try? Activity.request(
                attributes: attributes,
                content: ActivityContent(state: content, staleDate: staleDate(for: content, now: now))
            )
        }
    }

    /// Foreground minute-tick so the money figure never drifts far while the
    /// user can see both the app and the island.
    static func beginMinuteRefresh(state: WageState) {
        endMinuteRefresh()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak state] _ in
            guard let state else { return }
            Task { @MainActor in
                reconcile(state: state)
            }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        minuteRefreshTimer = timer
    }

    static func endMinuteRefresh() {
        minuteRefreshTimer?.invalidate()
        minuteRefreshTimer = nil
    }

    static func endAll() {
        for activity in Activity<WNFLiveActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
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
