import XCTest
@testable import NotesSidecar

final class RedactorTests: XCTestCase {
    func testRedact_longInput_keepsLast4() {
        let r = Redactor().redact("super-secret-value-1234")
        XCTAssertTrue(r.contains("•••"))
        XCTAssertTrue(r.hasSuffix("1234"))
    }

    func testRedact_shortInput_becomesAllDots() {
        let r = Redactor().redact("abc")
        XCTAssertTrue(r.allSatisfy { $0 == "•" })
        XCTAssertGreaterThanOrEqual(r.count, 3)
    }

    func testHeaders_filterSensitive() {
        let headers = [
            "Authorization": "Bearer secret-token-1234567890",
            "x-api-key": "sk-1234567890abcdef",
            "Content-Type": "application/json"
        ]
        let redacted = Redactor().redact(headers)
        XCTAssertNotEqual(redacted["Authorization"], headers["Authorization"])
        XCTAssertNotEqual(redacted["x-api-key"], headers["x-api-key"])
        XCTAssertEqual(redacted["Content-Type"], "application/json")
    }

    func testTruncateBody_preservesBoundary() {
        let long = String(repeating: "Lorem ipsum dolor sit amet. ", count: 20)
        let t = Redactor().truncateBody(long, max: 50)
        XCTAssertLessThanOrEqual(t.count, 60)
    }
}