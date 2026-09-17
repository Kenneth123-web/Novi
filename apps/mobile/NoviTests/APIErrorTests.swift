import XCTest
@testable import Novi

final class APIErrorTests: XCTestCase {

    func testSkipTimeoutDoesNotTalkAboutQuestions() {
        let error = APIError.transport(URLError(.timedOut), longRunning: false)
        XCTAssertEqual(error.code, "REQUEST_TIMED_OUT")
        XCTAssertTrue(error.isTimeout)
        XCTAssertFalse(error.message.contains("question"))
        XCTAssertTrue(error.message.contains("Try again"))
    }

    func testAskTimeoutSuggestsAShorterQuestion() {
        let error = APIError.transport(URLError(.timedOut), longRunning: true)
        XCTAssertTrue(error.message.contains("shorter question"))
    }

    func testUnreachableHostIsNotATimeout() {
        let url = URL(string: "http://127.0.0.1:8000/v1/auth/dev-skip")
        let error = APIError.transport(URLError(.cannotConnectToHost), reaching: url)
        XCTAssertEqual(error.code, "NETWORK_UNREACHABLE")
        XCTAssertFalse(error.isTimeout)
        XCTAssertTrue(error.message.contains("127.0.0.1"))
    }
}
