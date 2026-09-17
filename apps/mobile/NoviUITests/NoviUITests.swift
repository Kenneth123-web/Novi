import XCTest

/// The flows that decide what a new user sees, driven by real taps.
///
/// These run against the local API, because the questions they answer are
/// about what the server hands back: whether a fresh install starts empty,
/// and whether the answers the learner gives survive a relaunch. A mocked
/// backend would pass while the product was broken, which is exactly what
/// happened here.
final class NoviUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demoSkipIntro", "YES"] + extra
        app.launch()
        return app
    }

    // MARK: First run

    /// Fresh install → skip → the questionnaire, answered by tapping, → a
    /// feed built from those answers. Then a relaunch that must NOT ask again.
    func testFreshInstallAsksThenRemembers() {
        let app = launch(["-demoFreshInstall", "YES", "-demoSkipLogin", "YES"])

        let welcome = app.staticTexts["Before the feed,"]
        XCTAssertTrue(
            welcome.waitForExistence(timeout: 30),
            "A never-customised account must land on the questionnaire, not on a feed"
        )
        XCTAssertFalse(app.staticTexts["For you"].exists, "The feed must not be reachable yet")

        answerQuestionnaire(app)

        XCTAssertTrue(
            app.staticTexts["For you"].waitForExistence(timeout: 40),
            "Finishing the questionnaire must open the feed"
        )

        // Relaunch as a returning user: same install, no wipe.
        app.terminate()
        let again = launch([])
        XCTAssertTrue(
            again.staticTexts["For you"].waitForExistence(timeout: 40),
            "A returning launch must restore the saved profile, not re-ask"
        )
        XCTAssertFalse(
            again.staticTexts["Before the feed,"].exists,
            "The questionnaire must not reappear once it has been answered"
        )
    }

    /// Every step is answered the way a person would: tap a chip, tap
    /// Continue. Nothing here reaches into the app's state.
    private func answerQuestionnaire(_ app: XCUIApplication) {
        app.buttons["Let's go"].firstMatch.tap()

        tapChip(app, "High school")
        tapChip(app, "Grade 11")
        continueButton(app).tap()

        tapChip(app, "Mathematics")
        tapChip(app, "Physics")
        continueButton(app).tap()

        tapChip(app, "Mathematics")
        let goal = app.buttons["onboarding.focusGoal.mathematics"].firstMatch
        if !goal.waitForExistence(timeout: 6) {
            tapChip(app, "Choose a goal")
        } else {
            goal.tap()
        }
        tapChip(app, "Prepare for an exam")
        continueButton(app).tap()

        tapChip(app, "Calculus")
        tapChip(app, "Mechanics")
        continueButton(app).tap()

        tapChip(app, "Short videos")
        continueButton(app).tap()

        app.buttons["Start learning"].firstMatch.tap()
    }

    private func continueButton(_ app: XCUIApplication) -> XCUIElement {
        let button = app.buttons["Continue"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Continue never appeared")
        return button
    }

    private func tapChip(_ app: XCUIApplication, _ label: String) {
        let chip = app.buttons[label].firstMatch
        guard chip.waitForExistence(timeout: 10) else {
            XCTFail("No option called \(label)")
            return
        }
        chip.tap()
    }

    // MARK: Ask

    /// The keyboard has to be closable, and the composer has to stay visible
    /// while it is open. Both were broken: the tab stack ignored the keyboard
    /// safe area, so the keys covered the only input on the screen.
    func testAskKeyboardOpensAndCloses() {
        let app = launch(["-demoSkipLogin", "YES", "-demoTab", "ask"])

        let field = app.textViews["Ask anything…"].firstMatch
        let fallback = app.textFields["Ask anything…"].firstMatch
        let input = field.waitForExistence(timeout: 40) ? field : fallback
        XCTAssertTrue(input.waitForExistence(timeout: 20), "The composer is missing")

        input.tap()
        XCTAssertTrue(
            app.keyboards.element.waitForExistence(timeout: 10), "The keyboard never opened"
        )

        // The composer must still be on screen, above the keys.
        let keyboardTop = app.keyboards.element.frame.minY
        XCTAssertLessThan(
            input.frame.maxY, keyboardTop + 1,
            "The keyboard is covering the input"
        )

        app.buttons["Hide keyboard"].firstMatch.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: app.keyboards.element)
        waitForExpectations(timeout: 10)
    }
}
