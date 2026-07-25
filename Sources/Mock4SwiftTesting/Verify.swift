import Mock4Swift
import Testing

public func Verify<M: Mock>(
    _ mock: M,
    _ count: Count = .atLeast(1),
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) -> M.Verify {
    mock.verification(count: count) {
        record($0, sourceLocation: sourceLocation)
    }
}

public func Verify<M: Mock>(
    _ mock: M,
    _ count: Int,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) -> M.Verify {
    Verify(mock, .exactly(count), sourceLocation: sourceLocation)
}

public func Verify<M: StaticMock>(
    _ mock: M.Type,
    _ count: Count = .atLeast(1),
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) -> M.StaticVerify {
    M.verification(count: count) {
        record($0, sourceLocation: sourceLocation)
    }
}

public func Verify<M: StaticMock>(
    _ mock: M.Type,
    _ count: Int,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) -> M.StaticVerify {
    Verify(mock, .exactly(count), sourceLocation: sourceLocation)
}

private func record(_ result: VerificationResult, sourceLocation: SourceLocation) {
    guard !result.success else {
        return
    }
    Issue.record(Comment(rawValue: result.message), sourceLocation: sourceLocation)
}
