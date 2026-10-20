import XCTest

func launchMainShell() -> XCUIApplication {
    launchApp(
        arguments: ["-wnf.test.suppressClockOut"],
        stateID: UUID().uuidString
    )
}

func launchClockOutShell(now: String, stateID: String) -> XCUIApplication {
    launchApp(
        arguments: ["-wnf.test.now", now],
        stateID: stateID
    )
}

func launchOnboardingShell(stateID: String) -> XCUIApplication {
    launchApp(arguments: ["-wnf.test.suppressClockOut"], stateID: stateID, skipsOnboarding: false)
}

private func launchApp(
    arguments: [String],
    stateID: String,
    skipsOnboarding: Bool = true
) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += [
        "-wnf.test.stateID", stateID
    ] + arguments
    if skipsOnboarding {
        app.launchArguments += ["-wnf.onboarding.completed", "1"]
        app.launchEnvironment["WNF_SKIP_ONBOARDING"] = "1"
    }
    app.launch()
    if skipsOnboarding {
        skipOnboardingIfNeeded(app)
    }
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
