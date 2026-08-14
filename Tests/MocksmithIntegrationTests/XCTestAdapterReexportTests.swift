import MocksmithXCTest
import XCTest

final class XCTestAdapterReexportTests: XCTestCase {
    func testAdapterReexportsCoreMockAPIs() {
        let count: Count = .exactly(1)
        XCTAssertTrue(count.matches(1))
    }
}
