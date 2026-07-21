import Foundation

/// Defines type-level mock configuration, verification, and reset operations.
public protocol StaticMock {
    associatedtype StaticGiven
    associatedtype StaticVerify
    associatedtype StaticPerform
    static func given(_ configuration: StaticGiven)
    static func perform(_ configuration: StaticPerform)
    static func verification(_ configuration: StaticVerify, count: Count) -> VerificationResult
    static func resetMock(_ scopes: MockScope...)
}
