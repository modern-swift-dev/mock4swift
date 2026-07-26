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
        Mock4SwiftTesting.VerifyNoMoreInteractions(mock)
        Mock4SwiftXCTest.VerifyNoMoreInteractions(mock)
    }

    func testStaticAdaptersAcceptSuccessfulVerification() {
        Mock4SwiftTesting.Verify(StaticTestMock.self, .atLeast(1)).check()
        Mock4SwiftTesting.Verify(StaticTestMock.self, 1).check()
        Mock4SwiftXCTest.Verify(StaticTestMock.self, .atLeast(1)).check()
        Mock4SwiftXCTest.Verify(StaticTestMock.self, 1).check()
        Mock4SwiftTesting.VerifyNoMoreInteractions(StaticTestMock.self)
        Mock4SwiftXCTest.VerifyNoMoreInteractions(StaticTestMock.self)
    }

    func testXCTestInOrderAdapterAcceptsSuccessfulVerification() {
        Mock4SwiftXCTest.VerifyInOrder { order in
            order._append(
                source: InstanceMock(),
                invocations: { [_Mock4SwiftInvocation(sequence: 1, member: "check")] },
                member: "check",
                matches: { $0 == 1 },
                markVerified: { _ in }
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

    func testXCTestNoMoreInteractionsReportsMessageAndSourceLocation() {
        let expectedLine: UInt = 4244
        XCTExpectFailure(
            "The exhaustive adapter failure is intentional",
            strict: true,
            failingBlock: {
                Mock4SwiftXCTest.VerifyNoMoreInteractions(FailingMock(), file: #filePath, line: expectedLine)
            },
            issueMatcher: { issue in
                issue.compactDescription.contains("Unverified interactions: load(*:) ×2, save(*:) ×1")
                    && issue.sourceCodeContext.location?.lineNumber == Int(expectedLine)
            }
        )
    }

    func testXCTestStaticNoMoreInteractionsReportsMessageAndSourceLocation() {
        let expectedLine: UInt = 4245
        XCTExpectFailure(
            "The static exhaustive adapter failure is intentional",
            strict: true,
            failingBlock: {
                Mock4SwiftXCTest.VerifyNoMoreInteractions(FailingStaticMock.self, file: #filePath, line: expectedLine)
            },
            issueMatcher: { issue in
                issue.compactDescription.contains("Unverified interactions: load(*:) ×2, save(*:) ×1")
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

@Test private func swiftTestingNoMoreInteractionsReportsMessageAndSourceLocation() {
    let location = SourceLocation(fileID: #fileID, filePath: #filePath, line: 4244, column: 9)

    withKnownIssue {
        Mock4SwiftTesting.VerifyNoMoreInteractions(FailingMock(), sourceLocation: location)
    } matching: { issue in
        issue.sourceLocation == location
            && issue.comments.contains(Comment(rawValue: "Unverified interactions: load(*:) ×2, save(*:) ×1"))
    }
}

@Test private func swiftTestingStaticNoMoreInteractionsReportsMessageAndSourceLocation() {
    let location = SourceLocation(fileID: #fileID, filePath: #filePath, line: 4245, column: 10)

    withKnownIssue {
        Mock4SwiftTesting.VerifyNoMoreInteractions(FailingStaticMock.self, sourceLocation: location)
    } matching: { issue in
        issue.sourceLocation == location
            && issue.comments.contains(Comment(rawValue: "Unverified interactions: load(*:) ×2, save(*:) ×1"))
    }
}

private final class InstanceMock: Mock, _Mock4SwiftExhaustiveMock {
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

    var _mock4SwiftUnverifiedInvocations: [_Mock4SwiftInvocation] { [] }
}

private final class StaticTestMock: StaticMock, _Mock4SwiftExhaustiveStaticMock {
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

    static var _mock4SwiftUnverifiedInvocations: [_Mock4SwiftInvocation] { [] }
}

private final class FailingMock: Mock, _Mock4SwiftExhaustiveMock {
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

    var _mock4SwiftUnverifiedInvocations: [_Mock4SwiftInvocation] {
        [
            .init(sequence: 1, member: "load(_:)"),
            .init(sequence: 2, member: "save(_:)"),
            .init(sequence: 3, member: "load(_:)")
        ]
    }
}

private final class FailingStaticMock: StaticMock, _Mock4SwiftExhaustiveStaticMock {
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

    static var _mock4SwiftUnverifiedInvocations: [_Mock4SwiftInvocation] {
        [
            .init(sequence: 1, member: "load(_:)"),
            .init(sequence: 2, member: "save(_:)"),
            .init(sequence: 3, member: "load(_:)")
        ]
    }
}

private struct AdapterVerify {
    let result: VerificationResult
    let report: (VerificationResult) -> Void

    func check() {
        report(result)
    }
}
