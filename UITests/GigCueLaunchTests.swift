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
        XCTAssertTrue(app.textFields["show.newTitle"].exists)
        XCTAssertTrue(app.buttons["show.create"].exists)
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

    @MainActor
    func testShowBuilderCreateEditAndDuplicate() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()

        let titleField = app.textFields["show.newTitle"]
        XCTAssertTrue(titleField.waitForExistence(timeout: 10))
        titleField.tap()
        titleField.typeText("Tour Rehearsal")
        app.buttons["show.create"].tap()

        // Editor presented for new show
        let songTitle = app.textFields["editor.songTitle"]
        XCTAssertTrue(songTitle.waitForExistence(timeout: 5))
        songTitle.tap()
        songTitle.typeText("Opening Riff")

        let songKey = app.textFields["editor.songKey"]
        songKey.tap()
        songKey.typeText("D")

        let songTempo = app.textFields["editor.songTempo"]
        songTempo.tap()
        songTempo.typeText("124")

        let songCue = app.textFields["editor.songCue"]
        songCue.tap()
        songCue.typeText("Drum count-in 4 clicks")
        app.buttons["editor.addSong"].tap()

        let breakField = app.textFields["editor.breakTitle"]
        breakField.tap()
        breakField.typeText("Guitar Swap")
        app.buttons["editor.insertBreak"].tap()

        XCTAssertTrue(app.staticTexts["1. Opening Riff"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Guitar Swap"].exists)

        // Reorder: move song after the break.
        let moveDown = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'editor.moveDown.'"))
        XCTAssertTrue(moveDown.firstMatch.waitForExistence(timeout: 5))
        moveDown.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Guitar Swap"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2. Opening Riff"].exists)

        app.buttons["editor.done"].tap()

        // Back on Home, verify list entry and duplicate button
        XCTAssertTrue(app.staticTexts["Tour Rehearsal"].waitForExistence(timeout: 5))
        let duplicateButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'show.duplicate.'"))
        XCTAssertTrue(duplicateButtons.firstMatch.waitForExistence(timeout: 5))
        duplicateButtons.firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Tour Rehearsal Copy"].waitForExistence(timeout: 5))
    }
}
