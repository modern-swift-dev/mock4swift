import Mock4Swift
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

private func report(_ result: VerificationResult, file: StaticString, line: UInt) {
    guard !result.success else {
        return
    }
    XCTFail(result.message, file: file, line: line)
}
