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
                    } else {
                        state.persistCurrentDaySnapshot()
                        writeWidgetSnapshot()
                        state.pauseCalendarDayTimer()
                    }
                }
                .onAppear {
                    writeWidgetSnapshot()
                }
                .onChange(of: state.privacyMode) { _, _ in
                    writeWidgetSnapshot()
                }
        }
    }

    private func writeWidgetSnapshot() {
        let day = state.calculation
        let presentation = WorkStatusPresentation(status: day.status)
        let wrote = WNFWidgetSnapshotWriter.write(
            day: day,
            workStartMinute: state.workStart.minutesInDay,
            workEndMinute: state.workEnd.minutesInDay,
            statusLabel: presentation.label,
            hidesSensitiveInfo: state.privacyMode
        )
        if wrote {
            WNFWidgetReloader.scheduleReload()
        }
    }
}
