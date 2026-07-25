import Foundation

/// Represents a lazily produced value or error returned by a transient mock stub.
public enum TransientStubOutcome<Output: ~Copyable> {
    case produce(() -> Output)
    case throwError(any Error)

    public static func producing(_ producer: @escaping () -> Output) -> Self {
        .produce(producer)
    }

    public static func throwing(_ error: any Error) -> Self {
        .throwError(error)
    }
}

public struct _Mock4SwiftTransientStubRegistration<Output: ~Copyable> {
    private let appendOutcomes: ([TransientStubOutcome<Output>]) -> Void

    public init(_ appendOutcomes: @escaping ([TransientStubOutcome<Output>]) -> Void) {
        self.appendOutcomes = appendOutcomes
    }

    public func append(_ outcomes: [TransientStubOutcome<Output>]) {
        precondition(!outcomes.isEmpty, "Mock stub sequence additions need at least one outcome")
        appendOutcomes(outcomes)
    }
}
