import XCTest

func launchMainShell() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-wnf.onboarding.completed", "1"]
    app.launch()
    return app
}
