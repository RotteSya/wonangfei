import SwiftUI

@main
struct WNFApp: App {
    @StateObject private var state = WageState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
        }
    }
}
