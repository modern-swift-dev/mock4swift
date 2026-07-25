import Mock4Swift
import Mock4SwiftXCTest
import XCTest

@Mockable private protocol XCTestGreetingService {
    func greeting(for name: String) -> String
}

/// Keep XCTestCase internal because Linux uses generated test discovery and does
/// not discover private XCTestCase subclasses.
final class Mock4SwiftXCTestSample: XCTestCase {
    func testXCTestUsesTheSameGeneratedDSL() {
        let service = XCTestGreetingServiceMock()

        // Only the verification adapter changes. Given, generated mocks, and
        // matcher syntax are shared with Swift Testing.
        Given(service).greeting(for: .value("Taylor")).willReturn("Hello, Taylor")

        let greeting = service.greeting(for: "Taylor")

        XCTAssertEqual(greeting, "Hello, Taylor")
        Verify(service, 1).greeting(for: .value("Taylor"))
    }
}
