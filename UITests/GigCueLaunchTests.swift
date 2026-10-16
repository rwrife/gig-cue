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

        XCTAssertTrue(app.buttons["stage.enter"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Gig Cue"].exists)
        XCTAssertTrue(app.staticTexts["Reorderable setlists, restart-safe stage progress, and high-contrast performance mode land in the next milestones."].exists)
    }

    @MainActor
    func testStageGuardedNextBreakAndRestartResume() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-reset-stage"]
        app.launch()

        app.buttons["stage.enter"].tap()
        let title = app.staticTexts["stage.currentSongTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "First Track")

        // Next onto a break banner is immediate (no song skipped).
        // Kind-agnostic query: SwiftUI .accessibilityElement(children: .combine)
        // surfaces as group vs other depending on SDK, so don't pin the kind.
        app.buttons["stage.nextButton"].tap()
        let banner = app.descendants(matching: .any)
            .matching(identifier: "stage.breakBanner").firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 5))

        // Next song needs a deliberate confirming second tap.
        app.buttons["stage.nextButton"].tap()
        XCTAssertTrue(app.buttons["stage.nextButton"].label.contains("Tap again"))
        XCTAssertFalse(app.staticTexts["stage.currentSongTitle"].exists)
        app.buttons["stage.nextButton"].tap()
        XCTAssertTrue(app.staticTexts["stage.currentSongTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["stage.currentSongTitle"].label, "Closing Track")

        // Relaunch without reset: saved progress resumes on the same card.
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["-ui-testing"]
        relaunched.launch()
        relaunched.buttons["stage.enter"].tap()
        let resumed = relaunched.staticTexts["stage.currentSongTitle"]
        XCTAssertTrue(resumed.waitForExistence(timeout: 10))
        XCTAssertEqual(resumed.label, "Closing Track")
    }
}
