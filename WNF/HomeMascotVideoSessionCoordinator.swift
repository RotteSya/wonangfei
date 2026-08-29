import SwiftUI

@MainActor
final class HomeMascotVideoSessionCoordinator: ObservableObject {
    let controller: HomeMascotVideoController

    private var scenePhase: ScenePhase = .active
    private var selectedTab: AppTab = .home
    private var isHomeSessionVisible = false

    init(controller: HomeMascotVideoController? = nil) {
        self.controller = controller ?? HomeMascotVideoController()
    }

    func handleScenePhase(_ phase: ScenePhase, selectedTab: AppTab, isHomeSessionVisible: Bool) {
        scenePhase = phase
        self.selectedTab = selectedTab
        self.isHomeSessionVisible = isHomeSessionVisible

        switch phase {
        case .active:
            refreshPlayback()
        case .inactive:
            controller.pauseTemporarily()
        case .background:
            controller.pauseAndRelease()
        @unknown default:
            controller.pauseTemporarily()
        }
    }

    func handleTabChange(to tab: AppTab, isHomeSessionVisible: Bool) {
        selectedTab = tab
        self.isHomeSessionVisible = isHomeSessionVisible
        refreshPlayback()
    }

    private func refreshPlayback() {
        guard scenePhase == .active else { return }

        if selectedTab == .home && isHomeSessionVisible {
            controller.start()
        } else {
            controller.pauseTemporarily()
        }
    }
}
