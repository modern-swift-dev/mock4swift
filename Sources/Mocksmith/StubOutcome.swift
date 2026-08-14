import Foundation

public func _mocksmithNoAnswer<Outcome>(_ answer: Never) -> Outcome {}

/// Represents a value, error, or argument-dependent answer produced by a mock stub.
public enum StubOutcome<Arguments, Ephemeral, Output> {
    case returnValue(Output)
    case throwError(any Error)
    case answer((Arguments, borrowing Ephemeral) throws -> Output)
    case asyncAnswer((Arguments) async throws -> Output)

    public static func returning(_ value: Output) -> Self {
        .returnValue(value)
    }

    public static func throwing(_ error: any Error) -> Self {
        .throwError(error)
    }

    public static func answering(
        _ answer: @escaping (Arguments, borrowing Ephemeral) throws -> Output
    ) -> Self {
        .answer(answer)
    }

    public static func answering(
        _ answer: @escaping (Arguments) async throws -> Output
    ) -> Self {
        .asyncAnswer(answer)
    }

    static func suspending<Failure: Error>(
        on pending: PendingCall<Arguments, Output, Failure>,
        cancellation: PendingCancellationPolicy<Failure>
    ) -> Self {
        let failure: Failure? = switch cancellation {
            case .ignore: nil
            case let .fail(with: failure): failure
        }
        return .asyncAnswer { arguments in
            try await pending.suspend(arguments, cancellationFailure: failure)
        }
    }
}

public struct _MocksmithStubRegistration<Arguments, Ephemeral, Output> {
    private let appendOutcomes: ([StubOutcome<Arguments, Ephemeral, Output>]) -> Void

    public init(
        _ appendOutcomes: @escaping ([StubOutcome<Arguments, Ephemeral, Output>]) -> Void
    ) {
        self.appendOutcomes = appendOutcomes
    }

    public func append(_ outcomes: [StubOutcome<Arguments, Ephemeral, Output>]) {
        precondition(!outcomes.isEmpty, "Mock stub sequence additions need at least one outcome")
        appendOutcomes(outcomes)
    }
}
