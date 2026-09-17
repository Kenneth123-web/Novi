import XCTest

/// Skip as developer used the Ask/AI 150s URLSession, so a down or slow API
/// presented as "The server took too long to answer". This taps the real
/// button against the local API.
final class SkipTimeoutUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    func testSkipAsDeveloperLandsWithinAFewSeconds() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-demoSkipIntro", "YES",
            "-demoResetSession", "YES",
            "-demoFreshInstall", "YES",
        ]
        app.launch()

        let skip = app.buttons["Skip as developer"]
        XCTAssertTrue(skip.waitForExistence(timeout: 12), "Skip as developer never appeared")

        let started = Date()
        skip.tap()

        let timedOut = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS 'took too long'")
        ).firstMatch
        let welcome = app.staticTexts["Before the feed,"]
        let feed = app.staticTexts["For you"]
        let deadline = Date().addingTimeInterval(8)
        var arrived = false
        while Date() < deadline {
            if welcome.exists || feed.exists {
                arrived = true
                break
            }
            if timedOut.exists { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }

        XCTAssertTrue(arrived, "Skip as developer must open the product, not hang on the auth screen")
        XCTAssertFalse(timedOut.exists, "Skip as developer must not report a request timeout")
        XCTAssertLessThan(
            Date().timeIntervalSince(started), 8,
            "Skip as developer took too long on a local API"
        )
    }
}
