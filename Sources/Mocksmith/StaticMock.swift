import Foundation

/// Defines type-level mock configuration, verification, and reset operations.
public protocol StaticMock {
    associatedtype StaticGiven
    associatedtype StaticVerify
    associatedtype StaticPerform
    static func given() -> StaticGiven
    static func perform() -> StaticPerform
    static func verification(
        count: Count,
        report: @escaping (VerificationResult) -> Void
    ) -> StaticVerify
    static func resetMock(_ scopes: MockScope...)
}

public protocol _MocksmithExhaustiveStaticMock: StaticMock {
    static var _mocksmithUnverifiedInvocations: [_MocksmithInvocation] { get }
}

/// Opt-in support for generated typed static call-history selectors.
public protocol _MocksmithStaticCallInspectable: StaticMock {
    associatedtype StaticCalls
    static func _mocksmithStaticCalls() -> StaticCalls
}

/// Opt-in support for generated static property-state selectors.
public protocol _MocksmithStaticStateControllable: StaticMock {
    associatedtype StaticMockState
    static func _mocksmithStaticState() -> StaticMockState
}
