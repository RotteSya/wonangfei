import XCTest

/// Choreographed end-to-end tour of every new interaction, designed to run
/// while `simctl io recordVideo` captures the framebuffer. Each leg logs a
/// wall-clock marker so video frames can be mapped back to interactions.
final class JellyTourUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func mark(_ label: String, _ start: Date) {
        print("TOUR-MARK \(String(format: "%07.2f", Date().timeIntervalSince(start)))s \(label)")
    }

    func testGrandTour() throws {
        let app = XCUIApplication()
        app.launch()
        let t0 = Date()

        // 1. Watch the odometer tick + coins drop on home.
        mark("home-idle", t0)
        sleep(4)

        // 2. Long-press the money → charge squish + coin fountain.
        let money = app.descendants(matching: .any)["home.money"].firstMatch
        XCTAssertTrue(money.waitForExistence(timeout: 5), "money odometer should exist")
        mark("fountain-press", t0)
        money.press(forDuration: 0.7)
        sleep(2)

        // 3. Privacy toggle on and off (odometer → dots → back).
        let privacy = app.buttons["home.privacy"].firstMatch
        XCTAssertTrue(privacy.waitForExistence(timeout: 3))
        mark("privacy-on", t0)
        privacy.tap()
        sleep(1)
        mark("privacy-off", t0)
        privacy.tap()
        sleep(1)

        // 4. Slow interactive swipe home → records (jelly visible mid-drag).
        mark("swipe-to-records", t0)
        let window = app.windows.firstMatch
        let right = window.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.42))
        let left = window.coordinate(withNormalizedOffset: CGVector(dx: 0.10, dy: 0.42))
        right.press(forDuration: 0.05, thenDragTo: left, withVelocity: 420, thenHoldForDuration: 0.05)
        sleep(3) // records entrance choreography + bars grow

        // 5. Scrub the chart slowly left → right.
        let chart = app.descendants(matching: .any)["records.chart"].firstMatch
        if chart.waitForExistence(timeout: 4) {
            mark("chart-scrub", t0)
            let chartLeft = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5))
            let chartRight = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5))
            chartLeft.press(forDuration: 0.1, thenDragTo: chartRight, withVelocity: 160, thenHoldForDuration: 0.2)
            sleep(1)
        } else {
            // The chart may be below the fold on smaller devices.
            app.swipeUp()
            mark("chart-scrub-after-scroll", t0)
            sleep(1)
        }

        // 6. Switch periods: 周 then 年 (bars regrow with stagger).
        let week = app.buttons["records.period.week"].firstMatch
        if week.waitForExistence(timeout: 3) {
            mark("period-week", t0)
            week.tap()
            sleep(2)
            mark("period-year", t0)
            app.buttons["records.period.year"].firstMatch.tap()
            sleep(2)
        }

        // 7. Continue to settings, then flick all the way back to home.
        mark("swipe-to-settings", t0)
        right.press(forDuration: 0.05, thenDragTo: left, withVelocity: 900, thenHoldForDuration: 0.05)
        sleep(2)
        mark("flick-back-records", t0)
        left.press(forDuration: 0.05, thenDragTo: right, withVelocity: 1600, thenHoldForDuration: 0.02)
        sleep(1)
        mark("flick-back-home", t0)
        left.press(forDuration: 0.05, thenDragTo: right, withVelocity: 1600, thenHoldForDuration: 0.02)
        sleep(2)

        // 8. Tab-bar taps (pill morph + jelly kick): 记录 → 我的 → 首页.
        let tabRecords = app.buttons["tab.records"].firstMatch
        XCTAssertTrue(tabRecords.waitForExistence(timeout: 3), "tab bar should exist")
        mark("tab-records", t0)
        tabRecords.tap()
        sleep(2)
        mark("tab-settings", t0)
        app.buttons["tab.settings"].firstMatch.tap()
        sleep(2)
        mark("tab-home", t0)
        app.buttons["tab.home"].firstMatch.tap()
        sleep(2)

        // 9. Share card genie in/out (regression check for the overlay stack).
        let share = app.buttons["home.share"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 3))
        mark("share-open", t0)
        share.tap()
        sleep(3)
        mark("share-close", t0)
        let cancel = app.buttons["share.cancel"].firstMatch
        if cancel.waitForExistence(timeout: 2) {
            cancel.tap()
        } else {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18)).tap()
        }
        sleep(2)

        mark("tour-done", t0)
    }
}
