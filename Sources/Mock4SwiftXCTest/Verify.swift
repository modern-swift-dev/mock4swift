import Mock4Swift
import XCTest

public func Verify<M: Mock>(
    _ mock: M,
    _ count: Count = .atLeast(1),
    _ method: M.Verify,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    report(mock.verification(method, count: count), file: file, line: line)
}

public func Verify<M: Mock>(
    _ mock: M,
    _ count: Int,
    _ method: M.Verify,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    Verify(mock, .exactly(count), method, file: file, line: line)
}

public func Verify<M: StaticMock>(
    _ mock: M.Type,
    _ count: Count = .atLeast(1),
    _ method: M.StaticVerify,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    report(M.verification(method, count: count), file: file, line: line)
}

public func Verify<M: StaticMock>(
    _ mock: M.Type,
    _ count: Int,
    _ method: M.StaticVerify,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    Verify(mock, .exactly(count), method, file: file, line: line)
}

private func report(_ result: VerificationResult, file: StaticString, line: UInt) {
    guard !result.success else { return }
    XCTFail(result.message, file: file, line: line)
}
