import SwiftUI

@main
struct WNFApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var state = WageState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        state.resumeCalendarDayTimer()
                        writeWidgetSnapshot()
                        state.reconcileClockOutReminder()
                        WNFLiveActivityController.beginMinuteRefresh(state: state)
                    } else {
                        state.persistCurrentDaySnapshot()
                        writeWidgetSnapshot()
                        state.pauseCalendarDayTimer()
                        WNFLiveActivityController.endMinuteRefresh()
                    }
                }
                .onAppear {
                    writeWidgetSnapshot()
                }
                .onChange(of: state.privacyMode) { _, _ in
                    writeWidgetSnapshot()
                }
                .onChange(of: state.monthlySalary) { _, _ in
                    writeWidgetSnapshot()
                }
                .onChange(of: state.workdaysPerMonth) { _, _ in
                    writeWidgetSnapshot()
                }
                .onChange(of: state.workStart) { _, _ in
                    writeWidgetSnapshot()
                }
                .onChange(of: state.workEnd) { _, _ in
                    writeWidgetSnapshot()
                }
                .onChange(of: state.lunchStart) { _, _ in
                    writeWidgetSnapshot()
                }
                .onChange(of: state.lunchEnd) { _, _ in
                    writeWidgetSnapshot()
                }
                .onChange(of: state.hasLunchBreak) { _, _ in
                    writeWidgetSnapshot()
                }
                .onChange(of: state.includeOvertime) { _, _ in
                    writeWidgetSnapshot()
                }
                .onChange(of: state.selectedWeekdays) { _, _ in
                    writeWidgetSnapshot()
                }
        }
    }

    private func writeWidgetSnapshot() {
        let day = state.liveDay
        let presentation = WorkStatusPresentation(status: day.status)
        let wrote = WNFWidgetSnapshotWriter.write(
            day: day,
            workStartMinute: state.workStart.minutesInDay,
            workEndMinute: state.workEnd.minutesInDay,
            lunchStartMinute: state.lunchStart.minutesInDay,
            lunchEndMinute: state.lunchEnd.minutesInDay,
            hasLunchBreak: state.hasLunchBreak,
            includeOvertime: state.includeOvertime,
            selectedWeekdays: state.selectedWeekdays,
            statusLabel: presentation.label,
            hidesSensitiveInfo: state.privacyMode
        )
        if wrote {
            WNFWidgetReloader.scheduleReload()
        }
        WNFLiveActivityController.reconcile(state: state)
    }
}
