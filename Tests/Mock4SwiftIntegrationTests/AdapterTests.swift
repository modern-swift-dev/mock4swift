import Mock4Swift
import Mock4SwiftTesting
import Mock4SwiftXCTest
import Testing
import XCTest

final class AdapterTests: XCTestCase {
    func testInstanceAdaptersAcceptSuccessfulVerification() {
        let mock = InstanceMock()

        Mock4SwiftTesting.Verify(mock, .atLeast(1), ())
        Mock4SwiftTesting.Verify(mock, 1, ())
        Mock4SwiftXCTest.Verify(mock, .atLeast(1), ())
        Mock4SwiftXCTest.Verify(mock, 1, ())
    }

    func testStaticAdaptersAcceptSuccessfulVerification() {
        Mock4SwiftTesting.Verify(StaticTestMock.self, .atLeast(1), ())
        Mock4SwiftTesting.Verify(StaticTestMock.self, 1, ())
        Mock4SwiftXCTest.Verify(StaticTestMock.self, .atLeast(1), ())
        Mock4SwiftXCTest.Verify(StaticTestMock.self, 1, ())
    }

    #if canImport(Darwin)
    func testXCTestAdapterReportsMessageAndSourceLocation() {
        let expectedLine: UInt = 4242
        XCTExpectFailure(
            "The adapter failure is intentional",
            strict: true,
            failingBlock: {
                Mock4SwiftXCTest.Verify(FailingMock(), 1, (), file: #filePath, line: expectedLine)
            },
            issueMatcher: { issue in
                issue.compactDescription.contains("adapter failure")
                    && issue.sourceCodeContext.location?.lineNumber == Int(expectedLine)
            }
        )
    }
    #endif
}

@Test
private func swiftTestingAdapterReportsMessageAndSourceLocation() {
    let location = SourceLocation(
        fileID: #fileID,
        filePath: #filePath,
        line: 4242,
        column: 7
    )

    withKnownIssue {
        Mock4SwiftTesting.Verify(FailingMock(), 1, (), sourceLocation: location)
    } matching: { issue in
        issue.sourceLocation == location
            && issue.comments.contains(Comment(rawValue: "adapter failure"))
    }
}

private final class InstanceMock: Mock {
    typealias Given = Void
    typealias Verify = Void
    typealias Perform = Void

    func given(_ method: Void) {}
    func perform(_ method: Void) {}

    func verification(_ method: Void, count: Count) -> VerificationResult {
        VerificationResult(success: true, message: "")
    }

    func resetMock(_ scopes: MockScope...) {}
}

private final class StaticTestMock: StaticMock {
    typealias StaticGiven = Void
    typealias StaticVerify = Void
    typealias StaticPerform = Void

    static func given(_ method: Void) {}
    static func perform(_ method: Void) {}

    static func verification(_ method: Void, count: Count) -> VerificationResult {
        VerificationResult(success: true, message: "")
    }

    static func resetMock(_ scopes: MockScope...) {}
}

private final class FailingMock: Mock {
    typealias Given = Void
    typealias Verify = Void
    typealias Perform = Void

    func given(_ method: Void) {}
    func perform(_ method: Void) {}

    func verification(_ method: Void, count: Count) -> VerificationResult {
        VerificationResult(success: false, message: "adapter failure")
    }

    func resetMock(_ scopes: MockScope...) {}
}
