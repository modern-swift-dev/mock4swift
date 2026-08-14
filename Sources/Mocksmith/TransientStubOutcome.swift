import Foundation

/// Represents a lazily produced value, error, or borrowed argument-dependent answer.
public enum TransientStubOutcome<
    Arguments: ~Copyable,
    Ephemeral: ~Copyable,
    Output: ~Copyable
> {
    case produce(() -> Output)
    case throwError(any Error)
    case answer((borrowing Arguments, borrowing Ephemeral) throws -> Output)
    case asyncAnswer((borrowing Arguments) async throws -> Output)

    public static func producing(_ producer: @escaping () -> Output) -> Self {
        .produce(producer)
    }

    public static func throwing(_ error: any Error) -> Self {
        .throwError(error)
    }

    public static func answering(
        _ answer: @escaping (borrowing Arguments, borrowing Ephemeral) throws -> Output
    ) -> Self {
        .answer(answer)
    }

    public static func answering(
        _ answer: @escaping (borrowing Arguments) async throws -> Output
    ) -> Self {
        .asyncAnswer(answer)
    }
}

public struct _MocksmithTransientStubRegistration<
    Arguments: ~Copyable,
    Ephemeral: ~Copyable,
    Output: ~Copyable
> {
    private let appendOutcomes: ([TransientStubOutcome<Arguments, Ephemeral, Output>]) -> Void

    public init(
        _ appendOutcomes: @escaping ([TransientStubOutcome<Arguments, Ephemeral, Output>]) -> Void
    ) {
        self.appendOutcomes = appendOutcomes
    }

    public func append(_ outcomes: [TransientStubOutcome<Arguments, Ephemeral, Output>]) {
        precondition(!outcomes.isEmpty, "Mock stub sequence additions need at least one outcome")
        appendOutcomes(outcomes)
    }
}
