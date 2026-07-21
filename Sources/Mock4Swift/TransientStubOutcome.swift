import Foundation


/// Represents a lazily produced value or error returned by a transient mock stub.
public enum TransientStubOutcome<Output: ~Copyable> {
    case produce(() -> Output)
    case throwError(any Error)

    public static func producing(_ producer: @escaping () -> Output) -> Self { .produce(producer) }
    public static func throwing(_ error: any Error) -> Self { .throwError(error) }
}
