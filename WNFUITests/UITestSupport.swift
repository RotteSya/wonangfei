import XCTest

func launchMainShell() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-wnf.onboarding.completed", "1"]
    app.launchEnvironment["WNF_SKIP_ONBOARDING"] = "1"
    app.launch()

    let skip = app.buttons["跳到最后一步"]
    if skip.waitForExistence(timeout: 1) {
        skip.tap()
        let finish = app.buttons["开始使用"]
        if finish.waitForExistence(timeout: 2) {
            finish.tap()
        }
    }
    return app
}
