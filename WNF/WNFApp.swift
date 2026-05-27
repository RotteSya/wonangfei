import SwiftUI

@main
struct WNFApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var state = WageState()
    @StateObject private var premium = PremiumEntitlementStore()
    @StateObject private var premiumPreferences = PremiumPreferencesStore()
    @StateObject private var paywallController = PremiumPaywallController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environmentObject(premium)
                .environmentObject(premiumPreferences)
                .environmentObject(paywallController)
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        state.resumeCalendarDayTimer()
                        premium.handleSceneBecameActive()
                        state.autoSettleTodayIfNeeded()
                        writeWidgetSnapshot()
                        state.reconcileClockOutReminder()
                    } else {
                        state.persistCurrentDaySnapshot()
                        writeWidgetSnapshot()
                        state.pauseCalendarDayTimer()
                    }
                }
                .onChange(of: premium.accessState) { _, _ in
                    writeWidgetSnapshot()
                }
                .onChange(of: premiumPreferences.selectedTheme) { _, _ in
                    writeWidgetSnapshot()
                }
                .onChange(of: premiumPreferences.lockScreenWidgetShowsAmount) { _, _ in
                    writeWidgetSnapshot()
                }
                .onAppear {
                    state.autoSettleTodayIfNeeded()
                    writeWidgetSnapshot()
                }
        }
    }

    private func writeWidgetSnapshot() {
        let day = state.calculation
        let presentation = WorkStatusPresentation(status: day.status)
        WNFWidgetSnapshotWriter.write(
            day: day,
            workStartMinute: state.workStart.minutesInDay,
            workEndMinute: state.workEnd.minutesInDay,
            statusLabel: presentation.label,
            isPremiumUnlocked: premium.isPremiumUnlocked,
            selectedTheme: premiumPreferences.selectedTheme,
            lockScreenShowsAmount: premiumPreferences.lockScreenWidgetShowsAmount
        )
        PremiumWidgetBridge.scheduleReload()
    }
}
