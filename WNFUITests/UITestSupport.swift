import XCTest

func launchMainShell() -> XCUIApplication {
    launchApp(
        arguments: ["-wnf.test.suppressClockOut"],
        stateID: UUID().uuidString
    )
}

func launchClockOutShell(now: String, stateID: String) -> XCUIApplication {
    let arguments = ["-wnf.test.now", now]
    var app = launchApp(arguments: arguments, stateID: stateID)
    // Some simulator/Xcode versions drop argv on the first launch in a test
    // session. Verify the clock fixture before exercising the business flow.
    // Only retry launch setup once; never retry clock-out assertions.
    if !app.buttons["test.clock.jumpDeadline"].waitForExistence(timeout: 2) {
        app = launchApp(arguments: arguments, stateID: stateID)
    }
    XCTAssertTrue(
        app.buttons["test.clock.jumpDeadline"].waitForExistence(timeout: 2),
        "Simulator did not apply the requested frozen-clock launch arguments"
    )
    return app
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
    // A unit-test host or a manual simulator launch may still own this bundle.
    // Ensure the first UI test receives its clock and isolated-store arguments.
    app.terminate()
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
