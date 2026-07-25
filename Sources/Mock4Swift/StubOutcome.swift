import Foundation

/// Represents a value or error produced by a mock stub.
public enum StubOutcome<Output> {
    case returnValue(Output)
    case throwError(any Error)

    public static func returning(_ value: Output) -> Self {
        .returnValue(value)
    }

    public static func throwing(_ error: any Error) -> Self {
        .throwError(error)
    }
}
