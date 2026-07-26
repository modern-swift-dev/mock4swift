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

public protocol _Mock4SwiftExhaustiveStaticMock: StaticMock {
    static var _mock4SwiftUnverifiedInvocations: [_Mock4SwiftInvocation] { get }
}
