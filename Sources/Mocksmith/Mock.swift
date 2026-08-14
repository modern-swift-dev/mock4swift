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

public protocol _MocksmithExhaustiveMock: Mock {
    var _mocksmithUnverifiedInvocations: [_MocksmithInvocation] { get }
}

/// Opt-in support for generated typed call-history selectors.
public protocol _MocksmithCallInspectable: Mock {
    associatedtype Calls
    func _mocksmithCalls() -> Calls
}

/// Opt-in support for generated property-state selectors.
public protocol _MocksmithStateControllable: Mock {
    associatedtype MockState
    func _mocksmithState() -> MockState
}
