import AVFoundation
import SwiftUI
import Testing
@testable import WNF

@MainActor
struct HomeMascotPlaybackTests {
    @Test("真实视频跨越三个循环边界后仍播放，内存警告不清空当前项", .timeLimit(.minutes(2)))
    func loopsAndSurvivesMemoryPressure() async throws {
        let controller = HomeMascotVideoController()
        defer { controller.pauseAndRelease() }
        controller.start()
        let initial = try #require(controller.player.currentItem)
        controller.handleMemoryWarning()
        #expect(controller.player.currentItem === initial)
        #expect(controller.player.items().count == 2)

        var observed: Set<ObjectIdentifier> = [ObjectIdentifier(initial)]
        // Retain observed items so their identities cannot be recycled.
        var playedItems = [initial]
        let deadline = ContinuousClock.now.advanced(by: .seconds(65))
        while ContinuousClock.now < deadline, observed.count < 4 {
            try await Task.sleep(for: .milliseconds(250))
            if let item = controller.player.currentItem,
               observed.insert(ObjectIdentifier(item)).inserted {
                playedItems.append(item)
            }
        }
        #expect(playedItems.count >= 4)
        #expect(controller.player.error == nil)
        #expect(controller.player.rate > 0)
        #expect(!controller.player.items().isEmpty)
    }

    @Test("前后台、临时中断、切页及暂停时内存警告后恢复")
    func lifecycleRestoresPlayback() async throws {
        let controller = HomeMascotVideoController()
        let session = HomeMascotVideoSessionCoordinator(controller: controller)
        defer { controller.pauseAndRelease() }
        session.handleScenePhase(.active, selectedTab: .home, isHomeSessionVisible: true)
        let initial = try #require(controller.player.currentItem)
        session.handleScenePhase(.inactive, selectedTab: .home, isHomeSessionVisible: true)
        #expect(controller.player.rate == 0)
        #expect(controller.player.currentItem === initial)
        session.handleScenePhase(.active, selectedTab: .home, isHomeSessionVisible: true)
        try await assertAdvancing(controller)

        session.handleTabChange(to: .records, isHomeSessionVisible: false)
        #expect(controller.player.rate == 0)
        controller.handleMemoryWarning()
        #expect(controller.player.items().isEmpty)
        session.handleTabChange(to: .home, isHomeSessionVisible: true)
        try await assertAdvancing(controller)

        for _ in 0..<3 {
            session.handleScenePhase(.background, selectedTab: .home, isHomeSessionVisible: true)
            #expect(controller.player.items().isEmpty)
            #expect(controller.player.rate == 0)
            session.handleScenePhase(.active, selectedTab: .home, isHomeSessionVisible: true)
            try await assertAdvancing(controller)
        }

        session.handleScenePhase(.background, selectedTab: .records, isHomeSessionVisible: false)
        session.handleScenePhase(.active, selectedTab: .records, isHomeSessionVisible: false)
        #expect(controller.player.items().isEmpty)
        #expect(controller.player.rate == 0)
    }

    private func assertAdvancing(_ controller: HomeMascotVideoController) async throws {
        let initialTime = controller.player.currentTime().seconds
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
            if controller.player.currentTime().seconds > initialTime + 0.1 {
                return
            }
        }
        Issue.record("视频在恢复后 5 秒内未继续前进")
    }
}
