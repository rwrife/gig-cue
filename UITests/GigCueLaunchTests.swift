import XCTest

final class GigCueLaunchTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testBootstrapHomeLaunches() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        XCTAssertTrue(app.otherElements["bootstrap.home"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Gig Cue"].exists)
        XCTAssertTrue(app.staticTexts["Reorderable setlists, restart-safe stage progress, and high-contrast performance mode land in the next milestones."].exists)
    }
}
