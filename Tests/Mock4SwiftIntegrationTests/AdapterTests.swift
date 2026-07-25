import Mock4Swift
import Mock4SwiftTesting
import Mock4SwiftXCTest
import Testing
import XCTest

final class AdapterTests: XCTestCase {
    func testInstanceAdaptersAcceptSuccessfulVerification() {
        let mock = InstanceMock()

        Mock4SwiftTesting.Verify(mock, .atLeast(1)).check()
        Mock4SwiftTesting.Verify(mock, 1).check()
        Mock4SwiftXCTest.Verify(mock, .atLeast(1)).check()
        Mock4SwiftXCTest.Verify(mock, 1).check()
    }

    func testStaticAdaptersAcceptSuccessfulVerification() {
        Mock4SwiftTesting.Verify(StaticTestMock.self, .atLeast(1)).check()
        Mock4SwiftTesting.Verify(StaticTestMock.self, 1).check()
        Mock4SwiftXCTest.Verify(StaticTestMock.self, .atLeast(1)).check()
        Mock4SwiftXCTest.Verify(StaticTestMock.self, 1).check()
    }

    func testXCTestInOrderAdapterAcceptsSuccessfulVerification() {
        Mock4SwiftXCTest.VerifyInOrder { order in
            order._append(
                source: InstanceMock(),
                invocations: { [_Mock4SwiftInvocation(sequence: 1, member: "check")] },
                member: "check",
                matches: { $0 == 1 }
            )
        }
    }

    #if canImport(Darwin)
    func testXCTestInOrderAdapterReportsBlockLocation() {
        let expectedLine: UInt = 4243
        XCTExpectFailure(
            "The in-order adapter failure is intentional",
            strict: true,
            failingBlock: {
                Mock4SwiftXCTest.VerifyInOrder(file: #filePath, line: expectedLine) { _ in }
            },
            issueMatcher: { issue in
                issue.compactDescription.contains("In-order verification needs at least one expected invocation")
                    && issue.sourceCodeContext.location?.lineNumber == Int(expectedLine)
            }
        )
    }

    func testXCTestAdapterReportsMessageAndSourceLocation() {
        let expectedLine: UInt = 4242
        XCTExpectFailure(
            "The adapter failure is intentional",
            strict: true,
            failingBlock: {
                Mock4SwiftXCTest.Verify(FailingMock(), 1, file: #filePath, line: expectedLine).check()
            },
            issueMatcher: { issue in
                issue.compactDescription.contains("adapter failure")
                    && issue.sourceCodeContext.location?.lineNumber == Int(expectedLine)
            }
        )
    }
    #endif
}

@Test private func swiftTestingAdapterReportsMessageAndSourceLocation() {
    let location = SourceLocation(
        fileID: #fileID,
        filePath: #filePath,
        line: 4242,
        column: 7
    )

    withKnownIssue {
        Mock4SwiftTesting.Verify(FailingMock(), 1, sourceLocation: location).check()
    } matching: { issue in
        issue.sourceLocation == location
            && issue.comments.contains(Comment(rawValue: "adapter failure"))
    }
}

@Test private func swiftTestingInOrderAdapterReportsBlockLocation() {
    let location = SourceLocation(fileID: #fileID, filePath: #filePath, line: 4243, column: 8)

    withKnownIssue {
        Mock4SwiftTesting.VerifyInOrder(sourceLocation: location) { _ in }
    } matching: { issue in
        issue.sourceLocation == location
            && issue.comments.contains(Comment(rawValue: "In-order verification needs at least one expected invocation"))
    }
}

private final class InstanceMock: Mock {
    typealias Given = Void
    typealias Verify = AdapterVerify
    typealias Perform = Void

    func given() {}
    func perform() {}

    func verification(
        count: Count,
        report: @escaping (VerificationResult) -> Void
    ) -> AdapterVerify {
        AdapterVerify(result: VerificationResult(success: true, message: ""), report: report)
    }

    func resetMock(_ scopes: MockScope...) {}
}

private final class StaticTestMock: StaticMock {
    typealias StaticGiven = Void
    typealias StaticVerify = AdapterVerify
    typealias StaticPerform = Void

    static func given() {}
    static func perform() {}

    static func verification(
        count: Count,
        report: @escaping (VerificationResult) -> Void
    ) -> AdapterVerify {
        AdapterVerify(result: VerificationResult(success: true, message: ""), report: report)
    }

    static func resetMock(_ scopes: MockScope...) {}
}

private final class FailingMock: Mock {
    typealias Given = Void
    typealias Verify = AdapterVerify
    typealias Perform = Void

    func given() {}
    func perform() {}

    func verification(
        count: Count,
        report: @escaping (VerificationResult) -> Void
    ) -> AdapterVerify {
        AdapterVerify(result: VerificationResult(success: false, message: "adapter failure"), report: report)
    }

    func resetMock(_ scopes: MockScope...) {}
}

private struct AdapterVerify {
    let result: VerificationResult
    let report: (VerificationResult) -> Void

    func check() {
        report(result)
    }
}
