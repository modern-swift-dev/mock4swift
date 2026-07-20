import Mock4Swift
import Testing

public func Verify<M: Mock>(
    _ mock: M,
    _ count: Count = .atLeast(1),
    _ method: M.Verify,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) {
    record(mock.verification(method, count: count), sourceLocation: sourceLocation)
}

public func Verify<M: Mock>(
    _ mock: M,
    _ count: Int,
    _ method: M.Verify,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) {
    Verify(mock, .exactly(count), method, sourceLocation: sourceLocation)
}

public func Verify<M: StaticMock>(
    _ mock: M.Type,
    _ count: Count = .atLeast(1),
    _ method: M.StaticVerify,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) {
    record(M.verification(method, count: count), sourceLocation: sourceLocation)
}

public func Verify<M: StaticMock>(
    _ mock: M.Type,
    _ count: Int,
    _ method: M.StaticVerify,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) {
    Verify(mock, .exactly(count), method, sourceLocation: sourceLocation)
}

private func record(_ result: VerificationResult, sourceLocation: SourceLocation) {
    guard !result.success else { return }
    Issue.record(Comment(rawValue: result.message), sourceLocation: sourceLocation)
}
