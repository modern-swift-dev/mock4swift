import Foundation

/// Defines instance-level mock configuration, verification, and reset operations.
public protocol Mock: AnyObject {
    associatedtype Given
    associatedtype Verify
    associatedtype Perform
    func given() -> Given
    func perform() -> Perform
    func verification(
        count: Count,
        report: @escaping (VerificationResult) -> Void
    ) -> Verify
    func resetMock(_ scopes: MockScope...)
}
