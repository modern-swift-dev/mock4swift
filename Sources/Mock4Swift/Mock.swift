import Foundation

/// Defines instance-level mock configuration, verification, and reset operations.
public protocol Mock: AnyObject {
    associatedtype Given
    associatedtype Verify
    associatedtype Perform
    func given(_ configuration: Given)
    func perform(_ configuration: Perform)
    func verification(_ configuration: Verify, count: Count) -> VerificationResult
    func resetMock(_ scopes: MockScope...)
}
