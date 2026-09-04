import XCTest

func launchMainShell() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += [
        "-wnf.onboarding.completed", "1",
        "-wnf.test.suppressClockOut"
    ]
    app.launchEnvironment["WNF_SKIP_ONBOARDING"] = "1"
    app.launch()
    skipOnboardingIfNeeded(app)
    return app
}

func launchClockOutShell(now: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += [
        "-wnf.onboarding.completed", "1",
        "-wnf.test.now", now
    ]
    app.launchEnvironment["WNF_SKIP_ONBOARDING"] = "1"
    app.launchEnvironment["WNF_TEST_NOW"] = now
    app.launch()
    skipOnboardingIfNeeded(app)
    return app
}

private func skipOnboardingIfNeeded(_ app: XCUIApplication) {
    let skip = app.buttons["跳到最后一步"]
    if skip.waitForExistence(timeout: 1) {
        skip.tap()
        let finish = app.buttons["开始使用"]
        if finish.waitForExistence(timeout: 2) {
            finish.tap()
        }
    }
}
