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

public protocol _Mock4SwiftExhaustiveMock: Mock {
    var _mock4SwiftUnverifiedInvocations: [_Mock4SwiftInvocation] { get }
}

/// Opt-in support for generated typed call-history selectors.
public protocol _Mock4SwiftCallInspectable: Mock {
    associatedtype Calls
    func _mock4SwiftCalls() -> Calls
}
