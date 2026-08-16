import XCTest

/// Guards D2: in-app legal pages must render the bundled HTML immediately.
/// A remote-first load to a dead host used to sit on a timeout before fallback.
final class LegalDocumentUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPrivacyPolicyOpensFromBundle() throws {
        let app = XCUIApplication()
        app.launch()

        let settings = app.buttons["tab.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "settings tab should exist (onboarding must be completed)")
        settings.tap()

        let privacy = app.buttons["settings.legal.privacy"]
        let started = Date()
        while !privacy.exists, Date().timeIntervalSince(started) < 4 {
            app.swipeUp()
        }
        XCTAssertTrue(privacy.waitForExistence(timeout: 2), "privacy link should be reachable")

        let t0 = Date()
        privacy.tap()

        let title = app.navigationBars["Privacy Policy"]
        XCTAssertTrue(title.waitForExistence(timeout: 3), "legal sheet should appear without a network timeout")

        let exportLine = app.webViews.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "does not export wage history")
        ).firstMatch
        XCTAssertTrue(
            exportLine.waitForExistence(timeout: 3),
            "bundled privacy HTML should be visible immediately"
        )
        XCTAssertLessThan(
            Date().timeIntervalSince(t0),
            5,
            "legal page must not wait on a dead remote host"
        )

        let shot = XCUIScreen.main.screenshot()
        let url = URL(fileURLWithPath: "/tmp/wnf-d2/privacy-uitest.png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try shot.pngRepresentation.write(to: url)
    }
}
