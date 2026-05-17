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
                        state.refreshCalendarDayIfNeeded()
                    } else {
                        state.persistCurrentDaySnapshot()
                    }
                }
        }
    }
}
