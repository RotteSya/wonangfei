import XCTest

/// Choreographed end-to-end tour of every new interaction, designed to run
/// while `simctl io recordVideo` captures the framebuffer. Each leg logs a
/// wall-clock marker so video frames can be mapped back to interactions.
final class JellyTourUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testOnboardingCompletionSurvivesIsolatedRestart() throws {
        let stateID = UUID().uuidString
        let app = launchOnboardingShell(stateID: stateID)
        let skip = app.buttons["跳到最后一步"]
        requireHittable(skip, "a new session should start with onboarding", timeout: 8)
        skip.tap()
        let finish = app.buttons["开始使用"]
        requireHittable(finish, "the last onboarding page should be reachable")
        finish.tap()
        let money = app.descendants(matching: .any)["home.money"].firstMatch
        XCTAssertTrue(money.waitForExistence(timeout: 8))
        let entranceFinished = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"), object: money
        )
        XCTAssertEqual(XCTWaiter().wait(for: [entranceFinished], timeout: 8), .completed)
        app.terminate()

        let restored = launchOnboardingShell(stateID: stateID)
        XCTAssertTrue(restored.descendants(matching: .any)["home.money"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(restored.buttons["跳到最后一步"].exists)
        restored.terminate()

        let fresh = launchOnboardingShell(stateID: UUID().uuidString)
        XCTAssertTrue(fresh.buttons["跳到最后一步"].waitForExistence(timeout: 8))
        fresh.terminate()
    }

    private func mark(_ label: String, _ start: Date) {
        print("TOUR-MARK \(String(format: "%07.2f", Date().timeIntervalSince(start)))s \(label)")
    }

    private func attachScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func requireHittable(_ element: XCUIElement, _ message: String, timeout: TimeInterval = 4) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), message)
        XCTAssertTrue(element.isHittable, message)
    }

    private func requireText(_ app: XCUIApplication, _ text: String, _ message: String) {
        XCTAssertTrue(app.staticTexts[text].firstMatch.waitForExistence(timeout: 3), message)
    }

    func testGrandTour() throws {
        let app = launchMainShell()
        let t0 = Date()

        // 1. Watch the odometer tick + coins drop on home.
        mark("home-idle", t0)
        sleep(4)
        attachScreen("design-qa-home")

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
        attachScreen("design-qa-records")

        // 5. Scrub the chart slowly left → right.
        let chart = app.descendants(matching: .any)["records.chart"].firstMatch
        if chart.waitForExistence(timeout: 2) == false || chart.isHittable == false {
            window.swipeUp()
        }
        requireHittable(chart, "records chart should be on screen", timeout: 4)
        mark("chart-scrub", t0)
        let chartLeft = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5))
        let chartRight = chart.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5))
        chartLeft.press(forDuration: 0.1, thenDragTo: chartRight, withVelocity: 160, thenHoldForDuration: 0.2)
        sleep(1)

        // 6. Switch periods: 周 then 年 (bars regrow with stagger).
        let month = app.buttons["records.period.month"].firstMatch
        let week = app.buttons["records.period.week"].firstMatch
        let year = app.buttons["records.period.year"].firstMatch
        if week.isHittable == false {
            window.swipeDown()
        }
        requireHittable(month, "month period should be on screen")
        requireHittable(week, "week period should be on screen")
        requireHittable(year, "year period should be on screen")
        requireText(app, "本月窝囊费", "records should open on the month total")
        mark("period-week", t0)
        week.tap()
        requireText(app, "本周窝囊费", "week period should show the week total")
        XCTAssertFalse(app.staticTexts["本月窝囊费"].firstMatch.exists)
        mark("period-year", t0)
        year.tap()
        requireText(app, "本年窝囊费", "year period should show the year total")
        XCTAssertFalse(app.staticTexts["本周窝囊费"].firstMatch.exists)
        sleep(1)

        // 7. The retention layer must remain reachable below the data cards.
        let badges = app.descendants(matching: .any)["records.badges"].firstMatch
        for _ in 0..<3 where !badges.isHittable {
            window.swipeUp()
        }
        XCTAssertTrue(badges.waitForExistence(timeout: 3), "achievement badges should remain in records")
        XCTAssertTrue(badges.isHittable, "achievement badges should be reachable by scrolling")
        attachScreen("design-qa-records-badges")

        // 8. Continue to settings, then flick all the way back to home.
        mark("swipe-to-settings", t0)
        right.press(forDuration: 0.05, thenDragTo: left, withVelocity: 900, thenHoldForDuration: 0.05)
        sleep(2)
        attachScreen("design-qa-settings")
        mark("flick-back-records", t0)
        left.press(forDuration: 0.05, thenDragTo: right, withVelocity: 1600, thenHoldForDuration: 0.02)
        sleep(1)
        mark("flick-back-home", t0)
        left.press(forDuration: 0.05, thenDragTo: right, withVelocity: 1600, thenHoldForDuration: 0.02)
        sleep(2)

        // 9. Tab-bar taps (pill morph + jelly kick): 记录 → 我的 → 首页.
        let tabRecords = app.buttons["tab.records"].firstMatch
        let tabSettings = app.buttons["tab.settings"].firstMatch
        let tabHome = app.buttons["tab.home"].firstMatch
        requireHittable(tabRecords, "records tab should be hittable", timeout: 3)
        requireHittable(tabSettings, "settings tab should be hittable", timeout: 3)
        requireHittable(tabHome, "home tab should be hittable", timeout: 3)
        mark("tab-records", t0)
        tabRecords.tap()
        requireHittable(app.buttons["records.period.month"].firstMatch, "records period should show after the records tab")
        mark("tab-settings", t0)
        tabSettings.tap()
        let salary = app.staticTexts["月薪 · 税后"].firstMatch
        XCTAssertTrue(salary.waitForExistence(timeout: 4), "settings should show the salary row")
        mark("tab-home", t0)
        tabHome.tap()
        requireHittable(app.descendants(matching: .any)["home.money"].firstMatch, "home amount should show after the home tab")

        // 10. Share card genie in/out (regression check for the overlay stack).
        let share = app.buttons["home.share"].firstMatch
        requireHittable(share, "share button should be hittable", timeout: 3)
        mark("share-open", t0)
        share.tap()
        let cancel = app.buttons["share.cancel"].firstMatch
        requireHittable(cancel, "share cancel should be hittable", timeout: 4)
        mark("share-close", t0)
        cancel.tap()
        // The panel stays mounted and slides off. Closed means it no longer
        // takes taps, and the home amount does.
        let homeAmount = app.descendants(matching: .any)["home.money"].firstMatch
        let cardClosed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == false"),
            object: cancel
        )
        let homeReturned = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"),
            object: homeAmount
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [cardClosed, homeReturned], timeout: 4),
            .completed,
            "share card should close"
        )

        mark("tour-done", t0)
    }
}
