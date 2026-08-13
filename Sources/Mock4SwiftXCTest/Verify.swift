@_exported public import Mock4Swift
import XCTest

public func Verify<M: Mock>(
    _ mock: M,
    _ count: Count = .atLeast(1),
    file: StaticString = #filePath,
    line: UInt = #line
) -> M.Verify {
    mock.verification(count: count) {
        report($0, file: file, line: line)
    }
}

public func Verify<M: Mock>(
    _ mock: M,
    _ count: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) -> M.Verify {
    Verify(mock, .exactly(count), file: file, line: line)
}

public func Verify<M: StaticMock>(
    _ mock: M.Type,
    _ count: Count = .atLeast(1),
    file: StaticString = #filePath,
    line: UInt = #line
) -> M.StaticVerify {
    M.verification(count: count) {
        report($0, file: file, line: line)
    }
}

public func Verify<M: StaticMock>(
    _ mock: M.Type,
    _ count: Int,
    file: StaticString = #filePath,
    line: UInt = #line
) -> M.StaticVerify {
    Verify(mock, .exactly(count), file: file, line: line)
}

public func VerifyInOrder(
    file: StaticString = #filePath,
    line: UInt = #line,
    _ body: (InOrder) -> Void
) {
    let order = InOrder()
    body(order)
    report(order.verification(), file: file, line: line)
}

public func VerifyNoMoreInteractions(
    _ mock: some _Mock4SwiftExhaustiveMock,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    report(_mock4SwiftNoMoreInteractionsResult(mock._mock4SwiftUnverifiedInvocations), file: file, line: line)
}

public func VerifyNoMoreInteractions<M: _Mock4SwiftExhaustiveStaticMock>(
    _ mock: M.Type,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    report(_mock4SwiftNoMoreInteractionsResult(M._mock4SwiftUnverifiedInvocations), file: file, line: line)
}

private func report(_ result: VerificationResult, file: StaticString, line: UInt) {
    guard !result.success else {
        return
    }
    XCTFail(result.message, file: file, line: line)
}
