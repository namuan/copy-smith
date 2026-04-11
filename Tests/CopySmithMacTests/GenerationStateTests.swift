import XCTest
@testable import CopySmithMac

final class GenerationStateTests: XCTestCase {

    func testIsAddable_normalText() {
        let s = ModeResultState(text: "Some output.", status: .done, generation: 1)
        XCTAssertTrue(s.isAddable)
    }

    func testIsAddable_queuedPlaceholder() {
        let s = ModeResultState(text: "Queued...", status: .queued, generation: 1)
        XCTAssertFalse(s.isAddable)
    }

    func testIsAddable_loadingPlaceholder() {
        let s = ModeResultState(text: "Loading...", status: .running, generation: 1)
        XCTAssertFalse(s.isAddable)
    }

    func testIsAddable_emptyText() {
        let s = ModeResultState(text: "", status: .done, generation: 1)
        XCTAssertFalse(s.isAddable)
    }

    func testIsLoading_running() {
        let s = ModeResultState(text: "x", status: .running, generation: 1)
        XCTAssertTrue(s.isLoading)
    }

    func testIsLoading_done() {
        let s = ModeResultState(text: "x", status: .done, generation: 1)
        XCTAssertFalse(s.isLoading)
    }

    func testIsError() {
        let s = ModeResultState(text: "oops", status: .error("oops"), generation: 1)
        XCTAssertTrue(s.isError)
        XCTAssertFalse(s.isLoading)
    }
}
