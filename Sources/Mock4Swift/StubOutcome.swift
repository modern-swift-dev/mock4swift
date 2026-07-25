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

public struct _Mock4SwiftStubRegistration<Output> {
    private let appendOutcomes: ([StubOutcome<Output>]) -> Void

    public init(_ appendOutcomes: @escaping ([StubOutcome<Output>]) -> Void) {
        self.appendOutcomes = appendOutcomes
    }

    public func append(_ outcomes: [StubOutcome<Output>]) {
        precondition(!outcomes.isEmpty, "Mock stub sequence additions need at least one outcome")
        appendOutcomes(outcomes)
    }
}
