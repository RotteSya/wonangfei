import XCTest

final class ClockOutFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testClockOutDecisionOvertimeAndSettlement() throws {
        let app = launchClockOutShell(now: "2026-08-17T19:00:00")

        let confirm = app.descendants(matching: .any)["clockout.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 8), "大号下班决策应在截止后出现")
        XCTAssertTrue(
            app.staticTexts["到点了"].exists
                || app.descendants(matching: .any)["clockout.overlay"].firstMatch.exists
        )

        let overtime = app.descendants(matching: .any)["clockout.overtime"].firstMatch
        overtime.tap()
        let cancel = app.descendants(matching: .any)["overtime.cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 4), "加班时长选择应出现")
        XCTAssertTrue(app.staticTexts["还要再熬多久？"].exists)
        cancel.tap()

        XCTAssertTrue(confirm.waitForExistence(timeout: 4), "取消加班后应保持停表并回到决策层")

        overtime.tap()
        let overtimeConfirm = app.descendants(matching: .any)["overtime.confirm"].firstMatch
        XCTAssertTrue(overtimeConfirm.waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["预计熬到 20:00"].waitForExistence(timeout: 2))
        overtimeConfirm.tap()

        XCTAssertTrue(app.staticTexts["加班续命中"].waitForExistence(timeout: 4))
        XCTAssertFalse(confirm.exists)

        app.terminate()
        let appAfterDeadline = launchClockOutShell(now: "2026-08-17T20:00:01")
        let confirmAgain = appAfterDeadline.descendants(matching: .any)["clockout.confirm"].firstMatch
        XCTAssertTrue(confirmAgain.waitForExistence(timeout: 8), "加班截止后应再次出现大号下班决策")
        confirmAgain.tap()

        let share = appAfterDeadline.buttons["分享卡片"]
        XCTAssertTrue(share.waitForExistence(timeout: 8), "一次下班应进入结算仪式")

        let window = appAfterDeadline.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()

        let personalTime = appAfterDeadline.staticTexts["今日已下班 · 个人时间"]
        let settledCTA = appAfterDeadline.buttons["今日已下班 · 再看一眼"]
        XCTAssertTrue(
            personalTime.waitForExistence(timeout: 6) || settledCTA.waitForExistence(timeout: 2),
            "关闭结算卡后应进入个人时间态"
        )
    }
}
